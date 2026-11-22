"""Tests for keygen, publish and verify-published, against an in-process stub registry."""

import hashlib
import http.server
import os
import stat
import tempfile
import threading
import unittest

from sondpkg import canonical, ed25519, logformat
from sondpkg import publish as publish_module
from sondpkg.tests.helpers import base_args, make_licence, make_payload_tree, run_cli

LOG_SEED = bytes.fromhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
PUBLISHER_SEED = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")


def make_sth(size, root, seed=LOG_SEED):
    body = (
        "sond-dist-log-v1\nsize=%d\nroot=%s\nkey=%s\n" % (size, root.hex(), ed25519.public_key(seed).hex())
    ).encode("ascii")
    signature = ed25519.sign(seed, hashlib.sha256(body).digest())
    return body + b"signature=" + signature.hex().encode("ascii") + b"\n"


class Stub:
    """A registry that answers from a dict of routes: path -> (status, body)."""

    def __init__(self):
        self.routes = {}
        self.requests = []
        stub = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _answer(self, method):
                length = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(length) if length else b""
                stub.requests.append((method, self.path, dict(self.headers), body))
                status, payload = stub.routes.get((method, self.path), (404, b"not found\n"))
                self.send_response(status)
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(payload)

            def do_GET(self):
                self._answer("GET")

            def do_POST(self):
                self._answer("POST")

            def do_PUT(self):
                self._answer("PUT")

        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class RegistryCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        tree = make_payload_tree(os.path.join(self.root, "tree"))
        rc, out, err = run_cli(base_args(self.root, tree, os.path.join(self.root, "out")))
        self.assertEqual(rc, 0, err)
        self.bundle = out.strip()
        self.token_file = os.path.join(self.root, "token")
        with open(self.token_file, "w") as handle:
            handle.write("tok-secret\n")
        self.key_file = os.path.join(self.root, "key")
        with open(self.key_file, "w") as handle:
            handle.write(PUBLISHER_SEED.hex() + "\n")
        self.stub = Stub()

    def tearDown(self):
        self.stub.close()
        self.tmp.cleanup()

    def publish(self, *extra):
        return run_cli(
            ["publish", self.bundle, "--url", self.stub.url, "--token-file", self.token_file, "--key-file", self.key_file]
            + list(extra)
        )


class KeygenTest(unittest.TestCase):
    def test_writes_a_private_key_file_and_prints_the_public_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "k")
            rc, out, err = run_cli(["keygen", "--out", path])
            self.assertEqual(rc, 0, err)
            seed = ed25519.read_key_file(path)
            self.assertEqual(out, ed25519.public_key(seed).hex() + "\n")
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)

    def test_never_overwrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "k")
            run_cli(["keygen", "--out", path])
            with open(path) as handle:
                before = handle.read()
            rc, out, err = run_cli(["keygen", "--out", path])
            self.assertEqual(rc, 1)
            self.assertEqual(out, "")
            self.assertIn("overwrite", err)
            with open(path) as handle:
                self.assertEqual(handle.read(), before)


