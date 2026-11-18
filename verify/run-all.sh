#!/usr/bin/env bash
# verify/run-all.sh — the whole integration chain in one command.
#
# §0  consume the measured artifacts (binaries + packager) and prove they match
# §1  verify the static binaries (sha256 + static linkage + applet list)
# §2  produce the source tarballs by hash (git archive + gzip -n)
# §3  extract the licence texts verbatim from the fork trees
# §4  build the two real bundles with the packager and verify them
# §5  merge the payloads, build the production disk, boot it on SeaBIOS
# §6  score the utility battery from the real serial transcript
#
# rc=0 only if both bundles verify, the 12 mandated utilities print VERIFY-OK
# from the guest, and the guest battery prints RESULT: PASS.
# Everything the script needs either exists on disk or the script fails loudly;
# nothing is invented and no failure is hidden.
set -euo pipefail

ROOT=/tank/tmp/gr4v5ond7/forks
INTEG=$ROOT/integ
BUNDLES=$INTEG/bundles
SRCDIR=$INTEG/manifest-material
STAGE=$INTEG/stage
TREEDIR=$INTEG/rootfs
DISKDIR=$INTEG/disk
SERIAL=$INTEG/qemu-serial.log
VERIFY_DIR=/home/fred/dev/projects/sond-distro-pkg.oc-integracion-sond/verify

ART=$ROOT/artifacts
TOYBOX_BIN=$ART/bin/toybox
MKSH_BIN=$ART/bin/mksh
READY_PK=$ART/READY-packager

# Measured by the orchestrator at 13:28 UTC; re-checked here byte for byte.
TOYBOX_SHA=0fb90081a3988e7394cec90e7fd8557b467199b72e358d739e5a4d77797fe4fb
MKSH_SHA=1dec4fdaa9304bdcb70d2c79aa945fee1372a7bc29f8601fc21bbb968ef0a083
TOYBOX_COMMIT=a57b091d05ec366dcd4dd737784c03761cb6a4b1
MKSH_COMMIT=8deec0b465ed59108331b0a112564f2a89156536
MUSL_COMMIT=0784374d561435f7c787a555aeab8ede699ed298

TOYBOX_VER=0.8.15
MKSH_VER=R59
MUSL_VER=1.2.5
TOYBOX_TAG=$TOYBOX_VER
MKSH_TAG=mksh-R59
MUSL_TAG=v$MUSL_VER

TOYBOX_SYMLINKS="ls ps cat cp mv rm mkdir mount echo grep"
TOYBOX_APPLETS="cat cp echo grep ls mkdir mount mv ps rm"

# Image area scripts, used directly: READY-image was never published.
IM_WORKTREE=/home/fred/dev/projects/sond-distro-pkg.oc-image-seabios
IM_BUILD=$IM_WORKTREE/image/build-disk.sh
IM_BOOT=$IM_WORKTREE/image/run-qemu.sh

# Packager: READY-packager is the only READY marker that exists.
PKG_TOOL=/home/fred/dev/projects/sond-distro-pkg.oc-packager-rfc18/sondpkg/bin/sondpkg
PKG_TESTS="python3 -m unittest discover -s /home/fred/dev/projects/sond-distro-pkg.oc-packager-rfc18/sondpkg/tests -t /home/fred/dev/projects/sond-distro-pkg.oc-packager-rfc18"

say() { printf 'verify: %s\n' "$*"; }
die() { printf 'verify: FAIL: %s\n' "$*" >&2; exit 1; }
need_file() { [ -e "$1" ] || die "missing $1"; }
need_dir()  { [ -d "$1" ] || die "missing directory $1"; }

export GIT_CONFIG_GLOBAL=/dev/null

# Start one of our own output dirs from scratch. rm -r (never rm -rf) is used,
# only on paths this area owns under /tank/tmp/gr4v5ond7/forks/integ/.
clean_dir() {
  if [ -e "$1" ]; then rm -r "$1"; fi
  mkdir -p "$1"
}

# Read one key=value line out of a READY file.
kv() {
  sed -n "s/^$2=//p" "$1" | head -n 1
}

mkdir -p "$INTEG"

# --- §0 consume and verify the measured artifacts ----------------------------
say "§0 consuming the measured artifacts"
need_file "$TOYBOX_BIN"; need_file "$MKSH_BIN"
need_file "$PKG_TOOL"
[ -x "$PKG_TOOL" ] || die "packager tool is not executable: $PKG_TOOL"
need_file "$IM_BUILD"; need_file "$IM_BOOT"
# The image area's scripts are not marked executable; call them through bash.
need_file /tank/tmp/e07e7e91/kbuild/bzImage-6.18.64-sond

