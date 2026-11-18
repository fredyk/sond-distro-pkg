#!/usr/bin/env bash
# Boot a Sond test disk image under QEMU's default x86 firmware (SeaBIOS,
# legacy BIOS: no EFI firmware images are ever passed) and capture the serial
# console. TCG is fine: no /dev/kvm is required or used.
#
# QEMU runs with -nographic, so stdin is the serial console: after the guest
# drops to the shell prompt, a few commands are typed in, and the transcript
# shows the prompt plus the echoed keystrokes (proof of "from the shell").
#
# Exit code: 0 iff the log contains "RESULT: PASS" (the in-guest battery).
set -uo pipefail

usage() {
  cat <<'EOF'
usage: run-qemu.sh --disk IMG --log FILE
                   [--prompt-timeout N] [--total-timeout N] [--cmd 'line']...
  --disk IMG            raw disk built by build-disk.sh
  --log FILE            serial transcript destination (truncated; local FS best)
  --prompt-timeout N    seconds to wait for the shell prompt (default 420)
  --total-timeout N     overall wall-clock limit for QEMU (default 600)
  --cmd 'line'          interactive line to type at the prompt (repeatable;
                        default: ls -l / ; readlink /bin/ls ; echo ... ; exit)
EOF
}

DISK="" LOG=""
QEMU=${QEMU_BIN:-/tank/tmp/gr4v5ond7/qemu/root/usr/bin/qemu-system-x86_64}
QEMU_LIB=${QEMU_LD_LIBRARY_PATH:-/tank/tmp/gr4v5ond7/qemu/root/usr/lib/x86_64-linux-gnu}
# Unpacked (non-root) QEMU install: its TCG accelerator lives in loadable
# modules under $QEMU_LIB/qemu; without this the binary fatals on tcg-accel-ops.
# Same story for the firmware blobs (the default x86 BIOS, bios-256k.bin):
# pass -L so QEMU finds them instead of the missing system prefix.
QEMU_MODS=${QEMU_MODULE_DIR:-$QEMU_LIB/qemu}
if [ -z "${QEMU_DATADIR:-}" ]; then
  _libroot=$(dirname "$(dirname "$QEMU_LIB")")   # .../root/usr/lib/x86_64-linux-gnu -> .../root/usr
  for _d in "$_libroot/share/qemu" /usr/share/qemu; do
    [ -f "$_d/bios-256k.bin" ] || continue
    QEMU_DATADIR=$(cd "$_d" && pwd -P)
    break
  done
  QEMU_DATADIR=${QEMU_DATADIR:-}
fi
PROMPT_TIMEOUT=420
TOTAL_TIMEOUT=600
PROMPT='sond-shell#'
CMDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --disk)            DISK=$2; shift 2 ;;
    --log)             LOG=$2; shift 2 ;;
    --prompt-timeout)  PROMPT_TIMEOUT=$2; shift 2 ;;
    --total-timeout)   TOTAL_TIMEOUT=$2; shift 2 ;;
    --cmd)             CMDS+=("$2"); shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *) usage >&2; echo "run-qemu: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$DISK" ] && [ -n "$LOG" ] || { usage >&2; exit 2; }
[ -f "$DISK" ] || { echo "run-qemu: no such disk: $DISK" >&2; exit 2; }
[ -x "$QEMU" ] || { echo "run-qemu: no such qemu: $QEMU" >&2; exit 2; }
[ -d "$QEMU_LIB" ] || { echo "run-qemu: no such library dir: $QEMU_LIB" >&2; exit 2; }
[ -d "$QEMU_MODS" ] || { echo "run-qemu: no such module dir: $QEMU_MODS" >&2; exit 2; }
[ -d "$QEMU_DATADIR" ] || { echo "run-qemu: no such data (firmware) dir: $QEMU_DATADIR" >&2; exit 2; }

if [ ${#CMDS[@]} -eq 0 ]; then
  CMDS=("ls -l /" "readlink /bin/ls" "echo hola desde la consola" "exit")
fi

rm -f "$LOG"
: > "$LOG"

echo "run-qemu: booting $DISK (firmware: QEMU default x86 BIOS) -> $LOG" >&2

# Left side of the pipe types on the serial console once the prompt is up.
(
  waited=0
  while ! grep -Fq -- "$PROMPT" "$LOG" 2>/dev/null; do
    # QEMU-side fatal at startup (no guest will ever boot): stop waiting early.
    if grep -Eq 'qemu: could not|could not load PC BIOS|tcg-accel-ops' "$LOG" 2>/dev/null; then
      echo "run-qemu: qemu failed to start; see log" >&2
      break
    fi
    sleep 1
    waited=$((waited + 1))
    [ "$waited" -lt "$PROMPT_TIMEOUT" ] || break
  done
  if grep -Fq -- "$PROMPT" "$LOG" 2>/dev/null; then
    sleep 3   # let the line discipline settle after the battery output
    for c in "${CMDS[@]}"; do
      printf '%s\n' "$c"
      sleep 6
    done
  else
    echo "" >&2
    echo "run-qemu: shell prompt not seen within ${PROMPT_TIMEOUT}s" >&2
  fi
) | QEMU_MODULE_DIR="$QEMU_MODS" LD_LIBRARY_PATH="$QEMU_LIB" timeout "$TOTAL_TIMEOUT" "$QEMU" \
      -L "$QEMU_DATADIR" \
      -drive "file=$DISK,format=raw,if=virtio" \
      -m 512 -nographic -no-reboot > "$LOG" 2>&1
qemu_rc=$?

# The serial console emits CRLF, so anchor checks on a CR-stripped copy.
sbios=$(tr -d '\r' < "$LOG" | grep -ac 'SeaBIOS (version' || true)
pass=$(tr -d '\r' < "$LOG" | grep -ac '^RESULT: PASS$' || true)
echo "run-qemu: qemu exit=$qemu_rc, SeaBIOS banners=$sbios, RESULT:PASS lines=$pass" >&2

if [ "$pass" -ge 1 ] && [ "$sbios" -ge 1 ]; then
  exit 0
fi
exit 1
