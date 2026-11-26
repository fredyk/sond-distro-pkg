# `docker` — Docker's official static build as a Sond package

The `docker` package is the eight binaries of Docker's own static build of **29.10.1**,
unpacked from the official tarball and published with their licence texts. Nothing is
compiled, linked, stripped or patched: `payload_hash` describes the bytes
`download.docker.com` published.

| | |
|---|---|
| package | `docker` |
| version | `29.10.1` |
| tier | `public` |
| licence | `Apache-2.0 AND MIT` |
| linkage | `static prebuilt binaries from the official docker-29.10.1 static tarball` |
| recipe | `ci/forks/docker-sond.yml` (lives in the fork as `.github/workflows/sond-package-docker.yml`) |
| pins | `toolchain/common.sh` (`DOCKER_*`) |
| gate | `ci/test-docker-payload.sh`, `ci/test-fork-workflows.sh` |

## What the package contains

```
payload/bin/{dockerd,docker,containerd,containerd-shim-runc-v2,runc,docker-proxy,docker-init,ctr}
payload/share/licenses/docker/{COPYING,NOTICE,docker-cli-LICENSE,docker-cli-NOTICE,
  containerd-LICENSE,containerd-NOTICE,runc-LICENSE,runc-NOTICE,tini-LICENSE}
```

17 files. The eight binaries are byte-for-byte the tarball's (`sha256sum` of
`payload/bin/*` equals that of the extracted tarball), mode `0755`, and the nine licence
texts are byte-for-byte the files of the commits they were fetched from.

### The pin

| data | value |
|---|---|
| url | `https://download.docker.com/linux/static/stable/x86_64/docker-29.10.1.tgz` |
| sha256 | `061642059fa7f2ed9b2f04a327a951cff4249585cf04b2661c2a6539197c9962` |
| size | 78759647 bytes (mtime inside the tar 2026-11-24 19:49) |
| engine | `github.com/moby/moby` tag `docker-v29.10.1` → `54cd494d0b39abfc7a958fcc876f706271f8b909` |
| cli | `github.com/docker/cli` tag `v29.10.1` → `c48360f51c53d2029ab6721ad4d012f9e14df846` |

`--upstream` takes one `repo@sha40`, so it names the engine; the cli commit is in this
file and in the workflow's header comment. Both were resolved with
`GIT_CONFIG_GLOBAL=/dev/null git ls-remote --tags <repo> 'refs/tags/<tag>'` (the two
aliases in the global git config break plain https clones on this machine).

The rest of the payload, resolved from moby's `Dockerfile` at the pinned commit and
confirmed by running the binaries themselves (`--version`):

| binary | component | version | commit | bytes |
|---|---|---|---|---|
| `dockerd`, `docker`, `docker-proxy` | moby / docker cli | 29.10.1 | `54cd494…` / `c48360f…` | 101951568 · 34627549 · 2796392 |
| `containerd`, `containerd-shim-runc-v2`, `ctr` | containerd | v2.4.2 | `b7a25261e029d68978bbf290df0a62fc819b3c51` | 39497888 · 8478880 · 23584928 |
| `runc` | runc | v1.5.3 | `46365c62967c76a765a5e347f48f0c7b3b571fe9` | 15088808 |
| `docker-init` | tini | v0.19.0 | `de40ad007797e0dcd8b7126f27bb87401d224240` | 743016 |

`file` reports `dockerd` and `docker` as "ELF 64-bit … statically linked" and `runc` as
static-pie, as the tarball ships them.

## The recipe

`ci/forks/docker-sond.yml` declares `name: docker`, `version: 29.10.1`,
`license: Apache-2.0 AND MIT`, `upstream: github.com/moby/moby@54cd494…` and this
`build:` block:

1. `curl -fsSLO` the tarball and verify the pin **at build time** with
   `sha256sum -c <<<"<sha256>  docker-29.10.1.tgz"` — the pin is enforced, not merely
   documented (`ci/test-docker-payload.sh` checks that the recipe and
   `toolchain/common.sh` carry the same one, and only one copy, in `common.sh`);
2. unpack `docker/` and `install -m 0755` the eight named binaries into
   `$SOND_PAYLOAD/bin`;
3. stage the licence texts of the four components the fork does not carry (below).

No strip, no patch, no byte rewrite: `payload_hash` describes Docker's own binaries.

### Licence texts, and where each one comes from

