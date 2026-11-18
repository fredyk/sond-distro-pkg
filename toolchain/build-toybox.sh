#!/bin/bash
# Build a static toybox, linked against the private musl, with the minimal
# configuration this area ships: CONFIG_TOYBOX plus exactly the ten utilities
# from $TOYBOX_COMMANDS. No sh: /bin/sh is mksh.
#
# usage: build-toybox.sh [SOURCE_TREE] [WORK_DIR]
#   SOURCE_TREE  fork checkout to build from (default: forks/src/toybox-sond)
#   WORK_DIR     directory this build owns (default: $WORK_ROOT/oneoff/toybox)
#
# Produces:
#   WORK_DIR/tree/toybox   the binary, stripped with the host strip
#   WORK_DIR/root/         install_flat layout: toybox plus one symlink per
#                          command, which is what the package payload copies.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC=${1:-$SRC_ROOT/toybox-sond}
WORK=${2:-$WORK_ROOT/oneoff/toybox}
TREE=$WORK/tree
ROOTDIR=$WORK/root
MUSL_GCC=$PREFIX/bin/musl-gcc

if [ ! -x "$MUSL_GCC" ]; then
	printf 'error: %s not found, run build-musl.sh first\n' "$MUSL_GCC" >&2
	exit 1
fi
if [ ! -f "$SRC/Makefile" ]; then
	printf 'error: toybox source tree not found at %s (run build-forks.sh)\n' "$SRC" >&2
	exit 1
fi

mkdir -p "$WORK"
if [ ! -f "$TREE/Makefile" ]; then
	mkdir -p "$TREE"
	tar -C "$SRC" --exclude='./.git' -cf - . | tar -C "$TREE" -xf -
fi

cd "$TREE"

# --- non-interactive minimal configuration --------------------------------
# allnoconfig turns every symbol off (except the ones without a prompt, which
# kconfig resolves from their default), then the ten required utilities are
# turned on explicitly and silentoldconfig folds them in. No menu, no tty.
if [ ! -f .config ]; then
	make allnoconfig
fi
for sym in TOYBOX LS PS CAT CP MV RM MKDIR MOUNT ECHO GREP; do
	grep -qx "CONFIG_$sym=y" .config || printf 'CONFIG_%s=y\n' "$sym" >>.config
done
make silentoldconfig

printf 'enabled symbols: %s\n' \
	"$(grep -E '^CONFIG_[A-Z0-9_]+=y$' .config | sed 's/^CONFIG_//;s/=y$//' | tr '\n' ' ')"

# --- build -----------------------------------------------------------------
# Same compiler, same flags, same argument order in every run. The absolute
# path of this tree is rewritten to "." so that two builds in two different
# directories produce the same bytes.
CFLAGS=$(repro_cflags "$TREE")
LDFLAGS="-static $(repro_ldflags)"

VERSION=$TOYBOX_TAG make \
	CC="$MUSL_GCC" \
	CFLAGS="$CFLAGS" \
	LDFLAGS="$LDFLAGS"

[ -f "$TREE/toybox" ] || { printf 'error: toybox was not built\n' >&2; exit 1; }

# toybox links itself 0555; strip still has to rewrite it, and the same strip
# command in every run keeps the published bytes independent of the host
# defaults.
chmod u+w toybox
strip -s toybox
chmod 0755 toybox

# The binary must expose exactly the ten commands and nothing else. This is
# the requirement test-static.sh re-checks on the published copy.
EXPECTED=$(printf '%s\n' $TOYBOX_COMMANDS | sort)
ACTUAL=$("$TREE/toybox" 2>/dev/null | tr ' \t' '\n' | sed '/^$/d' | sort -u)
if [ "$ACTUAL" != "$EXPECTED" ]; then
	printf 'error: built toybox exposes a different command set\n' >&2
	printf '  expected: %s\n' "$(echo "$EXPECTED" | tr '\n' ' ')" >&2
	printf '  actual:   %s\n' "$(echo "$ACTUAL" | tr '\n' ' ')" >&2
	exit 1
fi
printf 'toybox commands: %s\n' "$(echo "$EXPECTED" | tr '\n' ' ')"

make install_flat PREFIX="$ROOTDIR"
[ -f "$ROOTDIR/toybox" ] || { printf 'error: install_flat produced no toybox\n' >&2; exit 1; }

printf 'build-toybox: OK (%s)\n' "$TREE/toybox"
