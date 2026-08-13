from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class Ukey2HandshakeCipher(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    RESERVED: _ClassVar[Ukey2HandshakeCipher]
    P256_SHA512: _ClassVar[Ukey2HandshakeCipher]
    CURVE25519_SHA512: _ClassVar[Ukey2HandshakeCipher]
RESERVED: Ukey2HandshakeCipher
P256_SHA512: Ukey2HandshakeCipher
CURVE25519_SHA512: Ukey2HandshakeCipher

class Ukey2Message(_message.Message):
    __slots__ = ("message_type", "message_data")
    class Type(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_DO_NOT_USE: _ClassVar[Ukey2Message.Type]
        ALERT: _ClassVar[Ukey2Message.Type]
        CLIENT_INIT: _ClassVar[Ukey2Message.Type]
        SERVER_INIT: _ClassVar[Ukey2Message.Type]
        CLIENT_FINISH: _ClassVar[Ukey2Message.Type]
    UNKNOWN_DO_NOT_USE: Ukey2Message.Type
    ALERT: Ukey2Message.Type
    CLIENT_INIT: Ukey2Message.Type
    SERVER_INIT: Ukey2Message.Type
    CLIENT_FINISH: Ukey2Message.Type
    MESSAGE_TYPE_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_DATA_FIELD_NUMBER: _ClassVar[int]
    message_type: Ukey2Message.Type
    message_data: bytes
    def __init__(self, message_type: _Optional[_Union[Ukey2Message.Type, str]] = ..., message_data: _Optional[bytes] = ...) -> None: ...

class Ukey2Alert(_message.Message):
    __slots__ = ("type", "error_message")
    class AlertType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        BAD_MESSAGE: _ClassVar[Ukey2Alert.AlertType]
        BAD_MESSAGE_TYPE: _ClassVar[Ukey2Alert.AlertType]
        INCORRECT_MESSAGE: _ClassVar[Ukey2Alert.AlertType]
        BAD_MESSAGE_DATA: _ClassVar[Ukey2Alert.AlertType]
        BAD_VERSION: _ClassVar[Ukey2Alert.AlertType]
        BAD_RANDOM: _ClassVar[Ukey2Alert.AlertType]
        BAD_HANDSHAKE_CIPHER: _ClassVar[Ukey2Alert.AlertType]
        BAD_NEXT_PROTOCOL: _ClassVar[Ukey2Alert.AlertType]
        BAD_PUBLIC_KEY: _ClassVar[Ukey2Alert.AlertType]
        INTERNAL_ERROR: _ClassVar[Ukey2Alert.AlertType]
    BAD_MESSAGE: Ukey2Alert.AlertType
    BAD_MESSAGE_TYPE: Ukey2Alert.AlertType
    INCORRECT_MESSAGE: Ukey2Alert.AlertType
    BAD_MESSAGE_DATA: Ukey2Alert.AlertType
    BAD_VERSION: Ukey2Alert.AlertType
    BAD_RANDOM: Ukey2Alert.AlertType
    BAD_HANDSHAKE_CIPHER: Ukey2Alert.AlertType
    BAD_NEXT_PROTOCOL: Ukey2Alert.AlertType
    BAD_PUBLIC_KEY: Ukey2Alert.AlertType
    INTERNAL_ERROR: Ukey2Alert.AlertType
    TYPE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    type: Ukey2Alert.AlertType
    error_message: str
    def __init__(self, type: _Optional[_Union[Ukey2Alert.AlertType, str]] = ..., error_message: _Optional[str] = ...) -> None: ...

class Ukey2ClientInit(_message.Message):
    __slots__ = ("version", "random", "cipher_commitments", "next_protocol")
    class CipherCommitment(_message.Message):
        __slots__ = ("handshake_cipher", "commitment")
        HANDSHAKE_CIPHER_FIELD_NUMBER: _ClassVar[int]
        COMMITMENT_FIELD_NUMBER: _ClassVar[int]
        handshake_cipher: Ukey2HandshakeCipher
        commitment: bytes
        def __init__(self, handshake_cipher: _Optional[_Union[Ukey2HandshakeCipher, str]] = ..., commitment: _Optional[bytes] = ...) -> None: ...
    VERSION_FIELD_NUMBER: _ClassVar[int]
    RANDOM_FIELD_NUMBER: _ClassVar[int]
    CIPHER_COMMITMENTS_FIELD_NUMBER: _ClassVar[int]
    NEXT_PROTOCOL_FIELD_NUMBER: _ClassVar[int]
    version: int
    random: bytes
    cipher_commitments: _containers.RepeatedCompositeFieldContainer[Ukey2ClientInit.CipherCommitment]
    next_protocol: str
    def __init__(self, version: _Optional[int] = ..., random: _Optional[bytes] = ..., cipher_commitments: _Optional[_Iterable[_Union[Ukey2ClientInit.CipherCommitment, _Mapping]]] = ..., next_protocol: _Optional[str] = ...) -> None: ...

class Ukey2ServerInit(_message.Message):
    __slots__ = ("version", "random", "handshake_cipher", "public_key")
    VERSION_FIELD_NUMBER: _ClassVar[int]
    RANDOM_FIELD_NUMBER: _ClassVar[int]
    HANDSHAKE_CIPHER_FIELD_NUMBER: _ClassVar[int]
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    version: int
    random: bytes
    handshake_cipher: Ukey2HandshakeCipher
    public_key: bytes
    def __init__(self, version: _Optional[int] = ..., random: _Optional[bytes] = ..., handshake_cipher: _Optional[_Union[Ukey2HandshakeCipher, str]] = ..., public_key: _Optional[bytes] = ...) -> None: ...

class Ukey2ClientFinished(_message.Message):
    __slots__ = ("public_key",)
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    public_key: bytes
    def __init__(self, public_key: _Optional[bytes] = ...) -> None: ...
