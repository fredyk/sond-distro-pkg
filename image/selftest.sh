#!/usr/bin/env bash
# Self-test for the Sond disk + SeaBIOS boot harness (image/ area).
# End-to-end gate, placeholder tree only (static host busybox); never touches artifacts/bin/.
# Red until build-disk.sh / run-qemu.sh / probe-utilities.sh exist and boot a real disk.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

# Paths come from the measured environment (01-entorno.md); missing ones fail loudly.
SELFWORK=${SELFTEST_WORK:-/tank/tmp/gr4v5ond7/forks/imgwork/selftest}
KERNEL=${SOND_KERNEL:-/tank/tmp/e07e7e91/kbuild/bzImage-6.18.64-sond}
QEMU=${QEMU_BIN:-/tank/tmp/gr4v5ond7/qemu/root/usr/bin/qemu-system-x86_64}
QEMU_LIB=${QEMU_LD_LIBRARY_PATH:-/tank/tmp/gr4v5ond7/qemu/root/usr/lib/x86_64-linux-gnu}
BUSYBOX=${BUSYBOX_STUB:-/bin/busybox}

BUILD="$HERE/build-disk.sh"
RUN="$HERE/run-qemu.sh"
PROBE="$HERE/probe-utilities.sh"

DISK="$SELFWORK/out/sond-disk.raw"
LOG="$SELFWORK/serial.log"

EXPECTED_CHECKS=14   # battery rows in probe-utilities.sh

failures=0
note()  { printf 'selftest: %s\n' "$*"; }
fail()  { printf 'SELFTEST FAIL: %s\n' "$*" >&2; failures=$((failures+1)); }
ok()    { printf 'SELFTEST ok: %s\n' "$*"; }
check() { # $1 description, $2 command (eval'd)
  if eval "$2" >/dev/null 2>&1; then ok "$1"; else fail "$1  [$2]"; fi
}

# ---------------------------------------------------------------- prerequisites
for f in "$BUILD" "$RUN" "$PROBE"; do
  [ -f "$f" ] || fail "missing harness file: $f (write it; this red is expected before the build)"
done
check "kernel present: $KERNEL"                 "[ -f '$KERNEL' ]"
check "qemu present: $QEMU"                     "[ -x '$QEMU' ]"
check "qemu libs present: $QEMU_LIB"            "[ -d '$QEMU_LIB' ]"
check "static busybox stub: $BUSYBOX"           "[ -f '$BUSYBOX' ]"

# The firmware is QEMU's default (SeaBIOS): the runner must never pass -bios/-pflash,
# and the old OVMF demo must not be referenced from it.
if [ -f "$RUN" ]; then
  if grep -Eq -- '-bios|pflash|OVMF' "$RUN"; then
    fail "run-qemu.sh mentions -bios/pflash/OVMF: SeaBIOS default firmware required"
  else
    ok "run-qemu.sh passes no -bios/-pflash/OVMF (default firmware = SeaBIOS)"
  fi
fi

[ "$failures" -eq 0 ] || { note "prerequisites: $failures failure(s)"; exit 1; }

# ---------------------------------------------------------------- placeholder tree
# A bundle payload shape: bin/ + share/licenses/. Deliberately NO init, NO boot/,
# NO etc/hostname: the harness must add those without stepping on the tree.
TREE="$SELFWORK/tree"
mkdir -p "$TREE/bin" "$TREE/share/licenses/stub"
cp -f "$BUSYBOX" "$TREE/bin/busybox"
for a in sh ls ps cat grep echo mkdir cp mv rm mount head readlink; do
  ln -sfn busybox "$TREE/bin/$a"
done
printf 'placeholder tree, not a real license\n' > "$TREE/share/licenses/stub/NOTICE"

# ---------------------------------------------------------------- build the disk
rm -f "$DISK"
note "building disk from $TREE"
bash "$BUILD" --tree "$TREE" --out "$SELFWORK/out"
check "disk exists: $DISK" "[ -f '$DISK' ]"
check "disk size plausible" "[ \$(stat -c%s '$DISK') -gt 260000000 ]"

# Partition table: two partitions, p1 = BIOS boot, p2 = Linux, and NO ESP anywhere.
PT=$(sgdisk -p "$DISK" 2>&1) || { fail "sgdisk -p"; PT=""; }
printf '%s\n' "$PT" | sed 's/^/    | /'
check "p1 is bios_grub (EF02)"  "printf '%s\n' \"\$PT\" | grep -q 'EF02'"
check "p2 is Linux FS (8300)"   "printf '%s\n' \"\$PT\" | grep -qE '0700|8300'"
check "no ESP (EF00 absent)"    "! printf '%s\n' \"\$PT\" | grep -q 'EF00'"
check "exactly two partitions"  "[ \$(printf '%s\n' \"\$PT\" | grep -cE '^[[:space:]]+[0-9]+[[:space:]]') -eq 2 ]"
check "bios_grub GUID present"  "sgdisk -i 1 '$DISK' 2>/dev/null | grep -qi '21686148-6449-6E6F-744E-656564454649'"

