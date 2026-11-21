"""Go binaries: every linked module's licence is read, shipped and declared in bundled."""

import os
import tempfile
import unittest

from sondpkg import golicences
from sondpkg.errors import PackagerError
from sondpkg.tests.helpers import run_cli, write_bytes

APACHE = (
    "                                 Apache License\n"
    "                           Version 2.0, January 2004\n"
    "                        http://www.apache.org/licenses/\n"
    "   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION\n"
)
MIT = (
    "MIT License\n\nCopyright (c) 2016 Someone\n\n"
    "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
    "of this software and associated documentation files (the \"Software\"), to deal\n"
    "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND\n"
)
BSD3 = (
    "Copyright (c) 2009 The Go Authors. All rights reserved.\n\n"
    "Redistribution and use in source and binary forms, with or without\n"
    "modification, are permitted provided that the following conditions are\nmet:\n\n"
    "   * Redistributions of source code must retain the above copyright\n"
    "   * Neither the name of Google Inc. nor the names of its\n"
    "contributors may be used to endorse or promote products derived from\n"
    "this software without specific prior written permission.\n"
)
BSD2 = (
    "Copyright (c) 2013, Someone\nAll rights reserved.\n\n"
    "Redistribution and use in source and binary forms, with or without modification,\n"
    "are permitted provided that the following conditions are met:\n\n"
    "* Redistributions of source code must retain the above copyright notice, this\n"
    "* Redistributions in binary form must reproduce the above copyright notice, this\n"
    "THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\"\n"
)
UNLICENSE = (
    "This is free and unencumbered software released into the public domain.\n\n"
    "Anyone is free to copy, modify, publish, use, compile, sell, or\n"
    "For more information, please refer to <http://unlicense.org/>\n"
)
ISC = (
    "ISC License\n\nCopyright (c) 2012 Someone\n\n"
    "Permission to use, copy, modify, and/or distribute this software for any\n"
    "purpose with or without fee is hereby granted, provided that the above\n"
)
MPL = "Mozilla Public License Version 2.0\n==================================\n"
CC_BY_SA = "Attribution-ShareAlike 4.0 International\n\nCreative Commons Corporation\n"

BUILD_INFO = (
    "/src/.out/incus: go1.26.9\n"
    "\tpath\tgithub.com/lxc/incus/v7/cmd/incus\n"
    "\tmod\tgithub.com/lxc/incus/v7\t(devel)\t\n"
    "\tdep\tgithub.com/FuturFusion/openfga-sync\tv0.0.0-2026\th1:x=\n"
    "\tdep\tgolang.org/x/sys\tv0.49.0\th1:y=\n"
    "\tdep\tgithub.com/zitadel/oidc/v3\tv3.51.16\th1:z=\n"
    "\tbuild\tCGO_ENABLED=0\n"
)


class ClassifyTest(unittest.TestCase):
    def test_each_admitted_text_is_recognised(self):
        for text, expected in (
            (APACHE, "Apache-2.0"),
            (MIT, "MIT"),
            (BSD3, "BSD-3-Clause"),
            (BSD2, "BSD-2-Clause"),
            (UNLICENSE, "Unlicense"),
            (ISC, "ISC"),
            (MPL, "MPL-2.0"),
        ):
            self.assertEqual(golicences.classify(text), expected, expected)

    def test_an_unknown_text_is_not_guessed(self):
        self.assertIsNone(golicences.classify(CC_BY_SA))
        self.assertIsNone(golicences.classify("All rights reserved.\n"))

    def test_a_file_with_several_texts_obliges_them_all(self):
        # go.opentelemetry.io/otel ships Apache-2.0 then the Go BSD text in one LICENSE.
        self.assertEqual(golicences.classify(APACHE + "\n----\n" + BSD3),
                         "Apache-2.0 AND BSD-3-Clause")
        self.assertEqual(golicences.classify(BSD3 + MIT + APACHE),
                         "Apache-2.0 AND MIT AND BSD-3-Clause")

    def test_markdown_and_rewrapped_text_still_match(self):
        markdown = "# The MIT License (MIT)\n\n" + MIT.replace("\n", " \n> ")
        self.assertEqual(golicences.classify(markdown), "MIT")


