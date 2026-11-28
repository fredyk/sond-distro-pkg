#!/bin/bash
# Shape checks for the liblzma recipe, a second workflow in the xz-sond fork at the same pin as
# xz-sond.yml: lib/liblzma.a, its headers and pkg-config file, static against the pinned musl,
# 0BSD with its texts. Packages that link liblzma (squashfs-tools) take it through depends:, so
# its source lands in their source bundle. Every rule ci/test-fork-workflows.sh applies to the
# other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-liblzma-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/tukaani-project/xz at its tag v5.8.4.
VERSION=5.8.4
UPSTREAM=github.com/tukaani-project/xz@d3e650e63c110e830fd5391e7f8b45df0b91d3da

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
check liblzma liblzma "$VERSION" "$UPSTREAM"

yml=$here/forks/liblzma-sond.yml
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
	[ "$l" = "0BSD" ] && ok "license 0BSD" || bad "license 0BSD (found: $l)"
	grep -q 'Generated from fredyk/sond-distro-pkg ci/forks' "$yml" && grep -q 'sond-package-liblzma.yml' "$yml" \
		&& ok "lives in the xz-sond fork as sond-package-liblzma.yml" \
		|| bad "lives in the xz-sond fork as sond-package-liblzma.yml"
	grep -qE -- '-DBUILD_SHARED_LIBS=OFF' "$yml" && ok "static library only" \
		|| bad "static library only (-DBUILD_SHARED_LIBS=OFF)"
	grep -qE -- '-DXZ_TOOL_XZ=OFF' "$yml" && ok "builds no xz command (that is the xz package)" \
		|| bad "builds no xz command (-DXZ_TOOL_XZ=OFF)"
	grep -qE -- '-DCMAKE_INSTALL_LIBDIR=lib' "$yml" && ok "installs under lib/, not lib64/" \
		|| bad "installs under lib/ (-DCMAKE_INSTALL_LIBDIR=lib)"
	grep -qE 'cmake --install build --prefix "\$SOND_PAYLOAD"' "$yml" \
		&& ok "installs lib/liblzma.a, include/lzma.h, include/lzma/, lib/pkgconfig/liblzma.pc" \
		|| bad "installs into the payload with cmake --install build --prefix \"\$SOND_PAYLOAD\""
	grep -qE 'rm -rf "\$SOND_PAYLOAD/lib/cmake" "\$SOND_PAYLOAD/share/doc" "\$SOND_PAYLOAD/share/man"' "$yml" \
		&& ok "ships nothing else (no cmake config, no docs, no man pages)" \
		|| bad "ships nothing else (rm -rf lib/cmake share/doc share/man from the payload)"
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
        dests.add(dest or "share/licenses/liblzma/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("liblzma", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
else
	bad "liblzma-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-liblzma-fork: OK\n'
else
	printf 'test-liblzma-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
