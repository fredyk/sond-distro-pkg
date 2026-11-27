#!/bin/bash
# toybox-static ships setfattr: incusd's startup looks it up on PATH and refuses to run without
# it (cmd/incusd/main_daemon.go), and its only call, setfattr -n NAME -v VALUE PATH
# (internal/server/storage/drivers/driver_cephfs_volumes.go), is covered by toybox's
# setfattr ("hn:|v:x:|[!xv]", toys/other/setfattr.c at a57b091d). Every list of toybox
# commands in this repository must agree with $TOYBOX_COMMANDS.
# Offline: no network, no build.
#
# usage: ci/test-toybox-setfattr.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

rbx=$here/rbx-toybox.sh
[ -f "$rbx" ] && sh -n "$rbx" 2>/dev/null \
	&& ok "ci/rbx-toybox.sh is a POSIX wrapper the gate can run" \
	|| bad "ci/rbx-toybox.sh is a POSIX wrapper the gate can run"
sorted() { printf '%s\n' $1 | sort | tr '\n' ' '; }

cmds=$(sed -n 's/^TOYBOX_COMMANDS="\(.*\)"$/\1/p' "$DISTRO/toolchain/common.sh")
case " $cmds " in
*" setfattr "*) ok "TOYBOX_COMMANDS lists setfattr" ;;
*) bad "TOYBOX_COMMANDS lists setfattr (found: $cmds)" ;;
esac

syms=$(sed -n 's/^for sym in \(.*\); do$/\1/p' "$DISTRO/toolchain/build-toybox.sh")
want=$(printf '%s\n' $cmds | tr 'a-z' 'A-Z' | sort | tr '\n' ' ')
got=$(printf '%s\n' $syms | grep -vx TOYBOX | sort | tr '\n' ' ')
[ "$got" = "$want" ] && ok "build-toybox.sh enables exactly the CONFIG_ of TOYBOX_COMMANDS" \
	|| bad "build-toybox.sh enables exactly the CONFIG_ of TOYBOX_COMMANDS (want: $want; got: $got)"

for var in TOYBOX_SYMLINKS TOYBOX_APPLETS; do
	v=$(sed -n "s/^$var=\"\(.*\)\"\$/\1/p" "$DISTRO/verify/run-all.sh")
	[ "$(sorted "$v")" = "$(sorted "$cmds")" ] && ok "verify/run-all.sh $var matches TOYBOX_COMMANDS" \
		|| bad "verify/run-all.sh $var matches TOYBOX_COMMANDS (found: $v)"
done

if [ "$fails" -eq 0 ]; then
	printf 'test-toybox-setfattr: OK\n'
else
	printf 'test-toybox-setfattr: FAIL (%d)\n' "$fails"
	exit 1
fi
