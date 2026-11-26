#!/bin/bash
# Shape checks for the dnsmasq fork recipe: the dnsmasq daemon alone (incusd execs it for every
# managed bridge, after exec.LookPath("dnsmasq"), internal/server/network/driver_bridge.go),
# static against the pinned musl, GPL-2.0 elected with its COPYING and its source lane. Every
# rule ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-dnsmasq-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from thekelleys.org.uk/git/dnsmasq.git at its tag v2.93 (peeled).
VERSION=2.93
UPSTREAM=thekelleys.org.uk/git/dnsmasq@3ff66da573a77c8783deca10ec8c6bba07cd85e6

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
check dnsmasq dnsmasq "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/dnsmasq-sond.yml
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
	# Every src/*.c and src/*.h at the tag: "version 2 dated June, 1991, or (at your option)
	# version 3 dated 29 June, 2007". Version 2 is elected; COPYING is its text.
	[ "$l" = "GPL-2.0-only" ] && ok "license GPL-2.0-only (elected from GPL-2.0-only OR GPL-3.0-only)" \
		|| bad "license GPL-2.0-only (found: $l)"
	grep -qE '^\s+COPYING$' "$yml" && ok "ships COPYING, the GPL-2.0 text" || bad "ships COPYING, the GPL-2.0 text"
	grep -qF 8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643 "$yml" \
		&& ok "COPYING is checked against its sha256 at the tag" || bad "COPYING is checked against its sha256 at the tag"
	# What incusd passes (driver_bridge.go) needs DHCPv4, DHCPv6 and RA, which are on by
	# default; it never uses dbus, IDN, conntrack, DNSSEC, TFTP, a lease script or ipset.
	copts=$(grep -oE 'COPTS="[^"]*"' "$yml" || true)
	for flag in -DNO_TFTP -DNO_SCRIPT -DNO_IPSET -DNO_AUTH; do
		case " ${copts//\"/ } " in *" $flag "*) ok "COPTS has $flag" ;; *) bad "COPTS has $flag (found: $copts)" ;; esac
	done
	for flag in HAVE_DBUS HAVE_IDN HAVE_LIBIDN2 HAVE_CONNTRACK HAVE_DNSSEC HAVE_UBUS HAVE_LUASCRIPT NO_DHCP NO_DHCP6; do
		case $copts in *"$flag"*) bad "COPTS leaves $flag out (found: $copts)" ;; *) ok "COPTS leaves $flag out" ;; esac
	done
	grep -qE -- '-static' "$yml" && ok "the executable is linked -static" || bad "the executable is linked -static"
	grep -qE 'install -D -m 0755 src/dnsmasq "\$SOND_PAYLOAD/bin/dnsmasq"' "$yml" && ok "ships bin/dnsmasq" \
		|| bad "ships bin/dnsmasq"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no man page, no translations)" || bad "ships nothing else ($n payload writes)"
	grep -qF "DVERSION='\\\"$VERSION\\\"'" "$yml" && ok "the version string is pinned, not read from git describe" \
		|| bad "the version string is pinned, not read from git describe"
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
        dests.add(dest or "share/licenses/dnsmasq/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("dnsmasq", "static", licence)]
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
	bad "dnsmasq-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-dnsmasq-fork: OK\n'
else
	printf 'test-dnsmasq-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
