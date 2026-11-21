"""The small subcommands build-action composes: object-id and needs-source."""

import os
import tempfile
import unittest

from sondpkg import canonical
from sondpkg.tests.helpers import base_args, make_payload_tree, run_cli


class ObjectIdTest(unittest.TestCase):
    def test_prints_the_canonical_object_id_of_a_bundle(self):
        with tempfile.TemporaryDirectory() as root:
            tree = make_payload_tree(os.path.join(root, "tree"))
            rc, out, err = run_cli(base_args(root, tree, os.path.join(root, "out")))
            self.assertEqual(rc, 0, err)
            bundle = out.strip()
            rc, out, err = run_cli(["object-id", bundle])
            self.assertEqual(rc, 0, err)
            self.assertEqual(out, canonical.object_id(bundle) + "\n")


class NeedsSourceTest(unittest.TestCase):
    def test_copyleft_in_the_licence_or_in_a_bundled_component_needs_the_source_lane(self):
        self.assertEqual(run_cli(["needs-source", "GPL-2.0-or-later AND GPL-2.0-only"])[0], 0)
        self.assertEqual(run_cli(["needs-source", "Apache-2.0", "--bundled", "lxc 6.0.5 LGPL-2.1-or-later"])[0], 0)
        self.assertEqual(run_cli(["needs-source", "MPL-2.0"])[0], 0)

    def test_a_permissive_package_does_not(self):
        rc, out, err = run_cli(["needs-source", "0BSD", "--bundled", "musl 1.2.5 MIT"])
        self.assertEqual(rc, 1, err)
        self.assertEqual(err, "")

    def test_a_malformed_expression_is_an_error_not_a_no(self):
        self.assertEqual(run_cli(["needs-source", "MIT AND"])[0], 2)


class LinuxHeaderNoticesTest(unittest.TestCase):
    def test_prints_the_used_headers_whose_notice_must_ship(self):
        with tempfile.TemporaryDirectory() as include:
            os.makedirs(os.path.join(include, "linux"))
            with open(os.path.join(include, "linux", "a.h"), "w") as h:
                h.write("/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */\n")
            with open(os.path.join(include, "linux", "b.h"), "w") as h:
                h.write("/* SPDX-License-Identifier: MIT */\n")
            rc, out, err = run_cli(["linux-header-notices", "--include", include, "linux/a.h", "linux/b.h"])
            self.assertEqual(rc, 0, err)
            self.assertEqual(out, "linux/b.h\n")
