"""Command line entry point for the Sond distro packager."""

import argparse
import sys

import os

from sondpkg import (
    bundle, canon, canonical, changemarks, ed25519, golicences, publish, rules, spdx,
)
from sondpkg.errors import PackagerError


def _parse_license_files(specs):
    files = []
    for spec in specs:
        source, separator, destination = spec.partition("=")
        files.append((source, destination if separator else None))
    return files


def _cmd_go_licences(args):
    bundled, files = golicences.collect(
        args.name, args.build_info, args.modcache, args.goroot, args.out, cgo=args.cgo,
        own=tuple(args.own_module))
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "bundled.txt"), "w", encoding="utf-8", newline="\n") as out:
        out.writelines(line + "\n" for line in bundled)
    with open(os.path.join(args.out, "licence-files.txt"), "w", encoding="utf-8",
              newline="\n") as out:
        out.writelines("%s=%s\n" % (os.path.abspath(src), dest) for src, dest in files)
    return 0


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
    for line in publish.fetch(args.name, args.version, args.url, args.log_key, args.into, args.token_file):
        print(line)
    return 0


def _cmd_object_id(args):
    print(canonical.object_id(args.bundle))
    return 0


def _cmd_linux_header_notices(args):
    from sondpkg import linuxheaders

    for relative in linuxheaders.notices_needed(args.include, args.header):
        print(relative)
    return 0


def _cmd_needs_source(args):
    """Exit 0 when the licence or a bundled component obliges the source lane, 1 when not,
    2 when an expression is malformed (an error is never a quiet no)."""
    try:
        expressions = [args.license] + [expr for _, _, expr in rules.parse_bundled(args.bundled)]
        copyleft = any(spdx.is_copyleft(expr) for expr in expressions)
    except PackagerError as error:
        print("sondpkg: error: " + str(error), file=sys.stderr)
        return 2
    return 0 if copyleft else 1


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
        "inclusion proof check out under the pinned log key; stdout: object=, log_index=, tree_size=, "
        "license=, source=",
    )
    child.add_argument("name")
    child.add_argument("version")
    child.add_argument("--url", required=True)
    child.add_argument("--log-key", required=True, help="the log public key (64 hex digits)")
    child.add_argument("--into", required=True, help="the sysroot; created when missing")
    child.add_argument(
        "--token-file", help="a read token for private tiers, sent only on the object download"
    )
    child.set_defaults(func=_cmd_fetch)

    child = subparsers.add_parser("object-id", help="print the object id (sha256:<hex>) of a bundle")
    child.add_argument("bundle")
    child.set_defaults(func=_cmd_object_id)

    child = subparsers.add_parser(
        "needs-source",
        help="exit 0 if the licence or a bundled component is copyleft (GPL, LGPL, MPL), 1 if not, "
        "2 on a malformed expression",
    )
    child.add_argument("license")
    child.add_argument("--bundled", action="append", default=[], help='"name version SPDX-expression"')
    child.set_defaults(func=_cmd_needs_source)

    child = subparsers.add_parser(
        "linux-header-notices",
        help="of the linux-headers headers a binary used, print those whose notice it must carry "
        "(no Linux-syscall-note branch and not under the kernel COPYING)",
    )
    child.add_argument("--include", required=True, help="the include directory the headers are in")
    child.add_argument("header", nargs="*", help="paths relative to --include")
    child.set_defaults(func=_cmd_linux_header_notices)

    child = subparsers.add_parser(
        "go-licences",
        help="read the licences of a pure Go binary's toolchain and modules; write bundled.txt "
        "and licence-files.txt (FILE=DEST lines for --license-file) into --out",
    )
    child.add_argument("--name", required=True, help="the package name")
    child.add_argument("--build-info", required=True, action="append",
                       help="output of go version -m <binary>, once per binary")
    child.add_argument("--modcache", required=True, help="GOMODCACHE the binary was built with")
    child.add_argument("--goroot", required=True, help="GOROOT of the toolchain that built it")
    child.add_argument("--out", required=True)
    child.add_argument("--cgo", action="store_true",
                       help="the binaries may link C code (CGO_ENABLED=1); the caller reads what C "
                       "they link from the link maps")
    child.add_argument("--own-module", action="append", default=[],
                       help="a module of the repository being packaged, replaced by its path in "
                       "the checkout: the package's own source, left out of the licences")
    child.set_defaults(func=_cmd_go_licences)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except PackagerError as error:
        print("sondpkg: error: " + str(error), file=sys.stderr)
        return 1
