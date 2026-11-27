#!/bin/bash
# Shape checks for the nftables fork recipe: the nft command alone, static against the pinned musl
# with libmnl and libnftnl built in-job from pinned tarballs. dockerd 29.10.1 built static runs
# its nftables firewall backend by exec'ing nft from PATH (moby docker-v29.10.1
# daemon/libnetwork/internal/nftables/nft_exec_linux.go:1,23-30, build tag !cgo || static_build),
# so bin/nft is the whole payload. Offline: no network, no build.
#
# usage: ci/test-nftables-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from git.netfilter.org (git ls-remote --tags).
VERSION=1.1.7
UPSTREAM=git.netfilter.org/nftables@4af22fb3bef5f1672878fd7ee373947c36d33dbd

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
check nftables nftables "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/nftables-sond.yml
if [ -f "$yml" ]; then
	grep -qF 'license: GPL-2.0-only AND GPL-2.0-or-later AND LGPL-2.1-or-later' "$yml" \
		&& ok "license names nftables, libnftnl and libmnl" || bad "license names nftables, libnftnl and libmnl"
	grep -qF 'libmnl-1.0.5' "$yml" && ok "libmnl pinned at 1.0.5" || bad "libmnl pinned at 1.0.5"
	grep -qF 'libnftnl-1.3.2' "$yml" && ok "libnftnl pinned at 1.3.2" || bad "libnftnl pinned at 1.3.2"
	# libmnl/libnftnl and nftables include linux/types.h, linux/netlink.h and the netfilter UAPI
	# headers: the pinned kernel headers, not the runner's.
	grep -qE '^\s+linux-headers 6\.12\.77$' "$yml" && ok "depends on linux-headers 6.12.77" \
		|| bad "depends on linux-headers 6.12.77"
	n=$(grep -cE 'sha256sum -c' "$yml" || true)
	[ "$n" -ge 2 ] && ok "both library tarballs are hash-checked" || bad "both library tarballs are hash-checked ($n)"
	for opt in --disable-shared --enable-static --with-mini-gmp --without-cli --without-xtables --without-json; do
		grep -qF -- "$opt" "$yml" && ok "configure $opt" || bad "configure $opt"
	done
	grep -qF -- '-all-static' "$yml" && ok "nft is linked fully static" || bad "nft is linked fully static"
	grep -qE 'install -D -m 0755 src/nft "\$SOND_PAYLOAD/bin/nft"' "$yml" && ok "ships bin/nft" || bad "ships bin/nft"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else" || bad "ships nothing else ($n payload writes)"
	grep -qF 'source-bundle:' "$yml" && ok "publishes its corresponding source" || bad "publishes its corresponding source"
	rc=0
	python3 "$DISTRO/sondpkg/bin/sondpkg" needs-source "GPL-2.0-only AND GPL-2.0-or-later AND LGPL-2.1-or-later" >/dev/null || rc=$?
	[ "$rc" = 0 ] && ok "sondpkg needs-source is 0" || bad "sondpkg needs-source is 0 (rc=$rc)"
else
	bad "nftables-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-nftables-fork: OK\n'
else
	printf 'test-nftables-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
