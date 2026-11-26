#!/bin/bash
# Shape checks for the glib fork recipe: a static library package (glib-2.0, gthread-2.0,
# gmodule-no-export-2.0 and their pkg-config files) for a static musl qemu, built with meson
# against the pinned musl, LGPL-2.1-or-later with its text pinned by sha256. pcre2 and libffi
# come in through `depends` (separate packages), never as meson wraps fetched at build time.
# Every rule ci/test-fork-workflows.sh applies to the other recipes applies here.
# Offline: no network, no build.
#
# usage: ci/test-glib-fork.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# Measured on 2026-11-26 from github.com/GNOME/glib at its tag 2.86.5 (peeled commit).
VERSION=2.86.5
UPSTREAM=github.com/GNOME/glib@3033f7862c2d3c7569cef2ad4b425cf42e95d4b4
# sha256 of COPYING at that commit (LGPL-2.1 text).
COPYING_SHA=65986a89240f59896ce42a3779bbe5ed486a0bca7df636a8eef030fd2e1a0984

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
check glib glib "$VERSION" "$UPSTREAM"

yml=$here/forks/glib-sond.yml
has() { grep -qE -- "$1" "$yml"; }
if [ -f "$yml" ]; then
	has '^ +license: LGPL-2\.1-or-later$' && ok "license LGPL-2.1-or-later" || bad "license LGPL-2.1-or-later"
	has "$COPYING_SHA" && ok "COPYING pinned by sha256" || bad "COPYING pinned by sha256"
	has 'meson setup' && ok "built with meson" || bad "built with meson"
	has -- '--default-library=static' && ok "static library only" || bad "--default-library=static"
	for opt in '-Dintrospection=disabled' '-Dtests=false' '-Ddocumentation=false' \
		'-Dman-pages=disabled' '-Dnls=disabled' '-Dselinux=disabled' '-Dxattr=false' \
		'-Dlibmount=disabled' '-Dsysprof=disabled' '-Dlibelf=disabled' '-Ddtrace=disabled' \
		'-Dsystemtap=disabled'; do
		has -- "$opt( |$)" && ok "option $opt" || bad "option $opt"
	done
	has -- '--wrap-mode=nodownload' && ok "no meson wrap is fetched at build time" \
		|| bad "--wrap-mode=nodownload"
	has '^ +pcre2 [0-9]' && ok "depends on pcre2" || bad "depends on pcre2"
	has '^ +libffi [0-9]' && ok "depends on libffi" || bad "depends on libffi"
	# payload: lib/*.a, include, lib/pkgconfig and nothing else (no bin/, share/ beyond licences).
	has 'rm -rf "\$SOND_PAYLOAD/bin" "\$SOND_PAYLOAD/share"' && ok "ships no programs or data" \
		|| bad "ships no programs or data (bin/ and share/ removed)"
	for pc in glib-2.0 gthread-2.0 gmodule-no-export-2.0; do
		has "lib/pkgconfig/$pc\.pc" && ok "asserts $pc.pc shipped" || bad "asserts $pc.pc shipped"
	done
	has 'lib/glib-2\.0/include' && ok "keeps glibconfig.h (lib/glib-2.0/include)" \
		|| bad "keeps glibconfig.h (lib/glib-2.0/include)"
	has '\.so' && bad "no shared object referenced" || ok "no shared object referenced"
else
	bad "glib-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-glib-fork: OK\n'
else
	printf 'test-glib-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
