# verify — end-to-end integration chain (area `integracion-sond`)

One command runs the whole chain: real bundles → real disk → SeaBIOS boot → the basic utilities
working inside the guest, proven from the serial transcript.

```
bash verify/run-all.sh
```

Measured result of the 2026-11-18 run: rc=0, `BATTERY ok=21 fail=0`, `RESULT: PASS`,
`SeaBIOS banners: 1`, `OVMF mentions: 0`.

## What it consumes

`READY-toolchain` and `READY-image` were never published, so the script consumes the measured
artifacts directly. `READY-packager` does exist and is cross-checked.

| source | what is used |
|---|---|
| `/tank/tmp/gr4v5ond7/forks/artifacts/bin/{toybox,mksh}` | the two static binaries, checked against the measured sha256 constants and `file` |
| `/tank/tmp/gr4v5ond7/forks/src/{toybox,mksh,musl}-sond` | the pinned commits (`0.8.15`, `mksh-R59`, `v1.2.5`), validated with `git cat-file` + `git rev-parse <tag>` |
| `/tank/tmp/gr4v5ond7/forks/artifacts/READY-packager` | `tool=`; its `tool` path must match the measured path, and its 43-test suite is run first |
| `…oc-toolchain-musl/toolchain/build-*.sh` | the build recipes recorded by hash in the manifests |
| `…oc-image-seabios/image/build-disk.sh`, `run-qemu.sh` | called through `bash` (the files are not marked executable) |

A missing artifact or a sha mismatch stops the script with a clear failure; it never fabricates an
artifact to keep going.

## What it produces

- `/tank/tmp/gr4v5ond7/forks/integ/bundles/<name>-<ver>-<H12>/` — the two real bundles with their
  `MANIFEST`, built by the real packager, verified by its `verify-bundle` and by an independent
  recomputation of the canonical payload hash.
- `/tank/tmp/gr4v5ond7/forks/integ/manifest-material/` — source tarballs cut with
  `git archive --format=tar | gzip -n` from the fork clones at the pinned commits, the verbatim
  licence texts, and the build recipes.
- `/tank/tmp/gr4v5ond7/forks/integ/rootfs/` — the merged payload tree handed to the image builder.
- `/tank/tmp/gr4v5ond7/forks/integ/disk/` — the disk built by the image area's `build-disk.sh`.
- `/tank/tmp/gr4v5ond7/forks/integ/qemu-serial.log` — the full serial transcript (never trimmed);
  it contains the init battery, every `VERIFY-OK: <utility> :: rc=0` line, `BATTERY ok=21 fail=0`
  and `RESULT: PASS`.

## Steps

1. Verify binaries before consuming: sha256 against the measured constants, `file` must say
   `statically linked`; the toybox applet list must be exactly `cat cp echo grep ls mkdir mount mv
   ps rm`; `mksh` must report `MIRBSD KSH R59`.
2. Source material by hash: `git archive` tarballs (toybox, mksh, musl), fork patches (counted, or
   declared absent), build recipes from the toolchain worktree.
3. Licence texts verbatim from the fork trees: toybox `LICENSE` (0BSD), musl `COPYRIGHT` complete
   (goes into both packages), mksh MirOS block from `sh.h:11-32` and the Unicode notice from
   `expr.c:888-926`.
4. Build `toybox-static` and `mksh-static` with the packager; `verify-bundle` both; paste both
   manifests.
5. Merge the payloads (toybox first, mksh second; only a colliding file/symlink is an error),
   build the disk, boot on SeaBIOS, capture `qemu-serial.log`.
6. Score the battery from the transcript: `ls ps cat grep echo mkdir cp mv rm mount sh cd`
   (`cd` as an mksh builtin, `ps -A` so it works without a controlling tty), symlink evidence
   (`/bin/ls -> toybox`, `/bin/sh -> mksh`), the frozen applet list, licences visible inside the
   guest, SeaBIOS present / OVMF absent.

## Decisions taken (recorded, not negotiated)

- Symlink targets are **relative** (`toybox`, `mksh`), as `02-contrato.md` §C writes them, so
  `ls -l /bin/ls` prints `-> toybox` and `ls -l /bin/sh` prints `-> mksh`. The canonical hash
  treats a symlink as its target string, so this choice is part of the bundle hash.
- **No `readlink` applet is added.** The toybox package freezes exactly ten applets; the encargo
  says not to add any. The links are proven with `ls -l`, and the image harness's own `readlink`
  row is declared as a harness artifact (see below).
- The battery is fed over the serial console (`verify/serial-battery.sh` lines passed as repeatable
  `--cmd` arguments), so the rootfs tree stays exactly the merged payloads — no extra verifier
  files inside the tree.
- `rm -r` (never `rm -rf`) is used, only on this area's own output dirs, for idempotency.
- The verdict `RESULT: PASS` is printed **by the guest** into the serial transcript; the host
  script separately checks SeaBIOS present / OVMF absent and the bundle hashes.
- The image area's scripts are invoked with `bash` because they are not executable in its worktree;
  this is read-only use of its interface, not a change to that area.

## Declared deviations and harness artifacts

- The Unicode notice shipped as `share/licenses/mksh-static/UNICODE-NOTICE` is the verbatim block
  `expr.c:888-926` (the hallazgos anchor was `888-905`, but that cut ends mid-sentence, inside the
  permission grant; the block closes with its `*/` at line 926). The tree wins, the deviation is
  declared.
- musl's `COPYRIGHT` in the pinned tree is **6204 B**, not the 6196 B quoted in the brief. The full
  file from the tree is shipped; the check is `> 6000 B` + `Rich Felker`, not the quoted size.
- The image area's init battery (`image/probe-utilities.sh`) reports two red rows that are not
  package failures:
  - `readlink` — the applet is outside the frozen ten (`rc=127`); links proven with `ls -l`.
  - `ps` (bare) — the init shell has no controlling tty and toybox's bare `ps` filters by the
    caller's tty, so it prints only the header and exits 1. This run's own `ps -A` lists every
    process and exits 0.
  The scorer accepts exactly those two, prints them verbatim, and stops on any other harness
  failure. The image area's files are not modified.
