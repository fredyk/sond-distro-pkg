#!/bin/bash
# Shape checks for the ca-certificates fork recipe: Mozilla's root certificates as the one PEM
# file Go's crypto/x509 reads first on linux (/etc/ssl/certs/ca-certificates.crt, root_linux.go),
# taken from certifi's pinned tree and checked by sha256, with the MPL-2.0 text it obliges and
# its source lane. Every rule ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-ca-certificates-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/certifi/python-certifi at its tag 2026.11.20 and from
# mozilla.org's MPL 2.0 plain text.
VERSION=2026.11.20
UPSTREAM=github.com/certifi/python-certifi@bf6a4859116b0cba96673893e394298bbe529b1f
BUNDLE_SHA=bb92c6ac31c92f4f553bffd6bf093db02c858c23e111b0b4df9bafa3fdbe00d1
MPL_SHA=3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04
DEST=etc/ssl/certs/ca-certificates.crt

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
check ca-certificates ca-certificates "$VERSION" "$UPSTREAM" copyleft

yml=$here/forks/ca-certificates-sond.yml
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
	[ "$l" = "MPL-2.0" ] && ok "license MPL-2.0" || bad "license MPL-2.0 (found: $l)"
	grep -qF "$BUNDLE_SHA" "$yml" && ok "pins the bundle sha256 $BUNDLE_SHA" \
		|| bad "pins the bundle sha256 $BUNDLE_SHA"
	grep -qF "$MPL_SHA" "$yml" && ok "checks the MPL-2.0 text against mozilla.org's sha256" \
		|| bad "checks the MPL-2.0 text against mozilla.org's sha256"
	[ "$(grep -cF 'sha256sum -c' "$yml")" -ge 2 ] && ok "checks the bundle and the text each with sha256sum -c" \
		|| bad "checks the bundle and the text each with sha256sum -c"
	grep -qF "certifi/cacert.pem" "$yml" && ok "takes the bundle from the pinned tree's certifi/cacert.pem" \
		|| bad "takes the bundle from the pinned tree's certifi/cacert.pem"
	grep -qE "install (-D )?-m 0644 \S+ \"\\\$SOND_PAYLOAD/$DEST\"" "$yml" && ok "installs it 0644 at \$SOND_PAYLOAD/$DEST" \
		|| bad "installs it 0644 at \$SOND_PAYLOAD/$DEST"
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
        dests.add(dest or "share/licenses/ca-certificates/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("ca-certificates", "static", licence)]
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
	bad "ca-certificates-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-ca-certificates-fork: OK\n'
else
	printf 'test-ca-certificates-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
