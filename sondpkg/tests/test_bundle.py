"""Tests for build-bundle, verify-bundle and show."""

import os
import tempfile
import unittest

from sondpkg import canon
from sondpkg.manifest import parse
from sondpkg.tests.helpers import (
    base_args,
    make_licence,
    make_payload_tree,
    run_cli,
    sha256_file,
    write_bytes,
)


def build_ok(testcase, argv):
    rc, out, err = run_cli(argv)
    testcase.assertEqual(rc, 0, err)
    return out.strip()


def bundle_dirs(out):
    return sorted(
        os.path.join(out, name)
        for name in os.listdir(out)
        if os.path.isdir(os.path.join(out, name))
    )


class BuildBundleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.tree = make_payload_tree(os.path.join(self.root, "tree"))
        self.out = os.path.join(self.root, "out")

    def tearDown(self):
        self.tmp.cleanup()

    def test_build_bundle_creates_payload_and_manifest(self):
        argv = base_args(self.root, self.tree, self.out)
        bundle = build_ok(self, argv)
        self.assertTrue(os.path.isdir(bundle))
        self.assertTrue(os.path.isfile(os.path.join(bundle, "payload", "bin", "toybox")))
        self.assertTrue(os.access(os.path.join(bundle, "payload", "bin", "toybox"), os.X_OK))
        link = os.path.join(bundle, "payload", "bin", "ls")
        self.assertTrue(os.path.islink(link))
        self.assertEqual(os.readlink(link), "toybox")

        text = open(os.path.join(bundle, "MANIFEST"), encoding="utf-8").read()
        manifest = parse(text)[0]
        self.assertEqual(manifest.name, "toybox-static")
        self.assertEqual(manifest.version, "0.8.15")
        self.assertEqual(manifest.license, "0BSD")
        self.assertEqual(manifest.tier, "public")
        self.assertEqual(manifest.linkage, "static musl 1.2.5 (MIT)")
        payload = os.path.join(bundle, "payload")
        self.assertEqual(manifest.files, len(canon.scan(payload)))
        self.assertEqual(manifest.bundle, "sha256:" + canon.hash_tree(payload))
        self.assertNotIn(self.root, text)

    def test_bundle_dir_name_carries_hash_prefix(self):
        bundle = build_ok(self, base_args(self.root, self.tree, self.out))
        digest = canon.hash_tree(os.path.join(bundle, "payload"))
        self.assertTrue(os.path.basename(bundle).endswith("-" + digest[:12]))
        self.assertTrue(os.path.basename(bundle).startswith("toybox-static-0.8.15-"))

    def test_license_file_copied_into_payload_and_listed(self):
        licence = make_licence(self.root, "CUSTOM-NOTICE", "custom notice\n")
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        argv = base_args(
            self.root, self.tree, self.out, license_files=[licence, musl]
        )
        bundle = build_ok(self, argv)
        inside = os.path.join(
            bundle, "payload", "share", "licenses", "toybox-static", "CUSTOM-NOTICE"
        )
        self.assertTrue(os.path.isfile(inside))
        self.assertEqual(open(inside, encoding="utf-8").read(), "custom notice\n")
        manifest = parse(open(os.path.join(bundle, "MANIFEST"), encoding="utf-8").read())[0]
        self.assertEqual(
            manifest.licences,
            [
                "share/licenses/toybox-static/CUSTOM-NOTICE",
                "share/licenses/toybox-static/musl-COPYRIGHT",
            ],
        )

    def test_license_file_honours_explicit_destination(self):
        licence = make_licence(self.root, "LICENSE", "0BSD text\n")
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            license_files=[
                licence + "=share/licenses/toybox-static/LICENSE",
                musl + "=share/licenses/toybox-static/musl-COPYRIGHT",
            ],
        )
        bundle = build_ok(self, argv)
        manifest = parse(open(os.path.join(bundle, "MANIFEST"), encoding="utf-8").read())[0]
        self.assertEqual(
            manifest.licences,
            [
                "share/licenses/toybox-static/LICENSE",
                "share/licenses/toybox-static/musl-COPYRIGHT",
            ],
        )

    def test_source_files_listed_with_sha256(self):
        tarball = os.path.join(self.root, "toybox-0.8.15.tar.xz")
        write_bytes(tarball, b"tarball bytes")
        recipe = os.path.join(self.root, "build-recipe.sh")
        write_bytes(recipe, b"#!/bin/sh\nmake\n")
        argv = base_args(
            self.root, self.tree, self.out, source_files=[tarball, recipe]
        )
        bundle = build_ok(self, argv)
        manifest = parse(open(os.path.join(bundle, "MANIFEST"), encoding="utf-8").read())[0]
        self.assertEqual(
            manifest.sources,
            [
                "sha256:" + sha256_file(tarball) + " toybox-0.8.15.tar.xz",
                "sha256:" + sha256_file(recipe) + " build-recipe.sh",
            ],
        )

    def test_build_rejects_existing_bundle(self):
        argv = base_args(self.root, self.tree, self.out)
        build_ok(self, argv)
        rc, _, err = run_cli(argv)
        self.assertNotEqual(rc, 0)
        self.assertIn("already exists", err)
        self.assertEqual(len(bundle_dirs(self.out)), 1)


class VerifyAndShowTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.tree = make_payload_tree(os.path.join(self.root, "tree"))
        self.out = os.path.join(self.root, "out")
        self.bundle = build_ok(self, base_args(self.root, self.tree, self.out))

    def tearDown(self):
        self.tmp.cleanup()

    def test_verify_bundle_ok(self):
        rc, out, err = run_cli(["verify-bundle", self.bundle])
        self.assertEqual(rc, 0, err)
        self.assertIn("ok", out)

    def test_verify_bundle_detects_tampered_payload(self):
        target = os.path.join(self.bundle, "payload", "bin", "toybox")
        with open(target, "ab") as handle:
            handle.write(b"x")
        rc, _, err = run_cli(["verify-bundle", self.bundle])
        self.assertNotEqual(rc, 0)
        self.assertIn("hash", err.lower())

    def test_show_prints_manifest_as_key_value(self):
        rc, out, err = run_cli(["show", self.bundle])
        self.assertEqual(rc, 0, err)
        self.assertIn("name = toybox-static", out)
        self.assertIn("version = 0.8.15", out)
        self.assertIn("license = 0BSD", out)
        self.assertIn("tier = public", out)
        self.assertIn("files = ", out)
        self.assertIn("bundle = sha256:", out)
        self.assertIn("licences = share/licenses/toybox-static/", out)


if __name__ == "__main__":
    unittest.main()
