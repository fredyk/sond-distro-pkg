#!/bin/bash
# Gate 2 of 2: the published binaries must be static musl, must expose exactly
# the ten utilities this area ships, and every one of them must actually run on
# this host without root.
#
# Exit 0 only when every check passes. Output is one line per check.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FAILURES=0
CHECKS=0

ok() {
	CHECKS=$((CHECKS + 1))
	printf 'ok   %s\n' "$1"
}

fail() {
	CHECKS=$((CHECKS + 1))
	FAILURES=$((FAILURES + 1))
	printf 'FAIL %s\n' "$1"
}

require() { # message, then command
	local msg=$1
	shift
	if "$@" >/dev/null 2>&1; then ok "$msg"; else fail "$msg"; fi
}

# ---------------------------------------------------------------------------
# 1. The binaries exist and are statically linked.
# ---------------------------------------------------------------------------
for bin in "$TOYBOX_BIN" "$MKSH_BIN"; do
	if [ ! -f "$bin" ]; then
		fail "missing binary $bin (publish artifacts/bin first)"
	fi
done

if [ -f "$TOYBOX_BIN" ] && [ -f "$MKSH_BIN" ]; then
	for bin in "$TOYBOX_BIN" "$MKSH_BIN"; do
		desc=$(file -b "$bin")
		case $desc in
		*"statically linked"*) ok "file(1) reports statically linked: $bin" ;;
		*) fail "not statically linked: $bin -> $desc" ;;
		esac
		case $desc in
		*"dynamically linked"*) fail "dynamically linked: $bin" ;;
		esac
	done
fi

# ---------------------------------------------------------------------------
# 2. Exactly the ten expected commands, no extras.
# ---------------------------------------------------------------------------
EXPECTED=$(printf '%s\n' $TOYBOX_COMMANDS | sort)

if [ -f "$TOYBOX_BIN" ]; then
	# "toybox" with no arguments prints the names of the commands compiled in.
	ACTUAL=$("$TOYBOX_BIN" 2>/dev/null | tr ' \t' '\n' | sed '/^$/d' | sort -u)
	if [ "$ACTUAL" = "$EXPECTED" ]; then
		ok "toybox exposes exactly: $TOYBOX_COMMANDS"
	else
		fail "toybox command set differs"
		printf '     expected: %s\n' "$(echo "$EXPECTED" | tr '\n' ' ')"
		printf '     actual:   %s\n' "$(echo "$ACTUAL" | tr '\n' ' ')"
	fi
fi

# ---------------------------------------------------------------------------
# 3. Every utility starts on the host and produces real output.
# ---------------------------------------------------------------------------
if [ -f "$TOYBOX_BIN" ]; then
	TB=$TOYBOX_BIN

	out=$("$TB" ls -l / 2>&1) && [ -n "$out" ] \
		&& ok "ls -l / -> ${#out} bytes" \
		|| fail "ls -l / produced no usable output"

	out=$("$TB" echo sond-echo-ok 2>&1) \
		&& [ "$out" = "sond-echo-ok" ] \
		&& ok "echo writes its argument" \
		|| fail "echo gave '$out'"

	out=$("$TB" cat /etc/hostname 2>&1) && [ -n "$out" ] \
		&& ok "cat /etc/hostname -> '$out'" \
		|| fail "cat /etc/hostname gave '$out'"

	out=$("$TB" grep -c . /etc/hostname 2>&1) \
		&& case $out in *[!0-9]*|'') fail "grep -c gave '$out'" ;; *) ok "grep -c . /etc/hostname -> $out" ;; esac \
		|| fail "grep -c failed: $out"

	out=$("$TB" ps 2>&1) && [ -n "$out" ] \
		&& ok "ps -> ${#out} bytes" \
		|| fail "ps produced no usable output"

	out=$("$TB" mount 2>&1) && [ -n "$out" ] \
		&& ok "mount (no args) -> ${#out} bytes" \
		|| fail "mount produced no usable output"
fi

# mkdir / cp / mv / rm inside a private temporary directory.
if [ -f "$TOYBOX_BIN" ]; then
	TB=$TOYBOX_BIN
	WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/toolchain-static.XXXXXX")
	# Only ever touches this directory, and only with find(1) on its own tree.
	cleanup() { find "$WORKDIR" -mindepth 1 -delete 2>/dev/null || true; rmdir "$WORKDIR" 2>/dev/null || true; }
	trap cleanup EXIT

	if "$TB" mkdir "$WORKDIR/d" 2>/dev/null; then
		ok "mkdir creates a directory"
	else
		fail "mkdir failed"
	fi
	printf 'sond-payload\n' >"$WORKDIR/src"
	if "$TB" cp "$WORKDIR/src" "$WORKDIR/d/copy" 2>/dev/null \
		&& [ "$(cat "$WORKDIR/d/copy")" = "sond-payload" ]; then
		ok "cp copies content verbatim"
	else
		fail "cp failed"
	fi
	if "$TB" mv "$WORKDIR/d/copy" "$WORKDIR/d/moved" 2>/dev/null \
		&& [ -f "$WORKDIR/d/moved" ] && [ ! -e "$WORKDIR/d/copy" ]; then
		ok "mv renames"
	else
		fail "mv failed"
	fi
	if "$TB" rm "$WORKDIR/d/moved" 2>/dev/null && [ ! -e "$WORKDIR/d/moved" ]; then
		ok "rm removes a file"
	else
		fail "rm failed"
	fi
	if "$TB" rmdir "$WORKDIR/d" 2>/dev/null; then
		ok "rm removes an empty directory (via rmdir path)"
	else
		# toybox has no rmdir in this config; remove the empty dir ourselves.
		rmdir "$WORKDIR/d" 2>/dev/null \
			&& ok "mkdir/cp/mv/rm cycle completed (empty dir removed by host rmdir)" \
			|| fail "could not remove test directory"
	fi
	cleanup
	trap - EXIT
fi

# ---------------------------------------------------------------------------
# 4. mksh is a working /bin/sh: cd is a builtin and prints the new directory.
# ---------------------------------------------------------------------------
if [ -f "$MKSH_BIN" ]; then
	out=$(printf 'cd /tmp\npwd\n' | "$MKSH_BIN" 2>&1) \
		&& [ "$out" = "/tmp" ] \
		&& ok "mksh builtin cd /tmp + pwd -> /tmp" \
		|| fail "mksh cd/pwd gave '$out'"

	out=$("$MKSH_BIN" -c 'echo mksh-$KSH_VERSION' 2>&1) \
		&& case $out in mksh-*) ok "mksh reports $out" ;; *) fail "mksh -c gave '$out'" ;; esac \
		|| fail "mksh -c failed"
fi

# ---------------------------------------------------------------------------
printf -- '---\n'
printf 'test-static: %d checks, %d failures\n' "$CHECKS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
