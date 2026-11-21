#!/bin/bash
# Build musl 1.2.5 from its fork's pinned tree into a private prefix, with no root.
#
# usage: build-musl.sh
#
# The tree is a fresh copy of the commit pinned in common.sh, taken from the
# fork clone build-forks.sh made (never a working tree that may hold other
# files); musl is configured with --prefix=$PREFIX, --disable-shared and --enable-wrapper=gcc (auto mode may skip musl-gcc).
# The result is proven before the script exits: musl-gcc must exist, a hello.c
# compiled with it must be statically linked, and the binary must run on this
# host.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FORK=$SRC_ROOT/musl-sond
SRC=$WORK_ROOT/src/musl-1.2.5
MUSL_GCC=$PREFIX/bin/musl-gcc

if ! git -C "$FORK" cat-file -e "$MUSL_COMMIT^{commit}" 2>/dev/null; then
	printf 'error: %s has no commit %s, run build-forks.sh first\n' "$FORK" "$MUSL_COMMIT" >&2
	exit 1
fi
rm -rf -- "$SRC"
mkdir -p "$SRC"
git -C "$FORK" archive "$MUSL_COMMIT" | tar -x -C "$SRC"

printf 'configuring musl with --prefix=%s --disable-shared --enable-wrapper=gcc\n' "$PREFIX"
(cd "$SRC" && ./configure --prefix="$PREFIX" --disable-shared --enable-wrapper=gcc)

printf 'building musl with -j%s\n' "$JOBS"
make -C "$SRC" -j"$JOBS"
make -C "$SRC" install

if [ ! -x "$MUSL_GCC" ]; then
	printf 'error: %s was not installed\n' "$MUSL_GCC" >&2
	exit 1
fi

# Smoke test: a static hello.c built by the private musl-gcc, run on the host.
SMOKE=$WORK_ROOT/musl-smoke
mkdir -p "$SMOKE"
cat >"$SMOKE/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("musl-static-ok"); return 0; }
EOF
"$MUSL_GCC" -static -O2 -o "$SMOKE/hello" "$SMOKE/hello.c"

DESC=$(file -b "$SMOKE/hello")
case $DESC in
*"statically linked"*) printf 'hello: %s\n' "$DESC" ;;
*)
	printf 'error: musl-gcc did not produce a static binary: %s\n' "$DESC" >&2
	exit 1
	;;
esac

OUT=$("$SMOKE/hello")
if [ "$OUT" != "musl-static-ok" ]; then
	printf 'error: static hello printed %q\n' "$OUT" >&2
	exit 1
fi
printf 'static hello runs on the host: %s\n' "$OUT"

printf 'build-musl: OK (prefix=%s)\n' "$PREFIX"
