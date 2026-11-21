"""Ed25519 (RFC 8032) in pure Python: vectors, determinism and key file handling."""

import os
import tempfile
import unittest

from sondpkg import ed25519
from sondpkg.errors import PackagerError

# RFC 8032 section 7.1, test vectors 1 and 2.
VECTORS = [
    (
        "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
        "",
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
        "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
    ),
    (
        "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
        "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
        "72",
        "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
        "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
    ),
]


class Ed25519Vectors(unittest.TestCase):
    def test_rfc8032_public_keys_and_signatures(self):
        for seed, public, message, signature in VECTORS:
            seed_b = bytes.fromhex(seed)
            self.assertEqual(ed25519.public_key(seed_b).hex(), public)
            sig = ed25519.sign(seed_b, bytes.fromhex(message))
            self.assertEqual(sig.hex(), signature)
            self.assertTrue(
                ed25519.verify(bytes.fromhex(public), bytes.fromhex(message), sig)
            )

    def test_verify_rejects_a_changed_message_signature_or_key(self):
        seed = bytes.fromhex(VECTORS[0][0])
        public = ed25519.public_key(seed)
        sig = ed25519.sign(seed, b"hello")
        self.assertTrue(ed25519.verify(public, b"hello", sig))
        self.assertFalse(ed25519.verify(public, b"hellp", sig))
        flipped = bytes([sig[0] ^ 1]) + sig[1:]
        self.assertFalse(ed25519.verify(public, b"hello", flipped))
        other = ed25519.public_key(bytes.fromhex(VECTORS[1][0]))
        self.assertFalse(ed25519.verify(other, b"hello", sig))
        self.assertFalse(ed25519.verify(public, b"hello", sig[:63]))

    def test_matches_the_cryptography_library_when_it_is_installed(self):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import (
                Ed25519PrivateKey,
            )
        except ImportError:
            self.skipTest("cryptography is not installed")
        for index in range(5):
            seed = bytes([index * 17 + 3]) * 32
            message = b"message %d" % index * (index + 1)
            reference = Ed25519PrivateKey.from_private_bytes(seed)
            self.assertEqual(ed25519.sign(seed, message), reference.sign(message))


class KeyFiles(unittest.TestCase):
    def test_generate_writes_a_private_key_file_and_returns_the_public_key_hex(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "publisher.key")
            public_hex = ed25519.generate_key_file(path)
            self.assertEqual(len(public_hex), 64)
            with open(path) as handle:
                text = handle.read()
            self.assertEqual(len(text.strip()), 64)
            self.assertTrue(text.endswith("\n"))
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            seed = ed25519.read_key_file(path)
            self.assertEqual(ed25519.public_key(seed).hex(), public_hex)

    def test_generate_refuses_to_overwrite_an_existing_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "publisher.key")
            ed25519.generate_key_file(path)
            with self.assertRaises(PackagerError):
                ed25519.generate_key_file(path)

    def test_read_rejects_a_malformed_key_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "bad.key")
            with open(path, "w") as handle:
                handle.write("not hex\n")
            with self.assertRaises(PackagerError):
                ed25519.read_key_file(path)
            with self.assertRaises(PackagerError):
                ed25519.read_key_file(os.path.join(tmp, "missing.key"))


if __name__ == "__main__":
    unittest.main()
