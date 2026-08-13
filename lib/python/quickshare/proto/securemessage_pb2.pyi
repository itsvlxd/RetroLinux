from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SigScheme(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    HMAC_SHA256: _ClassVar[SigScheme]
    ECDSA_P256_SHA256: _ClassVar[SigScheme]
    RSA2048_SHA256: _ClassVar[SigScheme]

class EncScheme(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    NONE: _ClassVar[EncScheme]
    AES_256_CBC: _ClassVar[EncScheme]

class PublicKeyType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    EC_P256: _ClassVar[PublicKeyType]
    RSA2048: _ClassVar[PublicKeyType]
    DH2048_MODP: _ClassVar[PublicKeyType]
HMAC_SHA256: SigScheme
ECDSA_P256_SHA256: SigScheme
RSA2048_SHA256: SigScheme
NONE: EncScheme
AES_256_CBC: EncScheme
EC_P256: PublicKeyType
RSA2048: PublicKeyType
DH2048_MODP: PublicKeyType

class SecureMessage(_message.Message):
    __slots__ = ("header_and_body", "signature")
    HEADER_AND_BODY_FIELD_NUMBER: _ClassVar[int]
    SIGNATURE_FIELD_NUMBER: _ClassVar[int]
    header_and_body: bytes
    signature: bytes
    def __init__(self, header_and_body: _Optional[bytes] = ..., signature: _Optional[bytes] = ...) -> None: ...

class Header(_message.Message):
    __slots__ = ("signature_scheme", "encryption_scheme", "verification_key_id", "decryption_key_id", "iv", "public_metadata", "associated_data_length")
    SIGNATURE_SCHEME_FIELD_NUMBER: _ClassVar[int]
    ENCRYPTION_SCHEME_FIELD_NUMBER: _ClassVar[int]
    VERIFICATION_KEY_ID_FIELD_NUMBER: _ClassVar[int]
    DECRYPTION_KEY_ID_FIELD_NUMBER: _ClassVar[int]
    IV_FIELD_NUMBER: _ClassVar[int]
    PUBLIC_METADATA_FIELD_NUMBER: _ClassVar[int]
    ASSOCIATED_DATA_LENGTH_FIELD_NUMBER: _ClassVar[int]
    signature_scheme: SigScheme
    encryption_scheme: EncScheme
    verification_key_id: bytes
    decryption_key_id: bytes
    iv: bytes
    public_metadata: bytes
    associated_data_length: int
    def __init__(self, signature_scheme: _Optional[_Union[SigScheme, str]] = ..., encryption_scheme: _Optional[_Union[EncScheme, str]] = ..., verification_key_id: _Optional[bytes] = ..., decryption_key_id: _Optional[bytes] = ..., iv: _Optional[bytes] = ..., public_metadata: _Optional[bytes] = ..., associated_data_length: _Optional[int] = ...) -> None: ...

class HeaderAndBody(_message.Message):
    __slots__ = ("header", "body")
    HEADER_FIELD_NUMBER: _ClassVar[int]
    BODY_FIELD_NUMBER: _ClassVar[int]
    header: Header
    body: bytes
    def __init__(self, header: _Optional[_Union[Header, _Mapping]] = ..., body: _Optional[bytes] = ...) -> None: ...

class HeaderAndBodyInternal(_message.Message):
    __slots__ = ("header", "body")
    HEADER_FIELD_NUMBER: _ClassVar[int]
    BODY_FIELD_NUMBER: _ClassVar[int]
    header: bytes
    body: bytes
    def __init__(self, header: _Optional[bytes] = ..., body: _Optional[bytes] = ...) -> None: ...

class EcP256PublicKey(_message.Message):
    __slots__ = ("x", "y")
    X_FIELD_NUMBER: _ClassVar[int]
    Y_FIELD_NUMBER: _ClassVar[int]
    x: bytes
    y: bytes
    def __init__(self, x: _Optional[bytes] = ..., y: _Optional[bytes] = ...) -> None: ...

class SimpleRsaPublicKey(_message.Message):
    __slots__ = ("n", "e")
    N_FIELD_NUMBER: _ClassVar[int]
    E_FIELD_NUMBER: _ClassVar[int]
    n: bytes
    e: int
    def __init__(self, n: _Optional[bytes] = ..., e: _Optional[int] = ...) -> None: ...

class DhPublicKey(_message.Message):
    __slots__ = ("y",)
    Y_FIELD_NUMBER: _ClassVar[int]
    y: bytes
    def __init__(self, y: _Optional[bytes] = ...) -> None: ...

class GenericPublicKey(_message.Message):
    __slots__ = ("type", "ec_p256_public_key", "rsa2048_public_key", "dh2048_public_key")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    EC_P256_PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    RSA2048_PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    DH2048_PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    type: PublicKeyType
    ec_p256_public_key: EcP256PublicKey
    rsa2048_public_key: SimpleRsaPublicKey
    dh2048_public_key: DhPublicKey
    def __init__(self, type: _Optional[_Union[PublicKeyType, str]] = ..., ec_p256_public_key: _Optional[_Union[EcP256PublicKey, _Mapping]] = ..., rsa2048_public_key: _Optional[_Union[SimpleRsaPublicKey, _Mapping]] = ..., dh2048_public_key: _Optional[_Union[DhPublicKey, _Mapping]] = ...) -> None: ...
