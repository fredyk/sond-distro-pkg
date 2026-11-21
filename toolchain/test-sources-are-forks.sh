#!/bin/bash
# The toolchain builds from fredyk's GitHub forks, never from an upstream or a
# release tarball: each *_URL is https://github.com/fredyk/<name>-sond, each
# upstream is kept only as provenance, and each fork's release tag resolves to
# the pinned commit.
#
# usage: test-sources-are-forks.sh   (reads the forks with git ls-remote)

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
set +e
here=$(dirname "${BASH_SOURCE[0]}")
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

check() { # <name> <url> <upstream> <tag> <commit>
	local name=$1 url=$2 upstream=$3 tag=$4 commit=$5 got
	[ "$url" = "https://github.com/fredyk/$name-sond" ] && ok "$name builds from fredyk/$name-sond" ||
		bad "$name builds from fredyk/$name-sond (got $url)"
	[ -n "$upstream" ] && [ "$upstream" != "$url" ] && ok "$name keeps its upstream as provenance ($upstream)" ||
		bad "$name keeps its upstream as provenance (got '$upstream')"
	got=$(git ls-remote "$url" "refs/tags/$tag^{}" "refs/tags/$tag" | awk '{print $1}' | tail -n1)
	[ "$got" = "$commit" ] && ok "fork tag $name $tag is the pinned commit" ||
		bad "fork tag $name $tag is the pinned commit (got '$got', want $commit)"
}

check toybox "$TOYBOX_URL" "${TOYBOX_UPSTREAM:-}" "$TOYBOX_TAG" "$TOYBOX_COMMIT"
check mksh "$MKSH_URL" "${MKSH_UPSTREAM:-}" "$MKSH_TAG" "$MKSH_COMMIT"
check musl "$MUSL_URL" "${MUSL_UPSTREAM:-}" "$MUSL_TAG" "$MUSL_COMMIT"
check ncurses "$NCURSES_URL" "${NCURSES_UPSTREAM:-}" "$NCURSES_TAG" "$NCURSES_COMMIT"
check linux-headers "$LINUX_HEADERS_URL" "${LINUX_HEADERS_UPSTREAM:-}" "$LINUX_HEADERS_TAG" "$LINUX_HEADERS_COMMIT"
check htop "$HTOP_URL" "${HTOP_UPSTREAM:-}" "$HTOP_TAG" "$HTOP_COMMIT"
check incus "$INCUS_URL" "${INCUS_UPSTREAM:-}" "$INCUS_TAG" "$INCUS_COMMIT"

if grep -qE 'curl|\.tar\.gz|TARBALL' "$here/build-musl.sh" "$here/common.sh"; then
	bad "musl is built from its fork, with no tarball download"
else
	ok "musl is built from its fork, with no tarball download"
fi

[ "$fail" = 0 ] && printf 'test-sources-are-forks: OK\n' || printf 'test-sources-are-forks: FAIL\n'
exit $fail
