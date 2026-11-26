#!/bin/bash
# Checks of the docker package recipe (ci/forks/docker-sond.yml) and of the official
# static tarball it unpacks.
#
# usage: ci/test-docker-payload.sh                  structure only; downloads nothing
#        ci/test-docker-payload.sh --tarball PATH   verify one tarball against the pin
#
# Without arguments this is pure structure, so it can run in a gate with no network.
# Every assertion prints one line and names itself; the first failing one is the reason
# of the non-zero exit.

set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
distro=$(cd "$here/.." && pwd)
recipe=$here/forks/docker-sond.yml
pins=$distro/toolchain/common.sh

# common.sh runs `set -euo pipefail` on the caller: this test collects every assertion
# instead of stopping at the first one, and reads unset pins through ${...:-} so a missing
# pin is a named failure rather than an unbound-variable abort.
. "$pins"
set +eu

fails=0
ok() { printf 'ok   docker-pkg: %s\n' "$1"; }
bad() { printf 'FAIL docker-pkg: %s\n' "$1"; fails=$((fails + 1)); }

# The payload of docker-29.10.1.tgz: name and exact size in bytes, measured with stat on
# the files extracted from the tarball (also frozen in .opencode-hallazgos/00-INTERFAZ.md).
payload() {
	cat <<'EOF'
dockerd 101951568
docker 34627549
containerd 39497888
containerd-shim-runc-v2 8478880
runc 15088808
docker-proxy 2796392
docker-init 743016
ctr 23584928
EOF
}