class PublishTest(RegistryCase):
    def test_the_publish_request_names_the_client(self):
        self.publish()
        self.assertRegex(self.stub.requests[0][2].get("User-Agent", ""), r"^sondpkg/\S+")

    def test_new_publish_prints_three_lines_and_exits_zero(self):
        self.stub.routes[("POST", "/publish")] = (
            201,
            b"object=sha256:" + b"ab" * 32 + b"\nlog_index=4\ntree_size=5\n",
        )
        rc, out, err = self.publish()
        self.assertEqual(rc, 0, err)
        self.assertEqual(out, "object=sha256:" + "ab" * 32 + "\nlog_index=4\ntree_size=5\n")

    def test_the_request_is_a_signed_entry_for_the_canonical_object(self):
        self.stub.routes[("POST", "/publish")] = (201, b"object=sha256:00\nlog_index=0\ntree_size=1\n")
        self.publish()
        method, path, headers, body = self.stub.requests[0]
        self.assertEqual(headers["Authorization"], "Bearer tok-secret")
        head, _, rest = body.partition(b"\n\n")
        lines = head.split(b"\n")
        self.assertEqual(lines[0], b"sond-dist-publish-v1")
        entry_length = int(lines[1].split(b"=")[1])
        object_length = int(lines[2].split(b"=")[1])
        entry, obj = rest[:entry_length], rest[entry_length:]
        self.assertEqual(len(obj), object_length)
        self.assertEqual(obj, canonical.canonical_object(self.bundle))
        parsed = logformat.parse_entry(entry)
        self.assertTrue(logformat.verify_entry(entry))
        self.assertEqual(parsed["content"], canonical.object_id(self.bundle))
        self.assertEqual(parsed["name"], "toybox-static")
        self.assertEqual(parsed["version"], "0.8.15")
        self.assertEqual(parsed["license"], "0BSD")
        self.assertEqual(parsed["publisher-key"], ed25519.public_key(PUBLISHER_SEED).hex())

    def test_already_logged_exits_three_with_the_same_lines(self):
        self.stub.routes[("POST", "/publish")] = (200, b"object=sha256:cd\nlog_index=2\ntree_size=9\n")
        rc, out, err = self.publish()
        self.assertEqual(rc, 3)
        self.assertEqual(out, "object=sha256:cd\nlog_index=2\ntree_size=9\n")

    def test_every_refusal_is_exit_one_with_nothing_on_stdout(self):
        for status in (400, 401, 403, 409, 502, 500):
            self.stub.routes[("POST", "/publish")] = (status, b"nope\n")
            rc, out, err = self.publish()
            self.assertEqual(rc, 1, status)
            self.assertEqual(out, "", status)
            self.assertIn(str(status), err)

    def test_an_unreachable_registry_or_bad_inputs_are_exit_one(self):
        rc, out, err = run_cli(
            ["publish", self.bundle, "--url", "http://127.0.0.1:1", "--token-file", self.token_file, "--key-file", self.key_file]
        )
        self.assertEqual((rc, out), (1, ""))
        rc, out, err = self.publish("--token-file", os.path.join(self.root, "missing"))
        self.assertEqual((rc, out), (1, ""))
        rc, out, err = self.publish("--key-file", self.token_file)
        self.assertEqual((rc, out), (1, ""))
        rc, out, err = run_cli(
            ["publish", self.root, "--url", self.stub.url, "--token-file", self.token_file, "--key-file", self.key_file]
        )
        self.assertEqual((rc, out), (1, ""))

    def test_a_success_status_with_an_unparsable_body_is_a_failure(self):
        self.stub.routes[("POST", "/publish")] = (201, b"all good\n")
        rc, out, err = self.publish()
        self.assertEqual((rc, out), (1, ""))

    def test_a_trailing_slash_on_the_url_is_harmless(self):
        self.stub.routes[("POST", "/publish")] = (201, b"object=sha256:00\nlog_index=0\ntree_size=1\n")
        rc, out, err = run_cli(
            ["publish", self.bundle, "--url", self.stub.url + "/", "--token-file", self.token_file, "--key-file", self.key_file]
        )
        self.assertEqual(rc, 0, err)


