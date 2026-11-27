"""A private-tier package: proprietary code that only a box holding a read token may fetch."""

import unittest

from sondpkg import rules
from sondpkg.errors import PackagerError

SHA = "a" * 40


def metadata(tier, license):
    return dict(
        name="lited",
        version="1.0.0",
        license=license,
        source="github.com/fredyk/lite-gateway@" + SHA,
        upstream="github.com/fredyk/lite-gateway@" + SHA,
        linkage="dynamic glibc, Go",
        tier=tier,
    )


class PrivateTierTest(unittest.TestCase):
    def test_private_is_a_known_tier(self):
        self.assertIn("private", rules.ALLOWED_TIERS)

    def test_private_tier_accepts_the_proprietary_licence(self):
        rules.validate_metadata(**metadata("private", rules.PROPRIETARY_LICENSE))

    def test_proprietary_licence_is_a_licenseref(self):
        self.assertEqual(rules.PROPRIETARY_LICENSE, "LicenseRef-Proprietary")

    def test_public_tier_refuses_the_proprietary_licence(self):
        with self.assertRaises(PackagerError) as caught:
            rules.validate_metadata(**metadata("public", rules.PROPRIETARY_LICENSE))
        self.assertIn("private", str(caught.exception))

    def test_private_tier_refuses_an_open_licence(self):
        # An open licence belongs in public: private would hide code its licence lets anyone have.
        with self.assertRaises(PackagerError) as caught:
            rules.validate_metadata(**metadata("private", "MIT"))
        self.assertIn(rules.PROPRIETARY_LICENSE, str(caught.exception))

    def test_unknown_tier_is_still_refused(self):
        with self.assertRaises(PackagerError) as caught:
            rules.validate_metadata(**metadata("staging", "MIT"))
        self.assertIn("tier", str(caught.exception))
