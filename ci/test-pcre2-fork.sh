#!/bin/bash
# Shape checks for the pcre2 fork recipe: static libpcre2-8 for glib, 8-bit only, JIT off,
# BSD-3-Clause WITH PCRE2-exception with LICENCE.md. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-pcre2-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/PCRE2Project/pcre2 at its tag pcre2-10.49.
VERSION=10.49
UPSTREAM=github.com/PCRE2Project/pcre2@6f9d7c1373262c541324a16a358785b33ef116cf

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
check pcre2 pcre2 "$VERSION" "$UPSTREAM"

yml=$here/forks/pcre2-sond.yml
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
	[ "$l" = "BSD-3-Clause WITH PCRE2-exception" ] && ok "license BSD-3-Clause WITH PCRE2-exception (LICENCE.md)" \
		|| bad "license BSD-3-Clause WITH PCRE2-exception (found: $l)"
	python3 - "$DISTRO" "$l" <<'PY3' && ok "sondpkg spdx admits $l" || bad "sondpkg spdx admits $l"
import sys
sys.path.insert(0, sys.argv[1])
from sondpkg import spdx
spdx.exceptions(sys.argv[2])
assert "PCRE2-exception" in spdx.EXCEPTIONS
PY3
	for o in -DBUILD_SHARED_LIBS=OFF -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF \
		-DPCRE2_SUPPORT_JIT=OFF -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF; do
		grep -qF -- "$o" "$yml" && ok "configured $o" || bad "configured $o"
	done
	for f in lib/libpcre2-8.a include/pcre2.h lib/pkgconfig/libpcre2-8.pc; do
		grep -qF "\"\$SOND_PAYLOAD/$f\"" "$yml" && ok "ships $f" || bad "ships $f"
	done
	n=$(grep -c 'SOND_PAYLOAD' "$yml" || true)
	[ "$n" = 3 ] && ok "ships nothing else" || bad "ships nothing else ($n payload writes)"
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
        dests.add(dest or "share/licenses/pcre2/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("pcre2", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
else
	bad "pcre2-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-pcre2-fork: OK\n'
else
	printf 'test-pcre2-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
