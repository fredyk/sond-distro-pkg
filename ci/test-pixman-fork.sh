#!/bin/bash
# Shape checks for the pixman fork recipe: a static library for qemu (lib/*.a, include/, lib/pkgconfig/*.pc only),
# static against the pinned musl, MIT with its texts. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-pixman-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from gitlab.freedesktop.org/pixman/pixman at its tag pixman-0.46.4.
VERSION=0.46.4
UPSTREAM=gitlab.freedesktop.org/pixman/pixman@9cc163c9da0fb4da430641715313d95a6ec466d9

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
check pixman pixman "$VERSION" "$UPSTREAM"

yml=$here/forks/pixman-sond.yml
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
	[ "$l" = "MIT" ] && ok "license MIT" || bad "license MIT (found: $l)"
	grep -qE -- '--default-library=static' "$yml" && ok "meson builds the static library only" \
		|| bad "meson builds the static library only (--default-library=static)"
	for o in -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled -Dopenmp=disabled; do
		grep -qE -- "$o" "$yml" && ok "configured $o" || bad "configured $o"
	done
	grep -qE 'meson install -C build --destdir "\$SOND_PAYLOAD"' "$yml" && ok "installs through meson into the payload" \
		|| bad "installs through meson into the payload"
	grep -qE 'test -f "\$SOND_PAYLOAD/lib/libpixman-1\.a"' "$yml" && ok "asserts lib/libpixman-1.a" || bad "asserts lib/libpixman-1.a"
	grep -qE 'test -f "\$SOND_PAYLOAD/include/pixman-1/pixman\.h"' "$yml" && ok "asserts include/pixman-1/pixman.h" \
		|| bad "asserts include/pixman-1/pixman.h"
	grep -qE 'test -f "\$SOND_PAYLOAD/lib/pkgconfig/pixman-1\.pc"' "$yml" && ok "asserts lib/pkgconfig/pixman-1.pc" \
		|| bad "asserts lib/pkgconfig/pixman-1.pc"
	grep -qE 'test -z "\$\(find "\$SOND_PAYLOAD"' "$yml" && ok "asserts nothing else is in the payload (no .so)" \
		|| bad "asserts nothing else is in the payload"
	grep -qxE "\s+COPYING" "$yml" && ok "ships the upstream COPYING (the licence and copyright notice)" \
		|| bad "ships the upstream COPYING in license-files"
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
        dests.add(dest or "share/licenses/pixman/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("pixman", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
else
	bad "pixman-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-pixman-fork: OK\n'
else
	printf 'test-pixman-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
