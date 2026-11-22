# Shared configuration for the Sond toolchain build scripts.
# Sourced, never executed. Shell: bash.
#
# Everything here is either pinned by the encargo or measured on this host;
# nothing is guessed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Contract data roots (02-contrato.md section A). Written by this area only.
# ---------------------------------------------------------------------------
FORKS=${SOND_FORKS:-/tank/tmp/gr4v5ond7/forks}
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
# Pinned revisions. Every tree is cloned from fredyk's GitHub fork
# (fredyk/<name>-sond, made 2026-11-21 with secretd-github fork); the upstream
# is kept only as provenance. Each fork's release tag resolves to the pinned
# commit (test-sources-are-forks.sh reads it with ls-remote).
# ---------------------------------------------------------------------------
TOYBOX_URL=https://github.com/fredyk/toybox-sond
TOYBOX_UPSTREAM=https://github.com/landley/toybox
TOYBOX_TAG=0.8.15
TOYBOX_COMMIT=a57b091d05ec366dcd4dd737784c03761cb6a4b1

MKSH_URL=https://github.com/fredyk/mksh-sond
MKSH_UPSTREAM=https://github.com/MirBSD/mksh
MKSH_TAG=mksh-R59
MKSH_COMMIT=8deec0b465ed59108331b0a112564f2a89156536

# musl's own server is slow to clone (over 5 minutes); its GitHub fork is not,
# so musl is built from the fork's pinned tree like the other two.
MUSL_URL=https://github.com/fredyk/musl-sond
MUSL_UPSTREAM=https://git.musl-libc.org/git/musl
MUSL_TAG=v1.2.5
MUSL_COMMIT=0784374d561435f7c787a555aeab8ede699ed298

# ncurses is released as snapshots; v6_6 is the 6.6 release (an annotated tag,
# so the pinned commit is the tag's target, not the tag object).
NCURSES_URL=https://github.com/fredyk/ncurses-sond
NCURSES_UPSTREAM=https://github.com/ThomasDickey/ncurses-snapshots
NCURSES_TAG=v6_6
NCURSES_VERSION=6.6
NCURSES_COMMIT=0096bd402c4a9c8f39bd7ed266e1b8920327e4d8

# linux-headers: the kernel's sanitized UAPI headers (make headers_install) as
# sabotage-linux keeps them, with its musl fixes to libc-compat.h; the tag is
# lightweight and resolves straight to the commit.
LINUX_HEADERS_URL=https://github.com/fredyk/linux-headers-sond
LINUX_HEADERS_UPSTREAM=https://github.com/sabotage-linux/kernel-headers
LINUX_HEADERS_TAG=v6.12.77
LINUX_HEADERS_COMMIT=eda76135ba1d81d84780af71dcb1b302eb641d39

# htop 3.5.3 is a lightweight tag: the tag resolves straight to the commit.
HTOP_URL=https://github.com/fredyk/htop-sond
HTOP_UPSTREAM=https://github.com/htop-dev/htop
HTOP_TAG=3.5.3
HTOP_COMMIT=20882b8ef8271fb49ea0eb74bbfd484e9b0a11d8
# The distro version: -r<n> counts Sond rebuilds of the same release (r1: the version string
# no longer comes from git describe of the sond branch).
HTOP_VERSION=3.5.3-r1

# incus v7.6.0 is an annotated tag; its commit is pinned. The distro version carries -sond1: the
# name stays incus without presenting the build as a Linux Containers release (opinion 2.10).
INCUS_URL=https://github.com/fredyk/incus-sond
INCUS_UPSTREAM=https://github.com/lxc/incus
INCUS_TAG=v7.6.0
INCUS_COMMIT=8f5e6c2235f6424ec59d3dc06f12e344a4a416e2
INCUS_VERSION=7.6.0-sond1

# libuv v1.53.0 is an annotated tag; its commit is pinned. A dependency of raft and cowsql (incusd).
LIBUV_URL=https://github.com/fredyk/libuv-sond
LIBUV_UPSTREAM=https://github.com/libuv/libuv
LIBUV_TAG=v1.53.0
LIBUV_COMMIT=840404ce8ba7cc0204be52389a6cfff9f2c90fb6

