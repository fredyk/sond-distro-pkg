#!/usr/bin/env bash
# Build a legacy-BIOS bootable Sond test disk, no root needed:
#   GPT, partition 1 = BIOS boot (bios_grub) holding GRUB's core.img,
#   partition 2 = ext4 rootfs assembled with mke2fs -d from a caller's tree.
# No ESP is created: this disk boots only under the x86 BIOS firmware.
#
# The harness adds to the tree (without touching the rest): boot/vmlinuz,
# boot/grub/grub.cfg, init (from this repo's probe script) and the mount
# directories proc/ sys/ dev/ tmp/ mnt/, plus etc/hostname if the tree has none.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
usage: build-disk.sh --tree DIR --out DIR [--kernel PATH]
  --tree DIR   rootfs content to install (bin/, share/, ...); never modified
  --out DIR    destination for sond-disk.raw (+ metadata files); created
  --kernel PATH bzImage to place at <root>/boot/vmlinuz
               (default: $SOND_KERNEL or the measured 6.18.64-sond build)
EOF
}

TREE="" OUT=""
KERNEL=${SOND_KERNEL:-/tank/tmp/e07e7e91/kbuild/bzImage-6.18.64-sond}
GRUB_DIR=${GRUB_I386_PC_DIR:-/usr/lib/grub/i386-pc}

while [ $# -gt 0 ]; do
  case "$1" in
    --tree)   TREE=$2; shift 2 ;;
    --out)    OUT=$2; shift 2 ;;
    --kernel) KERNEL=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; echo "build-disk: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TREE" ] && [ -n "$OUT" ] || { usage >&2; exit 2; }
[ -d "$TREE" ] || { echo "build-disk: no such tree: $TREE" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "build-disk: no such kernel: $KERNEL" >&2; exit 1; }
[ -f "$GRUB_DIR/boot.img" ] || { echo "build-disk: no i386-pc GRUB dir: $GRUB_DIR" >&2; exit 1; }

# Disk geometry (sectors of 512 B). Production puts bios_grub at LBA 34; this
# host's sfdisk/sgdisk insist on 2048-sector alignment (declared deviation), so
# the structure is identical, shifted one MiB:
#   p1 BIOS boot 2048..4095 (1 MiB, holds core.img)
#   p2 Linux     4096..528383 (256 MiB, ext4 label sondroot)
#   +33 trailing sectors for the backup GPT
S_BIOS_START=2048
S_BIOS_SIZE=2048
S_ROOT_START=$(((S_BIOS_START + S_BIOS_SIZE)))          # 4096
S_ROOT_SIZE=524288                                        # 256 MiB
DISK_SECTORS=$(((S_ROOT_START + S_ROOT_SIZE + 33)))
FS_SIZE=256M
LABEL=sondroot

TYPE_BIOS_BOOT=21686148-6449-6E6F-744E-656564454649
TYPE_LINUX=0FC63DAF-8483-4772-8E79-3D69D8477DE4

WORKROOT=${SOND_IMAGE_WORK:-$OUT}
mkdir -p "$WORKROOT" "$OUT"
WORK=$(mktemp -d "$WORKROOT/work.XXXXXX")
trap 'rm -r "$WORK"' EXIT   # only this script's own temporary directory

STAGE="$WORK/stage"

echo "build-disk: staging rootfs from $TREE"
mkdir -p "$STAGE"
cp -a "$TREE/." "$STAGE/"

# Harness-owned files (idempotent: overwritten on every build).
install -d -m 0755 "$STAGE/bin" "$STAGE/boot/grub" "$STAGE/etc" \
                   "$STAGE/proc" "$STAGE/sys" "$STAGE/dev" "$STAGE/tmp" "$STAGE/mnt"
install -m 0644 "$KERNEL" "$STAGE/boot/vmlinuz"
install -m 0755 "$HERE/probe-utilities.sh" "$STAGE/probe.sh"
[ -e "$STAGE/etc/hostname" ] || printf 'sond\n' > "$STAGE/etc/hostname"

