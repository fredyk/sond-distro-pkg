#!/bin/bash
# Build musl 1.2.5 from its release tarball into a private prefix, with no root.
#
# usage: build-musl.sh
#
# The tarball is downloaded once into $WORK_ROOT, its sha256 is checked against
# the pinned value in common.sh, and musl is configured with --prefix=$PREFIX
# and --disable-shared. The result is proven before the script exits: musl-gcc
# must exist, a hello.c compiled with it must be statically linked, and the
# binary must run on this host.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARBALL=$WORK_ROOT/$MUSL_TARBALL
SRC=$WORK_ROOT/src/musl-1.2.5
MUSL_GCC=$PREFIX/bin/musl-gcc

mkdir -p "$WORK_ROOT/src"

if [ ! -f "$TARBALL" ]; then
	printf 'downloading %s\n' "$MUSL_URL"
	curl -fsSL -o "$TARBALL" "$MUSL_URL"
fi

HAVE=$(sha256sum "$TARBALL" | cut -d' ' -f1)
if [ "$HAVE" != "$MUSL_TARBALL_SHA256" ]; then
	printf 'error: %s has sha256 %s, expected %s\n' \
		"$TARBALL" "$HAVE" "$MUSL_TARBALL_SHA256" >&2
	exit 1
fi

if [ ! -f "$SRC/configure" ]; then
	tar -xzf "$TARBALL" -C "$WORK_ROOT/src"
fi

printf 'configuring musl with --prefix=%s --disable-shared\n' "$PREFIX"
(cd "$SRC" && ./configure --prefix="$PREFIX" --disable-shared)

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
