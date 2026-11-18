#!/bin/bash
# Gate 1 of 2, and the gate the RFC-0018 reproducibility requirement rests on:
# two clean builds of toybox and mksh, in two different directories, with the
# same SOURCE_DATE_EPOCH, must produce the same sha256.
#
# Exit 0 only when both hashes of a pair are identical. The two sha256 lines
# are always printed so they can be copied into the delivery.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ ! -x "$PREFIX/bin/musl-gcc" ]; then
	printf 'musl prefix missing, running build-musl.sh\n'
	bash "$HERE/build-musl.sh"
fi

# One fresh directory per run per build tree: a clean build means a tree that
# has never been compiled into, and this script must stay idempotent without
# deleting anything. build-a/ and build-b/ are the two different roots.
mkdir -p "$BUILD_A" "$BUILD_B"
RUN_A=$(mktemp -d "$BUILD_A/run.XXXXXX")
RUN_B=$(mktemp -d "$BUILD_B/run.XXXXXX")

printf 'SOURCE_DATE_EPOCH=%s\n' "$SOURCE_DATE_EPOCH"
printf 'build A: %s\n' "$RUN_A"
printf 'build B: %s\n' "$RUN_B"

bash "$HERE/build-clean.sh" "$RUN_A"
bash "$HERE/build-clean.sh" "$RUN_B"

# --- hashes ----------------------------------------------------------------
A_TOY=$(sha256sum "$RUN_A/toybox/toybox" | cut -d' ' -f1)
A_MKS=$(sha256sum "$RUN_A/mksh/mksh" | cut -d' ' -f1)
B_TOY=$(sha256sum "$RUN_B/toybox/toybox" | cut -d' ' -f1)
B_MKS=$(sha256sum "$RUN_B/mksh/mksh" | cut -d' ' -f1)

REPRO_DIR=$ARTIFACTS/repro
mkdir -p "$REPRO_DIR"
printf '%s  toybox\n%s  mksh\n' "$A_TOY" "$A_MKS" >"$REPRO_DIR/build-a.sha256"
printf '%s  toybox\n%s  mksh\n' "$B_TOY" "$B_MKS" >"$REPRO_DIR/build-b.sha256"

printf -- '---\n'
printf 'build-a toybox %s\n' "$A_TOY"
printf 'build-a mksh   %s\n' "$A_MKS"
printf 'build-b toybox %s\n' "$B_TOY"
printf 'build-b mksh   %s\n' "$B_MKS"
printf -- '---\n'

RC=0
if [ "$A_TOY" = "$B_TOY" ]; then
	printf 'REPRODUCIBLE toybox\n'
else
	printf 'NOT REPRODUCIBLE toybox: %s vs %s\n' "$A_TOY" "$B_TOY"
	RC=1
fi
if [ "$A_MKS" = "$B_MKS" ]; then
	printf 'REPRODUCIBLE mksh\n'
else
	printf 'NOT REPRODUCIBLE mksh: %s vs %s\n' "$A_MKS" "$B_MKS"
	RC=1
fi

# When a pair diverges, show where the bytes differ so the cause is measured
# rather than guessed.
if [ "$RC" -ne 0 ]; then
	for PAIR in "toybox $RUN_A/toybox/toybox $RUN_B/toybox/toybox" \
		"mksh $RUN_A/mksh/mksh $RUN_B/mksh/mksh"; do
		set -- $PAIR
		NAME=$1 X=$2 Y=$3
		[ "$(sha256sum "$X" | cut -d' ' -f1)" = "$(sha256sum "$Y" | cut -d' ' -f1)" ] && continue
		printf -- '--- %s: first differing bytes (cmp -l) ---\n' "$NAME"
		cmp -l "$X" "$Y" 2>/dev/null | head -20 || true
		printf -- '--- %s: build paths present in the binary ---\n' "$NAME"
		strings "$X" 2>/dev/null | grep -F -m5 "$(basename "$(dirname "$(dirname "$X")")")" || true
	done
fi

printf 'test-reproducible: %s\n' "$([ "$RC" -eq 0 ] && echo PASS || echo FAIL)"
exit "$RC"
