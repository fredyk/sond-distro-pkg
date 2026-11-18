# image — measurements of a green end-to-end run

Run on 2026-11-18 (UTC), no root, TCG (no `/dev/kvm`). Placeholder tree built by
`selftest.sh` from the host's static `/bin/busybox`; the kernel is
`/tank/tmp/e07e7e91/kbuild/bzImage-6.18.64-sond`; QEMU is the non-root install
`/tank/tmp/gr4v5ond7/qemu/root/usr/bin/qemu-system-x86_64` (8.2.2).

Scratch for this run was `/tmp/imagen-seabios` (declared: `/tank/tmp` is NFS and
88 % full; a 258 MiB disk plus a boot is much faster on local `/`). The tree,
the disk, the logs and the script are the same ones used in production.

## Command

```
SELFTEST_WORK=/tmp/imagen-seabios/selftest2 bash image/selftest.sh; echo SELFTEST_RC=$?
```

Full serial transcript: `image/serial-console.txt`.

## Result

```
SELFTEST_RC=0
selftest: SELFTEST: PASS (14/14 utilities ok, disk boots under SeaBIOS)
```

## Required checks (literal output)

### `grep -c SeaBIOS` >= 1

```
$ grep -ac 'SeaBIOS (version' /tmp/imagen-seabios/selftest2/serial.log
1
```

### `grep -ci ovmf` == 0

```
$ grep -aci 'ovmf' /tmp/imagen-seabios/selftest2/serial.log
0
```

### `sgdisk -p`: two partitions, none `EF00`

```
Disk /tmp/imagen-seabios/selftest2/out/sond-disk.raw: 528417 sectors, 258.0 MiB
Sector size (logical): 512 bytes
Disk identifier (GUID): F2F3DAFB-B0A5-4DB3-989E-1858745BA568
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 2048, last usable sector is 528383
Partitions will be aligned on 2048-sector boundaries
Total free space is 0 sectors (0 bytes)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048            4095   1024.0 KiB  EF02  bios-grub
   2            4096          528383   256.0 MiB   8300  root
```

`EF00` (ESP) does not appear; `p1` is `EF02` (`bios_grub`), `p2` is `8300`.

### `xxd -s 446`: the protective MBR entry is still there (`ee`)

```
$ xxd -s 446 -l 16 /tmp/imagen-seabios/selftest2/out/sond-disk.raw
000001be: 0000 0200 eeff ffff 0100 0000 2010 0800  ............ ...
```

### GRUB embed (the two patched fields)

```
$ cat /tmp/imagen-seabios/selftest2/out/boot-embed-method.txt
grub-bios-setup: tried, refused raw image file (falls back to /dev/sda1); embedded by hand: core.img blocklist patched (start=2049, len=n-1, seg=0x0820) and written at LBA 2048 inside p1; boot.img kernel_sector (0x5c, LE64)=2048, 440 B to MBR (partition table untouched).
```

`build-disk.sh` itself reads the fields back after writing:

```
build-disk: embed verified: kernel_sector=2048, blocklist start=2049 len=288 seg=0x0820, protective MBR intact, core.img matches
```

### Battery 14/14 and `RESULT: PASS`

```
battery: 14/14 utilities ok (0 failed)
RESULT: PASS
```

## Boot from disk in the serial transcript

```
SeaBIOS (version 1.16.3-debian-1.16.3-2)
...
Booting from Hard Disk...
[    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz root=/dev/vda2 rw console=ttyS0,115200n8 init=/init panic=1
[    3.451899]  vda: vda1 vda2
[   34.602716] EXT4-fs (vda2): mounted filesystem 94b45ac7-c3a1-44f7-8328-bba6752de05a r/w with ordered data mode. Quota mode: none.
[   35.235835] Run /init as init process
INIT: proc and sys mounted
INIT: battery begin
ok: ls -> total 48
ok: ps -> PID   USER   COMMAND
ok: cat -> sond
ok: grep -c -> 1
ok: echo -> hola
ok: mkdir -> rc=0
ok: cp -> rc=0
ok: mv -> rc=0
ok: cat /tmp/d/h2 -> sond
ok: rm -r -> rc=0
ok: mount tmpfs -> none /mnt tmpfs rw,relatime 0 0
ok: cd + pwd -> /tmp
ok: sh -c -> desde-sh
ok: readlink -> busybox
battery: 14/14 utilities ok (0 failed)
RESULT: PASS
INIT: battery end; interactive shell follows (type on the serial console)
sond-shell# ls -l /
sond-shell# readlink /bin/ls
sond-shell# echo hola desde la consola
sond-shell# exit
```

`readlink -> busybox` is the placeholder tree (host busybox); with the real
toybox/mksh tree the same row reports `toybox`/`mksh`. The boot is from disk: no
`-kernel` and no `-initrd` are passed, and the transcript shows the firmware
loading the MBR, then the kernel from `vda2`.

Disk sha256 of this run:

```
e60e0dbaebb900d898fbf4de5d4136de43308ff8953506241d6968a86d6c503e
```

## Before the fix (red baseline, same harness)

Built with the unpatched `core.img` blocklist, the guest stopped at:

```
Booting from Hard Disk...
qemu-system-x86_64: terminating on signal 15 from pid ... (timeout)
```

and the blocklist read `start=2` instead of `start=2049`. The first sector of
`core.img` is now patched (`start=S+1`, `len=n-1`, `seg=0x0820`) and `boot.img`
writes 440 bytes instead of 512; with that, `vda: vda1 vda2` appears and the
root mounts.
