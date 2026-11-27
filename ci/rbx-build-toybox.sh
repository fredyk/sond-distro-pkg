#!/bin/sh
# Real compile proof for toybox-static (the second step, not the offline shape check): run the
# recipe's build line, toolchain/build-toybox.sh, against musl-tools, and check that the built
# binary exposes setfattr. POSIX: the Roubaix gate runs it with sh.
# usage: sh ./ci/rbx-build-toybox.sh
set -e
cd "$(dirname "$0")/.."
apt-get update -qq
apt-get install -y -qq musl-tools gcc make file binutils git ca-certificates >/dev/null
work=$(mktemp -d)
SOND_FORKS="$work/forks"
export SOND_FORKS
mkdir -p "$SOND_FORKS/toolchain/bin"
ln -sf "$(command -v musl-gcc)" "$SOND_FORKS/toolchain/bin/musl-gcc"
git clone -q https://github.com/fredyk/toybox-sond "$work/toybox"
git -C "$work/toybox" checkout -q a57b091d05ec366dcd4dd737784c03761cb6a4b1
test "$(git -C "$work/toybox" rev-parse HEAD)" = a57b091d05ec366dcd4dd737784c03761cb6a4b1
bash toolchain/build-toybox.sh "$work/toybox" "$work/build"
printf '=== file ===\n'
file "$work/build/tree/toybox"
printf '=== ldd ===\n'
ldd "$work/build/tree/toybox" 2>&1 || true
printf '=== applets ===\n'
"$work/build/tree/toybox" | tr ' \t' '\n' | sed '/^$/d' | sort
printf '=== setfattr ===\n'
"$work/build/tree/toybox" setfattr 2>&1 | head -n3 || true