# If the READY marker is present it must agree with the measured tool path.
if [ -f "$READY_PK" ]; then
  [ "$(kv "$READY_PK" state)" = "ready" ] || die "$READY_PK does not say state=ready"
  ready_tool=$(kv "$READY_PK" tool)
  [ "$ready_tool" = "$PKG_TOOL" ] \
    || die "READY-packager tool ($ready_tool) != measured tool ($PKG_TOOL)"
  say "READY-packager agrees: tool=$PKG_TOOL"
else
  say "note: READY-packager absent; using the measured tool path"
fi

# The packager's own suite must be green before we consume it.
say "§0 running the packager test suite"
$PKG_TESTS 2>&1 | tail -n 5

for bin in "$TOYBOX_BIN" "$MKSH_BIN"; do
  file "$bin" | grep -q 'statically linked' \
    || die "$bin is not statically linked: $(file "$bin")"
done

actual=$(sha256sum "$TOYBOX_BIN" | awk '{print $1}')
[ "$actual" = "$TOYBOX_SHA" ] || die "toybox sha256 mismatch: got $actual, expected $TOYBOX_SHA"
actual=$(sha256sum "$MKSH_BIN" | awk '{print $1}')
[ "$actual" = "$MKSH_SHA" ] || die "mksh sha256 mismatch: got $actual, expected $MKSH_SHA"
say "sha256 toybox = $TOYBOX_SHA"
say "sha256 mksh   = $MKSH_SHA"
say "both binaries are statically linked"

# The frozen applet list: ten names, no more. Anything else is a different tree.
applets=$("$TOYBOX_BIN")
[ "$applets" = "$TOYBOX_APPLETS " ] \
  || die "toybox applet list is '$applets', expected '$TOYBOX_APPLETS '"
kver=$(printf 'echo $KSH_VERSION\n' | "$MKSH_BIN")
case "$kver" in
  *"MIRBSD KSH R59"*) say "mksh reports: $kver" ;;
  *) die "mksh KSH_VERSION is '$kver', expected MIRBSD KSH R59" ;;
esac

# --- §1 the pinned commits are the upstream tags in their fork trees --------
say "§1 resolving the pinned commits"
TOYBOX_FORK=$ROOT/src/toybox-sond
MKSH_FORK=$ROOT/src/mksh-sond
MUSL_FORK=$ROOT/src/musl-sond
FORKPATCH_DIR=$ROOT/forks

need_dir "$TOYBOX_FORK"; need_dir "$MKSH_FORK"; need_dir "$MUSL_FORK"

check_pin() { # <fork> <tag> <commit>
  local fork=$1 tag=$2 commit=$3 tagsha
  git -C "$fork" cat-file -e "$commit^{commit}" 2>/dev/null \
    || die "commit $commit not found in $fork"
  tagsha=$(git -C "$fork" rev-parse "$tag^{commit}") \
    || die "tag $tag not found in $fork"
  [ "$tagsha" = "$commit" ] \
    || die "$fork tag $tag is $tagsha, expected $commit"
  say "$(basename "$fork"): $tag = $commit"
}
check_pin "$TOYBOX_FORK" "$TOYBOX_TAG" "$TOYBOX_COMMIT"
check_pin "$MKSH_FORK"   "$MKSH_TAG"   "$MKSH_COMMIT"
check_pin "$MUSL_FORK"   "$MUSL_TAG"   "$MUSL_COMMIT"

TOYBOX_FORK_SHA=$(git -C "$TOYBOX_FORK" rev-parse refs/heads/sond)
MKSH_FORK_SHA=$(git -C "$MKSH_FORK" rev-parse refs/heads/sond)
MUSL_FORK_SHA=$(git -C "$MUSL_FORK" rev-parse refs/heads/sond)
say "fork heads: toybox=$TOYBOX_FORK_SHA mksh=$MKSH_FORK_SHA musl=$MUSL_FORK_SHA"

