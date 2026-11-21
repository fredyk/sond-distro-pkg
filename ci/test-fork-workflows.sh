#!/bin/bash
# Static checks on the GitHub workflow each fork carries on its "sond" branch:
# it builds with fredyk/sond-build-action@v1, publishes with
# fredyk/sond-publish-action@v1, and names the version and upstream commit
# pinned in toolchain/common.sh.
#
# usage: ci/test-fork-workflows.sh

set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../toolchain/common.sh"

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

check() { # <fork> <package> <version> <upstream> [copyleft|marked]
	local name=$1 package=$2 version=$3 upstream=$4 copyleft=${5:-}
	local wf=$here/forks/$name-sond.yml
	[ -f "$wf" ] || { bad "$name: $wf exists"; return; }
	python3 - "$wf" "$name" "$package" "$version" "$upstream" "$copyleft" <<'PY' || fails=$((fails + 1))
import re, sys
path, name, package, version, upstream, copyleft = sys.argv[1:]
text = open(path).read()
fails = 0
def check(cond, what):
    global fails
    print(("ok   " if cond else "FAIL ") + f"{name}: {what}")
    fails += 0 if cond else 1
# Under jobs: every line is indented; one at column 0 ends the block scalar it sits in and the
# rest of the build command is silently lost.
body = text.split("\njobs:\n", 1)[1] if "\njobs:\n" in text else ""
check(body and all(not l or l[0] == " " for l in body.split("\n")),
      "every line under jobs: is indented")
check(re.search(r"^on:\n(  .*\n)*  push:\n    branches: \[sond\]\n", text, re.M) is not None, "runs on a push to sond")
check(re.search(r"^  workflow_dispatch:", text, re.M) is not None, "can be run by hand")
check(re.search(r"^permissions:\n  contents: read\n", text, re.M) is not None, "the token can only read")
check(re.search(r"uses: actions/checkout@v4\n\s+with:\n\s+fetch-depth: 0\n", text) is not None, "full clone of the fork")
check(re.search(r"^\s+- id: build\n\s+uses: fredyk/sond-build-action@v1\n", text, re.M) is not None, "builds with sond-build-action@v1")
check(f"name: {package}\n" in text, f"package {package}")
check(f"version: {version}\n" in text, f"version {version}")
check(f"upstream: {upstream}\n" in text, f"upstream {upstream}")
check(re.search(r"uses: fredyk/sond-publish-action@v1\n\s+with:\n\s+bundle: \$\{\{ steps.build.outputs.bundle \}\}\n"
                r"(\s+source-bundle: \$\{\{ steps.build.outputs.source_bundle \}\}\n)?"
                r"\s+token: \$\{\{ secrets.SOND_PUBLISH_TOKEN \}\}\n"
                r"\s+signing-key: \$\{\{ secrets.SOND_SIGNING_KEY \}\}\n", text) is not None,
      "publishes the bundle with the repository secrets")
check("secrets." not in text.split("sond-publish-action@v1", 1)[0], "no secret reaches the build step")
if copyleft == "copyleft":
    # the licence opinion: the corresponding source goes out first
    check(re.search(r"\n\s+source-bundle: \$\{\{ steps.build.outputs.source_bundle \}\}\n", text) is not None,
          "publishes the corresponding source first")
if copyleft:
    # copyleft or Apache-2.0 (4(b)): the workflow file the fork adds carries the change notice
    # like every other file it touches
    check(re.search(r"Modified by the Sond project, \d{4}-\d{2}-\d{2}", text) is not None,
          "carries the change notice")
sys.exit(1 if fails else 0)
PY
}

check toybox toybox-static "$TOYBOX_TAG" "github.com/landley/toybox@$TOYBOX_COMMIT"
check mksh mksh-static "${MKSH_TAG#mksh-}" "github.com/MirBSD/mksh@$MKSH_COMMIT"
check musl musl "${MUSL_TAG#v}" "git.musl-libc.org/git/musl@$MUSL_COMMIT"
check ncurses ncurses "$NCURSES_VERSION" "github.com/ThomasDickey/ncurses-snapshots@$NCURSES_COMMIT"
check linux-headers linux-headers "${LINUX_HEADERS_TAG#v}" "github.com/sabotage-linux/kernel-headers@$LINUX_HEADERS_COMMIT" copyleft
check htop htop "$HTOP_VERSION" "github.com/htop-dev/htop@$HTOP_COMMIT" copyleft
check incus incus "$INCUS_VERSION" "github.com/lxc/incus@$INCUS_COMMIT" marked
check incusd incusd "$INCUS_VERSION" "github.com/lxc/incus@$INCUS_COMMIT" copyleft
check libudev-zero libudev-zero "$LIBUDEV_ZERO_TAG" "github.com/illiliti/libudev-zero@$LIBUDEV_ZERO_COMMIT"
check libuv libuv "${LIBUV_TAG#v}" "github.com/libuv/libuv@$LIBUV_COMMIT"
check sqlite sqlite "${SQLITE_TAG#version-}" "github.com/sqlite/sqlite@$SQLITE_COMMIT"
check raft raft "${RAFT_TAG#v}" "github.com/cowsql/raft@$RAFT_COMMIT" copyleft
check cowsql cowsql "${COWSQL_TAG#v}" "github.com/cowsql/cowsql@$COWSQL_COMMIT" copyleft
check attr attr "${ATTR_TAG#v}" "git.savannah.gnu.org/r/attr@$ATTR_COMMIT" copyleft
check libcap libcap "${LIBCAP_TAG#v}" "git.kernel.org/pub/scm/libs/libcap/libcap@$LIBCAP_COMMIT"
check acl acl "${ACL_TAG#v}" "git.savannah.gnu.org/r/acl@$ACL_COMMIT" copyleft
check libseccomp libseccomp "${LIBSECCOMP_TAG#v}" "github.com/seccomp/libseccomp@$LIBSECCOMP_COMMIT" copyleft
check lxc lxc "${LXC_TAG#v}" "github.com/lxc/lxc@$LXC_COMMIT" copyleft

if [ "$fails" -eq 0 ]; then
	printf 'test-fork-workflows: OK\n'
else
	printf 'test-fork-workflows: FAIL\n'
	exit 1
fi
