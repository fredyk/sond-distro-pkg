#!/bin/sh
# Real compile proof for the tar recipe (the second step, not the offline shape check): install
# musl-tools, fetch the pinned release tarball, run ci/forks/tar-sond.yml's build: lines by hand
# against musl, and say what the binary is. POSIX: the Roubaix gate runs it with sh.
# usage: sh ./ci/rbx-build-tar.sh
set -e
cd "$(dirname "$0")/.."
apt-get update -qq
apt-get install -y -qq musl-tools gcc make file binutils curl ca-certificates xz-utils gzip coreutils findutils >/dev/null
work=$(mktemp -d)
curl -fsSL --retry 3 -o "$work/tar-1.35.tar.xz" https://ftp.gnu.org/gnu/tar/tar-1.35.tar.xz
printf '4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16  %s\n' "$work/tar-1.35.tar.xz" | sha256sum -c -
tar -xJf "$work/tar-1.35.tar.xz" -C "$work"
cd "$work/tar-1.35"
SOND_CC=musl-gcc
SOND_CFLAGS="-Os -pipe"
SOND_LDFLAGS=""
SOND_PAYLOAD="$work/payload"
export SOND_CC SOND_CFLAGS SOND_LDFLAGS SOND_PAYLOAD
mkdir -p "$SOND_PAYLOAD/bin"
find . -path ./.git -prune -o -type f -exec touch -r configure {} +
FORCE_UNSAFE_CONFIGURE=1 CC="$SOND_CC" CFLAGS="$SOND_CFLAGS" LDFLAGS="$SOND_LDFLAGS -static" \
  ./configure --disable-nls --disable-rpath --enable-xattrs --without-selinux \
  --without-posix-acls --with-rmt=/nonexistent/rmt --disable-gcc-warnings \
  DEFAULT_RMT_DIR=/nonexistent
make -j "$(nproc)" -C gnu
make -j "$(nproc)" -C lib
make -j "$(nproc)" -C src tar
install -D -m 0755 src/tar "$SOND_PAYLOAD/bin/tar"
printf '=== file ===\n'
file "$SOND_PAYLOAD/bin/tar"
printf '=== ldd ===\n'
ldd "$SOND_PAYLOAD/bin/tar" 2>&1 || true
printf '=== version ===\n'
"$SOND_PAYLOAD/bin/tar" --version | head -n1
