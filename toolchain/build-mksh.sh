#!/bin/bash
# Build mksh R59 statically against the private musl. This binary is the
# distribution's /bin/sh.
#
# usage: build-mksh.sh [SOURCE_TREE] [WORK_DIR]
#   SOURCE_TREE  fork checkout to build from (default: forks/src/mksh-sond)
#   WORK_DIR     directory this build owns (default: $WORK_ROOT/oneoff/mksh)
#
# Produces: WORK_DIR/tree/mksh

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC=${1:-$SRC_ROOT/mksh-sond}
WORK=${2:-$WORK_ROOT/oneoff/mksh}
TREE=$WORK/tree
MUSL_GCC=$PREFIX/bin/musl-gcc

if [ ! -x "$MUSL_GCC" ]; then
	printf 'error: %s not found, run build-musl.sh first\n' "$MUSL_GCC" >&2
	exit 1
fi
if [ ! -f "$SRC/Build.sh" ]; then
	printf 'error: mksh source tree not found at %s (run build-forks.sh)\n' "$SRC" >&2
	exit 1
fi

mkdir -p "$WORK"
if [ ! -f "$TREE/Build.sh" ]; then
	mkdir -p "$TREE"
	tar -C "$SRC" --exclude='./.git' -cf - . | tar -C "$TREE" -xf -
fi

cd "$TREE"

# Build.sh honours LDSTATIC (Build.sh:636-639 folds it into LDFLAGS) and -r is
# release mode, which skips the man page and FAQ generation. CFLAGS carries the
# same reproducibility flags as the toybox build; the absolute path of this
# tree is rewritten to "." so two builds in two directories give the same
# bytes.
CC="$MUSL_GCC" \
CFLAGS=$(repro_cflags "$TREE") \
LDFLAGS="$(repro_ldflags)" \
LDSTATIC=-static \
	sh Build.sh -r

[ -f "$TREE/mksh" ] || { printf 'error: mksh was not built\n' >&2; exit 1; }

# Fixed strip, same command in every run, so the published bytes do not depend
# on whether the build happened to be stripped already.
chmod u+w mksh
strip -s mksh
chmod 0755 mksh

printf 'build-mksh: OK (%s)\n' "$TREE/mksh"
