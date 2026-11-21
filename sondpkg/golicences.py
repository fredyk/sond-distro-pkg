"""Licences of a pure Go binary: the toolchain's and every module it links (dictamen 2.10 (a)).

Input is ``go version -m <binary>``: the exact modules compiled in, replacements resolved.
Each module's licence files are read from the module cache and classified; a module whose
files hold a text this packager does not recognise is refused; several texts oblige them all
(AND). A person's reading that narrows that, or covers a module without a licence file, is pinned below, by module version and by package (what a client compiles from a
module is not what a daemon compiles from it).
"""

import collections
import os
import re

from sondpkg import spdx
from sondpkg.errors import PackagerError

_LICENCE_NAME = re.compile(r"^(licen[cs]e|copying|unlicense)", re.IGNORECASE)
_SHIPPED_NAME = re.compile(r"^(licen[cs]e|copying|unlicense|notice|patents)", re.IGNORECASE)
_NOTICE_NAME = re.compile(r"^notice", re.IGNORECASE)

# Phrases that identify each admitted text, matched on lower-cased, de-marked, re-wrapped text.
_SIGNATURES = (
    ("Apache-2.0", ("apache license", "version 2.0")),
    ("MPL-2.0", ("mozilla public license version 2.0",)),
    ("Unlicense", ("this is free and unencumbered software released into the public domain",)),
    ("MIT", ("permission is hereby granted, free of charge",)),
    ("ISC", ("permission to use, copy, modify, and/or distribute this software for any purpose "
             "with or without fee",)),
    ("ISC", ("permission to use, copy, modify, and distribute this software for any purpose "
             "with or without fee",)),
)
_BSD = "redistribution and use in source and binary forms"
_BSD_THIRD = ("neither the name", "may be used to endorse or promote")
_BSD_BINARY = "redistributions in binary form must reproduce"
# Texts the package rules ask for by name when a linked component is under them.
_NAMED_TEXTS = ("MPL-2.0",)
_ORDER = ("Apache-2.0", "MIT", "BSD-3-Clause", "BSD-2-Clause", "ISC", "Unlicense", "MPL-2.0")

Reviewed = collections.namedtuple("Reviewed", "spdx ignore header_of reason")

# Read by hand, dictamen 2.10 (a). Key: (package or None for any package, module, version).
REVIEWED = {
    (None, "github.com/rootless-containers/proto/go-proto", "v0.0.0-20260207013450-f6ee952d53d9"):
        Reviewed("Apache-2.0", (), "rootlesscontainers.pb.go",
                 "no licence file; the generated source carries the Apache-2.0 header and the "
                 "repository README says the generated sources are Apache-2.0"),
    ("incus", "github.com/cyphar/filepath-securejoin", "v0.7.0"):
        Reviewed("BSD-3-Clause", (), None,
                 "BSD-3-Clause AND MPL-2.0 by file; the client compiles only doc.go, join*.go, "
                 "vfs.go and internal/consts, all BSD-3-Clause"),
    (None, "github.com/opencontainers/go-digest", "v1.0.0"):
        Reviewed("Apache-2.0", ("LICENSE.docs",), None,
                 "LICENSE.docs (CC-BY-SA-4.0) covers the documentation, not the code"),
}


def _normalise(text):
    text = re.sub(r"[#*>`_|]", " ", text.lower())
    return re.sub(r"\s+", " ", text)


def classify(text):
    """The SPDX expression of one licence file (several texts: all of them, AND), or None."""
    plain = _normalise(text)
    found = {spdx_id for spdx_id, phrases in _SIGNATURES if all(p in plain for p in phrases)}
    if _BSD in plain:
        if any(p in plain for p in _BSD_THIRD):
            found.add("BSD-3-Clause")
        elif _BSD_BINARY in plain:
            found.add("BSD-2-Clause")
    return " AND ".join(k for k in _ORDER if k in found) or None


def reviewed(package, module, version):
    return REVIEWED.get((package, module, version)) or REVIEWED.get((None, module, version))


