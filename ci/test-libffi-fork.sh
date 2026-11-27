#!/bin/bash
# Shape checks for the libffi fork recipe: the static library glib's gobject links, its headers
# and pkg-config file, against the pinned musl, MIT with its text. Every rule
# ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-libffi-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISTRO=$(cd "$here/.." && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/libffi/libffi at its tag v3.5.2 (lightweight: the tag
# ref is the commit itself, git ls-remote --tags lists no peeled ^{} entry).
VERSION=3.5.2
UPSTREAM=github.com/libffi/libffi@e2eda0cf72a0598b44278cc91860ea402273fa29

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
check libffi libffi "$VERSION" "$UPSTREAM"

yml=$here/forks/libffi-sond.yml
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
	# tramp.c, the dynamic trampoline source libffi 3.5.2 compiles for x86_64-linux, includes
	# <linux/limits.h>: without the sysroot headers of the linux-headers package the recipe is
	# not buildable at all ("linux/limits.h: No such file or directory").
	grep -qE -- '^ +linux-headers 6\.12\.77$' "$yml" \
		&& ok "depends linux-headers 6.12.77 (tramp.c includes <linux/limits.h>)" \
		|| bad "depends linux-headers 6.12.77 (tramp.c includes <linux/limits.h>)"
	[ "$l" = "MIT" ] && ok "license MIT" || bad "license MIT (found: $l)"
	grep -qE -- '--disable-shared --enable-static' "$yml" && ok "static library only" \
		|| bad "static library only (--disable-shared --enable-static)"
	grep -qE -- '--disable-docs' "$yml" && ok "no info manual" || bad "no info manual (--disable-docs)"
	grep -qE -- '--disable-multi-os-directory' "$yml" && ok "installs into lib/, not lib64/ or lib/../lib64" \
		|| bad "installs into lib/ (--disable-multi-os-directory)"
	grep -qE -- '--prefix=/ ' "$yml" && ok "prefix / (lib/, include/ at the payload root)" || bad "prefix /"
	grep -qE 'install-toolexeclibLTLIBRARIES' "$yml" && ok "ships lib/libffi.a" || bad "ships lib/libffi.a"
	grep -qE 'install-pkgconfigDATA' "$yml" && ok "ships lib/pkgconfig/libffi.pc" || bad "ships lib/pkgconfig/libffi.pc"
	grep -qE 'make -C include .*install-nodist_includeHEADERS' "$yml" && ok "ships include/ffi.h and include/ffitarget.h" \
		|| bad "ships include/ffi.h and include/ffitarget.h"
	grep -qE 'rm -f "\$SOND_PAYLOAD"/lib/\*\.la' "$yml" && ok "no libtool archive" || bad "no libtool archive (rm lib/*.la)"
	grep -qE '(^|[^-])make( -j"\$\(nproc\)")? (DESTDIR="\$SOND_PAYLOAD" )?install( |$)' "$yml" \
		&& bad "no blanket make install (it would ship the man pages)" || ok "no blanket make install"
	grep -qE 'apt-get install .*autoconf.*automake.*libtool' "$yml" && ok "autotools present for autogen.sh" \
		|| bad "autotools present for autogen.sh"
	grep -qE '^ +\./autogen\.sh$' "$yml" && ok "configure is generated from the git checkout" \
		|| bad "configure is generated from the git checkout (./autogen.sh)"
	grep -q 'source-bundle' "$yml" && bad "no source bundle (MIT is not copyleft)" || ok "no source bundle (MIT is not copyleft)"
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
        dests.add(dest or "share/licenses/libffi/%s" % src.rsplit("/", 1)[-1])
need = [r for r, _ in rules.required_licence_files("libffi", "static", licence)]
print(" ".join(r for r in need if r not in dests))
PY2
)
	[ -z "$missing" ] && ok "ships every licence text sondpkg requires for $l" \
		|| bad "ships every licence text sondpkg requires (missing: $missing)"
else
	bad "libffi-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-libffi-fork: OK\n'
else
	printf 'test-libffi-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
