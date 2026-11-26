#!/bin/bash
# Shape checks for the iproute2 fork recipe: the ip command alone (incusd looks for it on PATH
# at startup; the box brings up wg0 with ip link/addr/route), static against the pinned musl,
# with no libmnl, libelf, libbpf, libselinux or libcap, GPL-2.0 with its COPYING and its
# source lane. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-iproute2-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/iproute2/iproute2 at its tag v7.3.0.
VERSION=7.3.0
UPSTREAM=github.com/iproute2/iproute2@19d1276f766daa458fb55096edb38818a7d19606

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
check iproute2 iproute2 "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/iproute2-sond.yml
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
	# ip links ip/*.c and lib/*.c: GPL-2.0, GPL-2.0-or-later, and json_writer (GPL-2.0 OR
	# BSD-2-Clause, GPL elected). The whole is GPL-2.0-only.
	[ "$l" = "GPL-2.0-only" ] && ok "license GPL-2.0-only" || bad "license GPL-2.0-only (found: $l)"
	# include/uapi carries linux/ but not asm/: the pinned kernel headers give asm/types.h & co.
	grep -qE '^ +linux-headers 6\.12\.77$' "$yml" && ok "depends on linux-headers for asm/*" \
		|| bad "depends on linux-headers for asm/*"
	# Optional libraries: configure probes each through pkg-config; a PKG_CONFIG that finds
	# nothing switches every one off (libmnl only adds extack text to errors; the others
	# serve tc, ss and bpf, not ip link/addr/route).
	grep -qE 'PKG_CONFIG=false \./configure' "$yml" && ok "configure finds no optional library" \
		|| bad "configure finds no optional library (PKG_CONFIG=false ./configure)"
	for lib in HAVE_MNL HAVE_ELF HAVE_LIBBPF HAVE_SELINUX HAVE_CAP; do
		grep -qE "grep -q '\^$lib' config\.mk && exit 1" "$yml" && ok "the build refuses a config.mk with $lib" \
			|| bad "the build refuses a config.mk with $lib"
	done
	# The top Makefile sets CC := gcc, so CC goes on the command line; CFLAGS through the
	# environment, which the Makefile appends to its own.
	grep -qE 'CFLAGS="\$SOND_CFLAGS" .*make .*CC="\$SOND_CC"' "$yml" && ok "CC on make's command line, CFLAGS in the environment" \
		|| bad "CC on make's command line, CFLAGS in the environment"
	# A static musl has no dlopen: with SHARED_LIBS=y every link kind (veth, vlan...) is looked
	# up by dlsym and fails; SHARED_LIBS=n compiles static-syms.o instead.
	grep -qE 'SHARED_LIBS=n' "$yml" && ok "SHARED_LIBS=n: link kinds resolved without dlopen" \
		|| bad "SHARED_LIBS=n: link kinds resolved without dlopen"
	# Through the top Makefile (it carries -I../include and the defines down), lib and ip only.
	grep -qE 'make .*SUBDIRS="lib ip"$' "$yml" && ok "builds only lib/ and ip/ through the top Makefile" \
		|| bad "builds only lib/ and ip/ through the top Makefile"
	grep -qE -- '-static' "$yml" && ok "the executable is linked -static" || bad "the executable is linked -static"
	grep -qE 'install -D -m 0755 ip/ip "\$SOND_PAYLOAD/bin/ip"' "$yml" && ok "ships bin/ip" || bad "ships bin/ip"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no tc, ss, bridge, rtmon, routel)" || bad "ships nothing else ($n payload writes)"
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
        dests.add(dest or "share/licenses/iproute2/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("iproute2", "static", licence)]
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
	bad "iproute2-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-iproute2-fork: OK\n'
else
	printf 'test-iproute2-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
