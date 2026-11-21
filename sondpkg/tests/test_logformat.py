"""Log entry, signed tree head and Merkle proof formats (client side)."""

import hashlib
import unittest

from sondpkg import ed25519, logformat
from sondpkg.errors import PackagerError

SEED = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
PUBLIC = ed25519.public_key(SEED).hex()
CONTENT = "sha256:" + "ab" * 32


def make_entry(**overrides):
    fields = dict(
        name="toybox-static",
        version="0.8.15",
        content=CONTENT,
        publisher_key=PUBLIC,
        license="0BSD",
        timestamp="2026-11-21T10:00:00Z",
    )
    fields.update(overrides)
    return logformat.entry_text(**fields)


class EntryFormat(unittest.TestCase):
    def test_entry_text_is_fixed_and_line_oriented(self):
        text = make_entry()
        self.assertEqual(
            text.decode(),
            "sond-dist-entry-v1\n"
            "name=toybox-static\n"
            "version=0.8.15\n"
            "content=sha256:" + "ab" * 32 + "\n"
            "publisher-key=" + PUBLIC + "\n"
            "license=0BSD\n"
            "timestamp=2026-11-21T10:00:00Z\n",
        )

    def test_a_signed_entry_parses_and_verifies(self):
        stored = logformat.sign_entry(SEED, make_entry())
        self.assertTrue(stored.startswith(make_entry()))
        self.assertTrue(stored.endswith(b"\n"))
        parsed = logformat.parse_entry(stored)
        self.assertEqual(parsed["name"], "toybox-static")
        self.assertEqual(parsed["content"], CONTENT)
        self.assertEqual(parsed["publisher-key"], PUBLIC)
        self.assertTrue(logformat.verify_entry(stored))

    def test_a_tampered_entry_does_not_verify(self):
        stored = logformat.sign_entry(SEED, make_entry())
        forged = stored.replace(b"0.8.15", b"0.8.16")
        self.assertFalse(logformat.verify_entry(forged))

    def test_invalid_fields_are_refused_when_the_entry_is_built(self):
        for bad in (
            dict(name="Upper"),
            dict(name="-lead"),
            dict(name="a/b"),
            dict(name=""),
            dict(version="1 0"),
            dict(version="v" * 65),
            dict(content="sha256:xyz"),
            dict(content="md5:" + "a" * 32),
            dict(publisher_key="ab"),
            dict(license="GPL 2"),
            dict(timestamp="2026-11-21 10:00:00"),
        ):
            with self.assertRaises(PackagerError, msg=str(bad)):
                make_entry(**bad)


class TreeHead(unittest.TestCase):
    def test_sth_signature_is_over_the_sha256_of_the_body(self):
        body = "sond-dist-log-v1\nsize=3\nroot=" + "cd" * 32 + "\nkey=" + PUBLIC + "\n"
        signature = ed25519.sign(SEED, hashlib.sha256(body.encode()).digest())
        text = body + "signature=" + signature.hex() + "\n"
        head = logformat.parse_sth(text.encode())
        self.assertEqual((head["size"], head["root"], head["key"]), (3, "cd" * 32, PUBLIC))
        self.assertTrue(logformat.verify_sth(text.encode(), PUBLIC))

    def test_sth_signed_by_another_key_is_rejected(self):
        body = "sond-dist-log-v1\nsize=3\nroot=" + "cd" * 32 + "\nkey=" + PUBLIC + "\n"
        signature = ed25519.sign(SEED, hashlib.sha256(body.encode()).digest())
        text = (body + "signature=" + signature.hex() + "\n").encode()
        other = ed25519.public_key(bytes([7]) * 32).hex()
        self.assertFalse(logformat.verify_sth(text, other))
        tampered = text.replace(b"size=3", b"size=4")
        self.assertFalse(logformat.verify_sth(tampered, PUBLIC))
        with self.assertRaises(PackagerError):
            logformat.parse_sth(b"garbage")


def _h(data):
    return hashlib.sha256(data).digest()


class Proofs(unittest.TestCase):
    def test_inclusion_proof_matches_the_reference_vectors(self):
        # Same vectors as lib/merkle_test.snd (independent RFC 6962 implementation).
        leaves = [logformat.leaf_hash(b"leaf-%d" % i) for i in range(5)]
        proof = [
            bytes.fromhex("f76836325aec5699d8d71f8e42e9d47c5c29b08059ba296384f7ca40ad3a40ae"),
            bytes.fromhex("60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc"),
            bytes.fromhex("ea9fc1a1b6e191b460d0d6306e3e870c173f39330f13cda1b70cfc72bdc398ba"),
        ]
        root = bytes.fromhex("00d21829a5503145348abcf712513eacf2a274211ad83e970202bb5b6d80b286")
        self.assertTrue(logformat.verify_inclusion(leaves[2], 2, 5, proof, root))
        self.assertFalse(logformat.verify_inclusion(leaves[3], 2, 5, proof, root))
        self.assertFalse(logformat.verify_inclusion(leaves[2], 3, 5, proof, root))
        self.assertFalse(logformat.verify_inclusion(leaves[2], 2, 5, proof[:2], root))
        self.assertFalse(logformat.verify_inclusion(leaves[2], 5, 5, proof, root))

    def test_a_single_leaf_tree_has_an_empty_proof(self):
        leaf = logformat.leaf_hash(b"leaf-0")
        self.assertTrue(logformat.verify_inclusion(leaf, 0, 1, [], leaf))

    def test_consistency_proof_matches_the_reference_vector(self):
        proof = [
            bytes.fromhex(x)
            for x in (
                "fca89f57c9f8c8eb4047a7ff9d333acf9e0f3384b20b255bceab0f216dcca267",
                "f76836325aec5699d8d71f8e42e9d47c5c29b08059ba296384f7ca40ad3a40ae",
                "60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc",
                "f58aaab46122102d66b00c5eb50b13dd763b5f800139b424fda8b1cacae1408a",
            )
        ]
        root3 = bytes.fromhex("cf763a041c81ceef1578a6083f75c61bef2e0014f2a3e683a97fcfca5be7f19a")
        root8 = bytes.fromhex("ca6b7b3e674ac86c1027b59c87c064fc3bc27b313294c75f83bd05fdd13f0dcf")
        self.assertTrue(logformat.verify_consistency(3, 8, proof, root3, root8))
        self.assertFalse(logformat.verify_consistency(3, 8, proof, root8, root8))
        self.assertFalse(logformat.verify_consistency(3, 8, proof[1:], root3, root8))
        self.assertTrue(logformat.verify_consistency(8, 8, [], root8, root8))


if __name__ == "__main__":
    unittest.main()
