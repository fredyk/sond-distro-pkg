"""SPDX licence expressions, checked identifier by identifier.

Grammar (SPDX 2.3 annex D, the subset the distro uses):
    expr     := and-expr ("OR" and-expr)*
    and-expr := with-expr ("AND" with-expr)*
    with-expr:= atom ["WITH" exception] | "(" expr ")"
Operators are upper case. Which identifiers are admitted, and which oblige the source
lane, follows the licence opinion (dictamen-licencias-paquetes-distro-sond.md, section 3.1).
"""

import re

from sondpkg.errors import PackagerError

# Identifiers a package's own licence may use.
LICENSE_ATOMS = frozenset({
    "0BSD", "MirOS", "MIT", "X11-distribute-modifications-variant",
    "GPL-2.0-only", "GPL-2.0-or-later", "Apache-2.0", "LGPL-2.1-or-later",
    # linux-headers (section 2.11): the kernel UAPI headers' LGPL and BSD files
    "LGPL-2.1-only", "BSD-3-Clause",
    # the C libraries incusd links (section 2.10, its table), each published as a package:
    # SQLite, libuv (MIT with tree.h and inet.c), cowsql and raft
    "blessing", "BSD-2-Clause", "ISC", "LGPL-3.0-only",
})
# Identifiers a component linked into the package may use.
BUNDLED_ATOMS = LICENSE_ATOMS | frozenset({
    "LGPL-2.1-only", "LGPL-3.0-only", "MPL-2.0", "BSD-2-Clause", "BSD-3-Clause",
    "ISC", "Unlicense", "blessing",
})
EXCEPTIONS = frozenset({"LGPL-3.0-linking-exception", "Linux-syscall-note"})
_COPYLEFT = re.compile(r"^(GPL|LGPL|MPL)-")
_TOKEN = re.compile(r"\(|\)|[A-Za-z0-9.+-]+")


def _tokens(expression):
    text = expression or ""
    tokens = _TOKEN.findall(text)
    if "".join(tokens) != re.sub(r"\s+", "", text):
        raise PackagerError('malformed SPDX expression "%s"' % expression)
    return tokens


def _parse(expression):
    """Return ``(atoms, exceptions)`` or raise on a malformed expression."""
    tokens = _tokens(expression)
    atoms, exceptions = set(), set()
    pos = 0

    def bad():
        raise PackagerError('malformed SPDX expression "%s"' % expression)

    def operand():
        nonlocal pos
        if pos >= len(tokens):
            bad()
        token = tokens[pos]
        if token == "(":
            pos += 1
            disjunction()
            if pos >= len(tokens) or tokens[pos] != ")":
                bad()
            pos += 1
            return
        if token in (")", "AND", "OR", "WITH") or token.lower() in ("and", "or", "with"):
            bad()
        atoms.add(token)
        pos += 1
        if pos < len(tokens) and tokens[pos] == "WITH":
            pos += 1
            if pos >= len(tokens) or tokens[pos] in ("(", ")", "AND", "OR", "WITH"):
                bad()
            exceptions.add(tokens[pos])
            pos += 1

    def conjunction():
        nonlocal pos
        operand()
        while pos < len(tokens) and tokens[pos] == "AND":
            pos += 1
            operand()

    def disjunction():
        nonlocal pos
        conjunction()
        while pos < len(tokens) and tokens[pos] == "OR":
            pos += 1
            conjunction()

    disjunction()
    if pos != len(tokens):
        bad()
    return atoms, exceptions


def atoms(expression):
    return _parse(expression)[0]


def exceptions(expression):
    return _parse(expression)[1]


def _check(expression, allowed, what):
    found, excepted = _parse(expression)
    unknown = sorted(found - allowed) + sorted(excepted - EXCEPTIONS)
    if unknown:
        raise PackagerError(
            'unsupported SPDX identifier(s) %s in %s "%s"'
            % (", ".join(unknown), what, expression)
        )


def check_license(expression):
    """Reject a package licence with an identifier the distro does not admit."""
    _check(expression, LICENSE_ATOMS, "license")


def check_bundled(expression):
    """Reject a linked component's licence with an identifier not admitted."""
    _check(expression, BUNDLED_ATOMS, "bundled licence")


def is_copyleft(expression):
    """Does any identifier oblige the source lane (GPL, LGPL or MPL)?"""
    return any(_COPYLEFT.match(atom) for atom in atoms(expression))