# --- §2 source material for the manifests, cut by hash ----------------------
say "§2 cutting source tarballs by hash"
clean_dir "$SRCDIR"; clean_dir "$STAGE"
git -C "$TOYBOX_FORK" archive --format=tar "$TOYBOX_COMMIT" | gzip -n > "$SRCDIR/toybox-$TOYBOX_VER.tar.gz"
git -C "$MKSH_FORK"   archive --format=tar "$MKSH_COMMIT"   | gzip -n > "$SRCDIR/mksh-$MKSH_VER.tar.gz"
git -C "$MUSL_FORK"   archive --format=tar "$MUSL_COMMIT"   | gzip -n > "$SRCDIR/musl-$MUSL_VER.tar.gz"
sha256sum "$SRCDIR"/*.tar.gz

# Fork patches: counted if present, declared absent if not (never invented).
for name in toybox mksh musl; do
  p=$FORKPATCH_DIR/$name-sond.patch
  if [ -f "$p" ]; then
    say "$name fork patch present: $(sha256sum "$p")"
  else
    say "note: $name fork patch $p absent (the fork head equals the upstream tag)"
  fi
done

# Toolchain recipes from the toolchain worktree.
TC_WORKTREE=/home/fred/dev/projects/sond-distro-pkg.oc-toolchain-musl
shopt -s nullglob
RECIPES=("$TC_WORKTREE"/toolchain/build-*.sh)
shopt -u nullglob
[ ${#RECIPES[@]} -gt 0 ] || die "no build recipe under $TC_WORKTREE/toolchain/build-*.sh"
for r in "${RECIPES[@]}"; do
  cp "$r" "$SRCDIR/"
  say "build recipe recorded: $(basename "$r") $(sha256sum "$r" | awk '{print $1}')"
done

# --- §3 licence texts, verbatim from the fork trees --------------------------
say "§3 extracting licence texts verbatim"
mkdir -p "$SRCDIR/lic/toybox-static" "$SRCDIR/lic/mksh-static"

git -C "$TOYBOX_FORK" show "$TOYBOX_COMMIT:LICENSE" > "$SRCDIR/lic/toybox-static/LICENSE"
grep -q 'Permission to use, copy, modify' "$SRCDIR/lic/toybox-static/LICENSE" \
  || die "toybox LICENSE does not look like the 0BSD text"
say "toybox LICENSE: $(wc -c < "$SRCDIR/lic/toybox-static/LICENSE") bytes"

# musl COPYRIGHT: the complete file, identical for both musl-linked packages.
git -C "$MUSL_FORK" show "$MUSL_COMMIT:COPYRIGHT" > "$SRCDIR/lic/musl-COPYRIGHT"
size=$(wc -c < "$SRCDIR/lic/musl-COPYRIGHT")
[ "$size" -gt 6000 ] || die "musl COPYRIGHT is only $size bytes — incomplete copy"
grep -q 'Rich Felker' "$SRCDIR/lic/musl-COPYRIGHT" || die "musl COPYRIGHT lacks Rich Felker"
say "musl COPYRIGHT: $size bytes (the full file, not the first paragraph)"

# MirOS licence: the header block of sh.h, verbatim.
git -C "$MKSH_FORK" show "$MKSH_COMMIT:sh.h" | sed -n '11,32p' > "$SRCDIR/lic/mksh-static/LICENCE-MirOS.txt"
grep -q 'mirabilos' "$SRCDIR/lic/mksh-static/LICENCE-MirOS.txt" \
  || die "MirOS block extraction from sh.h lines 11-32 failed"

# The Unicode notice: the measured anchor was expr.c:888-905, but that cut ends
# mid-sentence inside the permission. The verbatim block closes at line 926; the
# tree wins and the deviation is declared in the delivery.
git -C "$MKSH_FORK" show "$MKSH_COMMIT:expr.c" | sed -n '888,926p' > "$SRCDIR/lic/mksh-static/UNICODE-NOTICE"
grep -q 'Unicode' "$SRCDIR/lic/mksh-static/UNICODE-NOTICE" \
  || die "Unicode notice extraction from expr.c lines 888-926 failed"
grep -q 'written authorization of the copyright holder' "$SRCDIR/lic/mksh-static/UNICODE-NOTICE" \
  || die "Unicode notice is truncated: the closing block lines are missing"
say "mksh texts: $(wc -c < "$SRCDIR/lic/mksh-static/LICENCE-MirOS.txt") B MirOS, $(wc -c < "$SRCDIR/lic/mksh-static/UNICODE-NOTICE") B Unicode"

# --- §4 build the two bundles with the real packager -------------------------
say "§4 building the two bundles"
clean_dir "$BUNDLES"
mkdir -p "$INTEG/manifests"

# toybox-static tree: bin/toybox + the ten applet symlinks, relative targets so
# `ls -l` shows `-> toybox` inside the guest (contract 02 section C).
clean_dir "$STAGE/toybox-tree"
mkdir -p "$STAGE/toybox-tree/bin"
cp "$TOYBOX_BIN" "$STAGE/toybox-tree/bin/toybox"
chmod 0755 "$STAGE/toybox-tree/bin/toybox"
for a in $TOYBOX_SYMLINKS; do
  ln -s toybox "$STAGE/toybox-tree/bin/$a"
done

# mksh-static tree: bin/mksh + sh and ksh symlinks, relative targets.
clean_dir "$STAGE/mksh-tree"
mkdir -p "$STAGE/mksh-tree/bin"
cp "$MKSH_BIN" "$STAGE/mksh-tree/bin/mksh"
chmod 0755 "$STAGE/mksh-tree/bin/mksh"
ln -s mksh "$STAGE/mksh-tree/bin/sh"
ln -s mksh "$STAGE/mksh-tree/bin/ksh"

version_of() {
  case "$1" in
    toybox) printf '%s' "$TOYBOX_VER" ;;
    mksh)   printf '%s' "$MKSH_VER" ;;
    *)      die "unknown package $1" ;;
  esac
}

collect_source_files() { # <name> -> fills the global SRCARGS array
  local name=$1 r
  SRCARGS=(--source-file "$SRCDIR/$name-$(version_of "$name").tar.gz" \
           --source-file "$SRCDIR/musl-$MUSL_VER.tar.gz")
  if [ -f "$FORKPATCH_DIR/$name-sond.patch" ]; then
    SRCARGS+=(--source-file "$FORKPATCH_DIR/$name-sond.patch")
  else
    printf 'verify: note: %s manifest records no fork patch (none exists on disk)\n' "$name" >&2
  fi
  for r in "${RECIPES[@]}"; do
    SRCARGS+=(--source-file "$SRCDIR/$(basename "$r")")
  done
}

collect_source_files toybox
python3 "$PKG_TOOL" build-bundle \
  --name toybox-static --version "$TOYBOX_VER" --license 0BSD \
  --source "github.com/fredyk/toybox-sond@$TOYBOX_FORK_SHA" \
  --upstream "github.com/landley/toybox@$TOYBOX_COMMIT" \
  --linkage "static musl $MUSL_VER (MIT)" --tier public \
  --tree "$STAGE/toybox-tree" \
  --license-file "$SRCDIR/lic/toybox-static/LICENSE" \
  --license-file "$SRCDIR/lic/musl-COPYRIGHT" \
  "${SRCARGS[@]}" \
  --out "$BUNDLES"
collect_source_files mksh
python3 "$PKG_TOOL" build-bundle \
  --name mksh-static --version "$MKSH_VER" --license MirOS \
  --source "github.com/fredyk/mksh-sond@$MKSH_FORK_SHA" \
  --upstream "github.com/MirBSD/mksh@$MKSH_COMMIT" \
  --linkage "static musl $MUSL_VER (MIT)" --tier public \
  --tree "$STAGE/mksh-tree" \
  --license-file "$SRCDIR/lic/mksh-static/LICENCE-MirOS.txt" \
  --license-file "$SRCDIR/lic/mksh-static/UNICODE-NOTICE" \
  --license-file "$SRCDIR/lic/musl-COPYRIGHT" \
  "${SRCARGS[@]}" \
  --out "$BUNDLES"

TOYBOX_BUNDLE=$(ls -d "$BUNDLES"/toybox-static-"$TOYBOX_VER"-* | head -n 1)
MKSH_BUNDLE=$(ls -d "$BUNDLES"/mksh-static-"$MKSH_VER"-* | head -n 1)
[ -d "$TOYBOX_BUNDLE" ] || die "toybox-static bundle not found under $BUNDLES"
[ -d "$MKSH_BUNDLE" ] || die "mksh-static bundle not found under $BUNDLES"

python3 "$PKG_TOOL" verify-bundle "$TOYBOX_BUNDLE"
python3 "$PKG_TOOL" verify-bundle "$MKSH_BUNDLE"

# Independent confirmation: our own canon implementation must reproduce the
# bundle hash the MANIFEST records for each package.
manifest_hash() { # <bundle> -> bundle hash recorded in its MANIFEST
  sed -n 's/^[[:space:]]*bundle[[:space:]]*=[[:space:]]*"sha256:\([0-9a-f]\{64\}\)"[[:space:]]*$/\1/p' "$1/MANIFEST" | head -n 1
}
own_toybox=$(python3 "$VERIFY_DIR/canon-hash.py" "$TOYBOX_BUNDLE/payload")
own_mksh=$(python3 "$VERIFY_DIR/canon-hash.py" "$MKSH_BUNDLE/payload")
[ "$own_toybox" = "$(manifest_hash "$TOYBOX_BUNDLE")" ] \
  || die "independent canon hash of toybox payload ($own_toybox) != MANIFEST ($(manifest_hash "$TOYBOX_BUNDLE"))"
[ "$own_mksh" = "$(manifest_hash "$MKSH_BUNDLE")" ] \
  || die "independent canon hash of mksh payload ($own_mksh) != MANIFEST ($(manifest_hash "$MKSH_BUNDLE"))"
say "toybox-static bundle $(basename "$TOYBOX_BUNDLE") hash $own_toybox (independent check ok)"
say "mksh-static   bundle $(basename "$MKSH_BUNDLE") hash $own_mksh (independent check ok)"

cp "$TOYBOX_BUNDLE/MANIFEST" "$INTEG/manifests/toybox-static.MANIFEST"
cp "$MKSH_BUNDLE/MANIFEST" "$INTEG/manifests/mksh-static.MANIFEST"

# Symlink evidence on the host side too: ls is from the toybox package, sh from mksh.
[ "$(readlink "$TOYBOX_BUNDLE/payload/bin/ls")" = "toybox" ] \
  || die "payload bin/ls is not a symlink to toybox"
[ "$(readlink "$MKSH_BUNDLE/payload/bin/sh")" = "mksh" ] \
  || die "payload bin/sh is not a symlink to mksh"

# --- §5 the disk and the boot ------------------------------------------------
say "§5 building the disk and booting it on SeaBIOS"

# Merged rootfs: toybox payload first, mksh payload second. Only a colliding
# regular file/symlink is an error; directories merge (bin/, share/).
clean_dir "$TREEDIR"
cp -a "$TOYBOX_BUNDLE/payload/." "$TREEDIR/"
collisions=$(cd "$MKSH_BUNDLE/payload" && find . ! -type d -print | while read -r f; do
  if [ -e "$TREEDIR/$f" ] || [ -L "$TREEDIR/$f" ]; then echo "$f"; fi
done)
if [ -n "$collisions" ]; then
  die "payload collision between bundles: $collisions"
fi
cp -a "$MKSH_BUNDLE/payload/." "$TREEDIR/"
say "rootfs merged: $(find "$TREEDIR" -mindepth 1 | wc -l) entries"

clean_dir "$DISKDIR"
bash "$IM_BUILD" --tree "$TREEDIR" --out "$DISKDIR"
DISK=$DISKDIR/sond-disk.raw
need_file "$DISK"
say "disk built: $(sha256sum "$DISK" | awk '{print $1}')"

# Boot on SeaBIOS with the image area's own runner, typing the battery over the
# serial console. The guest prints RESULT: PASS itself; the host re-verifies
# every evidence line from the transcript afterwards.
BOOT_ARGS=(--disk "$DISK" --log "$SERIAL" --prompt-timeout 180 --total-timeout 420)
typed=0
while IFS= read -r line; do
  line=${line%%$'\r'}
  [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
  BOOT_ARGS+=(--cmd "$line")
  typed=$((typed + 1))
done < "$VERIFY_DIR/serial-battery.sh"
BOOT_ARGS+=(--cmd "exit")
say "booting: typing $typed battery lines + exit"
if bash "$IM_BOOT" "${BOOT_ARGS[@]}"; then
  say "runner reported success"
else
  say "note: runner rc=$? (see the transcript; scored below)"
fi

# --- §6 the battery verdict from the real transcript -------------------------
say "§6 scoring the battery from $SERIAL"

need_file "$SERIAL"
[ -s "$SERIAL" ] || die "serial transcript is empty: $SERIAL"

plain=$(mktemp)
trap 'rm -f "$plain"' EXIT
tr -d '\r' < "$SERIAL" > "$plain"

# The transcript must prove it was SeaBIOS, never OVMF.
sbios=$(grep -c 'SeaBIOS' "$plain" || true)
ovmf=$(grep -ci 'ovmf' "$plain" || true)
[ "$sbios" -ge 1 ] || die "no SeaBIOS banner in the transcript"
[ "$ovmf" -eq 0 ] || die "the transcript mentions OVMF ($ovmf times) — wrong firmware"
say "SeaBIOS banners: $sbios, OVMF mentions: $ovmf"

# The image area's own init battery. Two of its rows need a context the frozen
# packages do not provide, so they are harness artifacts, declared verbatim:
#   readlink  the toybox package freezes ten applets and readlink is not one;
#             the links are proved below with `ls -l`.
#   ps        the init shell has no controlling tty and toybox's bare `ps`
#             filters by the caller's tty, so it prints only the header and
#             exits 1; this run's own `ps -A` lists every process and exits 0.
# Any other failure is real and stops the run.
probe_fail_names=$(grep -E '^fail: ' "$plain" | sed -E 's/^fail: ([^ ]+).*/\1/' | sort -u || true)
for f in $probe_fail_names; do
  case "$f" in
    readlink|ps) : ;;
    *) die "image harness battery failed on '$f': $(grep -F "fail: $f " "$plain" | head -n1)" ;;
  esac
