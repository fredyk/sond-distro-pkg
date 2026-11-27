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
modified or added file whose content lacks `Modified by the Sond project, <YYYY-MM-DD>`, and fails when the upstream sha is not a commit (`git cat-file -t`). Deleted
files are printed (`deleted: <path>`) but are not a failure. Read-only.

### `keygen --out FILE`

Writes a new Ed25519 private key to FILE (mode 0600, never over an existing file) and prints the
public key as 64 hex digits. **Key file format:** the 32-byte private seed as 64 lowercase hex
digits plus a newline. The first publish of a name fixes its publisher key (TOFU): keep the file.

### `publish <bundle> --url URL --token-file F --key-file F`

Builds the canonical object of the bundle (a deterministic ustar archive, see
`sondpkg/canonical.py`), signs a log entry (name, version, content hash, publisher key, licence,
timestamp) and POSTs both to `URL/publish` with the Bearer token. stdout carries **only**
`object=sha256:<hex>`, `log_index=<n>`, `tree_size=<n>`; everything else goes to stderr.
Exit codes: **0** published, **3** the same name, version and object was already logged (the
three lines are still printed), **1** any other failure.

### `verify-published <bundle> --url URL [--log-key HEX]`

Exits 0 only if the bundle's entry is in the log with a valid publisher signature, names this
bundle's object hash, the stored object hashes to it, and the inclusion proof checks out against
a tree head signed by the log key (`--log-key` pins it; by default the key is asked of the
registry, which proves integrity but not who runs it).

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
- `tier`: `public` (open licences) or `private` (only `LicenseRef-Proprietary`, objects served to a read token); anything else is rejected.
- `source`/`upstream`: must be `<repo>@<40-hex commit>`; no default, no invention.
- musl in `linkage`: `share/licenses/<pkg>/musl-COPYRIGHT` must exist or the build is rejected.
- `mksh-static`: `LICENCE-MirOS.txt` and `UNICODE-NOTICE` must exist or the build is rejected.
- Existing bundle: rejected, never overwritten.
- Empty or missing `--tree`: rejected.
- Sources: exactly the `--source-file` list is recorded; for a musl-linked package the caller also passes the musl source tarball (the `musl-COPYRIGHT` presence is what is enforced mechanically).
- Change mark: `Modified by the Sond project, <YYYY-MM-DD>` anywhere in the file (dictamen, section 3 step 6); deletions only reported.
- Package version: the upstream version with no distro suffix (`0.8.15`, `R59`, `1.2.5`).
- `cd` is a shell builtin of mksh, not a shipped `bin/cd`.
- Scope: local bundles only; no upload, no registry, no `Provides`/`Depends` graph.
