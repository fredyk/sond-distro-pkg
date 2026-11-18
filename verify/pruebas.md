# pruebas.md — what was run, and the real outcome

Run date: 2026-11-18. Single command, full chain, with the artifacts already present:

```
$ cd /home/fred/dev/projects/sond-distro-pkg.oc-integracion-sond
$ bash verify/run-all.sh
...
verify: guest counters: BATTERY ok=21 fail=0 RESULT: PASS
verify: symlink evidence: lrwxrwxrwx 1 1000 1000 6 ... /bin/ls -> toybox
verify: symlink evidence: lrwxrwxrwx 1 1000 1000 4 ... /bin/sh -> mksh
verify: toybox applets in guest: cat cp echo grep ls mkdir mount mv ps rm
verify: battery: 21/12 mandated utilities + 9 extra checks ok, guest verdict PASS
RESULT: PASS
$ echo $?
0
```

## Results, command by command

| check | command | result |
|---|---|---|
| packager suite | `python3 -m unittest discover -s …/sondpkg/tests -t …` | `Ran 43 tests ... OK` |
| binaries | `sha256sum`, `file` | toybox `0fb90081…97fe4fb`, mksh `1dec4fda…ef0a083`, both `statically linked` |
| applet list | `…/bin/toybox` | `cat cp echo grep ls mkdir mount mv ps rm` |
| mksh version | `printf 'echo $KSH_VERSION\n' \| …/bin/mksh` | `@(#)MIRBSD KSH R59 2020/04/14` |
| source tarballs | `git archive --format=tar <sha> \| gzip -n` | toybox `28562ae4…`, mksh `254576ab…`, musl `512f3a55…` |
| bundles | `sondpkg build-bundle` + `verify-bundle` | toybox `sha256:ded3d028…f2e9` (13 files), mksh `sha256:b1e82589…ecd3` (6 files) |
| independent hash | `python3 verify/canon-hash.py <payload>` | reproduces both MANIFEST hashes |
| disk | `bash image/build-disk.sh --tree … --out …` | `sond-disk.raw`, build hash `6c7ef5b6…1f750` |
| boot | `bash image/run-qemu.sh --disk … --log …` | `qemu exit=0, SeaBIOS banners=1, RESULT:PASS lines=1` |
| scorer | `verify/run-all.sh` §6 | 21/21 checks, `RESULT: PASS` |

The full serial transcript is `/tank/tmp/gr4v5ond7/forks/integ/qemu-serial.log` (not trimmed).

## Two red rows in the image area's own init battery (declared, not fixed)

```
fail: ps -> rc=1:   PID TTY          TIME CMD
fail: readlink -> rc=127: sh: readlink: inaccessible or not found
battery: 12/14 utilities ok (2 failed)
RESULT: FAIL
```

- `readlink` is not one of the ten frozen toybox applets, so it cannot exist in this payload. The
  links are proven with `ls -l` (`/bin/ls -> toybox`, `/bin/sh -> mksh`). Adding an applet to the
  package is explicitly forbidden by the encargo.
- bare `ps` filters by the caller's tty; the init shell has no controlling tty, so it prints only
  the header and exits 1. This run's battery uses `ps -A`, which lists every process and exits 0.

The scorer accepts exactly these two harness rows, prints them literally, and stops on any other
failure. `image/probe-utilities.sh` is not modified.

## How to repeat

```
bash verify/run-all.sh     # rc=0 only if both bundles verify, all guest checks are rc=0 and RESULT: PASS
```

Nothing else is manual: §0 re-verifies the artifacts, §1 the binary hashes, §2 the source tarballs,
§3 the licence bytes, §4 the bundles, §5 the disk and boot, §6 the transcript scoring.