class PartsPublishTest(RegistryCase):
    """An object larger than one part goes up in parts, then the entry with the list of parts."""

    def setUp(self):
        super().setUp()
        self.obj = canonical.canonical_object(self.bundle)
        self.part_bytes = 1000
        self.assertGreater(len(self.obj), 2 * self.part_bytes)
        self.parts = [self.obj[i : i + self.part_bytes] for i in range(0, len(self.obj), self.part_bytes)]
        for part in self.parts:
            self.stub.routes[("PUT", "/publish?part=sha256:" + hashlib.sha256(part).hexdigest())] = (201, b"stored\n")
        self.stub.routes[("POST", "/publish")] = (201, b"object=sha256:00\nlog_index=0\ntree_size=1\n")
        self.saved = publish_module.PART_BYTES
        publish_module.PART_BYTES = self.part_bytes

    def tearDown(self):
        publish_module.PART_BYTES = self.saved
        super().tearDown()

    def test_each_part_is_put_in_order_then_the_entry_names_them(self):
        rc, out, err = self.publish()
        self.assertEqual(rc, 0, err)
        puts = [r for r in self.stub.requests if r[0] == "PUT"]
        self.assertEqual([r[3] for r in puts], self.parts)
        for method, path, headers, body in puts:
            self.assertEqual(headers["Authorization"], "Bearer tok-secret")
        method, path, headers, body = self.stub.requests[-1]
        self.assertEqual((method, path), ("POST", "/publish"))
        head, _, rest = body.partition(b"\n\n")
        lines = head.split(b"\n")
        self.assertEqual(lines[0], b"sond-dist-publish-v2")
        entry_length = int(lines[1].split(b"=")[1])
        self.assertEqual(lines[2], b"parts-length=%d" % (len(rest) - entry_length))
        entry, listing = rest[:entry_length], rest[entry_length:]
        self.assertTrue(logformat.verify_entry(entry))
        self.assertEqual(logformat.parse_entry(entry)["content"], canonical.object_id(self.bundle))
        want = b"".join(hashlib.sha256(p).hexdigest().encode("ascii") + b"\n" for p in self.parts)
        self.assertEqual(listing, want)

    def test_a_refused_part_stops_the_publish(self):
        self.stub.routes[("PUT", "/publish?part=sha256:" + hashlib.sha256(self.parts[1]).hexdigest())] = (413, b"too big\n")
        rc, out, err = self.publish()
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("413", err)
        self.assertFalse([r for r in self.stub.requests if r[0] == "POST"])

    def test_a_part_already_there_is_fine(self):
        self.stub.routes[("PUT", "/publish?part=sha256:" + hashlib.sha256(self.parts[0]).hexdigest())] = (200, b"exists\n")
        rc, out, err = self.publish()
        self.assertEqual(rc, 0, err)

    def test_an_object_within_one_part_still_goes_whole(self):
        publish_module.PART_BYTES = len(self.obj) + 4096
        rc, out, err = self.publish()
        self.assertEqual(rc, 0, err)
        self.assertEqual([r[0] for r in self.stub.requests], ["POST"])
        self.assertTrue(self.stub.requests[0][3].startswith(b"sond-dist-publish-v1\n"))


class VerifyPublishedTest(RegistryCase):
    def setUp(self):
        super().setUp()
        self.object_bytes = canonical.canonical_object(self.bundle)
        self.object_id = canonical.object_id(self.bundle)
        self.stored = self.entry_for(self.object_id)
        other = self.entry_for("sha256:" + "11" * 32, "other", "2.0")
        # a two-entry log: leaf0 = our entry, leaf1 = another one
        self.leaf0 = logformat.leaf_hash(self.stored)
        self.leaf1 = logformat.leaf_hash(other)
        self.root = hashlib.sha256(b"\x01" + self.leaf0 + self.leaf1).digest()
        self.serve()

    def entry_for(self, content, name="toybox-static", version="0.8.15"):
        text = logformat.entry_text(
            name, version, content, ed25519.public_key(PUBLISHER_SEED).hex(), "0BSD", "2026-11-21T12:00:00Z"
        )
        return logformat.sign_entry(PUBLISHER_SEED, text)

    def serve(self, entry=None, obj=None, sth=None, proof=None, key=None):
        entry = self.stored if entry is None else entry
        obj = self.object_bytes if obj is None else obj
        sth = make_sth(2, self.root) if sth is None else sth
        proof = [self.leaf1] if proof is None else proof
        key = ed25519.public_key(LOG_SEED).hex() if key is None else key
        routes = self.stub.routes
        routes[("GET", "/log/lookup?name=toybox-static&version=0.8.15")] = (200, b"index=0\n" + entry)
        routes[("GET", "/o/" + self.object_id)] = (200, obj)
        routes[("GET", "/log/latest")] = (200, sth)
        routes[("GET", "/log/proof/0?size=2")] = (200, "".join(p.hex() + "\n" for p in proof).encode())
        routes[("GET", "/log/key")] = (200, key.encode() + b"\n")

    def verify(self, *extra):
        return run_cli(["verify-published", self.bundle, "--url", self.stub.url] + list(extra))

    def test_a_consistent_registry_verifies(self):
        rc, out, err = self.verify()
        self.assertEqual(rc, 0, err)

    def test_every_request_names_the_client(self):
        # the registry sits behind Cloudflare, which refuses urllib's default User-Agent (1010)
        self.verify()
        self.assertTrue(self.stub.requests)
        for method, path, headers, body in self.stub.requests:
            self.assertRegex(headers.get("User-Agent", ""), r"^sondpkg/\S+", path)

    def test_a_pinned_log_key_is_used_when_given(self):
        rc, out, err = self.verify("--log-key", ed25519.public_key(LOG_SEED).hex())
        self.assertEqual(rc, 0, err)
        rc, out, err = self.verify("--log-key", "00" * 32)
        self.assertEqual(rc, 1)

    def test_a_wrong_inclusion_proof_fails(self):
        self.serve(proof=[b"\x00" * 32])
        self.assertEqual(self.verify()[0], 1)
        self.serve(proof=[])
        self.assertEqual(self.verify()[0], 1)

    def test_a_tampered_object_fails(self):
        self.serve(obj=self.object_bytes + b"x")
        self.assertEqual(self.verify()[0], 1)

    def test_a_tree_head_signed_by_another_key_fails(self):
        other = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
        self.serve(sth=make_sth(2, self.root, other))
        self.assertEqual(self.verify()[0], 1)

    def test_an_entry_for_a_different_object_fails(self):
        self.serve(entry=self.entry_for("sha256:" + "22" * 32))
        self.assertEqual(self.verify()[0], 1)

    def test_a_forged_entry_signature_fails(self):
        forged = self.stored[:-5] + b"0" * 4 + b"\n"
        self.serve(entry=forged)
        self.assertEqual(self.verify()[0], 1)

    def test_a_bundle_that_was_never_logged_fails(self):
        del self.stub.routes[("GET", "/log/lookup?name=toybox-static&version=0.8.15")]
        rc, out, err = self.verify()
        self.assertEqual(rc, 1)
        self.assertIn("404", err)


