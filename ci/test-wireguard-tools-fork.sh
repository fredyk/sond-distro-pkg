#!/bin/bash
# Shape checks for the wireguard-tools fork recipe: the wg command alone (it configures the
# kernel's WireGuard devices over netlink), static against the pinned musl, GPL-2.0 with its
# COPYING and its source lane. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-wireguard-tools-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/WireGuard/wireguard-tools at its tag v1.0.20260223.
VERSION=1.0.20260223
UPSTREAM=github.com/WireGuard/wireguard-tools@49ce333da02056ae7b22ee2aeb6afe8aaed79b19

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
check wireguard-tools wireguard-tools "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/wireguard-tools-sond.yml
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
	# On linux wg links the .c files (GPL-2.0 OR MIT, GPL elected), ipc-linux.h and ipc-uapi*.h (MIT)
	# and netlink.h, a minimized libmnl (LGPL-2.1+), all under src/ at the pinned tag.
	[ "$l" = "GPL-2.0-only AND LGPL-2.1-or-later AND MIT" ] && ok "license GPL-2.0-only AND LGPL-2.1-or-later AND MIT" \
		|| bad "license GPL-2.0-only AND LGPL-2.1-or-later AND MIT (found: $l)"
	# wg includes <linux/types.h> (curve25519.c): the sond runner has no kernel headers of its own.
	grep -qE '^ +linux-headers 6\.12\.77$' "$yml" && ok "depends on linux-headers 6.12.77" || bad "depends on linux-headers 6.12.77"
	# The bundled uapi must win over linux-headers 6.12 (no WGALLOWEDIP_A_FLAGS there).
	grep -qF 'CFLAGS="-isystem uapi/linux $SOND_CFLAGS' "$yml" && ok "bundled uapi first" || bad "bundled uapi first"
	# build.sh reads .d files to know which linux-headers notices ship; the Makefile's -MMD leaves
	# system headers out, so a -M pass through $SOND_CC writes complete ones.
	grep -qF -- '-M -MF "${c%.c}.sond.d"' "$yml" && ok "dependency files list the kernel headers" || bad "dependency files list the kernel headers"
	# www.gnu.org went unreachable (26/11); ftp.gnu.org serves the same bytes, checked by the same sha.
	grep -qF 'https://ftp.gnu.org/gnu/Licenses/lgpl-2.1.txt' "$yml" && ok "LGPL text has a second source" || bad "LGPL text has a second source"
	grep -qF 20e50fe7aae3e56378ebf0417d9de904f55a0e61e4df315333e632a4d3555d95 "$yml" \
		&& ok "the LGPL-2.1 text is checked against gnu.org's sha256" || bad "the LGPL-2.1 text is checked against gnu.org's sha256"
	grep -qE 'make -C src .*wg$' "$yml" && ok "builds only the wg target" || bad "builds only the wg target"
	grep -qE -- '-static' "$yml" && ok "the executable is linked -static" || bad "the executable is linked -static"
	grep -qE 'install -D -m 0755 src/wg "\$SOND_PAYLOAD/bin/wg"' "$yml" && ok "ships bin/wg" || bad "ships bin/wg"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no wg-quick: it needs bash and ip)" || bad "ships nothing else ($n payload writes)"
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
        dests.add(dest or "share/licenses/wireguard-tools/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("wireguard-tools", "static", licence)]
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
	bad "wireguard-tools-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-wireguard-tools-fork: OK\n'
else
	printf 'test-wireguard-tools-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
