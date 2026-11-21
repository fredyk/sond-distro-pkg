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
[ ${#forks[@]} -gt 0 ] || forks=(toybox mksh musl ncurses linux-headers htop)

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

build_fork() { # <fork> <url> <tag> <commit>
	local fork=$1 url=$2 tag=$3 commit=$4
	local dir=$work/$fork/src
	local -A in=()
	[ -d "$dir/.git" ] || git clone -q --branch "$tag" "$url" "$dir"
	# What CI builds: the fork's sond branch when it exists, else the pinned upstream commit.
	if git -C "$dir" fetch -q origin sond 2>/dev/null; then
		git -C "$dir" checkout -q FETCH_HEAD
		git -C "$dir" merge-base --is-ancestor "$commit" HEAD || { bad "$fork: sond branch descends from $commit"; return; }
	else
		git -C "$dir" checkout -q "$commit"
	fi
	while IFS= read -r -d '' kv; do in[${kv%%=*}]=${kv#*=}; done < <(inputs_of "$here/forks/$fork-sond.yml")

	local args=(--fork "$dir" --repository "fredyk/$fork-sond" --name "${in[name]}"
		--version "${in[version]}" --license "${in[license]}" --upstream "${in[upstream]}"
		--build "${in[build]}" --out "$work/$fork/out")
	[ -z "${in[linkage]:-}" ] || args+=(--linkage "${in[linkage]}")
	while IFS= read -r f; do
		[ -n "$f" ] && args+=(--license-file "$f")
	done <<<"${in[license-files]:-}"
	while IFS= read -r d; do
		[ -n "$d" ] && args+=(--depends "$d")
	done <<<"${in[depends]:-}"

	local log=$work/$fork/build.log res
	if ! res=$(RUNNER_TEMP=$work/$fork/runner SOND_WORK=$work/$fork/runner/sond SOND_DISTRO_PKG=$distro \
		bash "$action/build.sh" "${args[@]}" 2>"$log"); then
		tail -40 "$log"
		bad "$fork: build.sh succeeds"
		return
	fi
	ok "$fork: build.sh succeeds"
	local bundle
	bundle=$(sed -n 's/^bundle=//p' <<<"$res")
	sed -n 's/^source_bundle=//p' <<<"$res" >"$work/$fork/source_bundle"
	python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$bundle" >/dev/null &&
		ok "$fork: bundle verifies" || bad "$fork: bundle verifies"
	printf '%s\n' "$bundle" >"$work/$fork/bundle"
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
		# dictamen 3.1 rule 5: exactly ncurses and musl are linked in
		[ "$(sed -n '/^ *bundled *=/,/\]/p' "$b/MANIFEST" | grep -oE '"[a-z0-9.+_-]+ ' | tr -d '" ' | sort | tr '\n' ' ')" = "musl ncurses " ] &&
			ok "htop: bundled is exactly ncurses and musl" || bad "htop: bundled is exactly ncurses and musl ($(grep -A4 bundled "$b/MANIFEST"))"
		src=$(cat "$work/htop/source_bundle")
		[ -n "$src" ] && python3 "$distro/sondpkg/bin/sondpkg" verify-bundle "$src" >/dev/null &&
			ok "htop: the corresponding source bundle verifies" || bad "htop: the corresponding source bundle verifies"
		for f in "htop-$HTOP_TAG.tar.gz" musl-1.2.5.tar.gz "ncurses-$NCURSES_VERSION.tar.gz" build-recipe.sh; do
			[ -f "$src/payload/share/src/htop/$f" ] && ok "htop-source: holds $f" || bad "htop-source: holds $f"
		done
		out=$(TERM=xterm-256color "$b/payload/bin/htop" --version 2>&1 || true)
		case $out in "htop $HTOP_TAG"*) ok "htop: runs" ;; *) bad "htop: runs (got $out)" ;; esac
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
