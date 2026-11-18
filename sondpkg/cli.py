"""Command line entry point for the Sond distro packager."""

import argparse
import sys

from sondpkg import bundle, canon, changemarks
from sondpkg.errors import PackagerError


def _parse_license_files(specs):
    files = []
    for spec in specs:
        source, separator, destination = spec.partition("=")
        files.append((source, destination if separator else None))
    return files


def _cmd_hash_tree(args):
    print(canon.hash_tree(args.tree))
    return 0


def _cmd_build_bundle(args):
    path = bundle.build_bundle(
        name=args.name,
        version=args.version,
        license=args.license,
        source=args.source,
        upstream=args.upstream,
        linkage=args.linkage,
        tier=args.tier,
        tree=args.tree,
        license_files=_parse_license_files(args.license_file),
        source_files=args.source_file,
        out=args.out,
    )
    print(path)
    return 0


def _cmd_verify_bundle(args):
    manifest, digest = bundle.verify_bundle(args.bundle)
    print(
        "ok: %s %s sha256:%s (%d files)"
        % (manifest.name, manifest.version, digest, manifest.files)
    )
    return 0


def _cmd_show(args):
    sys.stdout.write(bundle.show_bundle(args.bundle))
    return 0


def _cmd_check_change_marks(args):
    changemarks.check_change_marks(args.fork, args.commit)
    return 0


def build_parser():
    parser = argparse.ArgumentParser(
        prog="sondpkg",
        description="Sond distro packager: content-addressed bundles (RFC-0018).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    child = subparsers.add_parser(
        "hash-tree", help="print the canonical content hash of a tree"
    )
    child.add_argument("tree")
    child.set_defaults(func=_cmd_hash_tree)

    child = subparsers.add_parser(
        "build-bundle", help="build a content-addressed bundle from a payload tree"
    )
    child.add_argument("--name", required=True)
    child.add_argument("--version", required=True)
    child.add_argument("--license", required=True)
    child.add_argument("--source", required=True)
    child.add_argument("--upstream", required=True)
    child.add_argument("--linkage", required=True)
    child.add_argument("--tier", required=True)
    child.add_argument("--tree", required=True)
    child.add_argument(
        "--license-file",
        action="append",
        default=[],
        metavar="FILE[=DEST]",
        help="licence/notice text to ship; default DEST is "
        "share/licenses/<name>/<basename>",
    )
    child.add_argument(
        "--source-file",
        action="append",
        default=[],
        metavar="FILE",
        help="source tarball, patch or build recipe, recorded by sha256",
    )
    child.add_argument("--out", required=True)
    child.set_defaults(func=_cmd_build_bundle)

    child = subparsers.add_parser(
        "verify-bundle", help="recompute the payload hash and compare with MANIFEST"
    )
    child.add_argument("bundle")
    child.set_defaults(func=_cmd_verify_bundle)

    child = subparsers.add_parser(
        "show", help="print the parsed manifest as key = value"
    )
    child.add_argument("bundle")
    child.set_defaults(func=_cmd_show)

    child = subparsers.add_parser(
        "check-change-marks",
        help="fail if a fork file modified since upstream lacks a dated mark",
    )
    child.add_argument("fork")
    child.add_argument("commit")
    child.set_defaults(func=_cmd_check_change_marks)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except PackagerError as error:
        print("sondpkg: error: " + str(error), file=sys.stderr)
        return 1
