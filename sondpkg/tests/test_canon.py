"""Tests for the canonical content hash (canon.snd rule).

The frozen conformance vector is the first test on purpose: it is the only
thing that ties this implementation to the authoritative rule on disk.
"""

import os
import tempfile
import unittest

from sondpkg import canon
from sondpkg.tests.helpers import run_cli

VECTOR = "923345ba8a4816339aeac609bef11aaa7dd88d46459bf8886ed8cc68833b3a8d"


def write_tree(root, files):
    """Create every relative path in ``files`` under ``root`` with its bytes."""
    for rel, content in files.items():
        path = os.path.join(root, *rel.split("/"))
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(content)


def scan_tree(root):
    """Materialise canon.scan into a dict for assertions."""
    return dict(canon.scan(root))


class FrozenVectorTest(unittest.TestCase):
    def test_frozen_conformance_vector(self):
        files = {
            "a\u00f1o.snd": "fn a\u00f1adir() -> i64 { 42 }\n".encode("utf-8"),
            "sub/ni\u00f1o.snd": "fn ni\u00f1o() -> i64 { 7 }\n".encode("utf-8"),
        }
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, files)
            digest = canon.hash_tree(tmp)
        self.assertEqual(digest, VECTOR)


class HashTreeCliTest(unittest.TestCase):
    def test_hash_tree_cli_prints_the_frozen_vector(self):
        files = {
            "a\u00f1o.snd": "fn a\u00f1adir() -> i64 { 42 }\n".encode("utf-8"),
            "sub/ni\u00f1o.snd": "fn ni\u00f1o() -> i64 { 7 }\n".encode("utf-8"),
        }
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, files)
            rc, out, err = run_cli(["hash-tree", tmp])
        self.assertEqual(rc, 0, err)
        self.assertEqual(out.strip(), VECTOR)


class OrderingTest(unittest.TestCase):
    def test_bytewise_order_ascii_before_accented(self):
        # A path over 0x80 sorts after plain ASCII, whatever the locale says.
        files = {
            name: name.encode("utf-8")
            for name in ["z", "\u00e9", "a", "a\u00f1adir", "A", "Z"]
        }
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, files)
            paths = [path for path, _ in canon.scan(tmp)]
        self.assertEqual(paths, ["A", "Z", "a", "a\u00f1adir", "z", "\u00e9"])

    def test_nested_paths_sort_by_full_relative_path(self):
        files = {
            "b/x": b"1",
            "a/z": b"2",
            "a/y": b"3",
            "c": b"4",
        }
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, files)
            paths = [path for path, _ in canon.scan(tmp)]
        self.assertEqual(paths, ["a/y", "a/z", "b/x", "c"])


class ContentTest(unittest.TestCase):
    def test_symlink_contributes_its_target_string(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"target.txt": b"data\n"})
            os.symlink("target.txt", os.path.join(tmp, "link"))
            entries = scan_tree(tmp)
        self.assertEqual(entries["link"], b"target.txt")
        self.assertEqual(entries["target.txt"], b"data\n")

    def test_empty_file_is_hashed_with_zero_length(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"empty": b""})
            digest_with = canon.hash_tree(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            digest_without = canon.hash_tree(tmp)
        self.assertNotEqual(digest_with, digest_without)
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"empty": b""})
            self.assertEqual(scan_tree(tmp)["empty"], b"")

    def test_content_is_not_newline_normalised(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"f": b"a\r\nb"})
            crlf = canon.hash_tree(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, {"f": b"a\nb"})
            lf = canon.hash_tree(tmp)
        self.assertNotEqual(crlf, lf)

    def test_creation_order_does_not_matter(self):
        files = {"b": b"B", "a/c": b"C", "a/d": b"D", "e": b"E"}
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, files)
            first = canon.hash_tree(tmp)
        reversed_files = dict(reversed(list(files.items())))
        with tempfile.TemporaryDirectory() as tmp:
            write_tree(tmp, reversed_files)
            second = canon.hash_tree(tmp)
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
