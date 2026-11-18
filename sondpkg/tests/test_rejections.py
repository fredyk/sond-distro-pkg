"""Every mechanical obligation is a rejection, not a promise in a README."""

import os
import tempfile
import unittest

from sondpkg.tests.helpers import (
    SHA_A,
    SHA_B,
    base_args,
    make_licence,
    make_payload_tree,
    run_cli,
    write_bytes,
)


class RejectionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.tree = make_payload_tree(os.path.join(self.root, "tree"))
        self.out = os.path.join(self.root, "out")

    def tearDown(self):
        self.tmp.cleanup()

    def reject(self, argv, needle):
        rc, _, err = run_cli(argv)
        self.assertNotEqual(rc, 0, "expected a rejection, got rc=0")
        self.assertIn(needle, err)
        return err

    def test_reject_musl_linkage_without_musl_copyright(self):
        licence = make_licence(self.root, "LICENSE", "0BSD text\n")
        argv = base_args(self.root, self.tree, self.out, license_files=[licence])
        self.reject(argv, "musl-COPYRIGHT")

    def test_reject_mksh_without_miros_licence(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        unicode_notice = make_licence(self.root, "UNICODE-NOTICE", "Unicode text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            name="mksh-static",
            license="MirOS",
            license_files=[musl, unicode_notice],
        )
        self.reject(argv, "LICENCE-MirOS.txt")

    def test_reject_mksh_without_unicode_notice(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        miros = make_licence(self.root, "LICENCE-MirOS.txt", "MirOS text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            name="mksh-static",
            license="MirOS",
            license_files=[musl, miros],
        )
        self.reject(argv, "UNICODE-NOTICE")

    def test_reject_non_public_tier(self):
        argv = base_args(self.root, self.tree, self.out, tier="staging")
        self.reject(argv, "tier")

    def test_reject_unknown_spdx_license(self):
        argv = base_args(self.root, self.tree, self.out, license="GPL-3.0-only")
        self.reject(argv, "license")

    def test_reject_empty_license(self):
        argv = base_args(self.root, self.tree, self.out, license="")
        self.reject(argv, "license")

    def test_reject_source_without_commit(self):
        argv = base_args(
            self.root, self.tree, self.out, source="github.com/fredyk/toybox-sond"
        )
        self.reject(argv, "source")

    def test_reject_upstream_with_short_commit(self):
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            upstream="github.com/landley/toybox@" + "b" * 39,
        )
        self.reject(argv, "upstream")

    def test_reject_missing_tree(self):
        argv = base_args(
            self.root, os.path.join(self.root, "does-not-exist"), self.out
        )
        self.reject(argv, "tree")

    def test_reject_empty_tree(self):
        empty = os.path.join(self.root, "empty-tree")
        os.makedirs(empty)
        argv = base_args(self.root, empty, self.out)
        self.reject(argv, "tree")

    def test_reject_license_destination_outside_package(self):
        licence = make_licence(self.root, "LICENSE", "0BSD text\n")
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            license_files=[
                licence + "=share/licenses/toybox-static/../../escape",
                musl + "=share/licenses/toybox-static/musl-COPYRIGHT",
            ],
        )
        self.reject(argv, "destination")

    def test_reject_missing_source_file(self):
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            source_files=[os.path.join(self.root, "not-there.tar.gz")],
        )
        self.reject(argv, "source file")

    def test_reject_empty_linkage(self):
        argv = base_args(self.root, self.tree, self.out, linkage="")
        self.reject(argv, "linkage")

    def test_build_mksh_static_with_all_obligations_succeeds(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        miros = make_licence(self.root, "LICENCE-MirOS.txt", "MirOS text\n")
        unicode_notice = make_licence(self.root, "UNICODE-NOTICE", "Unicode text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            name="mksh-static",
            license="MirOS",
            license_files=[musl, miros, unicode_notice],
        )
        rc, out, err = run_cli(argv)
        self.assertEqual(rc, 0, err)
        self.assertTrue(os.path.isdir(out.strip()))


if __name__ == "__main__":
    unittest.main()
