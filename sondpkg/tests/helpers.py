"""Shared fixtures and an in-process CLI runner for the test suite."""

import contextlib
import hashlib
import io
import os

from sondpkg import cli

SHA_A = "a" * 40
SHA_B = "b" * 40


def run_cli(argv):
    """Run the CLI in-process and return ``(rc, stdout, stderr)``."""
    out = io.StringIO()
    err = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = cli.main(list(argv))
        except SystemExit as exit_error:  # argparse usage errors
            rc = exit_error.code if isinstance(exit_error.code, int) else 1
    return rc, out.getvalue(), err.getvalue()


def write_bytes(path, data, mode=None):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)
    if mode is not None:
        os.chmod(path, mode)


def make_payload_tree(root):
    """A tiny binary tree: one real file plus a symlink to it."""
    write_bytes(os.path.join(root, "bin", "toybox"), b"toybox-binary\n", 0o755)
    os.symlink("toybox", os.path.join(root, "bin", "ls"))
    return root


def make_licence(tmp, filename, text="licence text\n"):
    path = os.path.join(tmp, "licences", filename)
    write_bytes(path, text.encode("utf-8"))
    return path


def base_args(tmp, tree, out, **overrides):
    """A valid ``build-bundle`` argument list, with per-test overrides."""
    licence = make_licence(tmp, "LICENSE", "0BSD text\n")
    musl = make_licence(tmp, "musl-COPYRIGHT", "MIT text\n")
    values = {
        "name": "toybox-static",
        "version": "0.8.15",
        "license": "0BSD",
        "source": "github.com/fredyk/toybox-sond@" + SHA_A,
        "upstream": "github.com/landley/toybox@" + SHA_B,
        "linkage": "static musl 1.2.5 (MIT)",
        "tier": "public",
        "tree": tree,
        "license_files": [licence, musl],
        "source_files": [],
        "out": out,
    }
    values.update(overrides)
    argv = [
        "build-bundle",
        "--name", values["name"],
        "--version", values["version"],
        "--license", values["license"],
        "--source", values["source"],
        "--upstream", values["upstream"],
        "--linkage", values["linkage"],
        "--tier", values["tier"],
        "--tree", values["tree"],
        "--out", values["out"],
    ]
    for item in values["license_files"]:
        argv.extend(["--license-file", item])
    for item in values["source_files"]:
        argv.extend(["--source-file", item])
    return argv


def sha256_file(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()
