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
# COPYING at that commit is a symlink to LICENSES/LGPL-2.1-or-later.txt: a checkout reads the
# text through it, so the text is pinned, and shipped, at its own path. sha256 of that file:
LICENCE_TEXT=LICENSES/LGPL-2.1-or-later.txt
LICENCE_TEXT_SHA=fa6f36630bb1e0c571d34b2bbdf188d08495c9dbf58f28cac112f303fc1f58fb

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
	has "$LICENCE_TEXT_SHA  $LICENCE_TEXT" && ok "LGPL-2.1 text pinned by sha256 at its own path" \
		|| bad "LGPL-2.1 text pinned by sha256 at $LICENCE_TEXT"
	has "^ +$LICENCE_TEXT=share/licenses/glib/LGPL-2\.1$" && ok "ships the LGPL-2.1 text from its own path" \
		|| bad "ships $LICENCE_TEXT as share/licenses/glib/LGPL-2.1"
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
	# gio's gzlibcompressor.c (built by meson with the rest of glib) includes <zlib.h>; the pin so
	# the header comes from the sysroot of the zlib package, not from whatever the runner has.
	has '^ +zlib 1\.3\.2$' && ok "depends zlib 1.3.2 (gio compiles <zlib.h> against the sysroot)" \
		|| bad "depends zlib 1.3.2 (gio compiles <zlib.h> against the sysroot)"
	# The package ships the three promised libraries only: meson also installs gio and gobject
	# (their archives, .pc files and headers) and two more gmodule .pc variants, and leaving them
	# in makes a consumer's static run configure find gio (qemu's gio probe is an auto feature)
	# and drag libffi in through it. Deleted by file name, not by pattern.
	has 'rm -f "\$SOND_PAYLOAD/lib/libgio-2\.0\.a" "\$SOND_PAYLOAD/lib/libgobject-2\.0\.a"' \
		&& ok "removes the gio and gobject archives" || bad "removes the gio and gobject archives"
	has 'rm -f "\$SOND_PAYLOAD/lib/pkgconfig/gio-2\.0\.pc" "\$SOND_PAYLOAD/lib/pkgconfig/gio-unix-2\.0\.pc"' \
		&& ok "removes the gio .pc files" || bad "removes the gio .pc files"
	has '"\$SOND_PAYLOAD/lib/pkgconfig/gobject-2\.0\.pc"' && ok "removes gobject-2.0.pc" \
		|| bad "removes gobject-2.0.pc"
	has 'rm -f "\$SOND_PAYLOAD/lib/pkgconfig/gmodule-2\.0\.pc" "\$SOND_PAYLOAD/lib/pkgconfig/gmodule-export-2\.0\.pc"' \
		&& ok "removes the unused gmodule .pc variants" || bad "removes the unused gmodule .pc variants"
	has 'rm -rf "\$SOND_PAYLOAD/include/gio-unix-2\.0" "\$SOND_PAYLOAD/include/glib-2\.0/gio"' \
		&& ok "removes the gio headers" || bad "removes the gio headers"
	has '"\$SOND_PAYLOAD/include/glib-2\.0/gobject"' && ok "removes the gobject headers" \
		|| bad "removes the gobject headers"
	has 'rm -f "\$SOND_PAYLOAD/include/glib-2\.0/glib-object\.h"' && ok "removes glib-object.h" \
		|| bad "removes glib-object.h"
	# payload: lib/*.a, include, lib/pkgconfig and nothing else (no bin/, share/ beyond licences).
	has 'rm -rf "\$SOND_PAYLOAD/bin" "\$SOND_PAYLOAD/share"' && ok "ships no programs or data" \
		|| bad "ships no programs or data (bin/ and share/ removed)"
	for pc in glib-2.0 gthread-2.0 gmodule-no-export-2.0; do
		has "lib/pkgconfig/$pc\.pc" && ok "asserts $pc.pc shipped" || bad "asserts $pc.pc shipped"
	done
	has 'lib/glib-2\.0/include' && ok "keeps glibconfig.h (lib/glib-2.0/include)" \
		|| bad "keeps glibconfig.h (lib/glib-2.0/include)"
	has '\.so([^a-z_]|$)' && bad "no shared object referenced" || ok "no shared object referenced"
else
	bad "glib-sond.yml: present"
fi

if [ "$fails" -eq 0 ]; then
	printf 'test-glib-fork: OK\n'
else
	printf 'test-glib-fork: FAIL (%d)\n' "$fails"
	exit 1
fi
