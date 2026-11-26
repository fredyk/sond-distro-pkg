"""SPDX licence expressions are checked atom by atom, never as a whole string."""

import unittest

from sondpkg import spdx
from sondpkg.errors import PackagerError


class SpdxTest(unittest.TestCase):
    def test_atoms_of_compound_expressions(self):
        self.assertEqual(spdx.atoms("MIT"), {"MIT"})
        self.assertEqual(
            spdx.atoms("GPL-2.0-or-later AND GPL-2.0-only"),
            {"GPL-2.0-or-later", "GPL-2.0-only"},
        )
        self.assertEqual(
            spdx.atoms("(BSD-3-Clause OR GPL-2.0-only) AND LGPL-3.0-only WITH LGPL-3.0-linking-exception"),
            {"BSD-3-Clause", "GPL-2.0-only", "LGPL-3.0-only"},
        )
        self.assertEqual(
            spdx.exceptions("LGPL-3.0-only WITH LGPL-3.0-linking-exception AND MIT"),
            {"LGPL-3.0-linking-exception"},
        )

    def test_malformed_expressions_are_rejected(self):
        for bad in ("", "MIT AND", "AND MIT", "(MIT", "MIT)", "MIT OR OR 0BSD",
                    "MIT WITH", "MIT and 0BSD", "MIT, 0BSD", "WITH MIT"):
            with self.assertRaises(PackagerError, msg=bad):
                spdx.atoms(bad)

    def test_package_licence_atoms_must_be_allowed(self):
        spdx.check_license("GPL-2.0-or-later AND GPL-2.0-only")
        spdx.check_license("X11-distribute-modifications-variant")
        spdx.check_license("Apache-2.0 AND LGPL-2.1-or-later")
        with self.assertRaises(PackagerError) as ctx:
            spdx.check_license("GPL-2.0-only AND GPL-3.0-only")
        self.assertIn("GPL-3.0-only", str(ctx.exception))
        # bundled-only identifiers are not a package licence on their own
        with self.assertRaises(PackagerError):
            spdx.check_license("Unlicense")

    def test_linux_headers_licence_is_admitted(self):
        # the licence opinion, section 2.11 (1): the kernel UAPI headers' computed expression
        spdx.check_license(
            "GPL-2.0-only WITH Linux-syscall-note AND LGPL-2.1-only WITH Linux-syscall-note"
            " AND MIT AND BSD-3-Clause"
        )

    def test_mozillas_root_store_is_admitted_as_a_package_and_takes_the_source_lane(self):
        # ca-certificates ships Mozilla's root certificates (certdata.txt, MPL-2.0) as one PEM file.
        spdx.check_license("MPL-2.0")
        self.assertTrue(spdx.is_copyleft("MPL-2.0"))

    def test_rsync_is_admitted_as_a_package_and_takes_the_source_lane(self):
        # rsync (incusd receives dir volumes with it) is GPL-3.0-or-later, its COPYING the GPLv3.
        spdx.check_license("GPL-3.0-or-later")
        self.assertTrue(spdx.is_copyleft("GPL-3.0-or-later"))
        # only the "or later" grant is admitted: GPL-3.0-only stays out
        with self.assertRaises(PackagerError):
            spdx.check_license("GPL-3.0-only")

    def test_the_c_libraries_incusd_links_are_admitted_as_packages(self):
        # the licence opinion's incusd table: each library is published as a package of its own,
        # under the licence it carries when linked
        for expression in ("blessing", "MIT AND BSD-2-Clause AND ISC",
                           "LGPL-3.0-only WITH LGPL-3.0-linking-exception",
                           "LGPL-2.1-only", "LGPL-2.1-or-later", "BSD-3-Clause OR GPL-2.0-only"):
            spdx.check_license(expression)

    def test_bundled_licence_atoms_and_exceptions(self):
        spdx.check_bundled("LGPL-3.0-only WITH LGPL-3.0-linking-exception")
        spdx.check_bundled("BSD-3-Clause OR GPL-2.0-only")
        spdx.check_bundled("GPL-2.0-only WITH Linux-syscall-note")
        with self.assertRaises(PackagerError):
            spdx.check_bundled("MIT WITH Classpath-exception-2.0")
        with self.assertRaises(PackagerError):
            spdx.check_bundled("SSPL-1.0")

    def test_copyleft(self):
        self.assertTrue(spdx.is_copyleft("GPL-2.0-or-later AND GPL-2.0-only"))
        self.assertTrue(spdx.is_copyleft("Apache-2.0 AND LGPL-2.1-or-later"))
        self.assertTrue(spdx.is_copyleft("MPL-2.0"))
        self.assertFalse(spdx.is_copyleft("MIT"))
        self.assertFalse(spdx.is_copyleft("X11-distribute-modifications-variant"))
        self.assertFalse(spdx.is_copyleft("Apache-2.0"))


if __name__ == "__main__":
    unittest.main()
