# Pruebas: lo que se ejecutó y lo que salió

Fecha: 2026-11-18 UTC. Host: 6 vCPU, 11 GiB RAM, sin root. `gcc 13.3.0`,
`GNU make 4.3`, sin `musl-gcc` ni `clang` de sistema.

Todo lo de abajo es salida literal de esta máquina. Los dos binarios publicados
están en `/tank/tmp/gr4v5ond7/forks/artifacts/bin/`.

## Datos fijados

| dato | valor |
|---|---|
| `SOURCE_DATE_EPOCH` | `1794960000` = 2026-11-18T00:00:00Z |
| musl tarball | `musl-1.2.5.tar.gz`, 1.080.786 B, sha256 `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4` |
| musl commit | `0784374d561435f7c787a555aeab8ede699ed298` (v1.2.5) |
| toybox commit | `a57b091d05ec366dcd4dd737784c03761cb6a4b1` (tag 0.8.15) |
| mksh commit | `8deec0b465ed59108331b0a112564f2a89156536` (mksh-R59) |

## 1. Prefijo musl 1.2.5

```
$ cd /tmp/tc-work
$ curl -fsSL -o musl-1.2.5.tar.gz https://musl.libc.org/releases/musl-1.2.5.tar.gz
$ sha256sum musl-1.2.5.tar.gz
a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4  musl-1.2.5.tar.gz
$ tar -xzf musl-1.2.5.tar.gz -C src
$ cd src/musl-1.2.5
$ ./configure --prefix=/tmp/tc-work/prefix --disable-shared
$ make -j6 && make install
```

Comprobación:

```
$ /tmp/tc-work/prefix/bin/musl-gcc -static -O2 -o /tmp/tc-work/hi /tmp/tc-work/hi.c
$ /tmp/tc-work/hi
musl-static-ok
$ file /tmp/tc-work/hi
/tmp/tc-work/hi: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, not stripped
```

El prefijo se copió a `/tank/tmp/gr4v5ond7/forks/toolchain` y se reescribieron
`bin/musl-gcc` y `lib/musl-gcc.specs` a esa ruta. Re-probado en su sitio:

```
$ /tank/tmp/gr4v5ond7/forks/toolchain/bin/musl-gcc -static -O2 -o /tmp/tc-work/reloc /tmp/tc-work/reloc.c
$ /tmp/tc-work/reloc
relocated-musl-ok
$ file /tmp/tc-work/reloc
/tmp/tc-work/reloc: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, not stripped
```

## 2. toybox estático

Configuración: `make allnoconfig`, después una línea por símbolo y
`make silentoldconfig`. Símbolos que quedaron en `y`:

```
CONFIG_CAT=y CONFIG_CP=y CONFIG_MV=y CONFIG_ECHO=y CONFIG_GREP=y CONFIG_LS=y
CONFIG_MKDIR=y CONFIG_PS=y CONFIG_RM=y CONFIG_MOUNT=y CONFIG_TOYBOX=y
CONFIG_TOYBOX_LSM_NONE=y CONFIG_TOYBOX_FORK=y
```

(En 0.8.15 no existe el símbolo `CP_MV` que menciona el encargo: el código
compartido de `cp`/`mv` se activa con `CONFIG_CP`/`CONFIG_MV` y no hizo falta
nada más.)

Build, verbatim como lo ejecuta `build-clean.sh`:

```
make CC=/tmp/tc-work/prefix/bin/musl-gcc \
     CFLAGS="-Os -pipe -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=." \
     LDFLAGS="-static -Wl,--build-id=none" -j6
chmod u+w toybox && strip -s toybox && chmod 0755 toybox
```