class BuildInfoTest(unittest.TestCase):
    def test_go_version_and_deps(self):
        go, deps = golicences.parse_build_info(BUILD_INFO)
        self.assertEqual(go, "1.26.9")
        self.assertEqual(
            deps,
            [
                ("github.com/FuturFusion/openfga-sync", "v0.0.0-2026"),
                ("golang.org/x/sys", "v0.49.0"),
                ("github.com/zitadel/oidc/v3", "v3.51.16"),
            ],
        )

    def test_a_replacement_is_the_module_that_was_compiled(self):
        info = BUILD_INFO.replace(
            "\tdep\tgolang.org/x/sys\tv0.49.0\th1:y=\n",
            "\tdep\tgolang.org/x/sys\tv0.49.0\t\n\t=>\tgithub.com/fork/sys\tv0.50.0\th1:r=\n",
        )
        _, deps = golicences.parse_build_info(info)
        self.assertIn(("github.com/fork/sys", "v0.50.0"), deps)
        self.assertNotIn(("golang.org/x/sys", "v0.49.0"), deps)

    def test_a_local_replacement_is_refused(self):
        info = BUILD_INFO.replace(
            "\tdep\tgolang.org/x/sys\tv0.49.0\th1:y=\n",
            "\tdep\tgolang.org/x/sys\tv0.49.0\t\n\t=>\t../sys\t(devel)\t\n",
        )
        with self.assertRaisesRegex(PackagerError, "local replacement"):
            golicences.parse_build_info(info)

    def test_not_a_go_binary_is_refused(self):
        with self.assertRaisesRegex(PackagerError, "go version -m"):
            golicences.parse_build_info("/bin/sh: could not read Go build info\n")

    def test_a_cgo_binary_is_refused(self):
        with self.assertRaisesRegex(PackagerError, "CGO_ENABLED=0"):
            golicences.parse_build_info(BUILD_INFO.replace("CGO_ENABLED=0", "CGO_ENABLED=1"))


class CollectTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.modcache = os.path.join(self.root, "mod")
        self.goroot = os.path.join(self.root, "goroot")
        self.out = os.path.join(self.root, "out")
        write_bytes(os.path.join(self.goroot, "LICENSE"), BSD3.encode())
        self.info = os.path.join(self.root, "build-info.txt")
        write_bytes(self.info, BUILD_INFO.encode())
        self.module("github.com/!futur!fusion/openfga-sync@v0.0.0-2026", {"LICENSE": APACHE})
        self.module("golang.org/x/sys@v0.49.0", {"LICENSE": BSD3, "PATENTS": "patents\n"})
        self.module(
            "github.com/zitadel/oidc/v3@v3.51.16",
            {"LICENSE": APACHE, "NOTICE": "Copyright 2020 CAOS AG\n"},
        )

    def tearDown(self):
        self.tmp.cleanup()

    def module(self, escaped, files):
        for name, text in files.items():
            write_bytes(os.path.join(self.modcache, escaped, name), text.encode())

    def collect(self, name="incus"):
        return golicences.collect(name, self.info, self.modcache, self.goroot, self.out)

    def test_bundled_lists_go_and_every_module_with_its_licence(self):
        bundled, _ = self.collect()
        self.assertEqual(
            bundled,
            [
                "go 1.26.9 BSD-3-Clause",
                "github.com/FuturFusion/openfga-sync v0.0.0-2026 Apache-2.0",
                "golang.org/x/sys v0.49.0 BSD-3-Clause",
                "github.com/zitadel/oidc/v3 v3.51.16 Apache-2.0",
            ],
        )

    def test_licence_files_land_under_the_package_go_directory(self):
        _, files = self.collect()
        destinations = sorted(dest for _, dest in files)
        self.assertEqual(
            destinations,
            [
                "share/licenses/incus/NOTICE",
                "share/licenses/incus/go-LICENSE",
                "share/licenses/incus/go/github.com/FuturFusion/openfga-sync@v0.0.0-2026/LICENSE",
                "share/licenses/incus/go/github.com/zitadel/oidc/v3@v3.51.16/LICENSE",
                "share/licenses/incus/go/github.com/zitadel/oidc/v3@v3.51.16/NOTICE",
                "share/licenses/incus/go/golang.org/x/sys@v0.49.0/LICENSE",
                "share/licenses/incus/go/golang.org/x/sys@v0.49.0/PATENTS",
            ],
        )
        for source, _ in files:
            self.assertTrue(os.path.isfile(source), source)

    def test_the_aggregated_notice_carries_every_module_notice(self):
        _, files = self.collect()
        notice = dict((dest, src) for src, dest in files)["share/licenses/incus/NOTICE"]
        with open(notice, encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn("github.com/zitadel/oidc/v3 v3.51.16", text)
        self.assertIn("Copyright 2020 CAOS AG", text)

    def test_no_notice_file_when_no_module_has_one(self):
        os.remove(os.path.join(self.modcache, "github.com/zitadel/oidc/v3@v3.51.16/NOTICE"))
        _, files = self.collect()
        self.assertNotIn("share/licenses/incus/NOTICE", [dest for _, dest in files])

    def test_a_module_without_licence_file_is_refused(self):
        os.remove(os.path.join(self.modcache, "golang.org/x/sys@v0.49.0/LICENSE"))
        with self.assertRaisesRegex(PackagerError, "golang.org/x/sys@v0.49.0.*no licence file"):
            self.collect()

    def test_a_module_with_an_unknown_licence_is_refused(self):
        self.module("golang.org/x/sys@v0.49.0", {"LICENSE": CC_BY_SA})
        with self.assertRaisesRegex(PackagerError, "golang.org/x/sys@v0.49.0.*LICENSE"):
            self.collect()

    def test_a_module_with_two_licence_files_obliges_both(self):
        self.module("golang.org/x/sys@v0.49.0", {"LICENSE.MPL-2.0": MPL})
        bundled, _ = self.collect()
        self.assertIn("golang.org/x/sys v0.49.0 BSD-3-Clause AND MPL-2.0", bundled)

    def test_an_mpl_module_text_also_ships_where_the_rules_ask_for_it(self):
        self.module("golang.org/x/sys@v0.49.0", {"LICENSE.MPL-2.0": MPL})
        _, files = self.collect()
        sources = [src for src, dest in files if dest == "share/licenses/incus/MPL-2.0"]
        self.assertEqual(sources, [os.path.join(self.modcache, "golang.org/x/sys@v0.49.0",
                                                "LICENSE.MPL-2.0")])

    def test_a_licence_outside_the_admitted_set_is_refused(self):
        self.module("golang.org/x/sys@v0.49.0", {"LICENSE": MPL})
        with self.assertRaisesRegex(PackagerError, "MPL-2.0"):
            golicences.collect("incus", self.info, self.modcache, self.goroot, self.out,
                               admitted=("Apache-2.0", "BSD-3-Clause"))

    def test_several_binaries_union_their_modules(self):
        second = os.path.join(self.root, "build-info-2.txt")
        write_bytes(second, ("/src/.out/incus-agent: go1.26.9\n"
                             "\tdep\tgolang.org/x/sys\tv0.49.0\th1:y=\n"
                             "\tdep\tgithub.com/pkg/errors\tv0.9.1\th1:e=\n"
                             "\tbuild\tCGO_ENABLED=0\n").encode())
        self.module("github.com/pkg/errors@v0.9.1", {"LICENSE": BSD2})
        bundled, _ = golicences.collect("incus", [self.info, second], self.modcache,
                                        self.goroot, self.out)
        self.assertEqual(bundled.count("golang.org/x/sys v0.49.0 BSD-3-Clause"), 1)
        self.assertIn("github.com/pkg/errors v0.9.1 BSD-2-Clause", bundled)

    def test_binaries_built_by_different_go_versions_are_refused(self):
        second = os.path.join(self.root, "build-info-2.txt")
        write_bytes(second, BUILD_INFO.replace("go1.26.9", "go1.26.8").encode())
        with self.assertRaisesRegex(PackagerError, "1.26.8"):
            golicences.collect("incus", [self.info, second], self.modcache, self.goroot, self.out)

    def test_goroot_without_licence_is_refused(self):
        os.remove(os.path.join(self.goroot, "LICENSE"))
        with self.assertRaisesRegex(PackagerError, "Go toolchain"):
            self.collect()


class ReviewedTest(unittest.TestCase):
    """The modules read by hand (dictamen 2.10 (a)) are pinned by version and package."""

    def test_go_proto_is_apache_by_its_header(self):
        entry = golicences.reviewed(
            "incus", "github.com/rootless-containers/proto/go-proto",
            "v0.0.0-20260207013450-f6ee952d53d9")
        self.assertEqual(entry.spdx, "Apache-2.0")
        self.assertEqual(entry.header_of, "rootlesscontainers.pb.go")

    def test_securejoin_is_bsd_only_for_the_client(self):
        entry = golicences.reviewed("incus", "github.com/cyphar/filepath-securejoin", "v0.7.0")
        self.assertEqual(entry.spdx, "BSD-3-Clause")
        self.assertIsNone(
            golicences.reviewed("incusd", "github.com/cyphar/filepath-securejoin", "v0.7.0"))

    def test_go_digest_docs_licence_does_not_cover_code(self):
        entry = golicences.reviewed("incus", "github.com/opencontainers/go-digest", "v1.0.0")
        self.assertEqual(entry.spdx, "Apache-2.0")
        self.assertIn("LICENSE.docs", entry.ignore)

    def test_a_new_version_needs_a_new_review(self):
        self.assertIsNone(
            golicences.reviewed("incus", "github.com/cyphar/filepath-securejoin", "v0.8.0"))

    def test_header_of_ships_the_licence_comment(self):
        with tempfile.TemporaryDirectory() as root:
            info = os.path.join(root, "info")
            write_bytes(info, (
                "/x: go1.26.9\n\tdep\tgithub.com/rootless-containers/proto/go-proto"
                "\tv0.0.0-20260207013450-f6ee952d53d9\th1:a=\n\tbuild\tCGO_ENABLED=0\n").encode())
            mod = os.path.join(
                root, "mod",
                "github.com/rootless-containers/proto/go-proto@v0.0.0-20260207013450-f6ee952d53d9")
            write_bytes(os.path.join(mod, "rootlesscontainers.pb.go"), (
                "// Copyright (C) 2018 Rootless Containers Authors\n"
                "//\n// Licensed under the Apache License, Version 2.0 (the \"License\");\n"
                "\n// Code generated by protoc-gen-go. DO NOT EDIT.\npackage x\n").encode())
            write_bytes(os.path.join(root, "goroot", "LICENSE"), BSD3.encode())
            bundled, files = golicences.collect(
                "incus", info, os.path.join(root, "mod"), os.path.join(root, "goroot"),
                os.path.join(root, "out"))
            self.assertIn(
                "github.com/rootless-containers/proto/go-proto "
                "v0.0.0-20260207013450-f6ee952d53d9 Apache-2.0", bundled)
            header = [src for src, dest in files if dest.endswith("/HEADER-rootlesscontainers.pb.go")]
            self.assertEqual(len(header), 1)
            with open(header[0], encoding="utf-8") as handle:
                text = handle.read()
            self.assertIn("Apache License, Version 2.0", text)
            self.assertNotIn("Code generated", text)


class CliTest(unittest.TestCase):
    def test_go_licences_writes_bundled_and_licence_lists(self):
        with tempfile.TemporaryDirectory() as root:
            info = os.path.join(root, "info")
            write_bytes(info, ("/x: go1.26.9\n\tdep\tgolang.org/x/sys\tv0.49.0\th1:a=\n"
                               "\tbuild\tCGO_ENABLED=0\n").encode())
            write_bytes(os.path.join(root, "mod", "golang.org/x/sys@v0.49.0", "LICENSE"),
                        BSD3.encode())
            write_bytes(os.path.join(root, "goroot", "LICENSE"), BSD3.encode())
            out = os.path.join(root, "out")
            rc, _, err = run_cli([
                "go-licences", "--name", "incus", "--build-info", info,
                "--modcache", os.path.join(root, "mod"), "--goroot", os.path.join(root, "goroot"),
                "--out", out,
            ])
            self.assertEqual(rc, 0, err)
            with open(os.path.join(out, "bundled.txt"), encoding="utf-8") as handle:
                self.assertEqual(handle.read(),
                                 "go 1.26.9 BSD-3-Clause\ngolang.org/x/sys v0.49.0 BSD-3-Clause\n")
            with open(os.path.join(out, "licence-files.txt"), encoding="utf-8") as handle:
                lines = handle.read().splitlines()
            self.assertEqual(len(lines), 2)
            self.assertTrue(all("=share/licenses/incus/" in line for line in lines))


if __name__ == "__main__":
    unittest.main()