# SQLite 3.54.1 from its GitHub mirror; the tag is lightweight. A dependency of cowsql (incusd).
SQLITE_URL=https://github.com/fredyk/sqlite-sond
SQLITE_UPSTREAM=https://github.com/sqlite/sqlite
SQLITE_TAG=version-3.54.1
SQLITE_COMMIT=57520227c95396ce39ba6ecaac8d475b78dd3964

# raft v0.22.1 and cowsql v1.15.9 (lightweight tags): incusd's distributed SQLite. Their forks add
# gnu.org's GPL-3.0 and LGPL-3.0 texts (COPYING, COPYING.LESSER), which LGPL-3.0 asks for.
RAFT_URL=https://github.com/fredyk/raft-sond
RAFT_UPSTREAM=https://github.com/cowsql/raft
RAFT_TAG=v0.22.1
RAFT_COMMIT=9edb176a7924ce2b943cb56552366dc4b5a1a6b7
COWSQL_URL=https://github.com/fredyk/cowsql-sond
COWSQL_UPSTREAM=https://github.com/cowsql/cowsql
COWSQL_TAG=v1.15.9
COWSQL_COMMIT=783815b901470e27b7dfbcce3a67c888dad19e78

# attr v2.6.0, libcap v1.2.78, acl v2.4.0, libseccomp v2.6.2 and lxc v7.0.0 are annotated tags; their commits
# are pinned. The rest of what incusd links: libcap's BSD-3-Clause branch is the one elected
# (licence opinion, incusd table); libacl
# includes attr's error_context.h; lxc is built without openssl, so no libcrypto is linked.
ATTR_URL=https://github.com/fredyk/attr-sond
ATTR_UPSTREAM=https://git.savannah.gnu.org/r/attr.git
ATTR_TAG=v2.6.0
ATTR_COMMIT=c440855d6b33446edf4b5eb1a2d892281f15a99b
# libudev-zero 1.0.5 (a lightweight tag): libudev without udevd, for incusd's hotplug.
LIBUDEV_ZERO_URL=https://github.com/fredyk/libudev-zero-sond
LIBUDEV_ZERO_UPSTREAM=https://github.com/illiliti/libudev-zero
LIBUDEV_ZERO_TAG=1.0.5
LIBUDEV_ZERO_COMMIT=7a6eee2db11f2eb0f7fd065ae9597fcd270e6734
LIBCAP_URL=https://github.com/fredyk/libcap-sond
LIBCAP_UPSTREAM=https://git.kernel.org/pub/scm/libs/libcap/libcap.git
LIBCAP_VERSION=1.2.78-sond1 # -sond1: its own uapi headers win over the sysroot's since -isystem, so no linux-headers
LIBCAP_TAG=v1.2.78
LIBCAP_COMMIT=a1fef85d27d0ee12729a64d1c9b2183c6007e56a
ACL_URL=https://github.com/fredyk/acl-sond
ACL_UPSTREAM=https://git.savannah.gnu.org/r/acl.git
ACL_TAG=v2.4.0
ACL_COMMIT=3589787cd589b34bdd9265936e17190b6d3f17d1
LIBSECCOMP_URL=https://github.com/fredyk/libseccomp-sond
LIBSECCOMP_UPSTREAM=https://github.com/seccomp/libseccomp
LIBSECCOMP_TAG=v2.6.2
LIBSECCOMP_COMMIT=72d90906ebcc6a2706868d58404e10a3086ed142
LXC_URL=https://github.com/fredyk/lxc-sond
LXC_UPSTREAM=https://github.com/lxc/lxc
LXC_VERSION=7.0.0-sond1 # -sond1: 7.0.0 went out holding LTO bytecode, which links under one gcc only
LXC_TAG=v7.0.0
LXC_COMMIT=e4415af07e3ec291205bc828e2b4e8141f91a499

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
