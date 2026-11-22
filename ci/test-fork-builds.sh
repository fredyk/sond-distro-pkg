#!/bin/bash
# End-to-end check of the fork workflows: each fork, cloned at its pinned
# commit, is built with the exact inputs of ci/forks/<fork>-sond.yml through
# sond-build-action's build.sh, and the bundle must verify and hold the
# expected static binaries or files.
#
# usage: SOND_BUILD_ACTION=<sond-build-action checkout> ci/test-fork-builds.sh [fork...]
#   SOND_CI_WORK  scratch directory (default: a fresh temp dir)

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
distro=$(cd "$here/.." && pwd)
. "$distro/toolchain/common.sh"
action=${SOND_BUILD_ACTION:?set SOND_BUILD_ACTION to a sond-build-action checkout}
work=${SOND_CI_WORK:-$(mktemp -d)}
mkdir -p "$work"
forks=("$@")
[ ${#forks[@]} -gt 0 ] || forks=(toybox mksh musl ncurses linux-headers htop incus libuv sqlite raft cowsql attr libcap acl libseccomp lxc libudev-zero incusd)

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# The build step's inputs, as NUL-separated KEY=VALUE pairs.
inputs_of() { # <workflow>
	python3 - "$1" <<'PY'
import re, sys
# The workflows are generated with one layout: the build step's "with:" keys sit
# two spaces deeper than "with:", and a "|" value is the block indented below.
lines = open(sys.argv[1]).read().split("\n")
i = next(n for n, l in enumerate(lines) if l.strip() == "- id: build")
i = next(n for n in range(i, len(lines)) if lines[n].strip() == "with:")
indent = len(lines[i + 1]) - len(lines[i + 1].lstrip())
n = i + 1
while n < len(lines) and len(lines[n]) - len(lines[n].lstrip()) == indent and lines[n].strip():
    key, _, val = lines[n].strip().partition(": ")
    n += 1
    if val == "|":
        block = []
        while n < len(lines) and (not lines[n].strip() or len(lines[n]) - len(lines[n].lstrip()) > indent):
            block.append(lines[n][indent + 2:])
            n += 1
        val = "\n".join(block).rstrip("\n") + "\n"
    sys.stdout.write(f"{key}={val}\0")
PY
}

build_fork() { # <fork> <url> <tag> <commit> [package: another package built from the same fork]
	local fork=$1 url=$2 tag=$3 commit=$4 package=${5:-$1}
	local dir=$work/$package/src
	local -A in=()
	[ -d "$dir/.git" ] || git clone -q --branch "$tag" "$url" "$dir"
	# What CI builds: the fork's sond branch when it exists, else the pinned upstream commit.
	if git -C "$dir" fetch -q origin sond 2>/dev/null; then
		git -C "$dir" checkout -q FETCH_HEAD
		git -C "$dir" merge-base --is-ancestor "$commit" HEAD || { bad "$fork: sond branch descends from $commit"; return; }
	else
		git -C "$dir" checkout -q "$commit"
	fi
	while IFS= read -r -d '' kv; do in[${kv%%=*}]=${kv#*=}; done < <(inputs_of "$here/forks/$package-sond.yml")

	local args=(--fork "$dir" --repository "fredyk/$fork-sond" --name "${in[name]}"
		--version "${in[version]}" --license "${in[license]}" --upstream "${in[upstream]}"
		--build "${in[build]}" --out "$work/$package/out")
	[ -z "${in[linkage]:-}" ] || args+=(--linkage "${in[linkage]}")
	while IFS= read -r f; do
		[ -n "$f" ] && args+=(--license-file "$f")
	done <<<"${in[license-files]:-}"
	while IFS= read -r d; do
		[ -n "$d" ] && args+=(--depends "$d")
	done <<<"${in[depends]:-}"

	local log=$work/$package/build.log res
	if ! res=$(RUNNER_TEMP=$work/$package/runner SOND_WORK=$work/$package/runner/sond SOND_DISTRO_PKG=$distro \
		bash "$action/build.sh" "${args[@]}" 2>"$log"); then
		tail -40 "$log"
		bad "$package: build.sh succeeds"
		return
	fi
	ok "$package: build.sh succeeds"
	local bundle
	bundle=$(sed -n 's/^bundle=//p' <<<"$res")
	sed -n 's/^source_bundle=//p' <<<"$res" >"$work/$package/source_bundle"
	python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$bundle" >/dev/null &&
		ok "$package: bundle verifies" || bad "$package: bundle verifies"
	printf '%s\n' "$bundle" >"$work/$package/bundle"
}

static_bin() { # <fork> <path in payload>
	local f
	f=$(cat "$work/$1/bundle")/payload/$2
	case $(file -b "$f" 2>/dev/null) in
	*"statically linked"*) ok "$1: $2 is a static binary" ;;
	*) bad "$1: $2 is a static binary ($(file -b "$f" 2>&1))" ;;
	esac
}

link_to() { # <fork> <path in payload> <target>
	local f
	f=$(cat "$work/$1/bundle")/payload/$2
	[ "$(readlink "$f" 2>/dev/null)" = "$3" ] && ok "$1: $2 -> $3" || bad "$1: $2 -> $3"
}

has_file() { # <fork> <path in payload>
	[ -f "$(cat "$work/$1/bundle")/payload/$2" ] && ok "$1: ships $2" || bad "$1: ships $2"
}

for fork in "${forks[@]}"; do
	case $fork in
	toybox)
		build_fork toybox "$TOYBOX_URL" "$TOYBOX_TAG" "$TOYBOX_COMMIT"
		[ -f "$work/toybox/bundle" ] || continue
		static_bin toybox bin/toybox
		for a in $TOYBOX_COMMANDS; do link_to toybox "bin/$a" toybox; done
		has_file toybox share/licenses/toybox-static/musl-COPYRIGHT
		;;
	mksh)
		build_fork mksh "$MKSH_URL" "$MKSH_TAG" "$MKSH_COMMIT"
		[ -f "$work/mksh/bundle" ] || continue
		static_bin mksh bin/mksh
		link_to mksh bin/sh mksh
		link_to mksh bin/ksh mksh
		out=$("$(cat "$work/mksh/bundle")/payload/bin/mksh" -c 'echo $((6*7))' 2>&1 || true)
		[ "$out" = 42 ] && ok "mksh: runs a script" || bad "mksh: runs a script (got $out)"
		;;
	musl)
		build_fork musl "$MUSL_URL" "$MUSL_TAG" "$MUSL_COMMIT"
		[ -f "$work/musl/bundle" ] || continue
		has_file musl lib/libc.a
		has_file musl lib/crt1.o
		has_file musl include/stdio.h
		;;
	ncurses)
		build_fork ncurses "$NCURSES_URL" "$NCURSES_TAG" "$NCURSES_COMMIT"
		[ -f "$work/ncurses/bundle" ] || continue
		has_file ncurses lib/libncursesw.a
		has_file ncurses lib/libtinfow.a
		has_file ncurses include/ncursesw/curses.h
		has_file ncurses lib/pkgconfig/ncursesw.pc
		has_file ncurses share/licenses/ncurses/COPYING
		# A static binary on a host without a terminfo database still knows the
		# common terminals: they are compiled in as fallbacks.
		for t in linux xterm-256color screen-256color tmux-256color vt100; do
			strings "$(cat "$work/ncurses/bundle")/payload/lib/libtinfow.a" | grep -x "$t|.*" >/dev/null &&
				ok "ncurses: $t is a fallback" || bad "ncurses: $t is a fallback"
		done
		;;
	linux-headers)
		build_fork linux-headers "$LINUX_HEADERS_URL" "$LINUX_HEADERS_TAG" "$LINUX_HEADERS_COMMIT"
		[ -f "$work/linux-headers/bundle" ] || continue
		for f in linux/capability.h linux/version.h asm/unistd.h asm-generic/errno.h linux/libc-compat.h; do
			has_file linux-headers "include/$f"
		done
		b=$(cat "$work/linux-headers/bundle")
		n=$(find "$b/payload" -type f ! -name '*.h' ! -path '*/share/licenses/*' | wc -l)
		[ "$n" = 0 ] && ok "linux-headers: ships only headers and licences" || bad "linux-headers: ships only headers and licences ($n other files)"
		grep -q '^ *bundled *=' "$b/MANIFEST" && bad "linux-headers: nothing is linked into headers" || ok "linux-headers: nothing is linked into headers"
		src=$(cat "$work/linux-headers/source_bundle")
		[ -n "$src" ] && python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$src" >/dev/null &&
			ok "linux-headers: the corresponding source bundle verifies" || bad "linux-headers: the corresponding source bundle verifies"
		;;
	htop)
		build_fork htop "$HTOP_URL" "$HTOP_TAG" "$HTOP_COMMIT"
		[ -f "$work/htop/bundle" ] || continue
		static_bin htop bin/htop
		b=$(cat "$work/htop/bundle")
		for f in COPYING ncurses-COPYING musl-COPYRIGHT; do has_file htop "share/licenses/htop/$f"; done
		# the opinion read the kernel headers htop uses: all under the syscall note or the COPYING
		[ ! -e "$b/payload/share/licenses/htop/linux-headers" ] && ok "htop: carries no kernel header notice" ||
			bad "htop: carries no kernel header notice ($(ls "$b/payload/share/licenses/htop/linux-headers"))"
		# dictamen 3.1 rule 5: exactly ncurses and musl are linked in
		[ "$(sed -n '/^ *bundled *=/,/\]/p' "$b/MANIFEST" | grep -oE '"[a-z0-9.+_-]+ ' | tr -d '" ' | sort | tr '\n' ' ')" = "musl ncurses " ] &&
			ok "htop: bundled is exactly ncurses and musl" || bad "htop: bundled is exactly ncurses and musl ($(grep -A4 bundled "$b/MANIFEST"))"
		src=$(cat "$work/htop/source_bundle")
		[ -n "$src" ] && python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$src" >/dev/null &&
			ok "htop: the corresponding source bundle verifies" || bad "htop: the corresponding source bundle verifies"
		for f in "htop-$HTOP_VERSION.tar.gz" musl-1.2.5.tar.gz "ncurses-$NCURSES_VERSION.tar.gz" build-recipe.sh; do
			[ -f "$src/payload/share/src/htop/$f" ] && ok "htop-source: holds $f" || bad "htop-source: holds $f"
		done
		out=$(TERM=xterm-256color "$b/payload/bin/htop" --version 2>&1 || true)
		# the release's version, as upstream's tarball reports it: not git describe of the sond branch
		[ "$(head -n1 <<<"$out")" = "htop $HTOP_TAG" ] && ok "htop: runs and reports $HTOP_TAG" || bad "htop: runs and reports $HTOP_TAG (got $out)"
		;;
	incus)
		# the client only, pure Go (licence opinion 2.10 (a))
		build_fork incus "$INCUS_URL" "$INCUS_TAG" "$INCUS_COMMIT"
		[ -f "$work/incus/bundle" ] || continue
		static_bin incus bin/incus
		b=$(cat "$work/incus/bundle")
		for f in COPYING go-LICENSE NOTICE; do has_file incus "share/licenses/incus/$f"; done
		[ ! -e "$b/payload/share/licenses/incus/musl-COPYRIGHT" ] && ok "incus: no libc, no musl notice" || bad "incus: no libc, no musl notice"
		[ -z "$(cat "$work/incus/source_bundle")" ] && ok "incus: permissive throughout, no source lane" || bad "incus: permissive throughout, no source lane"
		for n in github.com/zitadel/oidc/v3 go.yaml.in/yaml/v4; do
			grep -q "^==== $n " "$b/payload/share/licenses/incus/NOTICE" && ok "incus: NOTICE carries $n" || bad "incus: NOTICE carries $n"
		done
		bundled=$(sed -n '/^ *bundled *=/,/\]/p' "$b/MANIFEST")
		for e in "go 1.26.9 BSD-3-Clause" "github.com/cyphar/filepath-securejoin v0.7.0 BSD-3-Clause" \
			"github.com/opencontainers/go-digest v1.0.0 Apache-2.0" "github.com/muhlemmer/gu v0.3.1 Unlicense"; do
			grep -qF "\"$e\"" <<<"$bundled" && ok "incus: bundled $e" || bad "incus: bundled $e"
		done
		# the opinion counted 71 modules linked into the client, plus Go itself
		[ "$(grep -c '"' <<<"$bundled")" = 72 ] && ok "incus: bundled is Go and 71 modules" || bad "incus: bundled is Go and 71 modules ($(grep -c '"' <<<"$bundled"))"
		# what upstream's own build reports: internal/version/flex.go says 7.6 for the v7.6.0 tag
		out=$("$b/payload/bin/incus" --version 2>&1 || true)
		want=$(sed -n 's/^var Version = "\(.*\)"$/\1/p' "$work/incus/src/internal/version/flex.go")
		[ -n "$want" ] && [ "$out" = "$want" ] && ok "incus: runs and reports $want" || bad "incus: runs and reports $want (got $out)"
		;;
	libudev-zero)
		# libudev without udevd (ISC): what incusd's device hotplug links on a system with no udev
		build_fork libudev-zero "$LIBUDEV_ZERO_URL" "$LIBUDEV_ZERO_TAG" "$LIBUDEV_ZERO_COMMIT"
		[ -f "$work/libudev-zero/bundle" ] || continue
		b=$(cat "$work/libudev-zero/bundle")
		for f in lib/libudev.a include/libudev.h lib/pkgconfig/libudev.pc share/licenses/libudev-zero/LICENSE; do has_file libudev-zero "$f"; done
		[ -z "$(find "$b/payload" -name '*.so*')" ] && ok "libudev-zero: static only" || bad "libudev-zero: static only"
		grep -q '^ *license *= *"ISC"' "$b/MANIFEST" && ok "libudev-zero: licence ISC" || bad "libudev-zero: licence ISC"
		[ -z "$(cat "$work/libudev-zero/source_bundle")" ] && ok "libudev-zero: permissive, no source lane" || bad "libudev-zero: permissive, no source lane"
		;;
	incusd)
		# the daemon: cgo, linked statically against the published C libraries (licence opinion 2.10 (b))
		build_fork incus "$INCUS_URL" "$INCUS_TAG" "$INCUS_COMMIT" incusd
		[ -f "$work/incusd/bundle" ] || continue
		static_bin incusd bin/incusd
		b=$(cat "$work/incusd/bundle")
		grep -q '^ *license *= *"Apache-2.0 AND LGPL-2.1-or-later"' "$b/MANIFEST" && ok "incusd: licence Apache-2.0 AND LGPL-2.1-or-later" || bad "incusd: licence ($(grep '^ *license' "$b/MANIFEST"))"
		for f in COPYING go-LICENSE NOTICE musl-COPYRIGHT LGPL-2.1 LGPL-3.0 GPL-3.0 MPL-2.0; do has_file incusd "share/licenses/incusd/$f"; done
		bundled=$(sed -n '/^ *bundled *=/,/\]/p' "$b/MANIFEST")
		for e in "lxc 7.0.0-sond2 LGPL-2.1-or-later" "libseccomp 2.6.2 LGPL-2.1-only" "acl 2.4.0 LGPL-2.1-or-later" \
			"libcap 1.2.78 BSD-3-Clause" "cowsql 1.15.9 LGPL-3.0-only WITH LGPL-3.0-linking-exception" \
			"raft 0.22.1 LGPL-3.0-only WITH LGPL-3.0-linking-exception" "sqlite 3.54.1 blessing" "musl 1.2.5 MIT" \
			"libudev-zero 1.0.5 ISC" "go 1.26.9 BSD-3-Clause" "github.com/lxc/go-lxc"; do
			grep -qF "\"$e" <<<"$bundled" && ok "incusd: bundled $e" || bad "incusd: bundled $e"
		done
		grep -qF '"github.com/mattn/go-sqlite3' <<<"$bundled" && ok "incusd: go-sqlite3 links the sqlite package (tag libsqlite3)" || bad "incusd: go-sqlite3 linked"
		[ -n "$(find "$b/payload/share/licenses/incusd/linux-headers" -name '*.h' 2>/dev/null)" ] && ok "incusd: the kernel headers without the syscall note carry their notices" || bad "incusd: the kernel headers without the syscall note carry their notices"
		src=$(cat "$work/incusd/source_bundle")
		[ -n "$src" ] && python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$src" >/dev/null &&
			ok "incusd: the corresponding source bundle verifies" || bad "incusd: the corresponding source bundle verifies"
		out=$("$b/payload/bin/incusd" --version 2>&1 || true)
		want=$(sed -n 's/^var Version = "\(.*\)"$/\1/p' "$work/incusd/src/internal/version/flex.go")
		[ -n "$want" ] && [ "$out" = "$want" ] && ok "incusd: runs and reports $want" || bad "incusd: runs and reports $want (got $out)"
		;;
	libuv)
		build_fork libuv "$LIBUV_URL" "$LIBUV_TAG" "$LIBUV_COMMIT"
		[ -f "$work/libuv/bundle" ] || continue
		b=$(cat "$work/libuv/bundle")
		for f in lib/libuv.a include/uv.h lib/pkgconfig/libuv.pc \
			share/licenses/libuv/LICENSE share/licenses/libuv/LICENSE-extra; do has_file libuv "$f"; done
		[ -z "$(find "$b/payload" -name '*.so*')" ] && ok "libuv: static only" || bad "libuv: static only"
		# LICENSE-extra: tree.h is BSD-2-Clause and src/inet.c ISC, both compiled in
		grep -q '^ *license *= *"MIT AND BSD-2-Clause AND ISC"' "$b/MANIFEST" &&
			ok "libuv: licence MIT AND BSD-2-Clause AND ISC" || bad "libuv: licence MIT AND BSD-2-Clause AND ISC ($(grep '^ *license' "$b/MANIFEST"))"
		;;
	sqlite)
		build_fork sqlite "$SQLITE_URL" "$SQLITE_TAG" "$SQLITE_COMMIT"
		[ -f "$work/sqlite/bundle" ] || continue
		b=$(cat "$work/sqlite/bundle")
		for f in lib/libsqlite3.a include/sqlite3.h lib/pkgconfig/sqlite3.pc share/licenses/sqlite/LICENSE.md; do has_file sqlite "$f"; done
		[ -z "$(find "$b/payload" -name '*.so*')" ] && ok "sqlite: static only" || bad "sqlite: static only"
		static_bin sqlite bin/sqlite3
		out=$("$b/payload/bin/sqlite3" :memory: 'select sqlite_version();' 2>&1 || true)
		[ "$out" = "${SQLITE_TAG#version-}" ] && ok "sqlite: runs and reports ${SQLITE_TAG#version-}" || bad "sqlite: runs and reports ${SQLITE_TAG#version-} (got $out)"
		;;
	raft | cowsql)
		# LGPL-3.0 with the static linking exception: static libraries, their source published first
		pin=$(tr a-z A-Z <<<"$fork")
		url=${pin}_URL tag=${pin}_TAG commit=${pin}_COMMIT
		build_fork "$fork" "${!url}" "${!tag}" "${!commit}"
		[ -f "$work/$fork/bundle" ] || continue
		b=$(cat "$work/$fork/bundle")
		for f in "lib/lib$fork.a" "include/$fork.h" "lib/pkgconfig/$fork.pc" \
			"share/licenses/$fork/LICENSE" "share/licenses/$fork/LGPL-3.0" "share/licenses/$fork/GPL-3.0"; do has_file "$fork" "$f"; done
		[ -z "$(find "$b/payload" -name '*.so*')" ] && ok "$fork: static only" || bad "$fork: static only"
		grep -q '^ *license *= *"LGPL-3.0-only WITH LGPL-3.0-linking-exception"' "$b/MANIFEST" &&
			ok "$fork: licence LGPL-3.0-only WITH LGPL-3.0-linking-exception" || bad "$fork: licence ($(grep '^ *license' "$b/MANIFEST"))"
		# a static library links nothing: its dependencies are only compiled against
		! grep -q '^ *bundled' "$b/MANIFEST" && ok "$fork: bundles nothing" || bad "$fork: bundles nothing ($(grep -A4 bundled "$b/MANIFEST"))"
		src=$(cat "$work/$fork/source_bundle")
		[ -n "$src" ] && python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$src" >/dev/null &&
			ok "$fork: the corresponding source bundle verifies" || bad "$fork: the corresponding source bundle verifies"
		;;
	attr | libcap | acl | libseccomp | lxc)
		# static libraries for incusd (licence opinion, its table); LGPL ones publish their source first
		pin=$(tr a-z A-Z <<<"$fork")
		url=${pin}_URL tag=${pin}_TAG commit=${pin}_COMMIT
		build_fork "$fork" "${!url}" "${!tag}" "${!commit}"
		[ -f "$work/$fork/bundle" ] || continue
		b=$(cat "$work/$fork/bundle")
		case $fork in
		attr) files="lib/libattr.a include/attr/error_context.h include/attr/attributes.h include/attr/libattr.h lib/pkgconfig/libattr.pc share/licenses/attr/LGPL-2.1"
			lic="LGPL-2.1-or-later" ;;
		libcap) files="lib/libcap.a include/sys/capability.h lib/pkgconfig/libcap.pc share/licenses/libcap/License"
			lic="BSD-3-Clause" ;;
		acl) files="lib/libacl.a include/sys/acl.h include/acl/libacl.h lib/pkgconfig/libacl.pc share/licenses/acl/LGPL-2.1"
			lic="LGPL-2.1-or-later" ;;
		libseccomp) files="lib/libseccomp.a include/seccomp.h lib/pkgconfig/libseccomp.pc share/licenses/libseccomp/LGPL-2.1"
			lic="LGPL-2.1-only" ;;
		lxc) files="lib/liblxc.a include/lxc/lxccontainer.h include/lxc/attach_options.h include/lxc/version.h lib/pkgconfig/lxc.pc share/licenses/lxc/LGPL-2.1"
			lic="LGPL-2.1-or-later" ;;
		esac
		for f in $files; do has_file "$fork" "$f"; done
		[ -z "$(find "$b/payload" -name '*.so*')" ] && ok "$fork: static only" || bad "$fork: static only"
		[ -z "$(find "$b/payload/bin" "$b/payload/sbin" "$b/payload/libexec" -type f 2>/dev/null)" ] && ok "$fork: no programs" || bad "$fork: no programs"
		grep -q "^ *license *= *\"$lic\"" "$b/MANIFEST" && ok "$fork: licence $lic" || bad "$fork: licence $lic ($(grep '^ *license' "$b/MANIFEST"))"
		! grep -q '^ *bundled' "$b/MANIFEST" && ok "$fork: bundles nothing" || bad "$fork: bundles nothing ($(grep -A4 bundled "$b/MANIFEST"))"
		if [ "$fork" = lxc ]; then
			# the licence opinion: no libcrypto in liblxc
			grep -q 'libssl\|libcrypto' "$b/payload/lib/pkgconfig/lxc.pc" && bad "lxc: links no openssl" || ok "lxc: links no openssl"
			# like liblxc.so: only the __public API is global, so lxc's internals cannot collide with a
			# program's own (incus defines lxc_abstract_unix_send_fds too)
			hidden=$(readelf -sW "$b/payload/lib/liblxc.a" | awk '$5=="GLOBAL" && $6=="HIDDEN" && $7!="UND"' | wc -l)
			[ "$hidden" = 0 ] && ok "lxc: exports only its public API" || bad "lxc: exports only its public API ($hidden hidden globals)"
			# -fexceptions would pull libgcc_eh's unwinder, built for glibc (_dl_find_object)
			unwind=$(nm "$b/payload/lib/liblxc.a" 2>/dev/null | grep -c ' U _Unwind_' || true)
			[ "$unwind" = 0 ] && ok "lxc: needs no unwinder" || bad "lxc: needs no unwinder ($unwind references)"
		fi
		src=$(cat "$work/$fork/source_bundle")
		if [ "$lic" = BSD-3-Clause ]; then
			[ -z "$src" ] && ok "$fork: the BSD-3-Clause branch needs no source lane" || bad "$fork: the BSD-3-Clause branch needs no source lane"
		else
			[ -n "$src" ] && python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$src" >/dev/null &&
				ok "$fork: the corresponding source bundle verifies" || bad "$fork: the corresponding source bundle verifies"
		fi
		;;
	*) bad "unknown fork $fork" ;;
	esac
done

if [ "$fails" -eq 0 ]; then
	printf 'test-fork-builds: OK\n'
else
	printf 'test-fork-builds: FAIL\n'
	exit 1
fi
