#!/bin/bash
# Shape checks for the rsync fork recipe: the rsync command alone (incusd needs it on PATH at
# startup and receives dir volumes with it), static against the pinned musl, GPL-3.0-or-later AND LGPL-2.1-or-later
# AND Zlib AND MIT with its COPYING and the LGPL-2.1 text and its source lane, ACLs and xattrs in, md2man and optional libraries out. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-rsync-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/RsyncProject/rsync at its tag v3.5.2 (latest release).
VERSION=3.5.2
UPSTREAM=github.com/RsyncProject/rsync@41bbd895668767e155b2eb6da64f37afa9cb8724

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
check rsync rsync "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/rsync-sond.yml
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
	# COPYING at the tag is the GPLv3 text; every source file grants "version 3 or later". The
	# binary also carries libacl/libattr linked statically (LGPL-2.1-or-later), and the zlib (Zlib)
	# and popt (MIT) rsync builds from its own tree (--with-included-zlib, --with-included-popt).
	want="GPL-3.0-or-later AND LGPL-2.1-or-later AND Zlib AND MIT"
	[ "$l" = "$want" ] && ok "license $want" || bad "license $want (found: $l)"
	grep -qF 'share/licenses/rsync/LGPL-2.1' "$yml" && ok "ships the LGPL-2.1 text for the static libacl" \
		|| bad "ships the LGPL-2.1 text for the static libacl"
	grep -qF -- '--disable-md2man' "$yml" && ok "md2man is disabled" || bad "md2man is disabled"
	for o in openssl xxhash zstd lz4; do
		grep -qF -- "--disable-$o" "$yml" && ok "$o is disabled (incus never asks for it)" \
			|| bad "$o is disabled"
	done
	# incus: LocalCopy runs "rsync -a -HA" and its features add --xattrs (internal/rsync/rsync.go)
	grep -qF -- '--enable-acl-support' "$yml" && grep -qF "SUPPORT_ACLS 1' config.h" "$yml" \
		&& ok "ACL support is on and asserted (incus passes -A)" || bad "ACL support is on and asserted"
	grep -qF -- '--enable-xattr-support' "$yml" && grep -qF "SUPPORT_XATTRS 1' config.h" "$yml" \
		&& ok "xattr support is on and asserted (incus passes --xattrs)" || bad "xattr support is on and asserted"
	grep -qE '^\s+acl [0-9]' "$yml" && ok "libacl comes from the acl package" || bad "libacl comes from the acl package"
	grep -qE -- '-static' "$yml" && ok "the executable is linked -static" || bad "the executable is linked -static"
	grep -qE 'make -j"\$\(nproc\)" rsync$' "$yml" && ok "builds only the rsync target" || bad "builds only the rsync target"
	grep -qE 'install -D -m 0755 rsync "\$SOND_PAYLOAD/bin/rsync"' "$yml" && ok "ships bin/rsync" || bad "ships bin/rsync"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no rsync-ssl, rrsync, manpages)" || bad "ships nothing else ($n payload writes)"
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
        dests.add(dest or "share/licenses/rsync/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("rsync", "static", licence)]
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
	bad "rsync-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-rsync-fork: OK\n'
else
	printf 'test-rsync-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
