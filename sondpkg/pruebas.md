# Entrega del area `packager-rfc18` — empaquetador RFC-0018

## Entorno: una discrepancia con el hallazgo 01, declarada

`01-entorno.md` dice `python3 3.11.15`; medido en este worktree hoy:

```
$ python3 --version
Python 3.12.3
```

El codigo es stdlib puro y compatible con 3.11+ (sin sintaxis nueva), asi que la
suite corre igual. Se reporta porque el hallazgo pide que una contradiccion se
declare, no se rodee en silencio.

## 1. Rojo primero: el vector congelado

Primer test escrito, contra un `canon.hash_tree` que todavia devolvia `None`
(placeholder). La primera ejecucion fue la de los 7 casos de `test_canon.py`
escritos en el mismo paso. Salida literal:

```
FAIL: test_frozen_conformance_vector (test_canon.FrozenVectorTest.test_frozen_conformance_vector)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/home/fred/dev/projects/sond-distro-pkg.oc-packager-rfc18/sondpkg/tests/test_canon.py", line 39, in test_frozen_conformance_vector
    self.assertEqual(
AssertionError: None != '923345ba8a4816339aeac609bef11aaa7dd88d46459bf8886ed8cc68833b3a8d'

----------------------------------------------------------------------
Ran 7 tests in 0.010s

FAILED (failures=3, errors=3)
```

El `Ran 7` (no `Ran 1`) es real: el vector se escribio junto a sus casos hermanos
de canon (orden byte-wise, symlink, fichero vacio, orden de creacion); no se
fabrico un `Ran 1` a posteriori. El vector sigue siendo el primer test del
fichero y el que ata la implementacion a `canon.snd`.

## 2. Verde: suite completa

```
$ cd /home/fred/dev/projects/sond-distro-pkg.oc-packager-rfc18
$ python3 -m unittest discover -s sondpkg/tests -v
...
Ran 43 tests in 0.481s

OK
rc=0
```

Recuento: **43 tests**, rc=0. De ellos, **15 son tests de rechazo** (13 en
`tests/test_rejections.py`, mas "bundle ya existente" y "payload manipulado" en
`tests/test_bundle.py`).

El vector con la CLI real sobre un arbol con `año.snd` y `sub/niño.snd`:

```
$ python3 sondpkg/bin/sondpkg hash-tree <dir-del-vector>
923345ba8a4816339aeac609bef11aaa7dd88d46459bf8886ed8cc68833b3a8d
```

Son los 64 hex del vector de `canon.snd` y del test
(`sondpkg/tests/test_canon.py:14`), no una invencion.

## 3. Bundle de ejemplo

Construido en `/tank/tmp/gr4v5ond7/forks/pkgwork/demo/`. **El
`payload/bin/toybox` de esta demo es un placeholder de texto**: el binario real
lo produce `toolchain-musl` y a las 12:25 `artifacts/bin/` seguia vacio. Los dos
textos de licencia SI son reales, copiados de los clones de upstream
(`toybox-sond/LICENSE`, `musl-sond/COPYRIGHT`), y el tarball de fuente se genero
con `git archive 0.8.15` del clon (sha real `a57b091d...`).

Comando exacto:

```
$ python3 sondpkg/bin/sondpkg build-bundle \
    --name toybox-static --version 0.8.15 --license 0BSD \
    --source github.com/fredyk/toybox-sond@6a0c0ef5eeb2c43e4feef9781398c1718b8bddcb \
    --upstream github.com/landley/toybox@a57b091d05ec366dcd4dd737784c03761cb6a4b1 \
    --linkage "static musl 1.2.5 (MIT)" --tier public \
    --tree /tank/tmp/gr4v5ond7/forks/pkgwork/demo/tree \
    --license-file /tank/tmp/gr4v5ond7/forks/src/toybox-sond/LICENSE=share/licenses/toybox-static/LICENSE \
    --license-file /tank/tmp/gr4v5ond7/forks/src/musl-sond/COPYRIGHT=share/licenses/toybox-static/musl-COPYRIGHT \
    --source-file /tank/tmp/gr4v5ond7/forks/pkgwork/demo/src/toybox-0.8.15.tar.gz \
    --source-file /tank/tmp/gr4v5ond7/forks/pkgwork/demo/src/build-recipe.sh \
    --out /tank/tmp/gr4v5ond7/forks/pkgwork/demo
/tank/tmp/gr4v5ond7/forks/pkgwork/demo/toybox-static-0.8.15-783ab36bb1d9
```

