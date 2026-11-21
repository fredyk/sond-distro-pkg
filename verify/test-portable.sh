#!/bin/bash
# The repo runs from any checkout (a GitHub Action's included): no script names
# a home directory or another worktree of this repo; each finds its siblings
# from its own location.
#
# usage: test-portable.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
hits=$(git ls-files -co --exclude-standard -- '*.sh' '*.py' | grep -v '^verify/test-portable.sh$' | xargs grep -nE '/home/|sond-distro-pkg[.]oc-' 2>/dev/null)
if [ -n "$hits" ]; then
	printf 'FAIL scripts name a home directory or another worktree:\n%s\n' "$hits"
	exit 1
fi
printf 'ok   no script names a home directory or another worktree\n'
