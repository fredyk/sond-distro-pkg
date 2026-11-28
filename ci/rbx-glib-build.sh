#!/bin/sh
# Build-line survival proof for the glib recipe: it installs the depends' sysroot first (zlib
# 1.3.2, pcre2 10.49, libffi 3.5.2 and linux-headers 6.12.77, the build lines of the sibling
# fork recipes, adapted only so SOND_PAYLOAD is the shared sysroot), then runs the glib recipe's
# build: lines, byte for byte, with musl-gcc (musl-tools) as $SOND_CC, then links a consumer
# with pkg-config --static the way sond-build-action's build.cfg does against the sysroot.
set -e
here=$(cd "$(dirname "$0")" && pwd)

export DEBIAN_FRONTEND=noninteractive
apt_install() { apt-get update -qq && apt-get install -y -qq "$@" >/dev/null; }
have() { command -v "$1" >/dev/null 2>&1; }
have python3 || apt_install python3
have git || apt_install git
have meson || apt_install meson python3-packaging pkg-config
have ninja || apt_install ninja-build
have cmake || apt_install cmake
have autoconf || apt_install autoconf automake libtool make gcc
have musl-gcc || apt_install musl-dev musl-tools
have gcc || apt_install gcc

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
sysroot=$work/sysroot
mkdir -p "$sysroot"

export SOND_CC=/usr/bin/musl-gcc
base_cflags="-Os -pipe"
base_ldflags="-Wl,--build-id=none"
export SOURCE_DATE_EPOCH=1794960000

# The dep blocks below repeat the build lines of the zlib, pcre2 and libffi fork recipes (and
# linux-headers from toolchain/common.sh) at the versions the glib recipe's depends: names, with
# SOND_PAYLOAD on the shared sysroot. A change to one of those recipes is mirrored here.

# linux-headers 6.12.77 (toolchain/common.sh): headers only, installed first, so the dep builds
# that include kernel headers (libffi's tramp.c includes <linux/limits.h>) resolve them from the
# sysroot, the way sond-build-action's -isystem does for a recipe with depends: linux-headers.
git clone -q --depth 1 --branch v6.12.77 https://github.com/fredyk/linux-headers-sond "$work/headers"
cd "$work/headers"
make ARCH=x86_64 prefix=/ DESTDIR="$sysroot" install
test -e "$sysroot/include/linux/virtio_blk.h"
syscflags="$base_cflags -isystem $sysroot/include"

# zlib 1.3.2: gio's gzlibcompressor.c includes <zlib.h>; the sysroot carries the pinned one.
git clone -q --depth 1 --branch v1.3.2 https://github.com/madler/zlib "$work/zlib"
cd "$work/zlib"
export SOND_CFLAGS="$base_cflags -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=."
export SOND_LDFLAGS=$base_ldflags
export SOND_PAYLOAD=$sysroot
CC="$SOND_CC" CFLAGS="$SOND_CFLAGS" LDFLAGS="$SOND_LDFLAGS -static" \
	./configure --prefix=/ --static
make -j"$(nproc)" libz.a
install -D -m 0644 libz.a "$SOND_PAYLOAD/lib/libz.a"
install -D -m 0644 zlib.h "$SOND_PAYLOAD/include/zlib.h"
install -D -m 0644 zconf.h "$SOND_PAYLOAD/include/zconf.h"
install -D -m 0644 zlib.pc "$SOND_PAYLOAD/lib/pkgconfig/zlib.pc"

# pcre2 10.49: the pcre2 recipe's build block, 8-bit only, no JIT.
git clone -q --depth 1 --branch pcre2-10.49 https://github.com/PCRE2Project/pcre2 "$work/pcre2"
cd "$work/pcre2"
export SOND_CFLAGS="$base_cflags -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=."
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ \
	-DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_COMPILER="$SOND_CC" \
	-DCMAKE_C_FLAGS="$SOND_CFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$SOND_LDFLAGS -static" \
	-DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
	-DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF \
	-DPCRE2_SUPPORT_JIT=OFF -DPCRE2_SUPPORT_UNICODE=ON \
	-DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF
cmake --build build -j"$(nproc)"
install -D -m 0644 build/libpcre2-8.a "$SOND_PAYLOAD/lib/libpcre2-8.a"
install -D -m 0644 build/interface/pcre2.h "$SOND_PAYLOAD/include/pcre2.h"
install -D -m 0644 build/libpcre2-8.pc "$SOND_PAYLOAD/lib/pkgconfig/libpcre2-8.pc"

# libffi 3.5.2: the libffi recipe's build block, configure generated from the checkout, with
# the kernel headers reachable (-isystem), as its recipe's depends: linux-headers gives.
git clone -q --depth 1 --branch v3.5.2 https://github.com/libffi/libffi "$work/libffi"
cd "$work/libffi"
export SOND_CFLAGS="$base_cflags -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=. -isystem $sysroot/include"
./autogen.sh
./configure --prefix=/ --disable-shared --enable-static --disable-docs \
	--disable-multi-os-directory --disable-builddir \
	CC="$SOND_CC" CFLAGS="$SOND_CFLAGS" LDFLAGS="$SOND_LDFLAGS -static"
