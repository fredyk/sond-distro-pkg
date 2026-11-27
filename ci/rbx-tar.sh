#!/bin/sh
# POSIX entry point for the Roubaix gate, which runs the script with sh (dash) and ignores the
# shebang: the shape checks below are bash-only and use ${BASH_SOURCE[0]}. Install what they and
# the repo's python suite need, run the suite, then hand over to the fork test.
# usage: sh ./ci/rbx-tar.sh
set -e
cd "$(dirname "$0")/.."
missing=
for tool in python3 bash git; do
	command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
	apt-get update -qq
	apt-get install -y -qq $missing >/dev/null
fi
python3 -m unittest discover -s sondpkg/tests -v || exit 1
exec bash ./ci/test-tar-fork.sh "$@"
