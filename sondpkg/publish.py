"""Publishing to, and verifying against, a dist.sond.dev registry.

Publish request (`POST <url>/publish`, `Authorization: Bearer <token>`):

    sond-dist-publish-v1
    entry-length=<L>
    object-length=<M>
    <blank line>
    <L bytes: the stored, signed log entry><M bytes: the canonical object>

Answers: 201 (new) or 200 (the same name, version and object was already logged), body
`object=sha256:<hex>`, `log_index=<n>`, `tree_size=<n>` one per line; 400 invalid, 401 unknown
token, 403 token scope or key mismatch, 409 version already published with another object, 502
a registry back end failed.

Key file (`sondpkg keygen --out F`): the Ed25519 private seed as 64 lowercase hex digits and a
newline, mode 0600. Token file: the Bearer token, surrounding whitespace ignored.
"""

import datetime
import hashlib
import urllib.error
import urllib.parse
import urllib.request

from sondpkg import bundle as bundle_module
from sondpkg import canonical, ed25519, logformat
from sondpkg.errors import PackagerError

EXIT_PUBLISHED = 0
EXIT_ALREADY_LOGGED = 3
TIMEOUT_SECONDS = 60


def _request(method, url, body=None, headers=None):
    """(status, body bytes); a transport failure is a PackagerError, an HTTP error status is not."""
    request = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, OSError) as error:
        raise PackagerError("cannot reach %s: %s" % (url, error))


def _base(url):
    return url.rstrip("/")


def _read_token(path):
    try:
        with open(path, encoding="utf-8") as handle:
            token = handle.read().strip()
    except OSError as error:
        raise PackagerError("cannot read token file %s: %s" % (path, error))
    if not token:
        raise PackagerError("token file %s is empty" % path)
    return token


def frame(entry, obj):
    return (
        b"sond-dist-publish-v1\nentry-length=%d\nobject-length=%d\n\n" % (len(entry), len(obj))
        + entry
        + obj
    )


def _parse_reply(body):
    fields = {}
    for line in body.decode("ascii", "replace").split("\n"):
        key, _, value = line.partition("=")
        if key:
            fields[key] = value
    try:
        object_id = fields["object"]
        index = int(fields["log_index"])
        size = int(fields["tree_size"])
    except (KeyError, ValueError):
        raise PackagerError("the registry answered with an unreadable body")
    if not object_id.startswith("sha256:"):
        raise PackagerError("the registry answered with an unreadable object id")
    return object_id, index, size


def publish(bundle_dir, url, token_file, key_file, now=None):
    """Sign and publish a bundle. Returns (exit code, the three stdout lines)."""
    manifest, _ = bundle_module.verify_bundle(bundle_dir)
    obj = canonical.canonical_object(bundle_dir)
    object_id = "sha256:" + hashlib.sha256(obj).hexdigest()
    seed = ed25519.read_key_file(key_file)
    token = _read_token(token_file)
    stamp = (now or datetime.datetime.now(datetime.timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    text = logformat.entry_text(
        manifest.name, manifest.version, object_id, ed25519.public_key(seed).hex(), manifest.license, stamp
    )
    entry = logformat.sign_entry(seed, text)
    status, body = _request(
        "POST",
        _base(url) + "/publish",
        frame(entry, obj),
        {"Authorization": "Bearer " + token, "Content-Type": "application/octet-stream"},
    )
    if status not in (200, 201):
        raise PackagerError(
            "publish refused with HTTP %d: %s" % (status, body.decode("utf-8", "replace").strip())
        )
    reply_object, index, size = _parse_reply(body)
    lines = ["object=" + reply_object, "log_index=%d" % index, "tree_size=%d" % size]
    return (EXIT_PUBLISHED if status == 201 else EXIT_ALREADY_LOGGED), lines


def _get(url, what):
    status, body = _request("GET", url)
    if status != 200:
        raise PackagerError("%s: HTTP %d from %s" % (what, status, url))
    return body


def verify_published(bundle_dir, url, log_key=None):
    """Check that the bundle is published: entry, object and inclusion in the signed head.

    Raises PackagerError on the first thing that does not check out. Without `log_key` the log
    key is read from the registry itself (integrity only); pass it to anchor the check.
    """
    manifest, _ = bundle_module.verify_bundle(bundle_dir)
    local = canonical.canonical_object(bundle_dir)
    object_id = "sha256:" + hashlib.sha256(local).hexdigest()
    base = _base(url)

    query = urllib.parse.urlencode({"name": manifest.name, "version": manifest.version})
    found = _get(base + "/log/lookup?" + query, "lookup")
    head, _, stored = found.partition(b"\n")
    if not head.startswith(b"index=") or not head[6:].isdigit():
        raise PackagerError("lookup answered with an unreadable body")
    index = int(head[6:])
    if not logformat.verify_entry(stored):
        raise PackagerError("the logged entry does not verify under its publisher key")
    entry = logformat.parse_entry(stored)
    if (entry["name"], entry["version"]) != (manifest.name, manifest.version):
        raise PackagerError("the logged entry is for another name or version")
    if entry["content"] != object_id:
        raise PackagerError(
            "the logged object %s is not this bundle's %s" % (entry["content"], object_id)
        )

    served = _get(base + "/o/" + object_id, "object")
    if hashlib.sha256(served).hexdigest() != object_id[7:] or served != local:
        raise PackagerError("the stored object does not hash to " + object_id)

    key = log_key or _get(base + "/log/key", "log key").decode("ascii", "replace").strip()
    sth_text = _get(base + "/log/latest", "tree head")
    if not logformat.verify_sth(sth_text, key):
        raise PackagerError("the signed tree head does not verify under the log key")
    sth = logformat.parse_sth(sth_text)
    if index >= sth["size"]:
        raise PackagerError("the entry is not inside the signed tree head")
    proof_text = _get(
        "%s/log/proof/%d?size=%d" % (base, index, sth["size"]), "inclusion proof"
    )
    try:
        proof = [bytes.fromhex(line) for line in proof_text.decode("ascii").split("\n") if line]
    except ValueError:
        raise PackagerError("the inclusion proof is unreadable")
    if not logformat.verify_inclusion(
        logformat.leaf_hash(stored), index, sth["size"], proof, bytes.fromhex(sth["root"])
    ):
        raise PackagerError("the inclusion proof does not match the signed root")
    return index, sth["size"]
