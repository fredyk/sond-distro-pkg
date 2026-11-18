# sondpkg — Sond distro packager (RFC-0018)

Turns a payload tree into a **content-addressed** package bundle with a
declarative `MANIFEST`, and refuses to build a bundle that breaks the licence
obligations. Python 3 standard library only; no network, no root, no external
packages.

> RFC-0018 is **not readable on this machine**: its symlink under
> `~/dev/projects` dangles and `docs/` stops at rfc-0017. The only authoritative
> text on disk is `lib/any/pkg/canon.snd` (the canonical hash rule and its
> frozen vector). Everything the RFC might have fixed and we cannot read is
> written below as a decision.

## install / run

The tool is a plain Python entry point, no shebang; call it with `python3`:

```
python3 sondpkg/bin/sondpkg <command> [options]
```

## commands

### `hash-tree <tree>`

Prints the canonical SHA-256 (lowercase hex) of every file under `<tree>`.

### `build-bundle`

```
python3 sondpkg/bin/sondpkg build-bundle \
    --name toybox-static --version 0.8.15 --license 0BSD \
    --source github.com/fredyk/toybox-sond@<sha40> \
    --upstream github.com/landley/toybox@<sha40> \
    --linkage "static musl 1.2.5 (MIT)" --tier public \
    --tree <payload-tree> \
    --license-file <file>[=<dest-inside-package>] ... \
    --source-file <tarball-or-patch-or-recipe> ... \
    --out <output-dir>
```

Creates `<out>/<name>-<version>-<H12>/{payload,MANIFEST}` and prints the bundle
path. `H12` is the first 12 hex digits of the payload hash. `--license-file`
defaults its destination to `share/licenses/<name>/<basename>`; an explicit
destination must stay inside the package. `--source-file` is recorded as
`sha256:<64> <basename>`, never as a host path.

### `verify-bundle <bundle>`

Recomputes the payload hash and compares it with `MANIFEST`. Prints `ok` and
exits 0, or rejects with a non-zero exit when a byte changed.

### `show <bundle>`

Prints the parsed manifest as `key = value` lines (arrays joined with `, `).

### `check-change-marks <fork-worktree> <upstream-sha40>`

Runs `git diff --name-status <sha> -- .` in the fork and fails, listing every
modified or added file whose content lacks `Sond change <YYYY-MM-DD>:`. Deleted
files are printed (`deleted: <path>`) but are not a failure. Read-only.

## tests

```
python3 -m unittest discover -s sondpkg/tests -v
```

No network, no root, everything written under a `tempfile`.

## decisions (one line each)

- Hash: the `canon.snd` rule, replicated and tied to its frozen vector by the first test.
- Hash root: `payload/` only; `MANIFEST` is never hashed.
- Symlink: contributes its target string as content.
- Path order: byte-wise on the UTF-8 relative path, never locale.
- Content: byte-for-byte, no newline normalisation, no BOM handling.
- Bundle name: `<name>-<version>-<H12>`; `H12` is carried by the directory name.
- Manifest: UTF-8, LF, one `package "<name>" { ... }` block, fixed key order.
- Manifest parser: the packager's own (`show`/`verify-bundle`); not JSON, not XML.
- Licences: `share/licenses/<name>/<basename>`, upstream file name kept.
- SPDX allowlist: `0BSD`, `MirOS`, `MIT`; anything else is rejected.
- `tier`: only `public` is defined today; anything else is rejected.
- `source`/`upstream`: must be `<repo>@<40-hex commit>`; no default, no invention.
- musl in `linkage`: `share/licenses/<pkg>/musl-COPYRIGHT` must exist or the build is rejected.
- `mksh-static`: `LICENCE-MirOS.txt` and `UNICODE-NOTICE` must exist or the build is rejected.
- Existing bundle: rejected, never overwritten.
- Empty or missing `--tree`: rejected.
- Sources: exactly the `--source-file` list is recorded; for a musl-linked package the caller also passes the musl source tarball (the `musl-COPYRIGHT` presence is what is enforced mechanically).
- Change mark: `Sond change <YYYY-MM-DD>:` anywhere in the file; deletions only reported.
- Package version: the upstream version with no distro suffix (`0.8.15`, `R59`, `1.2.5`).
- `cd` is a shell builtin of mksh, not a shipped `bin/cd`.
- Scope: local bundles only; no upload, no registry, no `Provides`/`Depends` graph.
