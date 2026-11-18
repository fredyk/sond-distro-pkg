"""Tests for check-change-marks: the fork's per-file dated mark obligation."""

import os
import subprocess
import tempfile
import unittest

from sondpkg.tests.helpers import run_cli, write_bytes

ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_SYSTEM": "/dev/null",
    "GIT_AUTHOR_NAME": "test",
    "GIT_AUTHOR_EMAIL": "test@example.invalid",
    "GIT_COMMITTER_NAME": "test",
    "GIT_COMMITTER_EMAIL": "test@example.invalid",
    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
}


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True,
        text=True,
        env=ENV,
    )
    if result.returncode != 0:
        raise AssertionError("git %s failed: %s" % (args, result.stderr))
    return result.stdout


def make_fork(root):
    repo = os.path.join(root, "fork")
    os.makedirs(repo)
    git(repo, "init", "-q")
    write_bytes(os.path.join(repo, "good.c"), b"int a;\n")
    write_bytes(os.path.join(repo, "bad.c"), b"int b;\n")
    write_bytes(os.path.join(repo, "gone.c"), b"int c;\n")
    git(repo, "add", ".")
    git(repo, "commit", "-q", "-m", "upstream")
    return repo, git(repo, "rev-parse", "HEAD").strip()


class ChangeMarkTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.repo, self.commit = make_fork(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def test_unmarked_modification_fails_naming_only_it(self):
        write_bytes(
            os.path.join(self.repo, "good.c"),
            b"/* Sond change 2026-11-18: tweak - fredyk/x-sond */\nint a;\n",
        )
        write_bytes(os.path.join(self.repo, "bad.c"), b"int b = 2;\n")
        rc, _, err = run_cli(["check-change-marks", self.repo, self.commit])
        self.assertNotEqual(rc, 0)
        self.assertIn("bad.c", err)
        self.assertNotIn("good.c", err)

    def test_all_marked_passes(self):
        write_bytes(
            os.path.join(self.repo, "good.c"),
            b"/* Sond change 2026-11-18: tweak - fredyk/x-sond */\nint a;\n",
        )
        write_bytes(
            os.path.join(self.repo, "bad.c"),
            b"# Sond change 2026-11-19: fix - fredyk/x-sond\nint b = 2;\n",
        )
        rc, _, err = run_cli(["check-change-marks", self.repo, self.commit])
        self.assertEqual(rc, 0, err)

    def test_deleted_file_is_reported_but_not_a_failure(self):
        os.remove(os.path.join(self.repo, "gone.c"))
        rc, out, err = run_cli(["check-change-marks", self.repo, self.commit])
        self.assertEqual(rc, 0, err)
        self.assertIn("gone.c", out + err)

    def test_added_file_requires_a_mark(self):
        write_bytes(os.path.join(self.repo, "new.c"), b"int n;\n")
        git(self.repo, "add", "-N", "new.c")
        rc, _, err = run_cli(["check-change-marks", self.repo, self.commit])
        self.assertNotEqual(rc, 0)
        self.assertIn("new.c", err)

    def test_bad_commit_argument_is_rejected(self):
        rc, _, err = run_cli(["check-change-marks", self.repo, "not-a-sha"])
        self.assertNotEqual(rc, 0)
        self.assertIn("commit", err)


if __name__ == "__main__":
    unittest.main()
