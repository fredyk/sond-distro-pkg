"""Tests for the declarative MANIFEST: render, parse, and contract shape."""

import json
import unittest

from sondpkg.manifest import Manifest, ManifestError, parse, render

H = "923345ba8a4816339aeac609bef11aaa7dd88d46459bf8886ed8cc68833b3a8d"


def sample_manifest():
    return Manifest(
        name="toybox-static",
        version="0.8.15",
        license="0BSD",
        tier="public",
        source="github.com/fredyk/toybox-sond@" + "a" * 40,
        upstream="github.com/landley/toybox@" + "b" * 40,
        linkage="static musl 1.2.5 (MIT)",
        bundle="sha256:" + H,
        files=3,
        licences=[
            "share/licenses/toybox-static/LICENSE",
            "share/licenses/toybox-static/musl-COPYRIGHT",
        ],
        sources=[
            "sha256:" + "1" * 64 + " toybox-0.8.15.tar.xz",
            "sha256:" + "2" * 64 + " musl-1.2.5.tar.gz",
            "sha256:" + "3" * 64 + " toybox-sond.patch",
            "sha256:" + "4" * 64 + " build-recipe.sh",
        ],
    )


class RenderTest(unittest.TestCase):
    def test_render_matches_contract_shape(self):
        text = render(sample_manifest())
        lines = text.splitlines()
        self.assertEqual(lines[0], 'package "toybox-static" {')
        self.assertEqual(lines[-1], "}")
        self.assertIn('  version  = "0.8.15"', text)
        self.assertIn('  license  = "0BSD"', text)
        self.assertIn('  tier     = "public"', text)
        self.assertIn('  bundle   = "sha256:' + H + '"', text)
        self.assertIn("  files    = 3", text)
        self.assertIn("  licences = [", text)
        self.assertIn("  sources  = [", text)
        self.assertNotIn("\r", text)

    def test_render_ends_in_single_newline(self):
        text = render(sample_manifest())
        self.assertTrue(text.endswith("\n"))
        self.assertFalse(text.endswith("\n\n"))


class OptionalFieldsTest(unittest.TestCase):
    def test_a_manifest_without_bundled_or_source_object_renders_as_before(self):
        text = render(sample_manifest())
        self.assertNotIn("bundled", text)
        self.assertNotIn("source_object", text)

    def test_bundled_and_source_object_render_and_parse_back(self):
        m = sample_manifest()
        m.bundled = ["ncurses 6.6 X11-distribute-modifications-variant", "musl 1.2.5 MIT"]
        m.source_object = "sha256:" + "c" * 64
        text = render(m)
        self.assertIn('  bundled  = ["ncurses 6.6 X11-distribute-modifications-variant",', text)
        self.assertIn('  source_object = "sha256:' + "c" * 64 + '"', text)
        self.assertEqual(parse(text), [m])


class RoundtripTest(unittest.TestCase):
    def test_render_parse_roundtrip(self):
        original = sample_manifest()
        parsed = parse(render(original))
        self.assertEqual(parsed, [original])

    def test_parse_contract_example(self):
        text = (
            'package "toybox-static" {\n'
            '  version  = "0.8.15"\n'
            '  license  = "0BSD"\n'
            '  tier     = "public"\n'
            '  source   = "github.com/fredyk/toybox-sond@' + "a" * 40 + '"\n'
            '  upstream = "github.com/landley/toybox@' + "b" * 40 + '"\n'
            '  linkage  = "static musl 1.2.5 (MIT)"\n'
            '  bundle   = "sha256:' + H + '"\n'
            "  files    = 3\n"
            '  licences = ["share/licenses/toybox-static/LICENSE",\n'
            '              "share/licenses/toybox-static/musl-COPYRIGHT"]\n'
            '  sources  = ["sha256:' + "1" * 64 + ' toybox-0.8.15.tar.xz",\n'
            '              "sha256:' + "2" * 64 + ' musl-1.2.5.tar.gz"]\n'
            "}\n"
        )
        manifests = parse(text)
        self.assertEqual(len(manifests), 1)
        manifest = manifests[0]
        self.assertEqual(manifest.name, "toybox-static")
        self.assertEqual(manifest.files, 3)
        self.assertEqual(manifest.licences[1], "share/licenses/toybox-static/musl-COPYRIGHT")
        self.assertEqual(manifest.sources[0], "sha256:" + "1" * 64 + " toybox-0.8.15.tar.xz")


class ParseErrorTest(unittest.TestCase):
    def test_missing_field_is_named(self):
        text = render(sample_manifest()).replace('  tier     = "public"\n', "")
        with self.assertRaises(ManifestError) as caught:
            parse(text)
        self.assertIn("tier", str(caught.exception))

    def test_garbage_is_rejected(self):
        with self.assertRaises(ManifestError):
            parse("this is not a manifest\n")

    def test_json_is_not_accepted(self):
        with self.assertRaises(ManifestError):
            parse(json.dumps({"name": "toybox-static"}))


if __name__ == "__main__":
    unittest.main()
