#!/bin/bash
# Shape checks for the squashfs-tools fork recipe: the unsquashfs command alone (incusd looks it
# up on PATH at startup), static against the pinned musl, reading gzip and xz images through the
# published zlib 1.3.2 and liblzma 5.8.4 packages under depends, GPL-2.0 with its COPYING and
# its source lane. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-squashfs-tools-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

rbx=$here/rbx-squashfs-tools.sh
[ -f "$rbx" ] && sh -n "$rbx" 2>/dev/null \
	&& ok "ci/rbx-squashfs-tools.sh is a POSIX wrapper the gate can run" \
	|| bad "ci/rbx-squashfs-tools.sh is a POSIX wrapper the gate can run"

# Measured on 2026-11-26 from github.com/plougher/squashfs-tools at its tag 4.7.5 (latest release).
VERSION=4.7.5
UPSTREAM=github.com/plougher/squashfs-tools@708c59ae80853b0845017c33b42e56061cc546cd
# The libraries linked in: the published liblzma 5.8.4 (0BSD) and zlib 1.3.2 (Zlib) packages.
LICENCE="GPL-2.0-or-later AND Zlib AND 0BSD"

# --- the same criterion as ci/test-fork-workflows.sh, through its own check() ---
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
check squashfs-tools squashfs-tools "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/squashfs-tools-sond.yml
field() { # <key> of the build step's with: block
	[ -f "$yml" ] || return 0
	python3 - "$yml" "$1" <<'PY'
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

if [ -f "$yml" ]; then
	l=$(field license)
	# unsquashfs links the squashfs-tools sources (GPL-2.0-or-later), zlib (Zlib) and liblzma (0BSD).
	[ "$l" = "$LICENCE" ] && ok "license $LICENCE" || bad "license $LICENCE (found: $l)"
	# zlib and liblzma are published packages: the recipe lists them under depends and does not
	# build them in the job.
	grep -qE '^\s+liblzma 5\.8\.4$' "$yml" && ok "depends on liblzma 5.8.4" || bad "depends on liblzma 5.8.4"
	grep -qE '^\s+zlib 1\.3\.2$' "$yml" && ok "depends on zlib 1.3.2" || bad "depends on zlib 1.3.2"
	if grep -qE 'zlib-1\.4|libz\.a|--target liblzma|github\.com/tukaani-project/xz' "$yml"; then
		bad "zlib and liblzma are not built in the job"
	else
		ok "zlib and liblzma are not built in the job"
	fi
	# Upstream's Makefile appends its own flags with "CFLAGS +=": on the command line CFLAGS would
	# override them, so the compile flags go through the environment.
	grep -qE 'CFLAGS="\$SOND_CFLAGS[^"]*" LDFLAGS="\$SOND_LDFLAGS[^"]*-static[^"]*" make -C squashfs-tools unsquashfs ' "$yml" \
		&& ok "builds only the unsquashfs target, flags from the environment, linked -static" \
		|| bad "builds only the unsquashfs target, flags from the environment, linked -static"
	for opt in GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=0 LZ4_SUPPORT=0 ZSTD_SUPPORT=0; do
		grep -qE "make -C squashfs-tools unsquashfs .*\b$opt\b" "$yml" && ok "make $opt" || bad "make $opt"
	done
	grep -qE 'install -D -m 0755 squashfs-tools/unsquashfs "\$SOND_PAYLOAD/bin/unsquashfs"' "$yml" \
		&& ok "ships bin/unsquashfs" || bad "ships bin/unsquashfs"
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 1 ] && ok "ships nothing else (no mksquashfs, no sqfscat link)" || bad "ships nothing else ($n payload writes)"
	grep -qE '^\s+COPYING$' "$yml" && ok "license-files ships COPYING" || bad "license-files ships COPYING"
	missing=$(python3 - "$DISTRO" "$yml" "$l" <<'PY2'
import sys
sys.path.insert(0, sys.argv[1])
from sondpkg import rules
yml, licence = sys.argv[2:]
dests, inside = set(), False
for line in open(yml).read().split("\n"):
    s = line.strip()
    if s == "license-files: |":
        inside = True
        continue
    if inside:
        if not s or (s.endswith(":") or ": " in s) and "=" not in s:
            break
        src, _, dest = s.partition("=")
        dests.add(dest or "share/licenses/squashfs-tools/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("squashfs-tools", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
	rc=0
	python3 "$DISTRO/sondpkg/bin/sondpkg" needs-source "$l" >/dev/null || rc=$?
	[ "$rc" = 0 ] && ok "sondpkg needs-source '$l' is 0: the source lane publishes first" \
		|| bad "sondpkg needs-source '$l' is 0 (rc=$rc)"
else
	bad "squashfs-tools-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-squashfs-tools-fork: OK\n'
else
	printf 'test-squashfs-tools-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
