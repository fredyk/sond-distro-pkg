"""Command line entry point for the Sond distro packager."""

import argparse
import sys

from sondpkg import bundle, canon, changemarks, ed25519, publish
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
        bundled=args.bundled,
        source_object=args.source_object or "",
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


def _cmd_keygen(args):
    print(ed25519.generate_key_file(args.out))
    return 0


def _cmd_publish(args):
    code, lines = publish.publish(args.bundle, args.url, args.token_file, args.key_file)
    for line in lines:
        print(line)
    return code


def _cmd_verify_published(args):
    index, size = publish.verify_published(args.bundle, args.url, args.log_key)
    print("ok: logged at index %d, included in the signed tree of %d" % (index, size), file=sys.stderr)
    return 0


def _cmd_fetch(args):
    for line in publish.fetch(args.name, args.version, args.url, args.log_key, args.into):
        print(line)
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
    child.add_argument(
        "--bundled",
        action="append",
        default=[],
        metavar="'NAME VERSION SPDX'",
        help="a component linked into the payload, with its licence (repeatable)",
    )
    child.add_argument(
        "--source-object",
        metavar="sha256:HEX",
        help="the published source bundle of this build (required when copyleft)",
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

    child = subparsers.add_parser(
        "keygen", help="write a new Ed25519 private key file and print its public key"
    )
    child.add_argument("--out", required=True, help="key file to create (mode 0600, never overwritten)")
    child.set_defaults(func=_cmd_keygen)

    child = subparsers.add_parser(
        "publish",
        help="sign a bundle and publish it; stdout: object=, log_index=, tree_size= "
        "(exit 0 published, 3 already logged, 1 any other failure)",
    )
    child.add_argument("bundle")
    child.add_argument("--url", required=True, help="registry base URL, e.g. https://dist.sond.dev")
    child.add_argument("--token-file", required=True, help="file holding the Bearer token")
    child.add_argument("--key-file", required=True, help="Ed25519 private key file (see keygen)")
    child.set_defaults(func=_cmd_publish)

    child = subparsers.add_parser(
        "verify-published",
        help="exit 0 only if the object hash, the entry signature and the inclusion proof "
        "against the signed tree head all check out",
    )
    child.add_argument("bundle")
    child.add_argument("--url", required=True)
    child.add_argument(
        "--log-key", help="the log public key (64 hex digits); default: asked of the registry"
    )
    child.set_defaults(func=_cmd_verify_published)

    child = subparsers.add_parser(
        "fetch",
        help="install a published package's payload into a sysroot, once its entry, object and "
        "inclusion proof check out under the pinned log key; stdout: object=, log_index=, tree_size=",
    )
    child.add_argument("name")
    child.add_argument("version")
    child.add_argument("--url", required=True)
    child.add_argument("--log-key", required=True, help="the log public key (64 hex digits)")
    child.add_argument("--into", required=True, help="the sysroot; created when missing")
    child.set_defaults(func=_cmd_fetch)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except PackagerError as error:
        print("sondpkg: error: " + str(error), file=sys.stderr)
        return 1
