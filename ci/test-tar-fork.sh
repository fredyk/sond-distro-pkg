#!/bin/bash
# Shape checks for the tar fork recipe: GNU tar's tar command alone, static against the pinned musl with xattrs on,
# GPL-3.0-or-later with its COPYING and its source lane, built hermetically from the release
# tarball (configure already generated, no ./bootstrap, no gnulib clone). Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here. GPL-3.0-or-later must be
# an admitted licence in sondpkg (branch rsync-fork).
# Offline: no network, no build.
#
# usage: ci/test-tar-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

rbx=$here/rbx-tar.sh
[ -f "$rbx" ] && sh -n "$rbx" 2>/dev/null \
	&& ok "ci/rbx-tar.sh is a POSIX wrapper the gate can run" \
	|| bad "ci/rbx-tar.sh is a POSIX wrapper the gate can run"

# Measured on 2026-11-26: sha256 of ftp.gnu.org/gnu/tar/tar-1.35.tar.xz (savannah's git timed
# out; no GitHub mirror carries release_1_35).
VERSION=1.35
TARBALL_SHA256=4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16
UPSTREAM=ftp.gnu.org/gnu/tar/tar-1.35.tar.xz@sha256:$TARBALL_SHA256

# --- the same criterion as ci/test-fork-workflows.sh, through its own check() ---
base_log=$(mktemp)
exit() {
	[ "${_sourcing:-}" = 1 ] || builtin exit "${1:-0}"
}
_sourcing=1
# shellcheck source=/dev/null
source "$here/test-fork-workflows.sh" >"$base_log" 2>&1 || true
unset _sourcing
if grep -q '^FAIL' "$base_log"; then
	bad "ci/test-fork-workflows.sh FAILs on the base recipes (see $base_log)"
fi
check tar tar "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/tar-sond.yml
field() { # <key> of the build step's with: block
	[ -f "$yml" ] || return 0
	python3 - "$yml" "$1" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
try:
    i = next(n for n, l in enumerate(lines) if l.strip() == "- id: build")
    i = next(n for n in range(i, len(lines)) if lines[n].strip() == "with:")
except StopIteration:
    sys.exit(0)
indent = len(lines[i + 1]) - len(lines[i + 1].lstrip())
for n in range(i + 1, len(lines)):
    stripped = lines[n].strip()
    if not stripped:
        continue
    ind = len(lines[n]) - len(lines[n].lstrip())
    if ind < indent:
        break
    if ind == indent and stripped.startswith(sys.argv[2] + ":"):
        sys.stdout.write(stripped.split(": ", 1)[1].strip())
        break
PY
}

if [ -f "$yml" ]; then
	l=$(field license)
	[ "$l" = "GPL-3.0-or-later" ] && ok "license GPL-3.0-or-later" || bad "license GPL-3.0-or-later (found: $l)"
	grep -qF "$TARBALL_SHA256" <(sed -n '1,/^name:/p' "$yml") \
		&& ok "the fork creation checks the tarball's sha256" || bad "the fork creation checks the tarball's sha256"
	grep -qE '(^|[^.])\./bootstrap|autoreconf|gnulib-tool|git clone' <(sed -n '/build: |/,/sond-publish-action/p' "$yml") \
		&& bad "hermetic: no ./bootstrap, autoreconf or clone in the build" || ok "hermetic: no ./bootstrap, autoreconf or clone in the build"
	grep -qE -- '--enable-xattrs' "$yml" && ok "xattr support is on (--xattrs-include)" || bad "xattr support is on (--enable-xattrs)"
	grep -qE -- '--disable-nls' "$yml" && ok "no NLS" || bad "no NLS (--disable-nls)"
	# GNU tar's configure rejects --without-rmt ("Invalid argument to --with-rmt"); an absolute
	# --with-rmt=FILE names the default rmt and stops the included copy from being built.
	grep -qE -- '--with-rmt=/nonexistent/rmt' "$yml" && ok "rmt is not built (--with-rmt=/nonexistent/rmt)" \
		|| bad "rmt is not built (--with-rmt=/nonexistent/rmt)"
	grep -qE 'make .*-C src tar$' "$yml" && ok "builds only the tar target" || bad "builds only the tar target"
	grep -qE -- '-static' "$yml" && ok "the executable is linked -static" || bad "the executable is linked -static"
	grep -qE 'install -D -m 0755 src/tar "\$SOND_PAYLOAD/bin/tar"' "$yml" && ok "ships bin/tar" || bad "ships bin/tar"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no rmt, no backup scripts)" || bad "ships nothing else ($n payload writes)"
	grep -qF 'source-bundle: ${{ steps.build.outputs.source_bundle }}' "$yml" \
		&& ok "publishes the source bundle" || bad "publishes the source bundle"
	missing=$(python3 - "$DISTRO" "$yml" "$l" <<'PY2'
import sys
sys.path.insert(0, sys.argv[1])
from sondpkg import rules
yml, licence = sys.argv[2:]
dests, inside = set(), False
for line in open(yml).read().split("\n"):
    s = line.strip()
    if s == "license-files: |":
        inside = True
        continue
    if inside:
        if not s or (s.endswith(":") or ": " in s) and "=" not in s:
            break
        src, _, dest = s.partition("=")
        dests.add(dest or "share/licenses/tar/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("tar", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
	rc=0
	python3 "$DISTRO/sondpkg/bin/sondpkg" needs-source "$l" >/dev/null || rc=$?
	[ "$rc" = 0 ] && ok "sondpkg needs-source '$l' is 0: the source lane publishes first" \
		|| bad "sondpkg needs-source '$l' is 0 (rc=$rc)"
else
	bad "tar-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-tar-fork: OK\n'
else
	printf 'test-tar-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