make -j"$(nproc)" libffi.la
make DESTDIR="$SOND_PAYLOAD" install-toolexeclibLTLIBRARIES install-pkgconfigDATA
make -C include DESTDIR="$SOND_PAYLOAD" install-nodist_includeHEADERS
rm -f "$SOND_PAYLOAD"/lib/*.la

# Now glib itself: the exact recipe build: block, from this tree, with the sond-build-action
# environment: the sysroot behind -isystem/-L and pkg-config, as the action wires it.
export SOND_LDFLAGS="$base_ldflags -L$sysroot/lib"
export PKG_CONFIG_LIBDIR=$sysroot/lib/pkgconfig PKG_CONFIG_SYSROOT_DIR=$sysroot
export SOND_PAYLOAD=$work/payload-glib
mkdir -p "$SOND_PAYLOAD"
python3 - "$repo/ci/forks/glib-sond.yml" "$work/build.sh" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
i = next(n for n, l in enumerate(lines) if l.strip() == "- id: build")
i = next(n for n in range(i, len(lines)) if lines[n].strip() == "with:")
indent = len(lines[i + 1]) - len(lines[i + 1].lstrip())
n = i + 1
out, mode = [], None
while n < len(lines):
    s = lines[n].strip()
    ind = len(lines[n]) - len(lines[n].lstrip())
    if not s:
        if mode == "block":
            out.append("")
        n += 1
        continue
    if ind < indent:
        break
    if mode is None:
        if s == "build: |":
            mode, out = "block", []
    else:
        out.append(lines[n][indent + 2:])
    n += 1
if mode != "block":
    sys.exit("build: | not found")
open(sys.argv[2], "w").write("\n".join(out).rstrip("\n") + "\n")
PY
git clone -q --depth 1 --branch 2.86.5 https://github.com/GNOME/glib "$work/glib"
cd "$work/glib"
export SOND_CFLAGS="$base_cflags -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=. -isystem $sysroot/include"
# -euo pipefail, as sond-build-action runs the build: block: a failing line stops the build.
bash -euo pipefail "$work/build.sh"
echo "glib build: lines done"

# The payload:
test -f "$SOND_PAYLOAD/lib/libglib-2.0.a"
test -f "$SOND_PAYLOAD/lib/libgthread-2.0.a"
test -f "$SOND_PAYLOAD/lib/libgmodule-2.0.a"
test -f "$SOND_PAYLOAD/lib/pkgconfig/glib-2.0.pc"
test -f "$SOND_PAYLOAD/lib/pkgconfig/gthread-2.0.pc"
test -f "$SOND_PAYLOAD/lib/pkgconfig/gmodule-no-export-2.0.pc"
test -f "$SOND_PAYLOAD/lib/glib-2.0/include/glibconfig.h"
# gio, gobject and girepository by their install paths (glib's own giochannel.h stays).
leftover='/lib/(libgio|libgobject|libgirepository)-2\.0\.a$|/pkgconfig/(gio|gio-unix|gobject|girepository)-2\.0\.pc$|/include/glib-2\.0/(gio|gobject|girepository)(/|$)|/include/gio-unix-2\.0(/|$)|/lib/gio(/|$)|/glib-object\.h$'
if find "$SOND_PAYLOAD" | grep -qE "$leftover"; then
	echo "gio, gobject or girepository inside the payload:"; find "$SOND_PAYLOAD" | grep -E "$leftover"; exit 1
fi
echo "glib payload: only its own product"

# A consumer's sysroot: the glib payload unpacked over its depends, as a package that depends on
# glib gets them. glib-2.0.pc Requires.private is libpcre2-8 (measured on the 2.86 tree), so the
# static link needs libpcre2-8.a from the sysroot; gio, gobject and girepository are out: nothing
# pulls libffi.
cp -a "$SOND_PAYLOAD/." "$sysroot/"
pc() { PKG_CONFIG_LIBDIR=$sysroot/lib/pkgconfig PKG_CONFIG_SYSROOT_DIR=$sysroot pkg-config --static "$@"; }
cflags=$(pc --cflags glib-2.0)
libs=$(pc --libs glib-2.0)
flags="$cflags $libs"
echo "consumer link flags: $flags"
case $flags in
*-lgobject-2.0* | *lgobject* | *-lffi*) echo "glib-2.0 pulled gobject/ffi" >&2; exit 1 ;;
esac

# A tiny consumer: the compile the static qemu does, with the same flags.
cat > "$work/consumer.c" <<'EOF'
#include <glib.h>
#include <stdio.h>
int main(void)
{
	const char *e = glib_check_version(GLIB_MAJOR_VERSION, GLIB_MINOR_VERSION, 0);
	printf("glib %u.%u.%u mismatch=%s\n", GLIB_MAJOR_VERSION, GLIB_MINOR_VERSION,
	       GLIB_MICRO_VERSION, e ? e : "none");
	return e ? 1 : 0;
}
EOF
# shellcheck disable=SC2086
musl-gcc -Os -static $cflags -o "$work/consumer" "$work/consumer.c" $libs
"$work/consumer"
echo "rbx-glib-build: OK"