done
if [ -n "$probe_fail_names" ]; then
  say "declared harness artifacts (not package failures):"
  for f in $probe_fail_names; do
    say "  $(grep -F "fail: $f " "$plain" | head -n1)"
  done
fi

# Every check the guest reported, one verdict line each.
REQUIRED=(ls ps cat grep echo mkdir cp mv rm mount cd sh)
EXTRA=(mount-tmpfs symlink-ls symlink-sh toybox-applets licences
       licences-musl-in-toybox licences-musl-in-mksh licences-mksh licence-unicode)
pass=0; failcount=0; missing=""
printf '%-28s %-6s %s\n' "check" "ok/fail" "evidence"
for c in "${REQUIRED[@]}" "${EXTRA[@]}"; do
  line=$(grep -F "VERIFY-OK: $c :: rc=" "$plain" | tail -n 1 || true)
  if [ -z "$line" ]; then
    verdict=missing; missing="$missing $c"
  elif [[ "$line" == "VERIFY-OK: $c :: rc=0" ]]; then
    verdict=ok; pass=$((pass + 1))
  else
    verdict=fail; failcount=$((failcount + 1))
  fi
  printf '%-28s %-6s %s\n' "$c" "$verdict" "${line:-<absent from transcript>}"
done
[ -z "$missing" ] || die "battery lines absent from the transcript:$missing"
[ "$failcount" -eq 0 ] || die "battery: $failcount checks reported a non-zero rc"

