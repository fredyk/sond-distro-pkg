#!/bin/bash
# Shape checks for the zlib fork recipe: a static library for qemu (lib/*.a, include/, lib/pkgconfig/*.pc only),
# static against the pinned musl, Zlib with its texts. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-zlib-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/madler/zlib at its tag v1.3.2.
VERSION=1.3.2
UPSTREAM=github.com/madler/zlib@da607da739fa6047df13e66a2af6b8bec7c2a498

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
check zlib zlib "$VERSION" "$UPSTREAM"

yml=$here/forks/zlib-sond.yml
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
	[ "$l" = "Zlib" ] && ok "license Zlib" || bad "license Zlib (found: $l)"
	grep -qE -- '\./configure .*--static' "$yml" && ok "configure builds the static library only" \
		|| bad "configure builds the static library only (--static)"
	grep -qE 'make .*libz\.a' "$yml" && ok "builds libz.a alone (no example programs, no shared object)" \
		|| bad "builds libz.a alone"
	for f in lib/libz.a include/zlib.h include/zconf.h lib/pkgconfig/zlib.pc; do
		grep -qE "install -D -m 0644 \S+ \"\\\$SOND_PAYLOAD/$f\"" "$yml" && ok "ships $f" || bad "ships $f"
	done
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 4 ] && ok "ships nothing else (no man page, no libz.so)" || bad "ships nothing else ($n payload writes)"
	grep -qE 'zlib\.3|share/man' "$yml" && bad "the zlib.3 man page is not shipped" || ok "the zlib.3 man page is not shipped"
	grep -qxE "\s+LICENSE" "$yml" && ok "ships the upstream LICENSE (the licence and copyright notice)" \
		|| bad "ships the upstream LICENSE in license-files"
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
        dests.add(dest or "share/licenses/zlib/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("zlib", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
else
	bad "zlib-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-zlib-fork: OK\n'
else
	printf 'test-zlib-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
