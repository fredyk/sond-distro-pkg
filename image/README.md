# image — production-like disk and SeaBIOS boot harness

Builds a legacy-BIOS (SeaBIOS) bootable disk from an arbitrary root tree and
boots it under QEMU, capturing the serial console. No root, no loop devices, no
EFI/OVMF: the disk has a GPT with a `bios_grub` partition and an ext4 root, and
nothing else.

## Files

| file | role |
|---|---|
| `build-disk.sh` | assembles `sond-disk.raw` (GPT + bios_grub + ext4 root) from a tree |
| `run-qemu.sh` | boots the disk under QEMU's default x86 firmware (SeaBIOS) and types on the serial console |
| `probe-utilities.sh` | the 14-utility battery that runs inside the guest |
| `selftest.sh` | end-to-end gate: builds a placeholder tree, boots it, checks the transcript |
| `pruebas.md` | the measured evidence of a green run |
| `serial-console.txt` | the complete serial transcript of that run |

## Build

```
image/build-disk.sh --tree <ROOTDIR> --out <OUTDIR> [--kernel <bzImage>]
```

`<ROOTDIR>` is a root filesystem payload: `bin/`, `share/licenses/`, … The
script copies it into `OUTDIR/work.XXXXXX` and adds, without touching the
original tree, `boot/vmlinuz`, `boot/grub/`, `init`, the mount points
(`proc/ sys/ dev/ tmp/ mnt/`) and `etc/hostname` when missing.

Outputs in `<OUTDIR>`: `sond-disk.raw`, `sond-disk.raw.sha256`,
`disk-layout.txt`, `boot-embed-method.txt`.

Geometry (512-byte sectors): p1 BIOS boot (type `EF02`, 1 MiB) at LBA 2048,
p2 Linux (type `8300`, 256 MiB, ext4 label `sondroot`) at LBA 4096. No ESP is
ever created. Production keeps `bios_grub` at LBA 34; this host's
`sfdisk`/`sgdisk` insist on 2048-sector alignment, so the same structure is
shifted one MiB (declared deviation, identical otherwise).

## Boot

```
image/run-qemu.sh --disk <OUTDIR>/sond-disk.raw --log <serial.log> \
                  [--prompt-timeout N] [--total-timeout N] [--cmd 'line']...
```

QEMU runs with `-nographic`, so stdin is the serial console; once the guest
prompt appears a few commands are typed in and echoed back into the transcript.
The runner never passes `-bios`/`-pflash`: the firmware is QEMU's default x86
BIOS (SeaBIOS). Exit code is 0 iff the transcript shows a SeaBIOS banner and
`RESULT: PASS`.

Mounting ext4 from a slow (NFS-backed) disk and booting in TCG can take 25-30 s;
keep the timeouts at 150 s or more and do not kill QEMU for being slow.

## How GRUB is embedded (two fields matter, both patched)

`grub-bios-setup` refuses a plain image file on this host (it resolves the
target through the running kernel's disks), so `build-disk.sh` embeds GRUB by
hand. Two independent fields must be patched or the disk never boots:

1. **`boot.img` kernel_sector** (u64 LE at `0x5c`): LBA where `core.img` starts.
   GRUB writes only the first **440** bytes of `boot.img`; writing 512 would zero
   the MBR partition entries at offset 446, Linux would stop trusting the GPT's
   protective entry (`0xEE`) and the root device would vanish.
2. **`core.img` blocklist** (last 12 bytes of its first sector): u64 LE `start`
   at `0x1f4` (LBA of the sector after the first), u16 LE `len` at `0x1fc`
   (`n_sectors - 1`), u16 LE `seg` at `0x1fe` (`0x0820`). `grub-mkimage` leaves
   it unpatched; without this `diskboot` loads garbage and the guest hangs at
   `Booting from Hard Disk...`.

The embedded `early.cfg` also brings up the serial console itself and boots the
on-disk kernel directly; with only `$prefix` configured GRUB would go looking
for `grub.cfg` and print nothing on the serial line.

`build-disk.sh` reads both fields back after writing and fails loudly if either
does not match.

## Self-test

```
SELFTEST_WORK=/tmp/imagen-... image/selftest.sh
```

Builds a placeholder tree from the host's static `/bin/busybox` (never
`artifacts/bin/`), builds the disk, boots it, and asserts: GPT has exactly two
partitions, p1 is `EF02`, no `EF00`, the protective MBR entry survives, the
`core.img` blocklist is patched, a SeaBIOS banner is present, OVMF appears
nowhere, the kernel runs `/init`, the battery reports `14/14` and
`RESULT: PASS`, and the typed commands echo from the prompt. It exits 0 only
when the transcript actually contains `RESULT: PASS`.

## Environment

The default kernel, QEMU and firmware paths come from the measured environment;
they can be overridden with `SOND_KERNEL`, `QEMU_BIN`,
`QEMU_LD_LIBRARY_PATH`, `QEMU_MODULE_DIR` and `QEMU_DATADIR`. Missing paths fail
loudly, never silently default to a wrong value.
