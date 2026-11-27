#!/bin/sh
# Real compile proof for the dnsmasq recipe (the second step, not the offline shape check):
# install musl-tools, fetch the v2.93 tag the recipe pins, verify COPYING, run
# ci/forks/dnsmasq-sond.yml's build: lines by hand against musl, and say what the binary is.
# POSIX: the Roubaix gate runs it with sh.
# usage: sh ./ci/rbx-build-dnsmasq.sh
set -e
cd "$(dirname "$0")/.."
DISTRO=$(pwd)
apt-get update -qq
apt-get install -y -qq musl-tools gcc make file binutils git ca-certificates python3 >/dev/null
work=$(mktemp -d)
# dnsmasq.h includes linux/version.h and five more linux/* headers: the recipe depends on
# linux-headers 6.12.77, so fetch it into a sysroot the way build.sh does.
sys="$work/sysroot"
python3 "$DISTRO/sondpkg/bin/sondpkg" fetch linux-headers 6.12.77 \
	--url https://dist.sond.dev \
	--log-key 072f2d42e0c81e0d075a50585e63bfbe74f2f8d65a0d6db2c1185f432d5a44e8 \
	--into "$sys"
git clone -q --depth 1 --branch v2.93 https://thekelleys.org.uk/git/dnsmasq.git "$work/dnsmasq"
test "$(git -C "$work/dnsmasq" rev-parse HEAD)" = 3ff66da573a77c8783deca10ec8c6bba07cd85e6
cd "$work/dnsmasq"
printf '8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643  COPYING\n' | sha256sum -c -
SOND_CC=musl-gcc
SOND_CFLAGS="-isystem $sys/include -Os -pipe"
SOND_LDFLAGS=""
SOND_PAYLOAD="$work/payload"
export SOND_CC SOND_CFLAGS SOND_LDFLAGS SOND_PAYLOAD
mkdir -p "$SOND_PAYLOAD/bin"
make CC="$SOND_CC" CFLAGS="$SOND_CFLAGS" LDFLAGS="$SOND_LDFLAGS -static" \
  COPTS="-DNO_TFTP -DNO_SCRIPT -DNO_IPSET -DNO_AUTH" \
  "version=-DVERSION='\\\"2.93\\\"'" all
install -D -m 0755 src/dnsmasq "$SOND_PAYLOAD/bin/dnsmasq"
printf '=== file ===\n'
file "$SOND_PAYLOAD/bin/dnsmasq"
printf '=== ldd ===\n'
ldd "$SOND_PAYLOAD/bin/dnsmasq" 2>&1 || true
printf '=== version ===\n'
"$SOND_PAYLOAD/bin/dnsmasq" --version | head -n1
