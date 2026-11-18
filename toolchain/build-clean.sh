#!/bin/bash
# One clean build of both binaries into a directory the caller owns: a fresh
# copy of each pinned tree, the same compiler, the same flags, the same
# SOURCE_DATE_EPOCH. This is the unit test-reproducible.sh runs twice.
#
# usage: build-clean.sh <DIR>
#
# Produces <DIR>/toybox/toybox and <DIR>/mksh/mksh (both stripped, mode 0755).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

R=${1:?usage: build-clean.sh <DIR>}
MGCC=$PREFIX/bin/musl-gcc

if [ ! -x "$MGCC" ]; then
	printf 'error: %s not found, run build-musl.sh first\n' "$MGCC" >&2
	exit 1
fi
if [ -e "$R/toybox" ] || [ -e "$R/mksh" ]; then
	printf 'error: %s already has a tree; a clean build needs an empty directory\n' "$R" >&2
	exit 1
fi

mkdir -p "$R/toybox" "$R/mksh"
tar -C "$SRC_ROOT/toybox-sond" --exclude='./.git' -cf - . | tar -C "$R/toybox" -xf -
tar -C "$SRC_ROOT/mksh-sond" --exclude='./.git' -cf - . | tar -C "$R/mksh" -xf -

# --- toybox ---------------------------------------------------------------
cd "$R/toybox"
make allnoconfig >/dev/null 2>&1
for sym in TOYBOX LS PS CAT CP MV RM MKDIR MOUNT ECHO GREP; do
	printf 'CONFIG_%s=y\n' "$sym" >>.config
done
make silentoldconfig >/dev/null 2>&1
make CC="$MGCC" \
	CFLAGS="$(repro_cflags "$PWD")" \
	LDFLAGS="-static $(repro_ldflags)" -j"$JOBS" >"$R/toybox-build.log" 2>&1
chmod u+w toybox
strip -s toybox
chmod 0755 toybox

# --- mksh -----------------------------------------------------------------
cd "$R/mksh"
CC="$MGCC" LDSTATIC=-static \
	CFLAGS="$(repro_cflags "$PWD")" \
	LDFLAGS="$(repro_ldflags)" \
	sh Build.sh -r >"$R/mksh-build.log" 2>&1
chmod u+w mksh
strip -s mksh
chmod 0755 mksh

printf 'built %s\n' "$R"
sha256sum "$R/toybox/toybox" "$R/mksh/mksh"
