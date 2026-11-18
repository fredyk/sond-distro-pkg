# sond-distro-pkg

Tooling to prove that a Sond distro package can be forked, rebuilt statically and repackaged
following the RFC-0018 package shape, and that the resulting utilities run on Sond OS.

Layout (one directory per disjoint work area, one worker per area):

| dir | what it holds | owner |
|---|---|---|
| `toolchain/` | forked upstreams, musl toolchain, reproducible static builds of toybox and mksh | worker `toolchain-musl` |
| `sondpkg/` | the packager: canonical bundle hash, manifest, license obligations, change marks | worker `packager-rfc18` |
| `image/` | production-like disk (GPT + bios_grub, no ESP) and the SeaBIOS boot/serial harness | worker `image-seabios` |
| `verify/` | end-to-end chain: real bundles -> disk -> boot -> utilities over the serial console | worker `integracion-sond` |

The frozen interface between the areas (paths, artifact names, manifest shape, decisions taken
where RFC-0018 is not readable from this machine) lives in the orchestration queue:
`~/dev/projects/.orquestacion-sond-distro-pkg/hallazgos/`. Every worker gets a copy at
`.opencode-hallazgos/`.