`MANIFEST` resultante:

```
package "toybox-static" {
  version  = "0.8.15"
  license  = "0BSD"
  tier     = "public"
  source   = "github.com/fredyk/toybox-sond@6a0c0ef5eeb2c43e4feef9781398c1718b8bddcb"
  upstream = "github.com/landley/toybox@a57b091d05ec366dcd4dd737784c03761cb6a4b1"
  linkage  = "static musl 1.2.5 (MIT)"
  bundle   = "sha256:783ab36bb1d9b72e3e7499418b9b67f2767ea11f3cb9b57875565e46478e70be"
  files    = 13
  licences = ["share/licenses/toybox-static/LICENSE",
              "share/licenses/toybox-static/musl-COPYRIGHT"]
  sources  = ["sha256:5081af782a964841d66e9ec883a921a63df350c419a1d74dd95160998f04becf toybox-0.8.15.tar.gz",
              "sha256:734e321a0bfd5cfa9c484d169ae55a1c5db9315c7e54bd429ac9c40a09394f6d build-recipe.sh"]
}
```

`show` parsea el mismo fichero con el parser propio:

```
name = toybox-static
version = 0.8.15
license = 0BSD
tier = public
source = github.com/fredyk/toybox-sond@6a0c0ef5eeb2c43e4feef9781398c1718b8bddcb
upstream = github.com/landley/toybox@a57b091d05ec366dcd4dd737784c03761cb6a4b1
linkage = static musl 1.2.5 (MIT)
bundle = sha256:783ab36bb1d9b72e3e7499418b9b67f2767ea11f3cb9b57875565e46478e70be
files = 13
licences = share/licenses/toybox-static/LICENSE, share/licenses/toybox-static/musl-COPYRIGHT
sources = sha256:5081af782a964841d66e9ec883a921a63df350c419a1d74dd95160998f04becf toybox-0.8.15.tar.gz, sha256:734e321a0bfd5cfa9c484d169ae55a1c5db9315c7e54bd429ac9c40a09394f6d build-recipe.sh
```

`verify-bundle` en verde:

```
$ python3 sondpkg/bin/sondpkg verify-bundle .../demo/toybox-static-0.8.15-783ab36bb1d9
ok: toybox-static 0.8.15 sha256:783ab36bb1d9b72e3e7499418b9b67f2767ea11f3cb9b57875565e46478e70be (13 files)
rc=0
```

Y en rojo tras cambiar un byte (copia en `pkgwork/demo-tampered/`, se añadio una
`x` a `payload/bin/toybox`):

```
$ python3 sondpkg/bin/sondpkg verify-bundle .../demo-tampered/toybox-static-0.8.15-783ab36bb1d9
sondpkg: error: bundle hash mismatch: MANIFEST says sha256:783ab36bb1d9b72e3e7499418b9b67f2767ea11f3cb9b57875565e46478e70be, payload hashes to sha256:6d7e2799206dd7e9bfdd95977e6c833d1f48cb5404c86c670e2297bd3c38bd6e
rc=1
```

## 4. Rechazos (uno por linea, con su mensaje)

