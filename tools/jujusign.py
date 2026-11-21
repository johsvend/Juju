"""Signing the Juju community pack (SharedData) so it can be shared player to
player in-game without anyone being able to forge numbers.

RSA-2048, e = 3, PKCS#1 v1.5 with SHA-256. Juju checks a signature without any
division: the signature carries s and q with  s^3 = m + q*n  (m = padded hash),
so the addon only needs big-number multiply/add/compare. The padded block is
compared in full, so the old e=3 tricks against lax padding parsing don't apply.

    python tools/jujusign.py keygen KEYFILE   # once: private key (keep it secret!)
    python tools/jujusign.py pubkey KEYFILE   # prints n for Juju/PubKey.lua

The merge tool signs when the env var JUJU_SIGNING_KEY holds the key file's
content (a GitHub Actions secret).
"""
import hashlib
import json
import secrets
import sys

E = 3
BITS = 2048
DIGEST_INFO = bytes.fromhex("3031300d060960864801650304020105000420")   # SHA-256


def _probable_prime(n, rounds=40):
    if n < 2:
        return False
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0:
            return n == p
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(rounds):
        a = secrets.randbelow(n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def _prime(bits):
    while True:
        c = secrets.randbits(bits) | (1 << (bits - 1)) | (1 << (bits - 2)) | 1
        if c % 3 == 2 and _probable_prime(c):        # gcd(3, c-1) = 1
            return c


def keygen():
    while True:
        p, q = _prime(BITS // 2), _prime(BITS // 2)
        n = p * q
        if p != q and n.bit_length() == BITS:
            break
    lam = (p - 1) * (q - 1) // _gcd(p - 1, q - 1)
    d = pow(E, -1, lam)
    return {"n": format(n, "x"), "d": format(d, "x")}


def _gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def padded(message: bytes, n: int) -> int:
    k = (n.bit_length() + 7) // 8
    t = DIGEST_INFO + hashlib.sha256(message).digest()
    em = b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t
    return int.from_bytes(em, "big")


def sign(message: bytes, key: dict) -> dict:
    n, d = int(key["n"], 16), int(key["d"], 16)
    m = padded(message, n)
    s = pow(m, d, n)
    q, rest = divmod(s ** 3 - m, n)
    assert rest == 0 and s ** 3 == m + q * n
    return {"s": format(s, "x"), "q": format(q, "x")}


def verify(message: bytes, sig: dict, n_hex: str) -> bool:
    n, s, q = int(n_hex, 16), int(sig["s"], 16), int(sig["q"], 16)
    return 0 < s < n and s ** 3 == padded(message, n) + q * n


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "keygen":
        with open(sys.argv[2], "x", encoding="utf-8") as f:     # never overwrite a key
            json.dump(keygen(), f)
        print("nøkkel laget:", sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "pubkey":
        with open(sys.argv[2], encoding="utf-8") as f:
            print(json.load(f)["n"])
    else:
        print(__doc__)
