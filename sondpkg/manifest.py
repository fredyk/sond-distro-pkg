"""Declarative MANIFEST: fixed-order block, one block per bundle.

The syntax is the block shape quoted from RFC-0018 section 3 (the RFC text itself
is not readable on this machine; see README): UTF-8, LF, one key per line,
``package "<name>" { ... }``. It is deliberately not JSON and not XML.
"""

import json
import re
from dataclasses import dataclass, field

from sondpkg.errors import PackagerError

ORDER = (
    "version",
    "license",
    "tier",
    "source",
    "upstream",
    "linkage",
    "bundle",
    "files",
    "licences",
    "sources",
)
ARRAY_FIELDS = ("licences", "sources")
REQUIRED = ORDER

_PACKAGE_RE = re.compile(r'^package\s+"((?:[^"\\]|\\.)*)"\s*\{$')
_FIELD_RE = re.compile(r"^([a-z][a-z_]*)\s*=\s*(.*)$")


class ManifestError(PackagerError):
    """The MANIFEST text is not a valid manifest."""


@dataclass
class Manifest:
    name: str = ""
    version: str = ""
    license: str = ""
    tier: str = ""
    source: str = ""
    upstream: str = ""
    linkage: str = ""
    bundle: str = ""
    files: int = 0
    licences: list = field(default_factory=list)
    sources: list = field(default_factory=list)


def _quote(value):
    return json.dumps(value, ensure_ascii=False)


def _unquote(token):
    if not (token.startswith('"') and token.endswith('"')):
        raise ManifestError("expected a quoted string, got: " + token)
    try:
        return json.loads(token)
    except ValueError as error:
        raise ManifestError("bad quoted string: " + str(error)) from error


def _array_lines(key, items):
    head = "  %-8s = [" % key
    quoted = [_quote(item) for item in items]
    if not quoted:
        return [head + "]"]
    if len(quoted) == 1:
        return [head + quoted[0] + "]"]
    pad = " " * len(head)
    lines = [head + quoted[0] + ","]
    for item in quoted[1:-1]:
        lines.append(pad + item + ",")
    lines.append(pad + quoted[-1] + "]")
    return lines


def render(manifest):
    """Render one manifest as the fixed-order UTF-8/LF block text."""
    lines = ["package " + _quote(manifest.name) + " {"]
    for key in ORDER:
        value = getattr(manifest, key)
        if key in ARRAY_FIELDS:
            lines.extend(_array_lines(key, value))
        elif key == "files":
            lines.append("  %-8s = %d" % (key, int(value)))
        else:
            lines.append("  %-8s = %s" % (key, _quote(value)))
    lines.append("}")
    return "\n".join(lines) + "\n"


def _parse_array(text):
    items = []
    index = 0
    while index < len(text):
        if text[index] != '"':
            index += 1
            continue
        end = index + 1
        buffer = []
        while end < len(text):
            char = text[end]
            if char == "\\":
                buffer.append(text[end:end + 2])
                end += 2
                continue
            if char == '"':
                break
            buffer.append(char)
            end += 1
        if end >= len(text):
            raise ManifestError("unterminated string in array: " + text)
        items.append(_unquote('"' + "".join(buffer) + '"'))
        index = end + 1
    return items


def _build(raw):
    name = raw.get("name", "")
    if not name:
        raise ManifestError("package block without a name")
    missing = [key for key in REQUIRED if key not in raw]
    if missing:
        raise ManifestError(
            'package "%s" is missing field(s): %s' % (name, ", ".join(missing))
        )
    return Manifest(
        name=name,
        version=raw["version"],
        license=raw["license"],
        tier=raw["tier"],
        source=raw["source"],
        upstream=raw["upstream"],
        linkage=raw["linkage"],
        bundle=raw["bundle"],
        files=raw["files"],
        licences=list(raw["licences"]),
        sources=list(raw["sources"]),
    )


def parse(text):
    """Parse manifest text into a list of :class:`Manifest` blocks."""
    manifests = []
    current = None
    pending = None
    key = None
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if current is None:
            match = _PACKAGE_RE.match(line)
            if not match:
                raise ManifestError(
                    'line %d: expected a package "<name>" { block' % number
                )
            current = {"name": _unquote('"' + match.group(1) + '"')}
            continue
        if pending is not None:
            pending += " " + line
            if "]" in line:
                current[key] = _parse_array(pending)
                pending = None
                key = None
            continue
        if line == "}":
            manifests.append(_build(current))
            current = None
            continue
        match = _FIELD_RE.match(line)
        if not match:
            raise ManifestError("line %d: expected key = value" % number)
        key, value = match.group(1), match.group(2).strip()
        if value.startswith("["):
            if "]" in value:
                current[key] = _parse_array(value)
                key = None
            else:
                pending = value
        elif value.startswith('"'):
            current[key] = _unquote(value)
        elif re.match(r"^-?\d+$", value):
            current[key] = int(value)
        else:
            raise ManifestError(
                "line %d: unsupported value for %s: %s" % (number, key, value)
            )
    if current is not None:
        raise ManifestError("unterminated package block")
    if not manifests:
        raise ManifestError("no package block found")
    return manifests
