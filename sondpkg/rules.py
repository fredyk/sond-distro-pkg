"""Mechanical licence and metadata obligations, derived from the measured trees.

Each rule below has a test in ``tests/test_rejections.py``: the packager refuses
the package instead of trusting a README.
"""

import os
import re

from sondpkg import spdx
from sondpkg.errors import PackagerError

ALLOWED_LICENSES = tuple(sorted(spdx.LICENSE_ATOMS))

# Licences whose notice must travel verbatim with every copy: the package ships
# the upstream file that carries it, under share/licenses/<name>/.
NOTICE_FILES = {"X11-distribute-modifications-variant": "COPYING"}
ALLOWED_TIERS = ("public",)

_COMMIT_RE = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def validate_metadata(name, version, license, source, upstream, linkage, tier):
    """Reject metadata that cannot be published as a Sond package."""
    for field, value in (("name", name), ("version", version), ("linkage", linkage)):
        if not value or not value.strip():
            raise PackagerError("%s is empty" % field)
    if not license or not license.strip():
        raise PackagerError(
            "license is empty: expected one of " + ", ".join(ALLOWED_LICENSES)
        )
    try:
        spdx.check_license(license)
    except PackagerError as error:
        raise PackagerError(
            "%s: allowed identifiers are %s" % (error, ", ".join(ALLOWED_LICENSES))
        ) from error
    if tier not in ALLOWED_TIERS:
        raise PackagerError(
            'unsupported tier "%s": only "public" is defined' % tier
        )
    if not _COMMIT_RE.match(source or ""):
        raise PackagerError(
            'source must be <repo>@<40-hex commit>, got: "%s"' % source
        )
    if not _COMMIT_RE.match(upstream or ""):
        raise PackagerError(
            'upstream must be <repo>@<40-hex commit>, got: "%s"' % upstream
        )


# The source bundle of a package: what it ships is the source, so it needs none of its own.
SOURCE_LINKAGE = "source"
_SOURCE_OBJECT_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_BUNDLED_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._+-]*) (\S+) (.+)$")
# Packages whose linked components are fixed by the licence opinion: anything else
# linked in is refused until its licence has been read (dictamen 2.9).
PINNED_BUNDLED = {"htop": frozenset({"ncurses", "musl"})}
# Texts a linked component's licence obliges the package to carry (dictamen 3.1, point 3).
_BUNDLED_TEXTS = (
    (re.compile(r"^LGPL-2\.1"), ("LGPL-2.1",)),
    (re.compile(r"^LGPL-3\.0"), ("LGPL-3.0", "GPL-3.0")),
    (re.compile(r"^MPL-2\.0"), ("MPL-2.0",)),
)


def parse_bundled(bundled):
    """``["name version licence-expression", ...]`` as ``[(name, version, expr)]``."""
    parsed = []
    for item in bundled or []:
        match = _BUNDLED_RE.match(item or "")
        if not match:
            raise PackagerError(
                'bundled component must be "<name> <version> <SPDX expression>", got: "%s"' % item
            )
        spdx.check_bundled(match.group(3))
        parsed.append(match.groups())
    return parsed


def validate_linking(name, license, linkage, bundled, source_object):
    """What is linked in, and the source lane it obliges (dictamen section 3)."""
    components = parse_bundled(bundled)
    names = {component for component, _, _ in components}
    if components and "musl" in (linkage or "").lower() and "musl" not in names:
        raise PackagerError('linkage "%s" links musl, but bundled does not list it' % linkage)
    pinned = PINNED_BUNDLED.get(name)
    if pinned is not None and names != pinned:
        raise PackagerError(
            "%s may link exactly %s; bundled lists %s"
            % (name, ", ".join(sorted(pinned)), ", ".join(sorted(names)) or "nothing")
        )
    if linkage == SOURCE_LINKAGE:
        return
    copyleft = spdx.is_copyleft(license) or any(spdx.is_copyleft(e) for _, _, e in components)
    if source_object and not _SOURCE_OBJECT_RE.match(source_object):
        raise PackagerError('source_object must be sha256:<64 hex>, got: "%s"' % source_object)
    if copyleft and not source_object:
        raise PackagerError(
            "%s is copyleft or links copyleft code: its corresponding source must be published "
            "first and named by source_object" % name
        )


def required_licence_files(name, linkage, license=None, bundled=None):
    """Return ``[(path_inside_payload, reason), ...]`` for this package."""
    required = []
    if license and any(atom.startswith("GPL-") for atom in spdx.atoms(license)):
        required.append(
            (
                "share/licenses/%s/COPYING" % name,
                "a GPL licence must ship its upstream COPYING unchanged",
            )
        )
    texts = []
    for component, _, expression in parse_bundled(bundled):
        if component == "ncurses":
            required.append(
                (
                    "share/licenses/%s/ncurses-COPYING" % name,
                    "linked ncurses requires its notice in every copy",
                )
            )
        for atom in spdx.atoms(expression):
            for pattern, files in _BUNDLED_TEXTS:
                if pattern.match(atom):
                    texts.extend(f for f in files if f not in texts)
    for text in texts:
        required.append(
            (
                "share/licenses/%s/%s" % (name, text),
                "a linked component is licensed under %s, whose text must ship" % text,
            )
        )
    if license in NOTICE_FILES:
        required.append(
            (
                "share/licenses/%s/%s" % (name, NOTICE_FILES[license]),
                "%s requires its notice in every copy" % license,
            )
        )
    if "musl" in (linkage or "").lower():
        required.append(
            (
                "share/licenses/%s/musl-COPYRIGHT" % name,
                'linkage "%s" links musl, whose COPYRIGHT must ship inside the package'
                % linkage,
            )
        )
    if name == "mksh-static":
        required.append(
            (
                "share/licenses/mksh-static/LICENCE-MirOS.txt",
                "mksh-static must ship the verbatim MirOS licence text",
            )
        )
        required.append(
            (
                "share/licenses/mksh-static/UNICODE-NOTICE",
                "mksh-static must ship the Unicode notice from expr.c",
            )
        )
    return required


def check_payload(name, linkage, payload, license=None, bundled=None):
    """Reject ``payload`` if a required licence file is not inside it."""
    for relative, reason in required_licence_files(name, linkage, license, bundled):
        path = os.path.join(payload, *relative.split("/"))
        if not os.path.isfile(path):
            raise PackagerError("missing licence file %s: %s" % (relative, reason))
