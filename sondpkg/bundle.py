"""Build, verify and display content-addressed package bundles."""

import hashlib
import os
import shutil
import tempfile

from sondpkg import canon, rules
from sondpkg.errors import PackagerError
from sondpkg.manifest import Manifest, parse, render


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _licence_destination(name, source, destination):
    if destination is None:
        return "share/licenses/%s/%s" % (name, os.path.basename(source))
    if destination.startswith(("/", "\\")):
        raise PackagerError(
            "licence destination must be relative to the package: " + destination
        )
    parts = destination.replace("\\", "/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise PackagerError(
            "licence destination must stay inside the package: " + destination
        )
    return "/".join(parts)


def _read_manifest(bundle):
    bundle = os.path.abspath(bundle)
    path = os.path.join(bundle, "MANIFEST")
    if not os.path.isfile(path):
        raise PackagerError("no MANIFEST in bundle: " + bundle)
    with open(path, encoding="utf-8") as handle:
        manifests = parse(handle.read())
    if len(manifests) != 1:
        raise PackagerError(
            "expected exactly one package block in %s, found %d"
            % (path, len(manifests))
        )
    return bundle, manifests[0]


def build_bundle(
    name,
    version,
    license,
    source,
    upstream,
    linkage,
    tier,
    tree,
    license_files,
    source_files,
    out,
):
    """Build ``<out>/<name>-<version>-<H12>/`` and return its path."""
    rules.validate_metadata(name, version, license, source, upstream, linkage, tier)

    tree = os.path.abspath(tree)
    if not os.path.isdir(tree):
        raise PackagerError("tree does not exist or is not a directory: " + tree)
    if not canon.scan(tree):
        raise PackagerError("tree is empty: " + tree)

    sources = []
    for path in source_files:
        path = os.path.abspath(path)
        if not os.path.isfile(path):
            raise PackagerError("source file not found: " + path)
        sources.append(
            "sha256:%s %s" % (sha256_file(path), os.path.basename(path))
        )

    licences = []
    for source_path, destination in license_files:
        source_path = os.path.abspath(source_path)
        if not os.path.isfile(source_path):
            raise PackagerError("licence file not found: " + source_path)
        licences.append(
            _licence_destination(name, source_path, destination)
        )

    os.makedirs(out, exist_ok=True)
    staging = tempfile.mkdtemp(prefix=".sondpkg-", dir=out)
    try:
        payload = os.path.join(staging, "payload")
        shutil.copytree(tree, payload, symlinks=True)

        for (source_path, _), relative in zip(license_files, licences):
            target = os.path.join(payload, *relative.split("/"))
            parent = os.path.dirname(target)
            if parent:
                os.makedirs(parent, exist_ok=True)
            shutil.copyfile(source_path, target)

        rules.check_payload(name, linkage, payload, license)

        entries = canon.scan(payload)
        digest = canon.hash_tree(payload)
        final = os.path.join(out, "%s-%s-%s" % (name, version, digest[:12]))
        if os.path.exists(final):
            raise PackagerError("bundle already exists: " + final)

        manifest = Manifest(
            name=name,
            version=version,
            license=license,
            tier=tier,
            source=source,
            upstream=upstream,
            linkage=linkage,
            bundle="sha256:" + digest,
            files=len(entries),
            licences=licences,
            sources=sources,
        )
        with open(
            os.path.join(staging, "MANIFEST"),
            "w",
            encoding="utf-8",
            newline="\n",
        ) as handle:
            handle.write(render(manifest))

        os.rename(staging, final)
        staging = None
        return final
    finally:
        if staging is not None and os.path.isdir(staging):
            shutil.rmtree(staging)


def verify_bundle(bundle):
    """Recompute the payload hash and compare it with the manifest."""
    bundle, manifest = _read_manifest(bundle)
    payload = os.path.join(bundle, "payload")
    if not os.path.isdir(payload):
        raise PackagerError("no payload/ directory in bundle: " + bundle)
    entries = canon.scan(payload)
    if len(entries) != manifest.files:
        raise PackagerError(
            "file count mismatch: MANIFEST says %d, payload has %d"
            % (manifest.files, len(entries))
        )
    digest = canon.hash_tree(payload)
    expected = "sha256:" + digest
    if manifest.bundle != expected:
        raise PackagerError(
            "bundle hash mismatch: MANIFEST says %s, payload hashes to %s"
            % (manifest.bundle, expected)
        )
    return manifest, digest


def show_bundle(bundle):
    """Return the parsed manifest as ``key = value`` lines."""
    _, manifest = _read_manifest(bundle)
    lines = [
        "name = " + manifest.name,
        "version = " + manifest.version,
        "license = " + manifest.license,
        "tier = " + manifest.tier,
        "source = " + manifest.source,
        "upstream = " + manifest.upstream,
        "linkage = " + manifest.linkage,
        "bundle = " + manifest.bundle,
        "files = " + str(manifest.files),
        "licences = " + ", ".join(manifest.licences),
        "sources = " + ", ".join(manifest.sources),
    ]
    return "\n".join(lines) + "\n"