`Apache-2.0 AND MIT` (`sondpkg.spdx.check_license` accepts it; `sondpkg needs-source`
answers 1 — no source lane, so the workflow publishes no `<name>-source` bundle, exactly
like `incus`). Every text is shipped through `license-files:`, which `build.sh` copies
into the payload and records in the MANIFEST's `licences = [...]`:

| shipped as | text | read from |
|---|---|---|
| `share/licenses/docker/COPYING` | Apache-2.0 licence (4(a)) | this fork's `LICENSE` @ `54cd494…` |
| `share/licenses/docker/NOTICE` | the engine's notice (4(d)) | this fork's `NOTICE` @ `54cd494…` |
| `share/licenses/docker/docker-cli-LICENSE` | Apache-2.0 | `docker/cli@c48360f…/LICENSE` |
| `share/licenses/docker/docker-cli-NOTICE` | cli notice (4(d)) | `docker/cli@c48360f…/NOTICE` |
| `share/licenses/docker/containerd-LICENSE` | Apache-2.0 | `containerd/containerd@b7a2526…/LICENSE` |
| `share/licenses/docker/containerd-NOTICE` | containerd notice (4(d)) | `containerd/containerd@b7a2526…/NOTICE` |
| `share/licenses/docker/runc-LICENSE` | Apache-2.0 | `opencontainers/runc@46365c6…/LICENSE` |
| `share/licenses/docker/runc-NOTICE` | runc notice (4(d)) | `opencontainers/runc@46365c6…/NOTICE` |
| `share/licenses/docker/tini-LICENSE` | MIT (tini, what `docker-init` is) | `krallin/tini@de40ad0…/LICENSE` |

`NOTICE` is not optional under Apache-2.0 §4(d), and each component has its own, so each
travels under its own name. Nothing is typed from memory: the engine's two are files of
the fork checkout; the other seven are fetched by the build block from commit-scoped
`raw.githubusercontent.com` URLs, which are immutable.

Why fetch them in the build block instead of committing them to the fork: `build.sh`
takes every licence file from the fork tree, this fork *is* moby plus the workflow file,
and `sondpkg check-change-marks` refuses an added file that carries no
`Modified by the Sond project, YYYY-MM-DD` mark (an official licence text is exempt only
if its sha256 is in `LICENCE_TEXTS`, which lists kernel and gnu.org texts, not these).
Downloading them untracked during the build keeps both rules intact.

## The linkage line

```
linkage: static prebuilt binaries from the official docker-29.10.1 static tarball
```

It must be truthful, and it must name neither `musl` nor `Go`: `build.sh:267-270` forces a
`musl-COPYRIGHT` file into the payload when the linkage text matches `*musl*`, and
`build.sh:277-290` runs `go version -m` plus `sondpkg go-licences` when it contains the
word `Go` (which would also demand `go` in `bundled`, refused by `validate_linking`).
Which libc the official build used cannot be proved from this recipe — the binaries are
already linked — so naming one would be inventing evidence; the line says what is
actually known: prebuilt static binaries from the pinned tarball.

## The end-to-end build (what was run here)

