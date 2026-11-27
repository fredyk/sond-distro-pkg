#!/bin/sh
# Real compile proof for the rsync recipe (the second step, not the offline shape check): install
# musl-tools, fetch the recipe's acl, attr and linux-headers dependencies from the registry, fetch
# the pinned rsync commit, run ci/forks/rsync-sond.yml's build: lines by hand against musl, and say
# what the binary is. POSIX: the Roubaix gate runs it with sh.
# usage: sh ./ci/rbx-build-rsync.sh
set -e
cd "$(dirname "$0")/.."
DISTRO=$(pwd)
apt-get update -qq
apt-get install -y -qq musl-tools gcc make file binutils git ca-certificates python3 \
	autoconf automake >/dev/null
work=$(mktemp -d)
sys="$work/sysroot"
log_key=072f2d42e0c81e0d075a50585e63bfbe74f2f8d65a0d6db2c1185f432d5a44e8
for dep in "acl 2.4.0" "attr 2.6.0" "linux-headers 6.12.77"; do
	set -- $dep
	python3 "$DISTRO/sondpkg/bin/sondpkg" fetch "$1" "$2" \
		--url https://dist.sond.dev --log-key "$log_key" --into "$sys" >/dev/null
done
mkdir -p "$work/rsync"
git -C "$work/rsync" init -q
git -C "$work/rsync" fetch -q --depth 1 https://github.com/RsyncProject/rsync 41bbd895668767e155b2eb6da64f37afa9cb8724
git -C "$work/rsync" checkout -q FETCH_HEAD
test "$(git -C "$work/rsync" rev-parse HEAD)" = 41bbd895668767e155b2eb6da64f37afa9cb8724
cd "$work/rsync"
SOND_CC=musl-gcc
SOND_CFLAGS="-isystem $sys/include -Os -pipe"
SOND_LDFLAGS="-L$sys/lib"
SOND_PAYLOAD="$work/payload"
export SOND_CC SOND_CFLAGS SOND_LDFLAGS SOND_PAYLOAD
mkdir -p "$SOND_PAYLOAD/bin"
./prepare-source build
./configure --disable-md2man --disable-openssl --disable-xxhash --disable-zstd \
  --disable-lz4 --disable-idn --disable-iconv --disable-locale --disable-roll-simd --disable-md5-asm \
  --with-included-zlib=yes --with-included-popt=yes \
  --enable-acl-support --enable-xattr-support \
  CC="$SOND_CC" CFLAGS="$SOND_CFLAGS" LDFLAGS="$SOND_LDFLAGS -static" LIBS="-lacl -lattr"
grep -q '^#define SUPPORT_ACLS 1' config.h
grep -q '^#define SUPPORT_XATTRS 1' config.h
make -j"$(nproc)" rsync
install -D -m 0755 rsync "$SOND_PAYLOAD/bin/rsync"
printf '=== file ===\n'
file "$SOND_PAYLOAD/bin/rsync"
printf '=== ldd ===\n'
ldd "$SOND_PAYLOAD/bin/rsync" 2>&1 || true
printf '=== version ===\n'
"$SOND_PAYLOAD/bin/rsync" --version | head -n1
