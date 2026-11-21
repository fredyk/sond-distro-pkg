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

    def test_reject_x11_variant_without_its_copying(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            name="ncurses",
            license="X11-distribute-modifications-variant",
            license_files=[musl],
        )
        self.reject(argv, "share/licenses/ncurses/COPYING")

    def test_build_ncurses_with_its_copying_succeeds(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        copying = make_licence(self.root, "COPYING", "X11 variant text\n")
        argv = base_args(
            self.root,
            self.tree,
            self.out,
            name="ncurses",
            license="X11-distribute-modifications-variant",
            license_files=[musl, copying],
        )
        rc, out, err = run_cli(argv)
        self.assertEqual(rc, 0, err)
        self.assertTrue(os.path.isdir(out.strip()))

    # --- copyleft and linked components (dictamen section 3 and 3.1) ---

    def htop_args(self, **overrides):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        copying = make_licence(self.root, "COPYING", "GPL-2.0 text\n")
        ncurses = make_licence(self.root, "ncurses-COPYING", "X11 variant text\n")
        values = dict(
            name="htop",
            license="GPL-2.0-or-later AND GPL-2.0-only",
            license_files=[musl, copying, ncurses],
            bundled=["ncurses 6.6 X11-distribute-modifications-variant", "musl 1.2.5 MIT"],
            source_object="sha256:" + "c" * 64,
        )
        values.update(overrides)
        return base_args(self.root, self.tree, self.out, **values)

    def test_build_htop_with_every_obligation_succeeds(self):
        rc, out, err = run_cli(self.htop_args())
        self.assertEqual(rc, 0, err)
        with open(os.path.join(out.strip(), "MANIFEST"), encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn('"ncurses 6.6 X11-distribute-modifications-variant"', text)
        self.assertIn('source_object = "sha256:' + "c" * 64 + '"', text)

    def test_reject_copyleft_package_without_a_source_object(self):
        self.reject(self.htop_args(source_object=None), "source_object")

    def test_reject_a_malformed_source_object(self):
        self.reject(self.htop_args(source_object="sha256:abc"), "source_object")

    def test_reject_permissive_package_linking_copyleft_without_a_source_object(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        lgpl = make_licence(self.root, "LGPL-2.1", "LGPL text\n")
        argv = base_args(self.root, self.tree, self.out,
                         license="Apache-2.0", license_files=[musl, lgpl],
                         bundled=["lxc 6.0.5 LGPL-2.1-or-later", "musl 1.2.5 MIT"])
        self.reject(argv, "source_object")

    def test_the_source_bundle_itself_needs_no_source_object(self):
        copying = make_licence(self.root, "COPYING", "GPL-2.0 text\n")
        argv = base_args(self.root, self.tree, self.out, name="htop-source",
                         license="GPL-2.0-or-later AND GPL-2.0-only", linkage="source",
                         license_files=[copying])
        rc, _, err = run_cli(argv)
        self.assertEqual(rc, 0, err)

    def test_reject_gpl_package_without_its_copying(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        ncurses = make_licence(self.root, "ncurses-COPYING", "X11 variant text\n")
        self.reject(self.htop_args(license_files=[musl, ncurses]), "share/licenses/htop/COPYING")

    def test_reject_linked_ncurses_without_its_copying(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        copying = make_licence(self.root, "COPYING", "GPL-2.0 text\n")
        self.reject(self.htop_args(license_files=[musl, copying]), "share/licenses/htop/ncurses-COPYING")

    def test_reject_linked_lgpl_without_its_text(self):
        musl = make_licence(self.root, "musl-COPYRIGHT", "MIT text\n")
        apache = make_licence(self.root, "COPYING", "Apache-2.0 text\n")
        argv = base_args(self.root, self.tree, self.out,
                         license="Apache-2.0", license_files=[musl, apache],
                         bundled=["lxc 6.0.5 LGPL-2.1-or-later", "musl 1.2.5 MIT"],
                         source_object="sha256:" + "c" * 64)
        self.reject(argv, "share/licenses/toybox-static/LGPL-2.1")

    def lgpl3_library_args(self, files):
        texts = [make_licence(self.root, n, n + " text\n") for n in files + ["musl-COPYRIGHT"]]
        return base_args(self.root, self.tree, self.out, name="raft",
                         license="LGPL-3.0-only WITH LGPL-3.0-linking-exception",
                         linkage="static musl 1.2.5 (MIT)", license_files=texts,
                         source_object="sha256:" + "c" * 64)

    def test_reject_an_lgpl3_package_without_the_gpl3_text(self):
        # LGPL-3.0 is a set of additional permissions on GPL-3.0: both texts go with the library
        self.reject(self.lgpl3_library_args(["LICENSE", "LGPL-3.0"]), "share/licenses/raft/GPL-3.0")
        self.reject(self.lgpl3_library_args(["LICENSE", "GPL-3.0"]), "share/licenses/raft/LGPL-3.0")

    def test_an_lgpl3_package_with_both_texts_packages(self):
        rc, _, err = run_cli(self.lgpl3_library_args(["LICENSE", "LGPL-3.0", "GPL-3.0"]))
        self.assertEqual(rc, 0, err)

    def test_reject_malformed_or_unadmitted_bundled_components(self):
        self.reject(self.htop_args(bundled=["ncurses"]), "bundled")
        self.reject(self.htop_args(bundled=["ncurses 6.6 SSPL-1.0", "musl 1.2.5 MIT"]), "SSPL-1.0")

    def test_reject_musl_linkage_whose_bundled_omits_musl(self):
        self.reject(self.htop_args(bundled=["ncurses 6.6 X11-distribute-modifications-variant"]), "musl")

    def test_reject_htop_linking_anything_beyond_ncurses_and_musl(self):
        argv = self.htop_args(bundled=["ncurses 6.6 X11-distribute-modifications-variant",
                                       "musl 1.2.5 MIT", "lm-sensors 3.6.0 LGPL-2.1-or-later"])
        self.reject(argv, "lm-sensors")

    def test_reject_unadmitted_atoms_in_the_package_license(self):
        self.reject(self.htop_args(license="GPL-2.0-only AND GPL-3.0-only"), "GPL-3.0-only")


class GoRejectionTest(unittest.TestCase):
    """A pure Go binary (dictamen 2.10 (a)): Apache text, Go's licence, each module's, NOTICE."""

    MODULE = "github.com/zitadel/oidc/v3"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.tree = make_payload_tree(os.path.join(self.root, "tree"))
        self.out = os.path.join(self.root, "out")
        base = "share/licenses/incus/"
        self.files = {
            base + "COPYING": "Apache-2.0 text\n",
            base + "go-LICENSE": "Go BSD text\n",
            base + "go/%s@v3.51.16/LICENSE" % self.MODULE: "Apache-2.0 text\n",
            base + "go/%s@v3.51.16/NOTICE" % self.MODULE: "Copyright 2020 CAOS AG\n",
            base + "NOTICE": "==== oidc ====\nCopyright 2020 CAOS AG\n",
        }

    def tearDown(self):
        self.tmp.cleanup()

    def args(self, drop=(), bundled=None, **overrides):
        specs = []
        for index, (dest, text) in enumerate(sorted(self.files.items())):
            if dest in drop:
                continue
            specs.append("%s=%s" % (make_licence(self.root, "f%d" % index, text), dest))
        values = dict(name="incus", version="7.6.0", license="Apache-2.0",
                      linkage="static Go 1.26.9, no libc", license_files=specs,
                      bundled=bundled if bundled is not None else [
                          "go 1.26.9 BSD-3-Clause", self.MODULE + " v3.51.16 Apache-2.0"])
        values.update(overrides)
        return base_args(self.root, self.tree, self.out, **values)

    def reject(self, argv, needle):
        rc, _, err = run_cli(argv)
        self.assertNotEqual(rc, 0, "expected a rejection, got rc=0")
        self.assertIn(needle, err)

    def test_a_complete_go_package_is_accepted(self):
        rc, _, err = run_cli(self.args())
        self.assertEqual(rc, 0, err)

    def test_reject_apache_package_without_its_licence_text(self):
        self.reject(self.args(drop={"share/licenses/incus/COPYING"}), "share/licenses/incus/COPYING")

    def test_reject_go_linkage_without_go_licence(self):
        self.reject(self.args(drop={"share/licenses/incus/go-LICENSE"}), "go-LICENSE")

    def test_reject_go_linkage_whose_bundled_omits_go(self):
        self.reject(self.args(bundled=[self.MODULE + " v3.51.16 Apache-2.0"]), "go")

    def test_reject_a_module_without_its_licence_directory(self):
        drop = {d for d in self.files if "/go/" in d}
        self.reject(self.args(drop=drop | {"share/licenses/incus/NOTICE"}),
                    "share/licenses/incus/go/%s@v3.51.16/" % self.MODULE)

    def test_a_cgo_package_bundles_c_components_beside_its_modules(self):
        # cgo (dictamen 2.10 (b)): a C component (version without the v of a Go module) ships
        # its licences beside the package's, not under go/.
        self.files["share/licenses/incus/musl-COPYRIGHT"] = "musl MIT text\n"
        self.files["share/licenses/incus/libcap-License"] = "libcap BSD-3-Clause text\n"
        rc, _, err = run_cli(self.args(
            linkage="static Go 1.26.9 + musl 1.2.5 (MIT), cgo",
            bundled=["go 1.26.9 BSD-3-Clause", self.MODULE + " v3.51.16 Apache-2.0",
                     "libcap 1.2.78 BSD-3-Clause", "musl 1.2.5 MIT"]))
        self.assertEqual(rc, 0, err)

    def test_reject_a_module_notice_missing_from_the_aggregated_notice(self):
        self.files["share/licenses/incus/NOTICE"] = "something else\n"
        self.reject(self.args(), "NOTICE")
        self.reject(self.args(drop={"share/licenses/incus/NOTICE"}), "NOTICE")


if __name__ == "__main__":
    unittest.main()
