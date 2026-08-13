"""UKEY2 handshake crypto and SecureMessage framing for Quick Share.

Derived directly from Google's own source at
https://github.com/google/nearby, including its `third_party/ukey2/ukey2`
submodule (google/ukey2), specifically:

- third_party/ukey2/ukey2/src/main/cpp/src/securegcm/ukey2_handshake.cc
  -- auth-string HKDF (salt "UKEY2 v1 auth") and next-secret HKDF
  (salt "UKEY2 v1 next"); info for both is the concatenated raw on-wire
  ClientInit || ServerInit Ukey2Message bytes. The reference length for
  "UKEY2 v1 auth" is the 13-byte UTF-8 string, per the canonical Java
  implementation (Ukey2Handshake.java) -- this repo's C++ port passes
  `sizeof(literal)` for that one salt, which includes the trailing NUL
  (14 bytes); that appears to be a bug specific to this C++ port, not the
  wire-compatible value, so the 13-byte Python literal here matches Java.
- .../d2d_crypto_ops.cc -- D2D client/server key derivation from the next
  secret, salt = SHA256("D2D"), info = "client"/"server" (literal ASCII).
- .../securemessage/src/securemessage/crypto_ops.cc -- per-message ENC/SIG
  subkey derivation, salt = SHA256("SecureMessage"), info = "ENC:2"/"SIG:1";
  and KeyAgreementSha256, confirming the raw ECDH secret is SHA-256 hashed
  before any HKDF step.
- .../crypto_ops_openssl.cc (ExportEcP256Key/ImportEcP256Key) -- the P-256
  coordinate signed-byte encoding implemented in encode_point_signed below.
"""

from __future__ import annotations

import hashlib
import hmac as hmac_mod
import math
import os
from dataclasses import dataclass

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.hkdf import HKDFExpand
from cryptography.hazmat.primitives import padding as sym_padding

# SHA256(b"D2D") and SHA256(b"SecureMessage") -- literal per upstream, verified to match.
_D2D_SALT = bytes.fromhex("82aa55a0d397f88346ca1cee8d3909b95f13fa7deb1d4ab38376b8256da85510")
_SECUREMESSAGE_SALT = bytes.fromhex("bf9d2a53c63616d75db0a7165b91c1ef73e537f2427405fa23610a4be657642e")

_AUTH_SALT = b"UKEY2 v1 auth"
_NEXT_SALT = b"UKEY2 v1 next"


def hkdf_extract_expand(salt: bytes, ikm: bytes, info: bytes, length: int = 32) -> bytes:
    """HKDF-SHA256 extract-then-expand, argument order matching upstream (salt, ikm, info, len)."""
    prk = hmac_mod.new(salt, ikm, hashlib.sha256).digest()
    return HKDFExpand(algorithm=hashes.SHA256(), length=length, info=info).derive(prk)


def generate_keypair() -> tuple[ec.EllipticCurvePrivateKey, ec.EllipticCurvePublicKey]:
    priv = ec.generate_private_key(ec.SECP256R1())
    return priv, priv.public_key()


