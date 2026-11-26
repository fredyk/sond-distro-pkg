#!/bin/bash
# Shape checks for the two rclone-area fork recipes (rclone, fusermount3):
# every rule ci/test-fork-workflows.sh applies to the published eighteen, the
# hash pins measured in .opencode-hallazgos/00-rclone-paquete.md and their
# derivation, and the real sondpkg needs-source for each recipe's licence.
# Offline: no network, no build.
#
# usage: ci/test-rclone-forks.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured against the real sources (2026-11-26, recomputed on this VM from
# downloads.rclone.org and the libfuse repo): the release zip, the rclone member
# inside it, and the upstream commits the recipes must pin.
RCLONE_VERSION=1.76.0
RCLONE_ZIP_SHA=b00f00b3266c3764413afe599d3ec316f6f43b3e0ea8a0bc1d186d2133e46df7
RCLONE_BIN_SHA=62e4d3e5432f2c685f1834b8bb342058ff0611c99d048aeb44bb8d8fd611527e
RCLONE_UPSTREAM=github.com/rclone/rclone@e982ff36668f5130d94b4f70409babb3d964df42
FUSERMOUNT3_VERSION=3.16.2
FUSERMOUNT3_UPSTREAM=github.com/libfuse/libfuse@7a92727d97c10290b3501d86a194738973edb61d

# --- the same criterion as ci/test-fork-workflows.sh, through its own check() ---
# Sourcing it runs the eighteen base recipes (which must stay OK; that script is never edited
# here) and brings in check(). Its final exit would end this test, so it is neutered during the
# source only, and its FAIL count is taken from the shared fails.
base_log=$(mktemp)
exit() {
	[ "${_sourcing:-}" = 1 ] || builtin exit "${1:-0}"
}
_sourcing=1
# shellcheck source=/dev/null
source "$here/test-fork-workflows.sh" >"$base_log" 2>&1 || true
unset _sourcing
if grep -q '^FAIL' "$base_log"; then
	bad "ci/test-fork-workflows.sh FAILs on the base recipes (see $base_log)"
fi
check rclone rclone "$RCLONE_VERSION" "$RCLONE_UPSTREAM" copyleft
check fusermount3 fusermount3 "$FUSERMOUNT3_VERSION" "$FUSERMOUNT3_UPSTREAM" copyleft

# The build step's with: block, same layout the workflows are generated with.
field() { # <file> <key>
	[ -f "$1" ] || return 0
	python3 - "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
try:
    i = next(n for n, l in enumerate(lines) if l.strip() == "- id: build")
    i = next(n for n in range(i, len(lines)) if lines[n].strip() == "with:")
except StopIteration:
    sys.exit(0)
indent = len(lines[i + 1]) - len(lines[i + 1].lstrip())
for n in range(i + 1, len(lines)):
    stripped = lines[n].strip()
    if not stripped:
        continue
    ind = len(lines[n]) - len(lines[n].lstrip())
    if ind < indent:
        break
    if ind == indent and stripped.startswith(sys.argv[2] + ":"):
        sys.stdout.write(stripped.split(": ", 1)[1].strip())
        break
PY
}