cat > "$STAGE/init" <<'INIT'
#!/bin/sh
# Sond harness init: mounts, utility battery, then an interactive shell on the
# serial console. POSIX sh only (runs as PID 1 under busybox ash or mksh).
export PATH=/bin
umask 022
mount -t proc proc /proc
mount -t sysfs sys /sys
echo "INIT: proc and sys mounted"
echo "INIT: battery begin"
sh /probe.sh
echo "INIT: battery end; interactive shell follows (type on the serial console)"
export PS1='sond-shell# '
exec sh -i
INIT
chmod 755 "$STAGE/init"

cat > "$STAGE/boot/grub/grub.cfg" <<'CFG'
# Sond test disk: boot the on-disk kernel in legacy BIOS mode, console on 16550A.
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial console
terminal_output serial console
set timeout=0
set default=0
menuentry 'Sond OS (disk boot, legacy BIOS)' {
	linux /boot/vmlinuz console=ttyS0,115200n8 root=/dev/vda2 rw init=/init panic=1
}
CFG

echo "build-disk: mke2fs -d (no root)"
FS_IMG="$WORK/root.ext4"
mke2fs -q -t ext4 -L "$LABEL" -d "$STAGE" "$FS_IMG" "$FS_SIZE"

DISK="$OUT/sond-disk.raw"
echo "build-disk: writing GPT disk $DISK"
rm -f "$DISK" "$OUT/sond-disk.raw.sha256" "$OUT/boot-embed-method.txt"
truncate -s "$((DISK_SECTORS * 512))" "$DISK"
{
  printf 'label: gpt\nunit: sectors\n\n'
  printf 'start=%s, size=%s, type=%s, name="bios-grub"\n'   "$S_BIOS_START" "$S_BIOS_SIZE" "$TYPE_BIOS_BOOT"
  printf 'start=%s, size=%s, type=%s, name="root"\n'        "$S_ROOT_START" "$S_ROOT_SIZE" "$TYPE_LINUX"
} | sfdisk -q "$DISK"

dd if="$FS_IMG" of="$DISK" bs=1M seek="$((S_ROOT_START / 2048))" conv=notrunc status=none

echo "build-disk: grub-mkimage (i386-pc)"
# early.cfg is embedded in core.img and boots the on-disk kernel directly. It
# must set the serial console up itself: with only $prefix configured, GRUB
# goes looking for grub.cfg and prints nothing at all on the serial line.
cat > "$WORK/early.cfg" <<'EARLY'
serial --unit=0 --speed=115200
terminal_input serial
terminal_output serial
set timeout=0
set root=(hd0,gpt2)
linux /boot/vmlinuz root=/dev/vda2 rw console=ttyS0,115200n8 init=/init panic=1
boot
EARLY
grub-mkimage -O i386-pc -o "$WORK/core.img" -p '(hd0,gpt2)/boot/grub' \
  -c "$WORK/early.cfg" \
  biosdisk part_gpt part_msdos ext2 normal linux search search_fs_uuid serial terminal configfile

CORE_BYTES=$(stat -c%s "$WORK/core.img")
if [ "$CORE_BYTES" -gt $((S_BIOS_SIZE * 512)) ]; then
  echo "build-disk: core.img ($CORE_BYTES B) does not fit the bios_grub partition" >&2
  exit 1
fi

# Embed by hand (declared method): grub-bios-setup refuses a raw image file on
# this host (it resolves the partition through the running kernel's disks), and
# grub-mkimage leaves core.img's blocklist unpatched, so a plain dd never boots.
#
# GRUB i386-pc protocol, two independent fields have to be patched:
#   - boot.img's u64 LE field at 0x5c is the kernel_sector: the LBA where
#     core.img starts. GRUB installs only its first 440 bytes, which leaves the
#     MBR partition table (offset 446) intact. Writing 512 bytes would zero the
#     protective MBR entry and Linux would stop trusting the GPT.
#   - core.img's first sector ends with the blocklist diskboot uses to load the
#     rest of core.img: u64 LE start at 0x1f4 (LBA of the sector after the
#     first one), u16 LE len at 0x1fc (n_sectors - 1), u16 LE seg at 0x1fe
#     (0x0820). core.img is written contiguous at S.
python3 - "$GRUB_DIR/boot.img" "$WORK/core.img" "$WORK/core-patched.img" \
          "$WORK/boot-patched.img" "$S_BIOS_START" <<'PY'