def parse_build_info(text):
    """``(go_version, [(module, version), ...])`` from ``go version -m`` output."""
    lines = text.splitlines()
    first = re.match(r"^\S.*: go(\d+\.\d+(?:\.\d+)?)\s*$", lines[0] if lines else "")
    if not first:
        raise PackagerError("not Go build info (expected the output of go version -m)")
    deps, cgo_disabled = [], False
    for line in lines[1:]:
        fields = line.strip("\n").split("\t")
        if len(fields) < 3 or fields[0] != "":
            continue
        kind = fields[1]
        if kind == "dep":
            deps.append((fields[2], fields[3]))
        elif kind == "=>":
            if fields[2].startswith((".", "/")) or fields[3] == "(devel)":
                raise PackagerError("local replacement %s: its licence cannot be read from the "
                                    "module cache" % fields[2])
            deps[-1] = (fields[2], fields[3])
        elif kind == "build" and fields[2] == "CGO_ENABLED=0":
            cgo_disabled = True
    if not cgo_disabled:
        raise PackagerError("the Go binary was not built with CGO_ENABLED=0: C code is linked "
                            "in and this path does not read its licences")
    return first.group(1), deps


def _escape(module):
    return re.sub(r"[A-Z]", lambda m: "!" + m.group(0).lower(), module)


def _read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def _header(path):
    """The leading comment block of a Go file, up to its first blank line."""
    kept = []
    for line in _read(path).splitlines():
        if not line.startswith("//"):
            break
        kept.append(line)
    return "\n".join(kept) + "\n"


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def collect(package, build_info, modcache, goroot, out, admitted=None):
    """Return ``(bundled_lines, [(source_file, destination), ...])`` for pure Go binaries.

    ``build_info`` is one ``go version -m`` output file or a list of them, one per binary.
    """
    infos = [build_info] if isinstance(build_info, str) else list(build_info)
    go_version, deps = None, []
    for info in infos:
        version, binary_deps = parse_build_info(_read(info))
        if go_version not in (None, version):
            raise PackagerError("the binaries were built by different Go toolchains (%s, %s)"
                                % (go_version, version))
        go_version = version
        deps.extend(d for d in binary_deps if d not in deps)
    base = "share/licenses/%s" % package
    go_licence = os.path.join(goroot, "LICENSE")
    if not os.path.isfile(go_licence) or classify(_read(go_licence)) != "BSD-3-Clause":
        raise PackagerError("the Go toolchain's LICENSE (BSD-3-Clause) is not at " + go_licence)
    bundled = ["go %s BSD-3-Clause" % go_version]
    files = [(go_licence, base + "/go-LICENSE")]
    notices = []
    named = {}
    for module, version in deps:
        label = "%s@%s" % (module, version)
        directory = os.path.join(modcache, _escape(label))
        names = sorted(os.listdir(directory)) if os.path.isdir(directory) else []
        shipped = [n for n in names if _SHIPPED_NAME.match(n)
                   and os.path.isfile(os.path.join(directory, n))]
        entry = reviewed(package, module, version)
        if entry:
            expression = entry.spdx
        else:
            licences = [n for n in shipped if _LICENCE_NAME.match(n)]
            if not licences:
                raise PackagerError("%s has no licence file in the module cache" % label)
            found = {}
            for name in licences:
                kind = classify(_read(os.path.join(directory, name)))
                if kind is None:
                    raise PackagerError("%s: %s is not a licence text this packager recognises"
                                        % (label, name))
                found[name] = kind
                if kind in _NAMED_TEXTS:
                    named.setdefault(kind, os.path.join(directory, name))
            atoms = set()
            for kind in found.values():
                atoms |= spdx.atoms(kind)
            expression = " AND ".join(k for k in _ORDER if k in atoms)
        spdx.check_bundled(expression)
        if admitted is not None and not spdx.atoms(expression) <= set(admitted):
            raise PackagerError("%s is %s, outside the admitted licences" % (label, expression))
        target = "%s/go/%s" % (base, label)
        for name in shipped:
            files.append((os.path.join(directory, name), "%s/%s" % (target, name)))
            if _NOTICE_NAME.match(name):
                notices.append((module, version, _read(os.path.join(directory, name))))
        if entry and entry.header_of:
            header = os.path.join(out, "headers", label, "HEADER-" + entry.header_of)
            _write(header, _header(os.path.join(directory, entry.header_of)))
            files.append((header, "%s/HEADER-%s" % (target, entry.header_of)))
        if not any(dest.startswith(target + "/") for _, dest in files):
            raise PackagerError("%s ships no licence text" % label)
        bundled.append("%s %s %s" % (module, version, expression))
    files.extend((src, "%s/%s" % (base, text)) for text, src in sorted(named.items()))
    if notices:
        aggregated = os.path.join(out, "NOTICE")
        _write(aggregated, "".join(
            "==== %s %s ====\n%s%s\n" % (m, v, t, "" if t.endswith("\n") else "\n")
            for m, v, t in notices))
        files.append((aggregated, base + "/NOTICE"))
    return bundled, files
