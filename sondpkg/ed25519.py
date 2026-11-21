"""Ed25519 (RFC 8032) in pure Python, standard library only.

This is the reference algorithm of RFC 8032 section 6, written for clarity and for running on a
bare CI runner without pip. It is not constant time: it signs with a publisher's key on the
publisher's own machine, never in a service that an attacker can time.

Key file format: the 32-byte private seed as 64 lowercase hex digits and a newline, mode 0600.
The Ed25519 public key is derived from it (RFC 8032 section 5.1.5).
"""

import hashlib
import os

from sondpkg.errors import PackagerError

_P = 2**255 - 19
_Q = 2**252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_I = pow(2, (_P - 1) // 4, _P)


def _sha512(data):
    return hashlib.sha512(data).digest()


def _inv(x):
    return pow(x, _P - 2, _P)


def _recover_x(y, sign):
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inv(_D * y * y + 1)
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * _I % _P
    if (x * x - x2) % _P != 0:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


_GY = 4 * _inv(5) % _P
_GX = _recover_x(_GY, 0)
_G = (_GX, _GY, 1, _GX * _GY % _P)


def _add(a, b):
    a_, b_ = (a[1] - a[0]) * (b[1] - b[0]) % _P, (a[1] + a[0]) * (b[1] + b[0]) % _P
    c_, d_ = 2 * a[3] * b[3] * _D % _P, 2 * a[2] * b[2] % _P
    e, f, g, h = b_ - a_, d_ - c_, d_ + c_, b_ + a_
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _mul(scalar, point):
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = _add(result, point)
        point = _add(point, point)
        scalar >>= 1
    return result


def _equal(a, b):
    if (a[0] * b[2] - b[0] * a[2]) % _P != 0:
        return False
    return (a[1] * b[2] - b[1] * a[2]) % _P == 0


def _compress(point):
    zinv = _inv(point[2])
    x, y = point[0] * zinv % _P, point[1] * zinv % _P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _decompress(data):
    if len(data) != 32:
        return None
    y = int.from_bytes(data, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    if x is None:
        return None
    return (x, y, 1, x * y % _P)


def _expand(seed):
    if len(seed) != 32:
        raise PackagerError("an Ed25519 seed is 32 bytes")
    digest = _sha512(seed)
    scalar = int.from_bytes(digest[:32], "little")
    scalar &= (1 << 254) - 8
    scalar |= 1 << 254
    return scalar, digest[32:]


def public_key(seed):
    """The 32-byte public key of a 32-byte seed."""
    scalar, _ = _expand(seed)
    return _compress(_mul(scalar, _G))


def sign(seed, message):
    """The 64-byte signature of `message` (any length) under the key `seed`."""
    scalar, prefix = _expand(seed)
    public = _compress(_mul(scalar, _G))
    r = int.from_bytes(_sha512(prefix + message), "little") % _Q
    big_r = _compress(_mul(r, _G))
    h = int.from_bytes(_sha512(big_r + public + message), "little") % _Q
    s = (r + h * scalar) % _Q
    return big_r + int.to_bytes(s, 32, "little")


def verify(public, message, signature):
    """True when `signature` is a valid signature of `message` under `public`."""
    if len(public) != 32 or len(signature) != 64:
        return False
    point = _decompress(public)
    if point is None:
        return False
    big_r = _decompress(signature[:32])
    if big_r is None:
        return False
    s = int.from_bytes(signature[32:], "little")
    if s >= _Q:
        return False
    h = int.from_bytes(_sha512(signature[:32] + public + message), "little") % _Q
    return _equal(_mul(s, _G), _add(big_r, _mul(h, point)))


def read_key_file(path):
    """The 32-byte seed held by a key file (64 hex digits and a newline)."""
    try:
        with open(path, encoding="ascii") as handle:
            text = handle.read().strip()
    except (OSError, UnicodeDecodeError) as error:
        raise PackagerError("cannot read key file %s: %s" % (path, error))
    try:
        seed = bytes.fromhex(text)
    except ValueError:
        seed = b""
    if len(seed) != 32 or text != text.lower():
        raise PackagerError("key file %s must hold 64 lowercase hex digits" % path)
    return seed


def generate_key_file(path):
    """Write a new private key file (mode 0600, never over an existing file); return the
    public key as 64 hex digits."""
    seed = os.urandom(32)
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise PackagerError("refusing to overwrite the existing key file " + path)
    with os.fdopen(descriptor, "w", encoding="ascii") as handle:
        handle.write(seed.hex() + "\n")
    return public_key(seed).hex()
