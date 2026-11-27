#!/bin/sh
# Real compile proof for the iproute2 recipe (the second step, not the offline shape check):
# install musl-tools and the kernel UAPI headers, fetch the upstream commit the recipe pins, run
# ci/forks/iproute2-sond.yml's build: lines by hand against musl, and say what the binary is.
# POSIX: the Roubaix gate runs it with sh.
# usage: sh ./ci/rbx-build-iproute2.sh
set -e
cd "$(dirname "$0")/.."
DISTRO=$(pwd)
apt-get update -qq
apt-get install -y -qq musl-tools gcc make file binutils git ca-certificates python3 \
	linux-libc-dev bison flex pkg-config >/dev/null
work=$(mktemp -d)
# The recipe depends on linux-headers 6.12.77: its include/asm/ is what iproute2's uapi headers
# need, and musl-gcc does not see the host's /usr/include/<triplet>/asm/. Fetch it as build.sh does.
sys="$work/sysroot"
python3 "$DISTRO/sondpkg/bin/sondpkg" fetch linux-headers 6.12.77 \
	--url https://dist.sond.dev \
	--log-key 072f2d42e0c81e0d075a50585e63bfbe74f2f8d65a0d6db2c1185f432d5a44e8 \
	--into "$sys"
git clone -q https://github.com/iproute2/iproute2 "$work/iproute2"
git -C "$work/iproute2" checkout -q 19d1276f766daa458fb55096edb38818a7d19606
test "$(git -C "$work/iproute2" rev-parse HEAD)" = 19d1276f766daa458fb55096edb38818a7d19606
cd "$work/iproute2"
SOND_CC=musl-gcc
SOND_CFLAGS="-isystem $sys/include -Os -pipe"
SOND_LDFLAGS=""
SOND_PAYLOAD="$work/payload"
export SOND_CC SOND_CFLAGS SOND_LDFLAGS SOND_PAYLOAD
mkdir -p "$SOND_PAYLOAD/bin"
CC="$SOND_CC" PKG_CONFIG=false ./configure --libbpf_force off
grep -q '^HAVE_MNL' config.mk && exit 1
grep -q '^HAVE_ELF' config.mk && exit 1
grep -q '^HAVE_LIBBPF' config.mk && exit 1
grep -q '^HAVE_SELINUX' config.mk && exit 1
grep -q '^HAVE_CAP' config.mk && exit 1
CFLAGS="$SOND_CFLAGS" LDFLAGS="$SOND_LDFLAGS -static" make SHARED_LIBS=n CC="$SOND_CC" SUBDIRS="lib ip"
install -D -m 0755 ip/ip "$SOND_PAYLOAD/bin/ip"
printf '=== file ===\n'
file "$SOND_PAYLOAD/bin/ip"
printf '=== ldd ===\n'
ldd "$SOND_PAYLOAD/bin/ip" 2>&1 || true
printf '=== version ===\n'
"$SOND_PAYLOAD/bin/ip" -V | head -n1