def encode_point_signed(coord: bytes) -> bytes:
    """EC P-256 coordinate encoding per securemessage's ExportEcP256Key
    (github.com/google/nearby: third_party/ukey2/ukey2/src/securemessage/src/securemessage/crypto_ops_openssl.cc):
    BN_bn2bin's unsigned minimal-length
    big-endian encoding (leading zero bytes stripped), then a single 0x00
    byte is UNCONDITIONALLY prepended -- "to make sure the byte format is in
    two's complement" per that file's comment -- regardless of whether the
    top bit was already clear. securemessage.proto documents the resulting
    field (EcP256PublicKey.x/y) as "big-endian two's complement (slightly
    wasteful)".
    """
    n = int.from_bytes(coord, "big")
    minimal = n.to_bytes((n.bit_length() + 7) // 8, "big") if n else b""
    return b"\x00" + minimal


def decode_point_unsigned(encoded: bytes, size: int = 32) -> bytes:
    """Inverse of encode_point_signed. BN_bin2bn (ImportEcP256Key) treats its
    input as unsigned big-endian, so it naturally absorbs the prepended 0x00
    (and any other leading zero bytes) -- left-pad the result back to a fixed
    width for reconstructing the EC point.
    """
    n = int.from_bytes(encoded, "big")
    return n.to_bytes(size, "big")


def public_key_xy(pub: ec.EllipticCurvePublicKey) -> tuple[bytes, bytes]:
    nums = pub.public_numbers()
    return nums.x.to_bytes(32, "big"), nums.y.to_bytes(32, "big")


def public_key_from_xy(x: bytes, y: bytes) -> ec.EllipticCurvePublicKey:
    nums = ec.EllipticCurvePublicNumbers(
        int.from_bytes(x, "big"), int.from_bytes(y, "big"), ec.SECP256R1()
    )
    return nums.public_key()


def ecdh_shared_secret(priv: ec.EllipticCurvePrivateKey, peer_pub: ec.EllipticCurvePublicKey) -> bytes:
    """Raw ECDH X-coordinate, then SHA-256 hashed (matches derived_secret = SHA256(dhs))."""
    raw = priv.exchange(ec.ECDH(), peer_pub)
    return hashlib.sha256(raw).digest()


def to_four_digit_pin(auth_string: bytes) -> str:
    """Port of upstream to_four_digit_string: signed-byte, truncating-modulo hash."""
    k_hash_modulo = 9973
    k_hash_base_multiplier = 31
    h = 0
    multiplier = 1
    for b in auth_string:
        signed_b = b - 256 if b >= 128 else b
        h = int(math.fmod(h + signed_b * multiplier, k_hash_modulo))
        multiplier = int(math.fmod(multiplier * k_hash_base_multiplier, k_hash_modulo))
    pin = f"{abs(h):04d}"
    # h is always reduced mod 9973 above, so abs(h) is always in [0, 9972] and
    # this can never actually fail -- a tripwire in one shared place (both
    # server.py's receive flow and send.py's send flow read D2DKeys.pin
    # through here) against a future refactor silently breaking that
    # guarantee and letting something other than 4 plain digits reach the
    # terminal via _interactive_confirm/on_pin.
    assert pin.isdigit() and len(pin) == 4, f"PIN derivation produced non-digit output: {pin!r}"
    return pin


@dataclass
class D2DKeys:
    decrypt_key: bytes
    recv_hmac_key: bytes
    encrypt_key: bytes
    send_hmac_key: bytes
    auth_string: bytes

    @property
    def pin(self) -> str:
        return to_four_digit_pin(self.auth_string)


def derive_d2d_keys(
    shared_secret: bytes, client_init_bytes: bytes, server_init_bytes: bytes, *, is_server: bool = True
) -> D2DKeys:
    """Derive the four D2D session keys from the (already SHA-256'd) ECDH secret.

    ukey_info = raw on-wire ClientInit Ukey2Message bytes || raw on-wire ServerInit
    Ukey2Message bytes -- must be the exact bytes seen on the socket, not a
    re-serialization, since the auth/next HKDF steps are byte-sensitive.

    Everything through the "client"/"server" D2D sub-keys is fully symmetric --
    both roles run the identical derivation (D2DConnectionContextV1::ToConnectionContext,
    third_party/ukey2/ukey2/src/main/cpp/src/securegcm/ukey2_handshake.cc). The
    only role-dependent step is which sub-key becomes "encrypt" vs "decrypt":
    is_server=True (default) matches this project's original server-only
    implementation (encrypt with the server key, decrypt with the client key);
    is_server=False swaps that assignment for the client role.
    """
    ukey_info = client_init_bytes + server_init_bytes

    auth_string = hkdf_extract_expand(_AUTH_SALT, shared_secret, ukey_info, 32)
    next_secret = hkdf_extract_expand(_NEXT_SALT, shared_secret, ukey_info, 32)

    d2d_client = hkdf_extract_expand(_D2D_SALT, next_secret, b"client", 32)
    d2d_server = hkdf_extract_expand(_D2D_SALT, next_secret, b"server", 32)

    own_key, peer_key = (d2d_server, d2d_client) if is_server else (d2d_client, d2d_server)

    encrypt_key = hkdf_extract_expand(_SECUREMESSAGE_SALT, own_key, b"ENC:2", 32)
    send_hmac_key = hkdf_extract_expand(_SECUREMESSAGE_SALT, own_key, b"SIG:1", 32)
    decrypt_key = hkdf_extract_expand(_SECUREMESSAGE_SALT, peer_key, b"ENC:2", 32)
    recv_hmac_key = hkdf_extract_expand(_SECUREMESSAGE_SALT, peer_key, b"SIG:1", 32)

    return D2DKeys(decrypt_key, recv_hmac_key, encrypt_key, send_hmac_key, auth_string)


def aes_cbc_encrypt(key: bytes, iv: bytes, plaintext: bytes) -> bytes:
    padder = sym_padding.PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    return encryptor.update(padded) + encryptor.finalize()


def aes_cbc_decrypt(key: bytes, iv: bytes, ciphertext: bytes) -> bytes:
    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()
    unpadder = sym_padding.PKCS7(128).unpadder()
    return unpadder.update(padded) + unpadder.finalize()


def hmac_sha256(key: bytes, data: bytes) -> bytes:
    return hmac_mod.new(key, data, hashlib.sha256).digest()


def hmac_verify(key: bytes, data: bytes, expected: bytes) -> bool:
    return hmac_mod.compare_digest(hmac_sha256(key, data), expected)


def random_bytes(n: int) -> bytes:
    return os.urandom(n)
