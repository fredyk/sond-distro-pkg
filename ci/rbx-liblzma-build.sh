#!/bin/sh
# Build-line survival proof for the liblzma recipe: runs the recipe's build: lines, byte for
# byte, with musl-gcc (musl-tools) as $SOND_CC, as sond-build-action's wrapper does, then links
# and runs a tiny consumer against lib/liblzma.a. Upstream: the v5.8.4 tag the test pins.
set -e

export DEBIAN_FRONTEND=noninteractive
apt_install() { apt-get update -qq && apt-get install -y -qq "$@" >/dev/null; }
have() { command -v "$1" >/dev/null 2>&1; }
have python3 || apt_install python3
have git || apt_install git
have cmake || apt_install cmake
have musl-gcc || apt_install musl-dev musl-tools
have gcc || apt_install gcc

work=$(mktemp -d)
url=https://github.com/tukaani-project/xz
tag=v5.8.4
git clone -q --depth 1 --branch "$tag" "$url" "$work/src"
cd "$work/src"

export SOND_CC=/usr/bin/musl-gcc
export SOND_CFLAGS="-Os -pipe -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=."
export SOND_LDFLAGS="-Wl,--build-id=none"
export SOURCE_DATE_EPOCH=1794960000
payload=$work/payload
export SOND_PAYLOAD=$payload
mkdir -p "$SOND_PAYLOAD"

# The recipe's build: block, from the tree this run ships.
python3 - "$OLDPWD/ci/forks/liblzma-sond.yml" "$work/build.sh" <<'PY'
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

# A tiny consumer links and runs against lib/liblzma.a: the recipe lines survived musl.
cat > "$work/consumer.c" <<'EOF'
#include <lzma.h>
#include <stdio.h>
int main(void)
{
	printf("%s\n", lzma_version_string());
	return 0;
}
EOF
musl-gcc -Os -static -I "$SOND_PAYLOAD/include" -o "$work/consumer" "$work/consumer.c" \
	"$SOND_PAYLOAD/lib/liblzma.a"
rc=0
out=$("$work/consumer") || rc=$?
[ "$rc" = 0 ] || { echo "consumer rc=$rc" >&2; exit 1; }
echo "liblzma consumer: $out"
case $out in
5.8.4*) ;;
*) echo "consumer output does not carry the pinned version: $out" >&2; exit 1 ;;
esac
echo "rbx-liblzma-build: OK"
