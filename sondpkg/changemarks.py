"""check-change-marks: every file the fork touches carries a dated mark.

The mark is the notice GPL-2.0 2(a), GPL-3.0 5(a) and Apache-2.0 4(b) ask for, worded as the
licence opinion fixes it (dictamen-licencias-paquetes-distro-sond.md, section 3, step 6):
"Modified by the Sond project, YYYY-MM-DD". The upstream must be a commit, never a tag object.
An added file that is an official licence text, byte for byte, carries no mark (the GPL forbids
changing its text): it is recognised by its sha256 in LICENCE_TEXTS (rule 6 of section 3.1).

Read-only: the fork worktree is never modified, only diffed against upstream.
"""

import hashlib
import os
import re
import subprocess
import sys

from sondpkg.errors import PackagerError

MARK = re.compile(rb"Modified by the Sond project, \d{4}-\d{2}-\d{2}")
_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")

# sha256 of each official licence text a fork may add unchanged, and where it comes from.
_KERNEL = "git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v6.12.77 "
LICENCE_TEXTS = {
    "fb5a425bd3b3cd6071a3a9aff9909a859e7c1158d54d32e07658398cd67eb6a0": _KERNEL + "COPYING",
    "f6b78c087c3ebdf0f3c13415070dd480a3f35d8fc76f3d02180a407c1c812f79": _KERNEL + "LICENSES/preferred/GPL-2.0",
    "8e378ab93586eb55135d3bc119cce787f7324f48394777d00c34fa3d0be3303f": _KERNEL + "LICENSES/exceptions/Linux-syscall-note",
    "efbaee946ac92a48b89eae36f655844042370d2f0e04eadea1e2998efae24ebd": _KERNEL + "LICENSES/preferred/LGPL-2.1",
    "323c587d0ccf10e376f8bf9a7f31fb4ca6078105194b42e0b1e0ee2bc9bde71f": _KERNEL + "LICENSES/preferred/MIT",
    "7a83b1aeb460458db9a4bd521d7f237c45b1650f6e60ea5ffc71e49472454de3": _KERNEL + "LICENSES/preferred/BSD-3-Clause",
    "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986": "https://www.gnu.org/licenses/gpl-3.0.txt",
    "e3a994d82e644b03a792a930f574002658412f62407f5fee083f2555c5f23118": "https://www.gnu.org/licenses/lgpl-3.0.txt",
}


def _diff(fork, commit):
    result = subprocess.run(
        ["git", "-C", fork, "diff", "--name-status", commit, "--", "."],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise PackagerError(
            "git diff failed in %s: %s" % (fork, result.stderr.strip())
        )
    return result.stdout


def _read(path):
    with open(path, "rb") as handle:
        return handle.read()


def check_change_marks(fork, commit):
    """Return the lists ``(unmarked, deleted)`` or raise on unmarked files."""
    fork = os.path.abspath(fork)
    if not os.path.isdir(fork):
        raise PackagerError("fork worktree does not exist: " + fork)
    if not _COMMIT_RE.match(commit or ""):
        raise PackagerError(
            "upstream commit must be a 40-hex sha, got: %r" % commit
        )

    kind = subprocess.run(
        ["git", "-C", fork, "cat-file", "-t", commit], capture_output=True, text=True
    ).stdout.strip()
    if kind != "commit":
        raise PackagerError(
            "upstream %s is not a commit in %s (git cat-file -t: %s)" % (commit, fork, kind or "missing")
        )

    modified = []
    added = set()
    deleted = []
    for line in _diff(fork, commit).splitlines():
        fields = line.split("\t")
        if len(fields) < 2:
            continue
        status = fields[0]
        if status[0] == "D":
            deleted.append(fields[1])
        elif status[0] == "R":
            modified.append(fields[2] if len(fields) >= 3 else fields[1])
        else:
            modified.append(fields[-1])
            if status[0] == "A":
                added.add(fields[-1])

    unmarked = []
    for relative in modified:
        full = os.path.join(fork, *relative.split("/"))
        if os.path.islink(full) or not os.path.isfile(full):
            unmarked.append(relative)
            continue
        data = _read(full)
        if relative in added and hashlib.sha256(data).hexdigest() in LICENCE_TEXTS:
            continue
        if not MARK.search(data):
            unmarked.append(relative)

    for relative in deleted:
        print("deleted: " + relative)

    if unmarked:
        for relative in unmarked:
            print("missing change mark: " + relative, file=sys.stderr)
        raise PackagerError(
            'files modified without a "Modified by the Sond project, <YYYY-MM-DD>" mark: '
            + ", ".join(unmarked)
        )
    return unmarked, deleted
