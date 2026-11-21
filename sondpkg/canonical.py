"""The canonical object of a bundle: a deterministic ustar archive of the bundle directory.

The registry stores and identifies a published bundle by the SHA-256 of these bytes
(`sha256:<hex>`). The format is fixed so that any machine builds the same object:

- Entries: every regular file and symbolic link under the bundle directory (MANIFEST and
  payload/...), in byte-wise order of the UTF-8 relative path (the order of `canon.snd`).
  Directories are implied and never written. Anything else (fifo, socket, device) is refused.
- Names: relative, `/` separated, no leading `./`. A name over 100 bytes is split into the ustar
  `prefix` and `name` fields at the leftmost `/` that leaves a name of at most 100 bytes; a path
  over 255 bytes is refused.
- Header (POSIX ustar, magic `ustar\\0`, version `00`): mode 0644, or 0755 when the owner
  execute bit is set (0777 for a symbolic link); uid, gid and mtime 0; empty uname and gname;
  typeflag `0` for a file, `2` for a symbolic link (size 0, linkname = the target, at most 100
  bytes); checksum the usual sum with the field read as spaces.
- Data: file bytes padded with zeros to 512; the archive ends with two zero blocks (1024 bytes).

Nothing about the host leaks in: owners, timestamps, umask and directory order do not matter.
"""

import hashlib
import os
import stat

from sondpkg.errors import PackagerError

_BLOCK = 512


def _octal(value, width):
    return ("%0*o" % (width - 1, value)).encode("ascii") + b"\0"


def _split_name(raw):
    if len(raw) <= 100:
        return b"", raw
    for index, byte in enumerate(raw):
        if byte == 0x2F and index <= 155 and len(raw) - index - 1 <= 100:
            return raw[:index], raw[index + 1 :]
    raise PackagerError("path too long for the canonical object: " + raw.decode("utf-8", "replace"))


def _header(raw_path, mode, size, typeflag, linkname):
    prefix, name = _split_name(raw_path)
    if len(linkname) > 100:
        raise PackagerError("symlink target too long for the canonical object")
    fields = [
        name.ljust(100, b"\0"),
        _octal(mode, 8),
        _octal(0, 8),
        _octal(0, 8),
        _octal(size, 12),
        _octal(0, 12),
        b" " * 8,
        typeflag,
        linkname.ljust(100, b"\0"),
        b"ustar\0",
        b"00",
        b"\0" * 32,
        b"\0" * 32,
        _octal(0, 8),
        _octal(0, 8),
        prefix.ljust(155, b"\0"),
    ]
    header = b"".join(fields).ljust(_BLOCK, b"\0")
    checksum = sum(header)
    return header[:148] + ("%06o" % checksum).encode("ascii") + b"\0 " + header[156:]


def _scan(root):
    entries = []

    def walk(directory, prefix):
        with os.scandir(directory) as iterator:
            for entry in iterator:
                relative = entry.name if not prefix else prefix + "/" + entry.name
                if entry.is_dir(follow_symlinks=False):
                    walk(entry.path, relative)
                else:
                    entries.append((os.fsencode(relative), entry.path))

    walk(os.fspath(root), "")
    entries.sort(key=lambda item: item[0])
    return entries


def canonical_object(bundle):
    """The canonical archive bytes of the bundle directory `bundle`."""
    chunks = []
    for raw_path, path in _scan(bundle):
        info = os.lstat(path)
        if stat.S_ISLNK(info.st_mode):
            chunks.append(_header(raw_path, 0o777, 0, b"2", os.fsencode(os.readlink(path))))
        elif stat.S_ISREG(info.st_mode):
            with open(path, "rb") as handle:
                content = handle.read()
            mode = 0o755 if info.st_mode & stat.S_IXUSR else 0o644
            chunks.append(_header(raw_path, mode, len(content), b"0", b""))
            chunks.append(content)
            chunks.append(b"\0" * (-len(content) % _BLOCK))
        else:
            raise PackagerError("not a regular file or symlink in the bundle: " + path)
    chunks.append(b"\0" * (2 * _BLOCK))
    return b"".join(chunks)


def object_id(bundle):
    """The object identifier `sha256:<hex>` of the bundle directory."""
    return "sha256:" + hashlib.sha256(canonical_object(bundle)).hexdigest()
