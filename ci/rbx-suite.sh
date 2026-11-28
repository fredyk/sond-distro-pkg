#!/bin/sh
# Roubaix gate wrapper (rbx-sh-test, python:3.12 or debian:trixie): the repo's whole offline suite,
# the sondpkg unittests and every ci/test-*.sh shape check. The gate runs this with dash and the
# shape checks are bash, so it stays POSIX and hands each one to bash.
# ci/test-fork-builds.sh builds the forks through a sond-build-action checkout the gate does not
# ship: without SOND_BUILD_ACTION it must refuse, and that refusal is what is checked here.
# usage: sh ./ci/rbx-suite.sh
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
rc=0
if out=$(python3 -m unittest discover -s sondpkg/tests 2>&1); then
	echo "PASS sondpkg unittests: $(printf '%s\n' "$out" | grep -E '^Ran ')"
else
	echo "FAIL sondpkg unittests"; printf '%s\n' "$out" | tail -40; rc=1
fi
for t in ci/test-*.sh; do
	n=$(basename "$t" .sh)
	if [ "$n" = test-fork-builds ]; then
		if out=$(env -u SOND_BUILD_ACTION bash "$t" 2>&1); then
			echo "FAIL $n: ran without SOND_BUILD_ACTION"; rc=1
		elif printf '%s\n' "$out" | grep -q 'SOND_BUILD_ACTION'; then
			echo "SKIP $n: needs SOND_BUILD_ACTION, a sond-build-action checkout (refused as expected)"
		else
			echo "FAIL $n: refused for another reason"; printf '%s\n' "$out" | tail -10; rc=1
		fi
		continue
	fi
	if out=$(bash "$t" 2>&1); then
		echo "PASS $n"
	else
		echo "FAIL $n"; printf '%s\n' "$out" | grep -vE '^ok ' | tail -20; rc=1
	fi
done
[ $rc -eq 0 ] && echo "suite: OK" || echo "suite: RED"
exit $rc
