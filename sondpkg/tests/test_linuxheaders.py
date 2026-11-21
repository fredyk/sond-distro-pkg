"""linux-headers: the package licence is computed from the installed headers' SPDX tags."""

import os
import tempfile
import unittest

from sondpkg import linuxheaders, rules
from sondpkg.errors import PackagerError
from sondpkg.tests.helpers import write_bytes

EXPECTED = (
    "GPL-2.0-only WITH Linux-syscall-note AND LGPL-2.1-only WITH Linux-syscall-note"
    " AND MIT AND BSD-3-Clause"
)
KERNEL_TEXTS = (
    "COPYING",
    "LICENSES/preferred/GPL-2.0",
    "LICENSES/exceptions/Linux-syscall-note",
    "LICENSES/preferred/LGPL-2.1",
    "LICENSES/preferred/MIT",
    "LICENSES/preferred/BSD-3-Clause",
)


def header(tag):
    return ("/* SPDX-License-Identifier: %s */\n#define X 1\n" % tag).encode()


class ComputedLicenceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.payload = self.tmp.name
        self.include = os.path.join(self.payload, "include")

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, relative, data):
        write_bytes(os.path.join(self.include, *relative.split("/")), data)

    def full_tree(self):
        # one header per kind of tag the opinion's table lists (section 2.11)
        self.put("linux/a.h", header("GPL-2.0 WITH Linux-syscall-note"))
        self.put("linux/b.h", header("GPL-2.0+ WITH Linux-syscall-note"))
        self.put("linux/c.h", header("GPL-1.0+ WITH Linux-syscall-note"))
        self.put("linux/d.h", header("((GPL-2.0 WITH Linux-syscall-note) OR BSD-2-Clause)"))
        self.put("linux/e.h", header("((GPL-2.0 WITH Linux-syscall-note) OR Linux-OpenIB)"))
        self.put("linux/f.h", header("((GPL-2.0 WITH Linux-syscall-note) OR CDDL-1.0)"))
        self.put("linux/g.h", header("LGPL-2.1+ WITH Linux-syscall-note"))
        self.put("linux/h.h", header("LGPL-2.0+ WITH Linux-syscall-note"))
        self.put("linux/i.h", header("MIT"))
        self.put("linux/j.h", header("BSD-3-Clause"))
        self.put("sound/k.h", header("(GPL-2.0 WITH Linux-syscall-note) AND MIT"))
        self.put("asm/unistd_64.h", b"#define __NR_read 0\n")  # unlabelled, in the reviewed table

    def test_the_opinions_choices_give_the_expected_expression(self):
        self.full_tree()
        self.assertEqual(linuxheaders.computed_license(self.include), EXPECTED)

    def test_or_takes_the_gpl_branch(self):
        self.put("linux/d.h", header("((GPL-2.0 WITH Linux-syscall-note) OR BSD-2-Clause)"))
        self.assertEqual(
            linuxheaders.computed_license(self.include), "GPL-2.0-only WITH Linux-syscall-note"
        )

    def test_unlabelled_header_outside_the_table_is_refused(self):
        self.put("linux/new_in_6_13.h", b"#define Y 2\n")
        with self.assertRaises(PackagerError) as ctx:
            linuxheaders.computed_license(self.include)
        self.assertIn("linux/new_in_6_13.h", str(ctx.exception))

    def test_unknown_identifier_is_refused(self):
        self.put("linux/x.h", header("GPL-3.0-only"))
        with self.assertRaises(PackagerError):
            linuxheaders.computed_license(self.include)

    def test_the_reviewed_table_has_the_87_unlabelled_headers(self):
        self.assertEqual(len(linuxheaders.UNLABELLED), 87)
        self.assertEqual(set(linuxheaders.UNLABELLED.values()), {"copying", "permissive"})
        self.assertEqual(linuxheaders.UNLABELLED["linux/aio_abi.h"], "copying")  # GPLv2 or other terms
        self.assertEqual(linuxheaders.UNLABELLED["linux/quota.h"], "permissive")

    def test_payload_check_refuses_a_licence_field_that_differs(self):
        self.full_tree()
        for relative in KERNEL_TEXTS:
            write_bytes(os.path.join(self.payload, "share/licenses/linux-headers", relative), b"t\n")
        rules.check_payload("linux-headers", "none (headers)", self.payload, EXPECTED, [])
        with self.assertRaises(PackagerError) as ctx:
            rules.check_payload(
                "linux-headers", "none (headers)", self.payload,
                "GPL-2.0-only WITH Linux-syscall-note", [],
            )
        self.assertIn(EXPECTED, str(ctx.exception))

    def test_payload_check_requires_the_six_kernel_texts(self):
        self.full_tree()
        for relative in KERNEL_TEXTS[:-1]:
            write_bytes(os.path.join(self.payload, "share/licenses/linux-headers", relative), b"t\n")
        with self.assertRaises(PackagerError) as ctx:
            rules.check_payload("linux-headers", "none (headers)", self.payload, EXPECTED, [])
        self.assertIn("LICENSES/preferred/BSD-3-Clause", str(ctx.exception))


class NoticeTest(unittest.TestCase):
    """Rule 10: a binary that includes a permissive-only kernel header carries its notice."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.include = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, relative, data):
        write_bytes(os.path.join(self.include, *relative.split("/")), data)

    def test_which_used_headers_need_their_notice(self):
        self.put("linux/capability.h", header("GPL-2.0 WITH Linux-syscall-note"))
        self.put("linux/either.h", header("(GPL-2.0 WITH Linux-syscall-note) OR BSD-3-Clause"))
        self.put("linux/bsd.h", header("BSD-3-Clause"))
        self.put("linux/quota.h", b"/* Redistribution and use ... */\n")  # untagged, permissive
        self.put("asm/types.h", b"#include <asm-generic/int-ll64.h>\n")  # untagged, COPYING
        used = ["linux/capability.h", "linux/either.h", "linux/bsd.h", "linux/quota.h", "asm/types.h"]
        self.assertEqual(
            linuxheaders.notices_needed(self.include, used), ["linux/bsd.h", "linux/quota.h"]
        )

    def test_an_untagged_header_outside_the_table_is_refused(self):
        self.put("linux/new.h", b"#define Z 3\n")
        with self.assertRaises(PackagerError):
            linuxheaders.notices_needed(self.include, ["linux/new.h"])


if __name__ == "__main__":
    unittest.main()
