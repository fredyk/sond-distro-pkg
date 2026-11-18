"""check-change-marks: every file the fork touches carries a dated mark.

Read-only: the fork worktree is never modified, only diffed against upstream.
"""

import os
import re
import subprocess
import sys

from sondpkg.errors import PackagerError

MARK = re.compile(rb"Sond change \d{4}-\d{2}-\d{2}:")
_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


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

    modified = []
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

    unmarked = []
    for relative in modified:
        full = os.path.join(fork, *relative.split("/"))
        if os.path.islink(full) or not os.path.isfile(full):
            unmarked.append(relative)
            continue
        if not MARK.search(_read(full)):
            unmarked.append(relative)

    for relative in deleted:
        print("deleted: " + relative)

    if unmarked:
        for relative in unmarked:
            print("missing change mark: " + relative, file=sys.stderr)
        raise PackagerError(
            'files modified without a "Sond change <YYYY-MM-DD>:" mark: '
            + ", ".join(unmarked)
        )
    return unmarked, deleted
