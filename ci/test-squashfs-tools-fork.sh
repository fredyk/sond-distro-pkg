#!/bin/bash
# Shape checks for the squashfs-tools fork recipe: the unsquashfs command alone (incusd looks it
# up on PATH at startup), static against the pinned musl, reading gzip and xz images through a
# zlib and a liblzma built in the same job from pinned sources and linked in, GPL-2.0 with its
# COPYING, the texts of both libraries and its source lane. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-squashfs-tools-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

rbx=$here/rbx-squashfs-tools.sh
[ -f "$rbx" ] && sh -n "$rbx" 2>/dev/null \
	&& ok "ci/rbx-squashfs-tools.sh is a POSIX wrapper the gate can run" \
	|| bad "ci/rbx-squashfs-tools.sh is a POSIX wrapper the gate can run"

# Measured on 2026-11-26 from github.com/plougher/squashfs-tools at its tag 4.7.5 (latest release).
VERSION=4.7.5
UPSTREAM=github.com/plougher/squashfs-tools@708c59ae80853b0845017c33b42e56061cc546cd
# The libraries linked in: xz at its tag v5.8.4, zlib's release tarball for v1.4 (madler/zlib).
XZ_COMMIT=d3e650e63c110e830fd5391e7f8b45df0b91d3da
ZLIB_URL=https://github.com/madler/zlib/releases/download/v1.4/zlib-1.4.tar.gz
ZLIB_SHA256=02dd159783677a749c04adbdd02b55b8a2bcc7e054f51b76b549199a916ad584
LICENCE="GPL-2.0-or-later AND Zlib AND 0BSD"

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
check squashfs-tools squashfs-tools "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/squashfs-tools-sond.yml
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
	# unsquashfs links the squashfs-tools sources (GPL-2.0-or-later), zlib (Zlib) and liblzma (0BSD).
	[ "$l" = "$LICENCE" ] && ok "license $LICENCE" || bad "license $LICENCE (found: $l)"
	grep -qF "$XZ_COMMIT" "$yml" && grep -qE "git -C \S+ rev-parse HEAD.*$XZ_COMMIT|$XZ_COMMIT.*rev-parse" "$yml" \
		&& ok "liblzma comes from xz at the pinned commit, checked" || bad "liblzma comes from xz at the pinned commit, checked"
	grep -qF "$ZLIB_URL" "$yml" && grep -qE "$ZLIB_SHA256 .*sha256sum -c|$ZLIB_SHA256.*\| sha256sum -c" "$yml" \
		&& ok "zlib comes from the pinned tarball, checked against its sha256" || bad "zlib comes from the pinned tarball, checked against its sha256"
	grep -qE -- '-DBUILD_SHARED_LIBS=OFF' "$yml" && grep -qE -- '--target liblzma' "$yml" \
		&& ok "only the static liblzma is built from xz" || bad "only the static liblzma is built from xz"
	grep -qE -- '--static' "$yml" && grep -qE 'make .*libz\.a' "$yml" \
		&& ok "only the static libz.a is built from zlib" || bad "only the static libz.a is built from zlib"
	# Upstream's Makefile appends its own flags with "CFLAGS +=": on the command line CFLAGS would
	# override them, so the compile flags go through the environment.
	grep -qE 'CFLAGS="\$SOND_CFLAGS[^"]*" LDFLAGS="\$SOND_LDFLAGS[^"]*-static[^"]*" make -C squashfs-tools unsquashfs ' "$yml" \
		&& ok "builds only the unsquashfs target, flags from the environment, linked -static" \
		|| bad "builds only the unsquashfs target, flags from the environment, linked -static"
	for opt in GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=0 LZ4_SUPPORT=0 ZSTD_SUPPORT=0; do
		grep -qE "make -C squashfs-tools unsquashfs .*\b$opt\b" "$yml" && ok "make $opt" || bad "make $opt"
	done
	grep -qE 'install -D -m 0755 squashfs-tools/unsquashfs "\$SOND_PAYLOAD/bin/unsquashfs"' "$yml" \
		&& ok "ships bin/unsquashfs" || bad "ships bin/unsquashfs"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no mksquashfs, no sqfscat link)" || bad "ships nothing else ($n payload writes)"
	for t in COPYING '=share/licenses/squashfs-tools/zlib-LICENSE' '=share/licenses/squashfs-tools/liblzma-COPYING.0BSD'; do
		grep -qE "^\s+\S*$t$" "$yml" && ok "license-files ships $t" || bad "license-files ships $t"
	done
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
        dests.add(dest or "share/licenses/squashfs-tools/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("squashfs-tools", "static", licence)]
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
	bad "squashfs-tools-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-squashfs-tools-fork: OK\n'
else
	printf 'test-squashfs-tools-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
