# toolchain: static, reproducible binaries for the Sond distro

This area builds the distribution's commands and its shell: toybox 0.8.15 and
mksh R59, both linked statically against musl 1.2.5. The result is published
under `/tank/tmp/gr4v5ond7/forks/artifacts/` for the packager and the image
builder to consume.

| item | value |
|---|---|
| toybox | 0.8.15, upstream commit `a57b091d05ec366dcd4dd737784c03761cb6a4b1` |
| mksh | mksh-R59, upstream commit `8deec0b465ed59108331b0a112564f2a89156536` |
| musl | 1.2.5, commit `0784374d561435f7c787a555aeab8ede699ed298`, built from the release tarball |
| `SOURCE_DATE_EPOCH` | `1794960000` (2026-11-18T00:00:00Z) |
| commands | `cat cp echo grep ls mkdir mount mv ps rm` (no `sh`: the shell is mksh) |

## Scripts

| script | what it does |
|---|---|
| `build-forks.sh` | clones the three upstreams at their pinned revisions into `forks/src/`, branch `sond`. Only needed for provenance/patching; the binaries are built from sources copied locally. |
| `build-musl.sh` | downloads `musl-1.2.5.tar.gz`, checks its sha256, builds and installs it into `forks/toolchain` with `--disable-shared`, then proves `musl-gcc` produces a static hello that runs. |
| `build-toybox.sh` | one toybox build from a fork checkout: `allnoconfig` + the ten utilities, `-Os`, prefix-mapped paths, static, stripped. |
| `build-mksh.sh` | one mksh build from a fork checkout: `Build.sh -r` with `LDSTATIC=-static`, `-Os`, prefix-mapped paths, stripped. |
| `build-clean.sh DIR` | the unit `test-reproducible.sh` runs twice: a pristine copy of both trees into `DIR`, built with the exact flags above. |
| `test-reproducible.sh` | gate 1: two clean builds in two different directories must give the same sha256. Writes `artifacts/repro/build-{a,b}.sha256`. |
| `test-static.sh` | gate 2: the published binaries are static and every utility runs on the host, and `cd`/`pwd` work inside mksh. |

`common.sh` holds the shared configuration and the pinned revisions; every
script sources it. The evidence of the run — literal output, hashes, `file`
output — is in `pruebas.md`.

## Where the builds happen

`/tank/tmp` is NFS and slow (measured 0.23 s per small file write). Builds
therefore run under `/tmp/tc-work` (local disk, 14 GiB free) and only the
results are copied to the contract paths under `/tank/tmp/gr4v5ond7/forks/`.
The binaries do not depend on the build path: the source root is rewritten to
`.` through `-ffile-prefix-map`/`-fdebug-prefix-map`, which is what makes the
two clean builds comparable. Set `TOOLCHAIN_WORK` to build somewhere else.

musl is built from its release tarball rather than the git checkout: cloning
`git.musl-libc.org` takes over 5 minutes on this host and the NFS checkout is
corrupt. The tarball corresponds to the pinned commit and its sha256 is pinned
in `common.sh`.

## Reproducibility

The recipe, in the order the levers matter:

1. `-Wl,--build-id=none` — a build id would otherwise carry content hashes and,
   depending on the linker, paths.
2. `-ffile-prefix-map=$PWD=.` and `-fdebug-prefix-map=$PWD=.` — the absolute
   build directory never reaches the binary.
3. the same `strip -s` in every run, after `chmod u+w` (toybox links itself
   `0555`, which strip refuses to rewrite).
4. the same compiler (`musl-gcc` from the private prefix), the same flags and
   the same argument order.

The published prefix was moved from `/tmp/tc-work/prefix` to
`/tank/tmp/gr4v5ond7/forks/toolchain`; `bin/musl-gcc` and
`lib/musl-gcc.specs` were rewritten to the new path and re-tested there. The
tarball in `artifacts/toolchain/` is that relocated prefix.

## Publishing

```
artifacts/bin/toybox                     0755
artifacts/bin/mksh                       0755
artifacts/toolchain/musl-1.2.5-prefix.tar.gz
artifacts/repro/build-a.sha256
artifacts/repro/build-b.sha256
artifacts/SHA256SUMS
artifacts/READY-toolchain                written last, only when both gates pass
```

`READY-toolchain` follows the key/value format of `02-contrato.md` §A and is
the marker the other areas wait for.