```
1. musl linkage, no musl-COPYRIGHT: rc=1 :: sondpkg: error: missing licence file share/licenses/toybox-static/musl-COPYRIGHT: linkage "static musl 1.2.5 (MIT)" links musl, whose COPYRIGHT must ship inside the package
2. mksh-static, no LICENCE-MirOS.txt: rc=1 :: sondpkg: error: missing licence file share/licenses/mksh-static/LICENCE-MirOS.txt: mksh-static must ship the verbatim MirOS licence text
3. mksh-static, no UNICODE-NOTICE: rc=1 :: sondpkg: error: missing licence file share/licenses/mksh-static/UNICODE-NOTICE: mksh-static must ship the Unicode notice from expr.c
4. tier staging: rc=1 :: sondpkg: error: unsupported tier "staging": only "public" is defined
5. license GPL-3.0-only: rc=1 :: sondpkg: error: unsupported SPDX license "GPL-3.0-only": allowed are 0BSD, MirOS, MIT
6. license empty: rc=1 :: sondpkg: error: license is empty: expected one of 0BSD, MirOS, MIT
7. source without commit: rc=1 :: sondpkg: error: source must be <repo>@<40-hex commit>, got: "github.com/fredyk/toybox-sond"
8. tree missing: rc=1 :: sondpkg: error: tree does not exist or is not a directory: /tmp/rej-*/nope
9. tree empty: rc=1 :: sondpkg: error: tree is empty: /tmp/rej-*/empty
10. license destination escapes: rc=1 :: sondpkg: error: licence destination must stay inside the package: share/licenses/x/../../escape
11. source file missing: rc=1 :: sondpkg: error: source file not found: /tmp/rej-*/nope.tar.gz
12. bundle already exists: rc=1 :: sondpkg: error: bundle already exists: /tmp/rej-*/ok-out/toybox-static-0.8.15-<H12>
13. verify-bundle after one changed byte: rc=1 :: sondpkg: error: bundle hash mismatch: MANIFEST says sha256:<H>, payload hashes to sha256:<different H>
```

(Los casos 1-12 se generaron con `tempfile.mkdtemp`, no con datos inventados de
upstream. Los `<...>` de 12-13 se abrevian aqui; las lineas completas se
reproducen en la seccion 3 para el 13.)

## 5. Recuento de tests

```
$ grep -rc "def test_" sondpkg/tests/*.py
sondpkg/tests/test_bundle.py:9
sondpkg/tests/test_canon.py:8
sondpkg/tests/test_changemarks.py:5
sondpkg/tests/test_manifest.py:7
sondpkg/tests/test_rejections.py:14
```

43 en total. No hubo refactor, asi que no hay antes/despues distinto.

## Decisiones tomadas (ante dudas del encargo)

- **Version de Python**: se usa la que hay (3.12.3), stdlib, sin features >3.11.
- **`--license-file`**: acepta `<file>` o `<file>=<dest>`; sin `=` el destino es
  `share/licenses/<name>/<basename>` (contrato §D.7); con `=` se exige relativo y
  sin `..`. Cada regla tiene su test.
- **`verify-bundle`**: ademas del sha256, compara el recuento `files`; un payload
  con el mismo hash pero otro numero de entradas no existe, pero el mensaje
  distingue ambos fallos.
- **`check-change-marks`**: sigue literalmente el comando del encargo
  (`git diff --name-status <sha> -- .`); un fichero nuevo solo aparece si esta
  intent-to-add o staged, que es el estado normal de un fork en curso. La marca
  se busca en el contenido (bytes), sin imponer `#` vs `/* */`: el formato lo fija
  el que escribe el fork, el empaquetador solo exige que exista y este fechada.
- **Borrados**: se imprimen (`deleted: <path>`) y no fallan, tal como pide el
  encargo.
- **Demo**: `payload/bin/toybox` es un placeholder de texto porque
  `artifacts/bin/` esta vacio; no se presenta como binario real. Las licencias y
  el tarball de fuente si son los de upstream.
- **Sin red, sin root, sin publicar**: el bundle es un directorio local; no hay
  `dist.sond.dev`, R2, OVH ni `Provides`/`Depends`.

## Limites que quedan fuera de esta area

- No se compilan ni se arrancan binarios (es de `toolchain-musl` / `image-seabios`).
- No se integra ni se hace commit: la integracion entra con `merge --no-ff`.