block() { # <key>  print the "|" block scalar the key holds (the recipe's own layout)
	awk -v key="$1" '
		$0 ~ "^ +" key ": \\|" { indent = match($0, /[^ ]/) - 1; grab = 1; next }
		grab {
			if ($0 == "") { print ""; next }
			cur = match($0, /[^ ]/) - 1
			if (cur <= indent) exit
			print substr($0, indent + 3)
		}' "$recipe"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

static_checks() {
	local sha=${DOCKER_STATIC_SHA256:-} url=${DOCKER_STATIC_URL:-}
	local version=${DOCKER_VERSION:-} build licences

	if [ -f "$recipe" ]; then ok "recipe $recipe exists"; else bad "recipe $recipe exists"; fi

	if [ -n "$sha" ]; then
		ok "toolchain/common.sh pins DOCKER_STATIC_SHA256"
	else
		bad "toolchain/common.sh pins DOCKER_STATIC_SHA256"
	fi
	if [ -n "$version" ]; then
		ok "toolchain/common.sh pins DOCKER_VERSION"
	else
		bad "toolchain/common.sh pins DOCKER_VERSION"
	fi
	if [ -n "$url" ]; then
		ok "toolchain/common.sh pins DOCKER_STATIC_URL"
	else
		bad "toolchain/common.sh pins DOCKER_STATIC_URL"
	fi

	# One copy in the pins: a second one could diverge from what the recipe verifies.
	if [ -n "$sha" ]; then
		if [ "$(grep -o "$sha" "$pins" | wc -l)" -eq 1 ]; then
			ok "toolchain/common.sh carries the docker sha256 once"
		else
			bad "toolchain/common.sh carries the docker sha256 once (found $(grep -o "$sha" "$pins" | wc -l) copies)"
		fi
	fi

	if [ -n "$sha" ] && [ -f "$recipe" ] && grep -qF "$sha" "$recipe"; then
		ok "recipe carries the exact sha256 $sha"
	else
		bad "recipe carries the exact sha256 $sha"
	fi
	if [ -n "$version" ] && [ -f "$recipe" ] && grep -q "^ *version: $version$" "$recipe"; then
		ok "recipe carries the exact version $version"
	else
		bad "recipe carries the exact version $version"
	fi
	if [ -n "$url" ] && [ -f "$recipe" ] && grep -qF "$url" "$recipe"; then
		ok "recipe downloads the pinned static build $url"
	else
		bad "recipe downloads the pinned static build $url"
	fi

	build=$(block build 2>/dev/null)
	if [ -f "$recipe" ] && [ -n "$build" ]; then
		ok "recipe carries a build block"
	else
		bad "recipe carries a build block"
	fi
	while read -r name _; do
		[ -n "$name" ] || continue
		if grep -qF "$name" <<<"$build"; then
			ok "recipe unpacks $name"
		else
			bad "recipe unpacks $name"
		fi
	done < <(payload)

	local expression
	expression=$(sed -n 's/^ *license: //p' "$recipe" 2>/dev/null | head -n1)
	if [ -n "$expression" ] &&
		PYTHONPATH=$distro python3 -c 'import sys; from sondpkg import spdx; spdx.check_license(sys.argv[1])' \
			"$expression" 2>/dev/null; then
		ok "licence \"$expression\" parses under sondpkg.spdx.check_license"
	else
		bad "recipe licence \"$expression\" parses under sondpkg.spdx.check_license"
	fi

	# Every text license-files names must be produced by the recipe itself: build.sh reads
	# them from the fork after the build, so a source nothing writes is a broken recipe.
	licences=$(block license-files 2>/dev/null)
	if [ -z "$licences" ]; then
		bad "recipe lists the licence texts it ships under license-files"
	else
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			src=${line%%=*}
			if grep -qF "$src" <<<"$build"; then
				ok "license-files source $src is made by the build block"
			else
				bad "license-files source $src is made by the build block"
			fi
		done <<<"$licences"
	fi
}

tarball_checks() { # <path>
	local tarball=$1 sha=${DOCKER_STATIC_SHA256:-} name size want entry

	if [ ! -f "$tarball" ]; then
		bad "--tarball: $tarball exists"
		return
	fi
	ok "--tarball: $tarball exists"

	if [ -z "$sha" ]; then
		bad "--tarball: toolchain/common.sh pins DOCKER_STATIC_SHA256"
		return
	fi
	if [ "$(sha256_of "$tarball")" = "$sha" ]; then
		ok "--tarball: sha256 matches the pin $sha"
	else
		bad "--tarball: sha256 matches the pin $sha (got $(sha256_of "$tarball"))"
		return
	fi

	while read -r name size; do
		[ -n "$name" ] || continue
		entry=$(tar --numeric-owner -tvzf "$tarball" "docker/$name" 2>/dev/null)
		if [ -z "$entry" ]; then
			bad "--tarball: docker/$name is in the tarball"
			continue
		fi
		want=$(awk '{print $3}' <<<"$entry")
		if [ "$want" = "$size" ]; then
			ok "--tarball: docker/$name is $size bytes"
		else
			bad "--tarball: docker/$name is $size bytes (got $want)"
		fi
	done < <(payload)

	# The pin describes this tarball and no other content: the directory entry plus the
	# eight binaries, nothing else.
	entry=$(tar --numeric-owner -tzf "$tarball" | sed 's|/$||' | grep -v '^docker$' | sort)
	if [ "$(wc -l <<<"$entry")" -eq 8 ]; then
		ok "--tarball: holds the eight binaries and nothing else"
	else
		bad "--tarball: holds the eight binaries and nothing else (got $(wc -l <<<"$entry") entries)"
	fi
}

case ${1:-} in
"")
	static_checks
	;;
--tarball)
	[ $# -eq 2 ] || { printf 'usage: %s [--tarball PATH]\n' "$0" >&2; exit 2; }
	tarball_checks "$2"
	;;
*)
	printf 'usage: %s [--tarball PATH]\n' "$0" >&2
	exit 2
	;;
esac

if [ "$fails" -eq 0 ]; then
	printf 'test-docker-payload: OK\n'
else
	printf 'test-docker-payload: FAIL (%d assertion(s))\n' "$fails"
	exit 1
fi
