#!/usr/bin/env python3
"""Independent recomputation of the canonical bundle-payload hash.

Implements the canon.snd rule directly: paths relative to the root, ``/``
separated, byte-wise UTF-8 ordering, each file contributing
``u64_le(len(path)) || path || u64_le(len(content)) || content``, symlinks
contributing their target string. It does not import the packager, so the
``bundle = "sha256:..."`` recorded in a MANIFEST is confirmed by a second,
separate implementation.
"""
import hashlib
import os
import struct
import sys


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: canon-hash.py <payload-root>\n")
        return 2
    root = sys.argv[1]
    if not os.path.isdir(root):
        sys.stderr.write("canon-hash.py: no such directory: %s\n" % root)
        return 1
    items = []
    stack = [""]
    while stack:
        prefix = stack.pop()
        base = os.path.join(root, prefix) if prefix else root
        for name in sorted(os.listdir(base)):
            relative = prefix + "/" + name if prefix else name
            path = os.path.join(base, name)
            if os.path.islink(path):
                items.append((relative, os.readlink(path).encode("utf-8")))
            elif os.path.isdir(path):
                stack.append(relative)
            else:
                with open(path, "rb") as handle:
                    items.append((relative, handle.read()))
    items.sort(key=lambda item: item[0].encode("utf-8", "surrogateescape"))
    digest = hashlib.sha256()
    for relative, content in items:
        encoded = relative.encode("utf-8")
        digest.update(struct.pack("<Q", len(encoded)))
        digest.update(encoded)
        digest.update(struct.pack("<Q", len(content)))
        digest.update(content)
    print(digest.hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