class SourceLaneTest(RegistryCase):
    """A bundle naming a source_object is published only after its source is logged."""

    SOURCE_BYTES = b"htop corresponding source\n"

    def setUp(self):
        super().setUp()
        source_id = "sha256:" + hashlib.sha256(self.SOURCE_BYTES).hexdigest()
        tree = make_payload_tree(os.path.join(self.root, "htop-tree"))
        licences = [
            make_licence(self.root, "musl-COPYRIGHT", "MIT text\n"),
            make_licence(self.root, "COPYING", "GPL-2.0 text\n"),
            make_licence(self.root, "ncurses-COPYING", "X11 variant text\n"),
        ]
        rc, out, err = run_cli(base_args(
            self.root, tree, os.path.join(self.root, "htop-out"), name="htop", version="3.5.3",
            license="GPL-2.0-or-later AND GPL-2.0-only", license_files=licences,
            bundled=["ncurses 6.6 X11-distribute-modifications-variant", "musl 1.2.5 MIT"],
            source_object=source_id,
        ))
        self.assertEqual(rc, 0, err)
        self.bundle = out.strip()
        self.stub.routes[("POST", "/publish")] = (
            201, b"object=sha256:" + b"ab" * 32 + b"\nlog_index=1\ntree_size=2\n",
        )

    def log_source(self, content_bytes, name="htop-source"):
        content = "sha256:" + hashlib.sha256(content_bytes).hexdigest()
        text = logformat.entry_text(
            name, "3.5.3", content, ed25519.public_key(PUBLISHER_SEED).hex(),
            "GPL-2.0-or-later AND GPL-2.0-only", "2026-11-21T12:00:00Z",
        )
        stored = logformat.sign_entry(PUBLISHER_SEED, text)
        routes = self.stub.routes
        routes[("GET", "/log/lookup?name=htop-source&version=3.5.3")] = (200, b"index=0\n" + stored)
        routes[("GET", "/o/" + content)] = (200, content_bytes)
        routes[("GET", "/log/latest")] = (200, make_sth(1, logformat.leaf_hash(stored)))
        routes[("GET", "/log/proof/0?size=1")] = (200, b"")
        routes[("GET", "/log/key")] = (200, ed25519.public_key(LOG_SEED).hex().encode() + b"\n")

    def posted(self):
        return [r for r in self.stub.requests if r[0] == "POST"]

    def test_publishes_when_the_source_is_logged_with_that_object(self):
        self.log_source(self.SOURCE_BYTES)
        rc, out, err = self.publish()
        self.assertEqual(rc, 0, err)
        self.assertEqual(len(self.posted()), 1)

    def test_refuses_when_the_source_is_not_logged(self):
        rc, out, err = self.publish()
        self.assertNotEqual(rc, 0)
        self.assertIn("htop-source", err)
        self.assertEqual(self.posted(), [])

    def test_refuses_when_the_logged_source_is_another_object(self):
        self.log_source(b"some other tarball\n")
        rc, out, err = self.publish()
        self.assertNotEqual(rc, 0)
        self.assertIn("source_object", err)
        self.assertEqual(self.posted(), [])


