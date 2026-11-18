"""Canonical content hash for a directory tree (the canon.snd rule).

The rule, replicated from ``lib/any/pkg/canon.snd``:

- every file under the root enters, with no exceptions or exclusions;
- paths are relative to the root, ``/`` separated, no leading ``./``;
- files are ordered by byte-wise comparison of the UTF-8 path (never locale);
- each file contributes ``u64_le(len(path)) || path || u64_le(len(content)) || content``;
- the digest is the SHA-256 of that concatenation, lowercase hex;
- content is hashed as is: no newline normalisation, no BOM handling.

A symlink contributes the string of its target as content.
"""

import hashlib
import os
import struct


def _content(path):
    if os.path.islink(path):
        return os.readlink(path).encode("utf-8", "surrogateescape")
    with open(path, "rb") as handle:
        return handle.read()


def scan(root):
    """Return ``[(relative_path, content_bytes), ...]`` in canonical order."""
    root = os.fspath(root)
    entries = []

    def walk(directory, prefix):
        with os.scandir(directory) as iterator:
            for entry in iterator:
                relative = entry.name if not prefix else prefix + "/" + entry.name
                if entry.is_dir(follow_symlinks=False):
                    walk(entry.path, relative)
                else:
                    entries.append((relative, _content(entry.path)))

    walk(root, "")
    entries.sort(key=lambda item: item[0].encode("utf-8", "surrogateescape"))
    return entries


def hash_tree(root):
    """Return the lowercase hex SHA-256 of every file under ``root``."""
    digest = hashlib.sha256()
    for relative, content in scan(root):
        path = relative.encode("utf-8", "surrogateescape")
        digest.update(struct.pack("<Q", len(path)))
        digest.update(path)
        digest.update(struct.pack("<Q", len(content)))
        digest.update(content)
    return digest.hexdigest()