import struct, sys
boot_src, core_src, core_dst, boot_dst, sector = sys.argv[1:6]
sector = int(sector)

core = bytearray(open(core_src, 'rb').read())
n = (len(core) + 511) // 512
core += b'\0' * (n * 512 - len(core))
struct.pack_into('<Q', core, 0x1f4, sector + 1)   # blocklist start
struct.pack_into('<H', core, 0x1fc, n - 1)        # blocklist len
struct.pack_into('<H', core, 0x1fe, 0x0820)       # blocklist seg
open(core_dst, 'wb').write(bytes(core))

img = bytearray(open(boot_src, 'rb').read())
assert len(img) == 512 and img[0x1fe:0x200] == b'\x55\xaa', 'unexpected boot.img'
struct.pack_into('<Q', img, 0x5c, sector)          # kernel_sector = LBA of core.img
open(boot_dst, 'wb').write(bytes(img[:440]))       # 440 B, never 512
PY
dd if="$WORK/core-patched.img" of="$DISK" bs=512 seek="$S_BIOS_START" conv=notrunc status=none
dd if="$WORK/boot-patched.img" of="$DISK" bs=440 count=1 conv=notrunc status=none
printf 'grub-bios-setup: tried, refused raw image file (falls back to /dev/sda1); embedded by hand: core.img blocklist patched (start=%s, len=n-1, seg=0x0820) and written at LBA %s inside p1; boot.img kernel_sector (0x5c, LE64)=%s, 440 B to MBR (partition table untouched).\n' \
  "$((S_BIOS_START + 1))" "$S_BIOS_START" "$S_BIOS_START" > "$OUT/boot-embed-method.txt"

# Read back what we just wrote: both patches and the protective MBR must hold.
python3 - "$DISK" "$WORK/core-patched.img" "$S_BIOS_START" <<'PY'
import struct, sys
disk, core_path, sector = sys.argv[1], sys.argv[2], int(sys.argv[3])
core = open(core_path, 'rb').read()
n = (len(core) + 511) // 512
d = open(disk, 'rb')
mbr = d.read(512)
got = struct.unpack('<Q', mbr[0x5c:0x64])[0]
assert got == sector, f'kernel_sector field reads {got}, expected {sector}'
assert mbr[0x1fe:0x200] == b'\x55\xaa', 'MBR signature lost'
assert mbr[450] == 0xee, f'protective MBR entry lost (type=0x{mbr[450]:02x})'
d.seek(sector * 512)
head = d.read(512)
assert head == core[:512], 'core.img first sector does not match what was written'
start = struct.unpack('<Q', head[0x1f4:0x1fc])[0]
length = struct.unpack('<H', head[0x1fc:0x1fe])[0]
seg = struct.unpack('<H', head[0x1fe:0x200])[0]
assert start == sector + 1, f'blocklist start reads {start}, expected {sector + 1}'
assert length == n - 1, f'blocklist len reads {length}, expected {n - 1}'
assert seg == 0x0820, f'blocklist seg reads 0x{seg:04x}, expected 0x0820'
print(f'build-disk: embed verified: kernel_sector={got}, blocklist start={start} len={length} seg=0x{seg:04x}, protective MBR intact, core.img matches')
PY

(cd "$OUT" && sha256sum sond-disk.raw > sond-disk.raw.sha256)

cat > "$OUT/disk-layout.txt" <<EOF
disk sectors: $DISK_SECTORS (x 512 B)
p1 $S_BIOS_START..$((S_BIOS_START + S_BIOS_SIZE - 1))  BIOS boot ($TYPE_BIOS_BOOT)  name=bios-grub
p2 $S_ROOT_START..$((S_ROOT_START + S_ROOT_SIZE - 1))  Linux      ($TYPE_LINUX)  name=root  ext4 label=$LABEL
no ESP. firmware: default x86 BIOS (SeaBIOS), never EFI.
EOF

echo "build-disk: done: $DISK ($DISK_SECTORS sectors)"
