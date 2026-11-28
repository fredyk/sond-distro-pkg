#!/bin/sh
# Build-line survival proof for the libffi recipe: runs the recipe's build: lines, byte for byte,
# with musl-gcc (musl-tools) as $SOND_CC, as sond-build-action's wrapper does, then links and
# runs a tiny consumer against lib/libffi.a. Upstream: the v3.5.2 tag the test pins.
set -e

export DEBIAN_FRONTEND=noninteractive
apt_install() { apt-get update -qq && apt-get install -y -qq "$@" >/dev/null; }
have() { command -v "$1" >/dev/null 2>&1; }
have python3 || apt_install python3
have git || apt_install git
have autoconf || apt_install autoconf automake libtool pkg-config make
have musl-gcc || apt_install musl-dev musl-tools

work=$(mktemp -d)
url=https://github.com/libffi/libffi
tag=v3.5.2
git clone -q --depth 1 --branch "$tag" "$url" "$work/src"

# linux-headers 6.12.77 (the recipe's depends: block): tramp.c includes <linux/limits.h>, so the
# headers must be reachable -isystem the way sond-build-action wires a recipe with depends.
# Installed before the exports, so $syscflags is final by then.
git clone -q --depth 1 --branch v6.12.77 https://github.com/fredyk/linux-headers-sond "$work/headers"
sysroot=$work/sysroot
echo "installing linux-headers into $sysroot"
(cd "$work/headers" && make ARCH=x86_64 prefix=/ DESTDIR="$sysroot" install)
test -e "$sysroot/include/linux/limits.h"
syscflags="-isystem $sysroot/include"

cd "$work/src"

export SOND_CC=/usr/bin/musl-gcc
export SOND_CFLAGS="-Os -pipe -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=. $syscflags"
export SOND_LDFLAGS="-Wl,--build-id=none"
export SOURCE_DATE_EPOCH=1794960000
payload=$work/payload
export SOND_PAYLOAD=$payload
mkdir -p "$SOND_PAYLOAD"

# The recipe's build: block, from the tree this run ships.
python3 - "$OLDPWD/ci/forks/libffi-sond.yml" "$work/build.sh" <<'PY'
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

# -euo pipefail, as sond-build-action runs the build: block: a failing line stops the build.
bash -euo pipefail "$work/build.sh"
echo "build: lines done"

# A consumer links and runs against lib/libffi.a: the recipe lines survived musl.
cat > "$work/consumer.c" <<'EOF'
#include <ffi.h>
#include <stdio.h>
int main(void)
{
	printf("ffi_type_sint64 size=%zu\n", ffi_type_sint64.size);
	return ffi_type_sint64.size == sizeof(long long) ? 0 : 1;
}
EOF
musl-gcc -Os -static -I "$SOND_PAYLOAD/include" -o "$work/consumer" "$work/consumer.c" \
	"$SOND_PAYLOAD/lib/libffi.a"
"$work/consumer"
echo "rbx-libffi-build: OK"