# --- rclone: recipe pins the official zip and member; derivation is reproducible ---
yml=$here/forks/rclone-sond.yml
if [ -f "$yml" ]; then
	grep -qF "$RCLONE_ZIP_SHA" "$yml" \
		&& ok "rclone-sond.yml: pins the release-zip sha256 $RCLONE_ZIP_SHA" \
		|| bad "rclone-sond.yml: pins the release-zip sha256 $RCLONE_ZIP_SHA"
	grep -qF "$RCLONE_BIN_SHA" "$yml" \
		&& ok "rclone-sond.yml: pins the rclone member sha256 $RCLONE_BIN_SHA" \
		|| bad "rclone-sond.yml: pins the rclone member sha256 $RCLONE_BIN_SHA"
	version=$(field "$yml" version)
	if [ "$version" = "$RCLONE_VERSION" ]; then
		# the same version names both the zip URL and the member path inside it
		grep -qF "https://downloads.rclone.org/v${version}/rclone-v${version}-linux-amd64.zip" "$yml" \
			&& ok "rclone-sond.yml: the zip URL derives from version $version" \
			|| bad "rclone-sond.yml: the zip URL derives from version $version"
		grep -qF "rclone-v${version}-linux-amd64/rclone" "$yml" \
			&& ok "rclone-sond.yml: the member path derives from version $version" \
			|| bad "rclone-sond.yml: the member path derives from version $version"
	else
		bad "rclone-sond.yml: version $RCLONE_VERSION (found: $version)"
	fi
	[ "$(grep -cF 'sha256sum -c' "$yml")" -ge 2 ] \
		&& ok "rclone-sond.yml: checks the zip and the member each with sha256sum -c" \
		|| bad "rclone-sond.yml: checks the zip and the member each with sha256sum -c"
	grep -qF '$SOND_PAYLOAD/bin/rclone' "$yml" \
		&& ok 'rclone-sond.yml: installs the member at $SOND_PAYLOAD/bin/rclone' \
		|| bad 'rclone-sond.yml: installs the member at $SOND_PAYLOAD/bin/rclone'
	# github.com/cloudsoda/sddl, linked into the release binary, ships the LGPL-3.0 text
	# (sondpkg golicences.REVIEWED): the binary takes the source lane.
	grep -q 'source-bundle:' "$yml" \
		&& ok "rclone-sond.yml: publishes its corresponding source (an LGPL-3.0 module is linked)" \
		|| bad "rclone-sond.yml: publishes its corresponding source (an LGPL-3.0 module is linked)"
	l=$(field "$yml" license)
	[ "$l" = "MIT AND LGPL-3.0-only" ] \
		&& ok "rclone-sond.yml: license MIT AND LGPL-3.0-only" \
		|| bad "rclone-sond.yml: license MIT AND LGPL-3.0-only (found: $l)"
	rc=0
	python3 "$DISTRO/sondpkg/bin/sondpkg" needs-source "$l" >/dev/null || rc=$?
	[ "$rc" = 0 ] \
		&& ok "sondpkg needs-source '$l' (rclone) is 0: the source lane publishes first" \
		|| bad "sondpkg needs-source '$l' (rclone) is 0: the source lane publishes first (rc=$rc)"
else
	bad "rclone-sond.yml: present"
fi

# --- fusermount3: the -Ddisable-mtab=true decision, util-only, GPL source lane ---
yml=$here/forks/fusermount3-sond.yml
if [ -f "$yml" ]; then
	grep -qF -- '-Ddisable-mtab=true' "$yml" \
		&& ok "fusermount3-sond.yml: -Ddisable-mtab=true, so it always goes by mount(2) (no /etc/mtab needed)" \
		|| bad "fusermount3-sond.yml: -Ddisable-mtab=true, so it always goes by mount(2) (no /etc/mtab needed)"
	# ubuntu-24.04 runners carry neither meson nor ninja (run 45809854976: "meson: command not found")
	awk '/sond-build-action/{exit} /apt-get install/ && /meson/ && /ninja-build/{f=1} END{exit !f}' "$yml" \
		&& ok "fusermount3-sond.yml: installs meson and ninja-build before the build step" \
		|| bad "fusermount3-sond.yml: installs meson and ninja-build before the build step"
	grep -qF 'build/util/fusermount3' "$yml" \
		&& ok "fusermount3-sond.yml: builds the util target and ships only bin/fusermount3" \
		|| bad "fusermount3-sond.yml: builds the util target and ships only bin/fusermount3"
	l=$(field "$yml" license)
	rc=0
	python3 "$DISTRO/sondpkg/bin/sondpkg" needs-source "$l" >/dev/null || rc=$?
	[ "$rc" = 0 ] \
		&& ok "sondpkg needs-source '$l' (fusermount3) is 0: the source lane publishes first" \
		|| bad "sondpkg needs-source '$l' (fusermount3) is 0: the source lane publishes first (rc=$rc)"
else
	bad "fusermount3-sond.yml: present"
fi

# --- both recipes keep arriving through the same action as the other eighteen ---
total=$(grep -l 'fredyk/sond-build-action' "$here"/forks/*.yml | wc -l)
[ "$total" -ge 20 ] \
	&& ok "$total fork recipes build with fredyk/sond-build-action (base was 18)" \
	|| bad "$total fork recipes build with fredyk/sond-build-action (base was 18)"

if [ "$fails" -eq 0 ]; then
	printf 'test-rclone-forks: OK\n'
else
	printf 'test-rclone-forks: FAIL (%d)\n' "$fails"
	exit 1
fi
