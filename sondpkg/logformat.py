"""Formats of the dist.sond.dev transparency log, shared with the Sond services.

Log entry (the message a publisher signs; UTF-8, LF, fixed key order):

    sond-dist-entry-v1
    name=<name>                 [a-z0-9][a-z0-9._+-]{0,63}
    version=<version>           [A-Za-z0-9][A-Za-z0-9._+~-]{0,63}
    content=sha256:<64 hex>     the object id of the canonical object
    publisher-key=<64 hex>      the Ed25519 public key
    license=<SPDX id>           [A-Za-z0-9][A-Za-z0-9.+-]{0,63}
    timestamp=<YYYY-MM-DDTHH:MM:SSZ>

The stored entry is that text plus one line `signature=<128 hex>` (Ed25519 over the text bytes).
Its Merkle leaf hash is SHA-256(0x00 || stored entry bytes) (RFC 6962).

Signed tree head (served by `GET /log/latest`):

    sond-dist-log-v1
    size=<n>
    root=<64 hex>
    key=<64 hex>                the log's Ed25519 public key
    signature=<128 hex>         Ed25519 over the 32-byte SHA-256 of the four lines above

Proofs are RFC 6962 audit and consistency paths, verified here with the iterative algorithms of
RFC 9162 section 2.1.
"""

import hashlib
import re

from sondpkg import ed25519
from sondpkg.errors import PackagerError

ENTRY_MAGIC = "sond-dist-entry-v1"
STH_MAGIC = "sond-dist-log-v1"

_NAME = re.compile(r"[a-z0-9][a-z0-9._+-]{0,63}\Z")
_VERSION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._+~-]{0,63}\Z")
_LICENSE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.+-]{0,63}\Z")
_CONTENT = re.compile(r"sha256:[0-9a-f]{64}\Z")
_HEX64 = re.compile(r"[0-9a-f]{64}\Z")
_HEX128 = re.compile(r"[0-9a-f]{128}\Z")
_TIME = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")

_FIELDS = (
    ("name", _NAME),
    ("version", _VERSION),
    ("content", _CONTENT),
    ("publisher-key", _HEX64),
    ("license", _LICENSE),
    ("timestamp", _TIME),
)


def _check(field, pattern, value):
    if not pattern.match(value):
        raise PackagerError("invalid %s: %r" % (field, value))


def entry_text(name, version, content, publisher_key, license, timestamp):
    """The unsigned entry text (what the publisher signs)."""
    values = [name, version, content, publisher_key, license, timestamp]
    lines = [ENTRY_MAGIC]
    for (field, pattern), value in zip(_FIELDS, values):
        _check(field, pattern, value)
        lines.append("%s=%s" % (field, value))
    return ("\n".join(lines) + "\n").encode("ascii")


def sign_entry(seed, text):
    """The stored entry: the text followed by its `signature=` line."""
    return text + b"signature=" + ed25519.sign(seed, text).hex().encode("ascii") + b"\n"


def parse_entry(stored):
    """The fields of a stored entry as a dict (plus `signature` and `text`)."""
    try:
        lines = stored.decode("ascii").split("\n")
    except UnicodeDecodeError:
        raise PackagerError("entry is not ASCII")
    if len(lines) != len(_FIELDS) + 3 or lines[-1] != "" or lines[0] != ENTRY_MAGIC:
        raise PackagerError("malformed log entry")
    parsed = {}
    for line, (field, pattern) in zip(lines[1:-2], _FIELDS):
        key, _, value = line.partition("=")
        if key != field:
            raise PackagerError("malformed log entry: expected %s" % field)
        _check(field, pattern, value)
        parsed[field] = value
    key, _, signature = lines[-2].partition("=")
    if key != "signature" or not _HEX128.match(signature):
        raise PackagerError("malformed log entry signature")
    parsed["signature"] = signature
    parsed["text"] = "\n".join(lines[:-2]).encode("ascii") + b"\n"
    return parsed


def verify_entry(stored):
    """True when the stored entry is well formed and signed by its own publisher-key."""
    try:
        parsed = parse_entry(stored)
    except PackagerError:
        return False
    return ed25519.verify(
        bytes.fromhex(parsed["publisher-key"]),
        parsed["text"],
        bytes.fromhex(parsed["signature"]),
    )


def parse_sth(text):
    """The fields of a signed tree head: size (int), root, key, signature (hex), body."""
    try:
        lines = text.decode("ascii").split("\n")
    except UnicodeDecodeError:
        raise PackagerError("tree head is not ASCII")
    if len(lines) != 6 or lines[-1] != "" or lines[0] != STH_MAGIC:
        raise PackagerError("malformed tree head")
    fields = {}
    for line, expected in zip(lines[1:5], ("size", "root", "key", "signature")):
        key, _, value = line.partition("=")
        if key != expected:
            raise PackagerError("malformed tree head: expected %s" % expected)
        fields[key] = value
    if not fields["size"].isdigit() or not _HEX64.match(fields["root"]):
        raise PackagerError("malformed tree head values")
    if not _HEX64.match(fields["key"]) or not _HEX128.match(fields["signature"]):
        raise PackagerError("malformed tree head key or signature")
    fields["size"] = int(fields["size"])
    fields["body"] = "\n".join(lines[:4]).encode("ascii") + b"\n"
    return fields


def verify_sth(text, log_key_hex):
    """True when the tree head is well formed, names `log_key_hex` and is signed by it."""
    try:
        head = parse_sth(text)
    except PackagerError:
        return False
    if head["key"] != log_key_hex:
        return False
    return ed25519.verify(
        bytes.fromhex(log_key_hex),
        hashlib.sha256(head["body"]).digest(),
        bytes.fromhex(head["signature"]),
    )


def leaf_hash(data):
    return hashlib.sha256(b"\x00" + data).digest()


def _node(left, right):
    return hashlib.sha256(b"\x01" + left + right).digest()


def verify_inclusion(leaf, index, size, proof, root):
    """RFC 9162 section 2.1.3.2."""
    if index >= size:
        return False
    fnum, snum = index, size - 1
    current = leaf
    for sibling in proof:
        if snum == 0:
            return False
        if fnum & 1 or fnum == snum:
            current = _node(sibling, current)
            if not fnum & 1:
                while not fnum & 1 and fnum != 0:
                    fnum >>= 1
                    snum >>= 1
        else:
            current = _node(current, sibling)
        fnum >>= 1
        snum >>= 1
    return snum == 0 and current == root


def verify_consistency(first, second, proof, first_root, second_root):
    """RFC 9162 section 2.1.4.2."""
    if first > second:
        return False
    if first == second:
        return not proof and first_root == second_root
    if first == 0:
        return not proof
    items = list(proof)
    if first & (first - 1) == 0:
        items.insert(0, first_root)
    if not items:
        return False
    fnum, snum = first - 1, second - 1
    while fnum & 1:
        fnum >>= 1
        snum >>= 1
    fr = sr = items[0]
    for node in items[1:]:
        if snum == 0:
            return False
        if fnum & 1 or fnum == snum:
            fr = _node(node, fr)
            sr = _node(node, sr)
            if not fnum & 1:
                while not fnum & 1 and fnum != 0:
                    fnum >>= 1
                    snum >>= 1
        else:
            sr = _node(sr, node)
        fnum >>= 1
        snum >>= 1
    return snum == 0 and fr == first_root and sr == second_root