`ci/test-fork-builds.sh docker` needs the fork repo `fredyk/docker-sond`, which does not
exist and this VM cannot create, so the recipe was proven with the same inputs, read out
of `ci/forks/docker-sond.yml` with `inputs_of` (the reader `ci/test-fork-builds.sh`
itself uses, so `--build` is the workflow's block verbatim and not a retyped copy),
against a moby checkout at the pinned commit (`/tmp/docker-work/moby-fork`,
`HEAD = 54cd494d0b39abfc7a958fcc876f706271f8b909`):

```bash
SOND_DISTRO_PKG=$PWD SOND_WORK=$(mktemp -d) \
bash /home/fred/dev/projects/sond-build-action/build.sh \
  --fork /tmp/docker-work/moby-fork --repository fredyk/docker-sond \
  --name docker --version 29.10.1 \
  --license 'Apache-2.0 AND MIT' \
  --upstream github.com/moby/moby@54cd494d0b39abfc7a958fcc876f706271f8b909 \
  --linkage 'static prebuilt binaries from the official docker-29.10.1 static tarball' \
  --license-file LICENSE=share/licenses/docker/COPYING \
  --license-file NOTICE=share/licenses/docker/NOTICE \
  --license-file .sond-licences/docker-cli/LICENSE=share/licenses/docker/docker-cli-LICENSE \
  --license-file .sond-licences/docker-cli/NOTICE=share/licenses/docker/docker-cli-NOTICE \
  --license-file .sond-licences/containerd/LICENSE=share/licenses/docker/containerd-LICENSE \
  --license-file .sond-licences/containerd/NOTICE=share/licenses/docker/containerd-NOTICE \
  --license-file .sond-licences/runc/LICENSE=share/licenses/docker/runc-LICENSE \
  --license-file .sond-licences/runc/NOTICE=share/licenses/docker/runc-NOTICE \
  --license-file .sond-licences/tini/LICENSE=share/licenses/docker/tini-LICENSE \
  --build "$(the build block of ci/forks/docker-sond.yml, verbatim)" \
  --out /tmp/docker-bundle
```

Result:

```
docker-29.10.1.tgz: OK
bundle=/tmp/docker-bundle/docker-29.10.1-0b6c7574d7f9
payload_hash=sha256:0b6c7574d7f96641d72db2457d7b75e0a2def3b0acc365c249e600dc314e31f1
```

```bash
python3 sondpkg/bin/sondpkg verify-bundle /tmp/docker-bundle/docker-29.10.1-0b6c7574d7f9
python3 sondpkg/bin/sondpkg show /tmp/docker-bundle/docker-29.10.1-0b6c7574d7f9
python3 sondpkg/bin/sondpkg object-id /tmp/docker-bundle/docker-29.10.1-0b6c7574d7f9
python3 sondpkg/bin/sondpkg needs-source 'Apache-2.0 AND MIT'
```

Output, verbatim:

```
ok: docker 29.10.1 sha256:0b6c7574d7f96641d72db2457d7b75e0a2def3b0acc365c249e600dc314e31f1 (17 files)
name = docker
version = 29.10.1
license = Apache-2.0 AND MIT
tier = public
source = github.com/fredyk/docker-sond@54cd494d0b39abfc7a958fcc876f706271f8b909
upstream = github.com/moby/moby@54cd494d0b39abfc7a958fcc876f706271f8b909
linkage = static prebuilt binaries from the official docker-29.10.1 static tarball
bundle = sha256:0b6c7574d7f96641d72db2457d7b75e0a2def3b0acc365c249e600dc314e31f1
files = 17
licences = share/licenses/docker/COPYING, share/licenses/docker/NOTICE, share/licenses/docker/docker-cli-LICENSE, share/licenses/docker/docker-cli-NOTICE, share/licenses/docker/containerd-LICENSE, share/licenses/docker/containerd-NOTICE, share/licenses/docker/runc-LICENSE, share/licenses/docker/runc-NOTICE, share/licenses/docker/tini-LICENSE
sources = sha256:f69c4b9ef63445bee157f0e13d60626edd5bc2e8ce6c4916c29ab72e7542dc8f docker-29.10.1.tar.gz
sha256:46e7adc3d1696f3fc216f974ed5b793d844bf3e9cc540e58b0da716636d462ec
needs-source: exit 1 (no source lane)
```

`sondpkg/bin/sondpkg` is Python with no shebang: always `python3 sondpkg/bin/sondpkg`.

## Publishing: what blocks it (operator's checklist)

Everything up to the signature is done and verified above: the recipe, the pins, the
bundle, its `payload_hash`/`object-id`, `verify-bundle`, `show` and `needs-source`.
Publishing is blocked by three verified facts:

1. **No `fredyk/docker-sond` repo exists**, and this VM cannot create GitHub repos.
   The fork must carry `.github/workflows/sond-package-docker.yml`, generated from
   `ci/forks/docker-sond.yml`.
2. **`SOND_PUBLISH_TOKEN` and `SOND_SIGNING_KEY` exist only as GitHub Actions secrets**;
   nothing on this machine can sign or publish a bundle.
3. **The signing key on this machine is dist.sond.dev's verification key** (the public
   one), not the key that signs what the registry accepts.

What an operator with GitHub access runs, once 1 and 2 hold:

```bash
gh workflow run sond-package-docker.yml -R fredyk/docker-sond
```

The workflow builds with `fredyk/sond-build-action@v1` and publishes with
`fredyk/sond-publish-action@v1` (`secrets.SOND_PUBLISH_TOKEN` + `secrets.SOND_SIGNING_KEY`).
There is no `source-bundle:` input in its publish step: the licence is not copyleft, and
`sondpkg needs-source 'Apache-2.0 AND MIT'` exits 1, so `build.sh` produces no
`<name>-source` bundle to publish first.
