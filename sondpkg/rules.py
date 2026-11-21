"""Mechanical licence and metadata obligations, derived from the measured trees.

Each rule below has a test in ``tests/test_rejections.py``: the packager refuses
the package instead of trusting a README.
"""

import os
import re

from sondpkg.errors import PackagerError

ALLOWED_LICENSES = ("0BSD", "MirOS", "MIT", "X11-distribute-modifications-variant")

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
    if license not in ALLOWED_LICENSES:
        raise PackagerError(
            'unsupported SPDX license "%s": allowed are %s'
            % (license, ", ".join(ALLOWED_LICENSES))
        )
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


def required_licence_files(name, linkage, license=None):
    """Return ``[(path_inside_payload, reason), ...]`` for this package."""
    required = []
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


def check_payload(name, linkage, payload, license=None):
    """Reject ``payload`` if a required licence file is not inside it."""
    for relative, reason in required_licence_files(name, linkage, license):
        path = os.path.join(payload, *relative.split("/"))
        if not os.path.isfile(path):
            raise PackagerError("missing licence file %s: %s" % (relative, reason))
