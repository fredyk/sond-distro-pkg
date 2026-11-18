#!/bin/bash
# Create the three local forks of the Sond toolchain: clone each upstream,
# pin it to the revision from the encargo and put the local branch "sond" on
# that exact commit. Then export each fork's Sond patch series.
#
# usage: build-forks.sh
#
# Idempotent: clones that are already correct are left alone.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mkdir -p "$SRC_ROOT" "$PATCH_DIR"

# Bring one clone to the pinned revision: HEAD, index and working tree all at
# $commit, on the local branch "sond".
pin_fork() { # <name> <url> <tag> <commit>
	local name=$1 url=$2 tag=$3 commit=$4
	local dir=$SRC_ROOT/$name-sond

	if [ ! -d "$dir/.git" ]; then
		printf 'cloning %s at %s -> %s\n' "$url" "$tag" "$dir"
		git clone --branch "$tag" "$url" "$dir"
	fi

	if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
		printf 'error: %s does not contain the pinned commit %s\n' "$dir" "$commit" >&2
		return 1
	fi

	if git -C "$dir" show-ref --verify --quiet refs/heads/sond; then
		local have
		have=$(git -C "$dir" rev-parse refs/heads/sond)
		if [ "$have" != "$commit" ]; then
			printf 'error: branch sond in %s points at %s, expected %s\n' \
				"$dir" "$have" "$commit" >&2
			return 1
		fi
	else
		git -C "$dir" branch sond "$commit"
	fi

	# A clone whose checkout was interrupted ends up with an empty index and a
	# working tree from another revision. Repair index and working tree from
	# the pinned tree instead of working around it.
	if [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ] ||
		[ -n "$(git -C "$dir" diff --cached --name-only "$commit" | head -n1)" ] ||
		[ -n "$(git -C "$dir" diff --name-only "$commit" | head -n1)" ]; then
		printf 'restoring index and working tree of %s to %s\n' "$dir" "$commit"
		git -C "$dir" restore --source="$commit" --staged --worktree :/
	fi
	git -C "$dir" symbolic-ref HEAD refs/heads/sond

	# Files that belong to another revision would be picked up by musl's source
	# globs, so they go. Regular files only, one at a time, never a recursive
	# delete.
	local leftover
	leftover=$(git -C "$dir" ls-files --others --exclude-standard)
	if [ -n "$leftover" ]; then
		printf 'removing leftover file(s) in %s that are not part of %s\n' "$dir" "$commit"
		while IFS= read -r f; do
			[ -n "$f" ] && rm -f -- "$dir/$f"
		done <<<"$leftover"
	fi

	if [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
		printf 'error: %s HEAD is %s, expected %s\n' \
			"$dir" "$(git -C "$dir" rev-parse HEAD)" "$commit" >&2
		return 1
	fi
	printf 'pinned %-6s @ %s on branch sond (%s)\n' \
		"$name" "$(git -C "$dir" rev-parse --short=12 HEAD)" "$commit"
}

# Export the fork's own commits as a patch series. A fork without Sond commits
# has no patch: say so rather than writing an empty file.
export_patch() { # <name> <commit>
	local name=$1 commit=$2
	local dir=$SRC_ROOT/$name-sond
	local out=$PATCH_DIR/$name-sond.patch
	local count
	count=$(git -C "$dir" rev-list --count "$commit..sond")
	if [ "$count" -eq 0 ]; then
		printf 'no Sond commits on %s: no patch emitted\n' "$name"
		rm -f -- "$out"
	else
		git -C "$dir" format-patch "$commit..sond" --stdout >"$out"
		printf 'wrote %s (%s commit(s))\n' "$out" "$count"
	fi
}

pin_fork toybox "$TOYBOX_URL" "$TOYBOX_TAG" "$TOYBOX_COMMIT"
pin_fork mksh "$MKSH_URL" "$MKSH_TAG" "$MKSH_COMMIT"
pin_fork musl "$MUSL_URL" "$MUSL_TAG" "$MUSL_COMMIT"

export_patch toybox "$TOYBOX_COMMIT"
export_patch mksh "$MKSH_COMMIT"
export_patch musl "$MUSL_COMMIT"

printf 'build-forks: OK\n'