# Regression guards for the two measured defects: writing 512 bytes of boot.img
# zeroes the protective MBR entry (Linux then ignores the GPT), and an unpatched
# core.img blocklist makes diskboot load garbage and hang before the kernel.
check "protective MBR (0xEE) intact at 446" "xxd -s 446 -l 16 -p '$DISK' | grep -q 'eeffffff'"
if python3 - "$DISK" <<'PY'
import struct, sys
f = open(sys.argv[1], 'rb')
mbr = f.read(512)
assert mbr[450] == 0xee, 'protective MBR entry lost'
sector = struct.unpack('<Q', mbr[0x5c:0x64])[0]
assert sector > 0, 'boot.img kernel_sector not patched'
f.seek(sector * 512)
head = f.read(512)
assert struct.unpack('<Q', head[0x1f4:0x1fc])[0] == sector + 1, 'blocklist start wrong'
assert struct.unpack('<H', head[0x1fe:0x200])[0] == 0x0820, 'blocklist seg wrong'
PY
then ok "core.img blocklist + kernel_sector patched, 440-byte MBR write"
else fail "core.img blocklist/kernel_sector not patched correctly"
fi

# ---------------------------------------------------------------- boot it for real
note "booting disk in QEMU (SeaBIOS default, TCG, serial captured to $LOG)"
rm -f "$LOG"
RUN_RC=0
bash "$RUN" --disk "$DISK" --log "$LOG" || RUN_RC=$?
note "run-qemu.sh rc=$RUN_RC"

check "log exists" "[ -s '$LOG' ]"
check "SeaBIOS banner in log (firmware proof)" "grep -aq 'SeaBIOS (version' '$LOG'"
check "no OVMF anywhere in log"                "! grep -aiq 'ovmf' '$LOG'"
check "kernel ran /init"                       "grep -aq 'Run /init' '$LOG'"

# Battery outcome line and per-utilisation counts. The serial console emits
# CRLF, so anchor the RESULT check on a CR-stripped copy of the transcript.
check "RESULT: PASS present"           "tr -d '\\r' < '$LOG' | grep -aq '^RESULT: PASS\$'"
check "no fail: lines in battery"      "! grep -aq '^fail: ' '$LOG'"
BAT=$(grep -aoE '^battery: [0-9]+/[0-9]+' "$LOG" | tail -n1 || true)
note "battery summary line: ${BAT:-<none>}"
OKS=${BAT#battery: }; OKS=${OKS%%/*}
TOTAL=${BAT##*/}
check "battery total is $EXPECTED_CHECKS" "[ \"\$TOTAL\" = \"$EXPECTED_CHECKS\" ]"
check "battery all ok"                    "[ \"\$OKS\" = \"\$TOTAL\" ] && [ \"\$TOTAL\" = \"$EXPECTED_CHECKS\" ]"

# "From the shell": the prompt appears and the typed commands are echoed back.
# The interactive shell emits a cursor-position query (ESC[6n) between the
# prompt and the echoed line, so allow anything up to the command text.
check "interactive prompt shown"        "grep -aq 'sond-shell#' '$LOG'"
check "typed: ls -l /"                  "grep -aq 'sond-shell#.*ls -l /' '$LOG'"
check "typed: readlink /bin/ls"         "grep -aq 'sond-shell#.*readlink /bin/ls' '$LOG'"
check "typed: echo from console"        "grep -aq 'sond-shell#.*echo hola desde la consola' '$LOG'"

# ---------------------------------------------------------------- report
SHA=$(sha256sum "$DISK" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA" "$DISK" > "$SELFWORK/out/sond-disk.raw.sha256"
note "disk sha256: $SHA"
note "serial log:  $LOG"

# Hard gate: rc=0 only when the in-guest battery actually reported PASS. A
# zero exit without that line would be a silent green.
if ! tr -d '\r' < "$LOG" 2>/dev/null | grep -aq '^RESULT: PASS$'; then
  note "SELFTEST: FAIL (serial log has no 'RESULT: PASS')"
  exit 1
fi

if [ "$failures" -ne 0 ]; then
  note "SELFTEST: FAIL ($failures check(s) red)"
  exit 1
fi
note "SELFTEST: PASS ($EXPECTED_CHECKS/$EXPECTED_CHECKS utilities ok, disk boots under SeaBIOS)"