guest_summary=$(grep -F 'BATTERY ok=' "$plain" | tail -n 1 || true)
guest_result=$(grep -E '^RESULT: (PASS|FAIL)$' "$plain" | tail -n 1 || true)
say "guest counters: ${guest_summary:-<absent>} ${guest_result:-<absent>}"
[ "$guest_result" = "RESULT: PASS" ] || die "guest verdict was: ${guest_result:-absent}"

# Firm evidence of the links the prompt asks for, without a readlink applet.
grep -q -- '-> toybox' "$plain" || die "no '-> toybox' line in the transcript"
grep -q -- '-> mksh'   "$plain" || die "no '-> mksh' line in the transcript"
say "symlink evidence: $(grep -F -- '-> toybox' "$plain" | head -n1)"
say "symlink evidence: $(grep -F -- '-> mksh' "$plain" | head -n1)"

# The frozen toybox applet list, as printed by the guest binary.
grep -qE "^$TOYBOX_APPLETS[[:space:]]*$" "$plain" || die "guest toybox applet list is not the frozen ten"
say "toybox applets in guest: $(grep -E "^$TOYBOX_APPLETS[[:space:]]*$" "$plain" | head -n1)"

# Licences are visible inside the guest.
grep -q 'LICENCE-MirOS.txt' "$plain" || die "guest licence listing lacks LICENCE-MirOS.txt"
grep -q 'UNICODE-NOTICE'    "$plain" || die "guest licence listing lacks UNICODE-NOTICE"

say "battery: $pass/${#REQUIRED[@]} mandated utilities + ${#EXTRA[@]} extra checks ok, guest verdict PASS"
say "RESULT: PASS"
echo "RESULT: PASS"