`chmod u+w` es necesario: toybox se enlaza a sí mismo en modo `0555` y `strip`
se niega a reescribirlo ("unable to copy file 'toybox'; reason: Permission
denied" fue el primer intento, medido).

Salida del binario:

```
$ ./toybox
cat cp echo grep ls mkdir mount mv ps rm
```

## 3. mksh R59 estático

```
$ CC=/tmp/tc-work/prefix/bin/musl-gcc LDSTATIC=-static \
  CFLAGS="-Os -ffile-prefix-map=$PWD=. -fdebug-prefix-map=$PWD=." \
  LDFLAGS="-Wl,--build-id=none" sh Build.sh -r
$ chmod u+w mksh && strip -s mksh && chmod 0755 mksh
$ printf 'cd /tmp\npwd\n' | ./mksh
/tmp
```

## 4. Reproducibilidad: dos builds limpios

Ejecutado con `toolchain/test-reproducible.sh` (que llama dos veces a
`toolchain/build-clean.sh`, cada una sobre una copia recién hecha del árbol en
un directorio distinto, `/tmp/tc-work/a/run.*` y `/tmp/tc-work/b/run.*`).
Salida literal:

```
SOURCE_DATE_EPOCH=1794960000
build A: /tmp/tc-work/a/run.Vq9asB
build B: /tmp/tc-work/b/run.6mb69r
built /tmp/tc-work/a/run.Vq9asB
0fb90081a3988e7394cec90e7fd8557b467199b72e358d739e5a4d77797fe4fb  /tmp/tc-work/a/run.Vq9asB/toybox/toybox
1dec4fdaa9304bdcb70d2c79aa945fee1372a7bc29f8601fc21bbb968ef0a083  /tmp/tc-work/a/run.Vq9asB/mksh/mksh
built /tmp/tc-work/b/run.6mb69r
0fb90081a3988e7394cec90e7fd8557b467199b72e358d739e5a4d77797fe4fb  /tmp/tc-work/b/run.6mb69r/toybox/toybox
1dec4fdaa9304bdcb70d2c79aa945fee1372a7bc29f8601fc21bbb968ef0a083  /tmp/tc-work/b/run.6mb69r/mksh/mksh
---
build-a toybox 0fb90081a3988e7394cec90e7fd8557b467199b72e358d739e5a4d77797fe4fb
build-a mksh   1dec4fdaa9304bdcb70d2c79aa945fee1372a7bc29f8601fc21bbb968ef0a083
build-b toybox 0fb90081a3988e7394cec90e7fd8557b467199b72e358d739e5a4d77797fe4fb
build-b mksh   1dec4fdaa9304bdcb70d2c79aa945fee1372a7bc29f8601fc21bbb968ef0a083
---
REPRODUCIBLE toybox
REPRODUCIBLE mksh
test-reproducible: PASS
```

Los dos sha256 que se publican:

```
toybox 0fb90081a3988e7394cec90e7fd8557b467199b72e358d739e5a4d77797fe4fb
mksh   1dec4fdaa9304bdcb70d2c79aa945fee1372a7bc29f8601fc21bbb968ef0a083
```

Los mismos valores salieron del build original (`/tmp/tc-work/a` y
`/tmp/tc-work/b`, construidos a mano antes de escribir `build-clean.sh`), así
que las dos tandas coinciden.

## 5. Binarios publicados: `file` y gate estático

```
$ file /tank/tmp/gr4v5ond7/forks/artifacts/bin/toybox
/tank/tmp/gr4v5ond7/forks/artifacts/bin/toybox: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, stripped
$ file /tank/tmp/gr4v5ond7/forks/artifacts/bin/mksh
/tank/tmp/gr4v5ond7/forks/artifacts/bin/mksh:   ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, stripped
```

`toolchain/test-static.sh`, salida literal:

```
ok   file(1) reports statically linked: /tank/tmp/gr4v5ond7/forks/artifacts/bin/toybox
ok   file(1) reports statically linked: /tank/tmp/gr4v5ond7/forks/artifacts/bin/mksh
ok   toybox exposes exactly: cat cp echo grep ls mkdir mount mv ps rm
ok   ls -l / -> 1589 bytes
ok   echo writes its argument
ok   cat /etc/hostname -> 'hermes-opencode'
ok   grep -c . /etc/hostname -> 1
ok   ps -> 9098 bytes
ok   mount (no args) -> 6858 bytes
ok   mkdir creates a directory
ok   cp copies content verbatim
ok   mv renames
ok   rm removes a file
ok   mkdir/cp/mv/rm cycle completed (empty dir removed by host rmdir)
ok   mksh builtin cd /tmp + pwd -> /tmp
ok   mksh reports mksh-@(#)MIRBSD KSH R59 2020/04/14
---
test-static: 16 checks, 0 failures
```

## 6. Artefactos

```
artifacts/bin/toybox                                 0755
artifacts/bin/mksh                                   0755
artifacts/toolchain/musl-1.2.5-prefix.tar.gz         prefijo ya reubicado y re-probado
artifacts/repro/build-a.sha256
artifacts/repro/build-b.sha256
artifacts/SHA256SUMS
artifacts/READY-toolchain
```

## Decisiones tomadas (no había con quien consultarlas)

1. **Los builds corren en `/tmp/tc-work`, no en NFS**, porque `/tank/tmp` mide
   0,23 s por fichero pequeño y hay 605 ficheros por árbol. Sólo el resultado
   se copia a los paths del contrato. El binario no depende de la ruta
   (`-ffile-prefix-map`).
2. **musl desde el tarball**, no desde el clon git: el clon tarda >5 min y el
   checkout en NFS está roto. El tarball está clavado por sha256 y corresponde
   al commit `0784374d…`.
3. **`strip -s` después de `chmod u+w`**, el mismo comando en las dos tandas,
   porque toybox se enlaza `0555`. Sin el `chmod`, strip falla; quedó medido.
4. **El prefijo publicado se reubica** a `forks/toolchain` reescribiendo
   `musl-gcc` y `musl-gcc.specs`, y se vuelve a probar allí. El tar de
   `artifacts/toolchain/` es ese prefijo reubicado.
5. **`SOURCE_DATE_EPOCH=1794960000`** (2026-11-18T00:00:00Z), la fecha de este
   área, escrita en `common.sh`.
