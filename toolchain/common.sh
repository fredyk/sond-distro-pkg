# Shared configuration for the Sond toolchain build scripts.
# Sourced, never executed. Shell: bash.
#
# Everything here is either pinned by the encargo or measured on this host;
# nothing is guessed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Contract data roots (02-contrato.md section A). Written by this area only.
# ---------------------------------------------------------------------------
FORKS=/tank/tmp/gr4v5ond7/forks
SRC_ROOT=$FORKS/src
PREFIX=$FORKS/toolchain
ARTIFACTS=$FORKS/artifacts
PATCH_DIR=$FORKS/forks

# Clean-build scratch.
#
# /tank/tmp is NFS: measured 2026-11-18, 200 small file writes took 46.8 s
# (0.23 s per file) against 0.01 s in /tmp. A toybox tree alone is 605 files
# and the reproducibility gate builds it twice, so busy work lives in /tmp,
# where the 14 GiB local disk also fits comfortably. Binaries do not depend on
# this path: -ffile-prefix-map rewrites it, which is what makes the two builds
# comparable. Set TOOLCHAIN_WORK=/tank/tmp/gr4v5ond7/forks to build on the
# contract mount instead.
WORK_ROOT=${TOOLCHAIN_WORK:-/tmp/tc-work}
BUILD_A=$WORK_ROOT/a
BUILD_B=$WORK_ROOT/b

# ---------------------------------------------------------------------------
# Pinned upstream revisions (measured with ls-remote on 2026-11-18).
# ---------------------------------------------------------------------------
TOYBOX_URL=https://github.com/landley/toybox
TOYBOX_TAG=0.8.15
TOYBOX_COMMIT=a57b091d05ec366dcd4dd737784c03761cb6a4b1

MKSH_URL=https://github.com/MirBSD/mksh
MKSH_TAG=mksh-R59
MKSH_COMMIT=8deec0b465ed59108331b0a112564f2a89156536

# musl is built from its release tarball, not from the git checkout: a full
# clone of git.musl-libc.org takes over 5 minutes here, the tarball takes
# 2.4 s, and the NFS copy of the checkout is corrupt. The tarball still
# corresponds to the pinned commit; the clone under SRC_ROOT is kept only as
# provenance.
MUSL_URL=https://musl.libc.org/releases/musl-1.2.5.tar.gz
MUSL_TARBALL=musl-1.2.5.tar.gz
MUSL_TARBALL_SHA256=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
MUSL_TAG=v1.2.5
MUSL_COMMIT=0784374d561435f7c787a555aeab8ede699ed298

# ---------------------------------------------------------------------------
# Reproducibility (RFC-0018): two clean builds, same bytes.
# ---------------------------------------------------------------------------
# 2026-11-18T00:00:00Z, the date this area was written; recorded in README.md
# and pruebas.md. The recipe is not allowed to invent another one.
SOURCE_DATE_EPOCH=1794960000
export SOURCE_DATE_EPOCH

export LC_ALL=C
export LANG=C
export TZ=UTC
# The global git config aliases github.com to an unresolvable ssh host on this
# machine; every git call against GitHub must bypass it.
export GIT_CONFIG_GLOBAL=/dev/null

JOBS=6

# Reproducibility flags shared by every compile.
#   -ffile-prefix-map / -fdebug-prefix-map  the absolute build-tree path must
#       not reach the binary: build-a and build-b live in different directories.
#   -Wl,--build-id=none                     a build id can carry temp paths.
repro_cflags() { # $1 = absolute root of the source tree being compiled
	printf '%s' "-Os -pipe -ffile-prefix-map=$1=. -fdebug-prefix-map=$1=."
}

repro_ldflags() {
	printf '%s' "-Wl,--build-id=none"
}

# The ten utilities this area has to ship. No sh: /bin/sh is mksh, and the
# toybox toysh lives in toys/pending, which is not built.
TOYBOX_COMMANDS="cat cp echo grep ls mkdir mount mv ps rm"

# Absolute path of the two delivered binaries, once published.
TOYBOX_BIN=$ARTIFACTS/bin/toybox
MKSH_BIN=$ARTIFACTS/bin/mksh