class FetchTest(VerifyPublishedTest):
    """`fetch` installs a published package's payload into a sysroot, only once it checks out."""

    def fetch(self, *extra, key=None):
        self.sysroot = os.path.join(self.tmp.name, "sysroot")
        key = ed25519.public_key(LOG_SEED).hex() if key is None else key
        return run_cli(
            ["fetch", "toybox-static", "0.8.15", "--url", self.stub.url, "--log-key", key, "--into", self.sysroot]
            + list(extra)
        )

    def test_the_payload_lands_in_the_sysroot(self):
        rc, out, err = self.fetch()
        self.assertEqual(rc, 0, err)
        with open(os.path.join(self.sysroot, "bin", "toybox"), "rb") as handle:
            self.assertEqual(handle.read(), b"toybox-binary\n")
        self.assertTrue(os.stat(os.path.join(self.sysroot, "bin", "toybox")).st_mode & stat.S_IXUSR)
        self.assertEqual(os.readlink(os.path.join(self.sysroot, "bin", "ls")), "toybox")
        licences = os.path.join(self.sysroot, "share", "licenses", "toybox-static")
        self.assertTrue(os.path.isfile(os.path.join(licences, "LICENSE")))
        self.assertIn("object=" + self.object_id, out)

    def test_it_reports_the_licence_and_the_source_of_what_it_installed(self):
        rc, out, err = self.fetch()
        self.assertEqual(rc, 0, err)
        lines = out.splitlines()
        self.assertIn("license=0BSD", lines)
        self.assertTrue(any(l.startswith("source=github.com/fredyk/toybox-sond@") for l in lines), out)

    def test_the_log_key_is_required(self):
        rc, out, err = run_cli(["fetch", "toybox-static", "0.8.15", "--url", self.stub.url, "--into", self.tmp.name + "/s"])
        self.assertEqual(rc, 2)

    def test_nothing_is_installed_when_a_check_fails(self):
        for kwargs in ({"obj": self.object_bytes + b"x"}, {"proof": [b"\x00" * 32]},
                       {"entry": self.entry_for("sha256:" + "22" * 32)}):
            self.serve(**kwargs)
            rc, out, err = self.fetch()
            self.assertEqual(rc, 1, kwargs)
            self.assertFalse(os.path.exists(os.path.join(self.sysroot, "bin")), kwargs)
        self.serve()
        self.assertEqual(self.fetch(key="00" * 32)[0], 1)
        self.assertFalse(os.path.exists(os.path.join(self.sysroot, "bin")))

    def test_a_different_file_already_in_the_sysroot_is_not_overwritten(self):
        target = os.path.join(self.tmp.name, "sysroot", "bin", "toybox")
        os.makedirs(os.path.dirname(target))
        with open(target, "wb") as handle:
            handle.write(b"another package's file\n")
        self.assertEqual(self.fetch()[0], 1)
        with open(target, "rb") as handle:
            self.assertEqual(handle.read(), b"another package's file\n")

    def test_fetching_the_same_package_twice_is_harmless(self):
        self.assertEqual(self.fetch()[0], 0)
        rc, out, err = self.fetch()
        self.assertEqual(rc, 0, err)
