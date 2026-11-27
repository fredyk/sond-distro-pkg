#!/bin/sh
# Real compile proof for the nftables recipe (the second step, not the offline shape check):
# install musl-tools and autotools, fetch the hash-checked libmnl/libnftnl tarballs, build them
# statically, fetch the nftables v1.1.7 tag, run ci/forks/nftables-sond.yml's build: lines by
# hand, and say what the binary is. POSIX: the Roubaix gate runs it with sh.
# usage: sh ./ci/rbx-build-nftables.sh
set -e
cd "$(dirname "$0")/.."
DISTRO=$(pwd)
apt-get update -qq
apt-get install -y -qq musl-tools gcc make file binutils git ca-certificates curl python3 \
	autoconf automake libtool pkg-config bison flex xz-utils bzip2 m4 >/dev/null
work=$(mktemp -d)
# libmnl, libnftnl and nftables include linux/types.h, linux/netlink.h and the netfilter UAPI
# headers: the recipe depends on linux-headers 6.12.77, fetched as build.sh does.
sys="$work/sysroot"
python3 "$DISTRO/sondpkg/bin/sondpkg" fetch linux-headers 6.12.77 \
	--url https://dist.sond.dev \
	--log-key 072f2d42e0c81e0d075a50585e63bfbe74f2f8d65a0d6db2c1185f432d5a44e8 \
	--into "$sys"
deps="$work/deps"
mkdir -p "$deps/src" "$work/nftables"
cd "$deps/src"
curl -fsSL --retry 3 -O https://www.netfilter.org/projects/libmnl/files/libmnl-1.0.5.tar.bz2
curl -fsSL --retry 3 -O https://www.netfilter.org/projects/libnftnl/files/libnftnl-1.3.2.tar.xz
printf '274b9b919ef3152bfb3da3a13c950dd60d6e2bcd54230ffeca298d03b40d0525  libmnl-1.0.5.tar.bz2\n' | sha256sum -c -
printf 'c97abc3409f8fa396b4462b2bb7f147a3a47a4ddc97cfa0b2f18890c9cfde8b0  libnftnl-1.3.2.tar.xz\n' | sha256sum -c -
tar -xjf libmnl-1.0.5.tar.bz2
tar -xJf libnftnl-1.3.2.tar.xz
export CC=musl-gcc CFLAGS="-isystem $sys/include -Os -pipe" LDFLAGS=""
export PKG_CONFIG_PATH="$deps/lib/pkgconfig" PKG_CONFIG="pkg-config --static"
(cd libmnl-1.0.5 && ./configure --prefix="$deps" --disable-shared --enable-static && make -j"$(nproc)" install)
(cd libnftnl-1.3.2 && ./configure --prefix="$deps" --disable-shared --enable-static && make -j"$(nproc)" install)
git -C "$work/nftables" init -q
git -C "$work/nftables" fetch -q --depth 1 https://git.netfilter.org/nftables tag v1.1.7
git -C "$work/nftables" checkout -q FETCH_HEAD
cd "$work/nftables"
./autogen.sh
./configure --disable-shared --enable-static --with-mini-gmp --without-cli \
  --without-xtables --without-json --disable-man-doc --disable-python
make -j"$(nproc)" LDFLAGS="-all-static"
mkdir -p "$work/payload/bin"
install -D -m 0755 src/nft "$work/payload/bin/nft"
printf '=== file ===\n'
file "$work/payload/bin/nft"
printf '=== ldd ===\n'
ldd "$work/payload/bin/nft" 2>&1 || true
printf '=== version ===\n'
"$work/payload/bin/nft" --version | head -n1
