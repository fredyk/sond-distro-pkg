"""The canonical object of a bundle: a deterministic ustar archive of the bundle directory."""

import hashlib
import io
import os
import tarfile
import tempfile
import time
import unittest

from sondpkg import canonical
from sondpkg.errors import PackagerError
from sondpkg.tests.helpers import write_bytes


def make_bundle(root):
    write_bytes(os.path.join(root, "MANIFEST"), b'package "demo" {\n}\n', 0o644)
    write_bytes(os.path.join(root, "payload", "bin", "demo"), b"binary\n", 0o755)
    write_bytes(os.path.join(root, "payload", "share", "doc.txt"), b"doc\n", 0o644)
    os.symlink("demo", os.path.join(root, "payload", "bin", "alias"))
    return root


class CanonicalObject(unittest.TestCase):
    def test_entries_are_sorted_bytewise_and_carry_no_host_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = canonical.canonical_object(make_bundle(tmp))
        self.assertEqual(len(data) % 512, 0)
        self.assertEqual(data[-1024:], b"\0" * 1024)
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            members = archive.getmembers()
        self.assertEqual(
            [m.name for m in members],
            [
                "MANIFEST",
                "payload/bin/alias",
                "payload/bin/demo",
                "payload/share/doc.txt",
            ],
        )
        by_name = {m.name: m for m in members}
        self.assertTrue(by_name["payload/bin/alias"].issym())
        self.assertEqual(by_name["payload/bin/alias"].linkname, "demo")
        self.assertEqual(by_name["payload/bin/demo"].mode, 0o755)
        self.assertEqual(by_name["payload/share/doc.txt"].mode, 0o644)
        self.assertEqual(by_name["MANIFEST"].mode, 0o644)
        for member in members:
            self.assertEqual((member.uid, member.gid, member.mtime), (0, 0, 0))
            self.assertEqual((member.uname, member.gname), ("", ""))

    def test_the_object_does_not_depend_on_mtimes_creation_order_or_umask(self):
        with tempfile.TemporaryDirectory() as one, tempfile.TemporaryDirectory() as two:
            make_bundle(one)
            # the same tree, built in another order with other timestamps
            os.makedirs(os.path.join(two, "payload", "share"))
            write_bytes(os.path.join(two, "payload", "share", "doc.txt"), b"doc\n", 0o600)
            write_bytes(os.path.join(two, "payload", "bin", "demo"), b"binary\n", 0o700)
            os.symlink("demo", os.path.join(two, "payload", "bin", "alias"))
            write_bytes(os.path.join(two, "MANIFEST"), b'package "demo" {\n}\n', 0o664)
            old = time.time() - 10**7
            for base, _, files in os.walk(two):
                for name in files:
                    path = os.path.join(base, name)
                    if not os.path.islink(path):
                        os.utime(path, (old, old))
            self.assertEqual(
                canonical.canonical_object(one), canonical.canonical_object(two)
            )

    def test_content_and_the_executable_bit_change_the_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            before = canonical.canonical_object(tmp)
            os.chmod(os.path.join(tmp, "payload", "share", "doc.txt"), 0o755)
            executable = canonical.canonical_object(tmp)
            write_bytes(os.path.join(tmp, "payload", "share", "doc.txt"), b"doc!\n", 0o755)
            changed = canonical.canonical_object(tmp)
        self.assertEqual(len({before, executable, changed}), 3)

    def test_object_id_is_the_sha256_of_the_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            data = canonical.canonical_object(tmp)
            self.assertEqual(
                canonical.object_id(tmp), "sha256:" + hashlib.sha256(data).hexdigest()
            )

    def test_a_long_path_uses_the_ustar_prefix_and_a_too_long_one_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            deep = os.path.join(tmp, "payload", "d" * 60, "e" * 60, "f.txt")
            write_bytes(deep, b"x", 0o644)
            data = canonical.canonical_object(tmp)
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                self.assertIn("payload/%s/%s/f.txt" % ("d" * 60, "e" * 60), archive.getnames())
        with tempfile.TemporaryDirectory() as tmp:
            write_bytes(os.path.join(tmp, *(["p" * 100] * 3)), b"x", 0o644)
            with self.assertRaises(PackagerError):
                canonical.canonical_object(tmp)

    def test_special_files_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.mkfifo(os.path.join(tmp, "pipe"))
            with self.assertRaises(PackagerError):
                canonical.canonical_object(tmp)

    def test_frozen_vector(self):
        # A fixed bundle must always hash to this id: it is the conformance vector in the docs.
        with tempfile.TemporaryDirectory() as tmp:
            make_bundle(tmp)
            self.assertEqual(canonical.object_id(tmp), FROZEN_ID)


FROZEN_ID = "sha256:c706da9c7352f1a315f321fde5c47b549593f7217a33fe58b3f4704b8fd8a313"

if __name__ == "__main__":
    unittest.main()
