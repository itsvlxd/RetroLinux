import datetime

from google.protobuf import timestamp_pb2 as _timestamp_pb2
from proto import sharing_enums_pb2 as _sharing_enums_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class FileMetadata(_message.Message):
    __slots__ = ("name", "type", "payload_id", "size", "mime_type", "id", "parent_folder", "attachment_hash", "is_sensitive_content")
    class Type(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[FileMetadata.Type]
        IMAGE: _ClassVar[FileMetadata.Type]
        VIDEO: _ClassVar[FileMetadata.Type]
        ANDROID_APP: _ClassVar[FileMetadata.Type]
        AUDIO: _ClassVar[FileMetadata.Type]
        DOCUMENT: _ClassVar[FileMetadata.Type]
        CONTACT_CARD: _ClassVar[FileMetadata.Type]
    UNKNOWN: FileMetadata.Type
    IMAGE: FileMetadata.Type
    VIDEO: FileMetadata.Type
    ANDROID_APP: FileMetadata.Type
    AUDIO: FileMetadata.Type
    DOCUMENT: FileMetadata.Type
    CONTACT_CARD: FileMetadata.Type
    NAME_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    MIME_TYPE_FIELD_NUMBER: _ClassVar[int]
    ID_FIELD_NUMBER: _ClassVar[int]
    PARENT_FOLDER_FIELD_NUMBER: _ClassVar[int]
    ATTACHMENT_HASH_FIELD_NUMBER: _ClassVar[int]
    IS_SENSITIVE_CONTENT_FIELD_NUMBER: _ClassVar[int]
    name: str
    type: FileMetadata.Type
    payload_id: int
    size: int
    mime_type: str
    id: int
    parent_folder: str
    attachment_hash: int
    is_sensitive_content: bool
    def __init__(self, name: _Optional[str] = ..., type: _Optional[_Union[FileMetadata.Type, str]] = ..., payload_id: _Optional[int] = ..., size: _Optional[int] = ..., mime_type: _Optional[str] = ..., id: _Optional[int] = ..., parent_folder: _Optional[str] = ..., attachment_hash: _Optional[int] = ..., is_sensitive_content: _Optional[bool] = ...) -> None: ...

class TextMetadata(_message.Message):
    __slots__ = ("text_title", "type", "payload_id", "size", "id", "is_sensitive_text")
    class Type(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[TextMetadata.Type]
        TEXT: _ClassVar[TextMetadata.Type]
        URL: _ClassVar[TextMetadata.Type]
        ADDRESS: _ClassVar[TextMetadata.Type]
        PHONE_NUMBER: _ClassVar[TextMetadata.Type]
    UNKNOWN: TextMetadata.Type
    TEXT: TextMetadata.Type
    URL: TextMetadata.Type
    ADDRESS: TextMetadata.Type
    PHONE_NUMBER: TextMetadata.Type
    TEXT_TITLE_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    ID_FIELD_NUMBER: _ClassVar[int]
    IS_SENSITIVE_TEXT_FIELD_NUMBER: _ClassVar[int]
    text_title: str
    type: TextMetadata.Type
    payload_id: int
    size: int
    id: int
    is_sensitive_text: bool
    def __init__(self, text_title: _Optional[str] = ..., type: _Optional[_Union[TextMetadata.Type, str]] = ..., payload_id: _Optional[int] = ..., size: _Optional[int] = ..., id: _Optional[int] = ..., is_sensitive_text: _Optional[bool] = ...) -> None: ...

class WifiCredentialsMetadata(_message.Message):
    __slots__ = ("ssid", "security_type", "payload_id", "id")
    class SecurityType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_SECURITY_TYPE: _ClassVar[WifiCredentialsMetadata.SecurityType]
        OPEN: _ClassVar[WifiCredentialsMetadata.SecurityType]
        WPA_PSK: _ClassVar[WifiCredentialsMetadata.SecurityType]
        WEP: _ClassVar[WifiCredentialsMetadata.SecurityType]
        SAE: _ClassVar[WifiCredentialsMetadata.SecurityType]
    UNKNOWN_SECURITY_TYPE: WifiCredentialsMetadata.SecurityType
    OPEN: WifiCredentialsMetadata.SecurityType
    WPA_PSK: WifiCredentialsMetadata.SecurityType
    WEP: WifiCredentialsMetadata.SecurityType
    SAE: WifiCredentialsMetadata.SecurityType
    SSID_FIELD_NUMBER: _ClassVar[int]
    SECURITY_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    ID_FIELD_NUMBER: _ClassVar[int]
    ssid: str
    security_type: WifiCredentialsMetadata.SecurityType
    payload_id: int
    id: int
    def __init__(self, ssid: _Optional[str] = ..., security_type: _Optional[_Union[WifiCredentialsMetadata.SecurityType, str]] = ..., payload_id: _Optional[int] = ..., id: _Optional[int] = ...) -> None: ...

class AppMetadata(_message.Message):
    __slots__ = ("app_name", "size", "payload_id", "id", "file_name", "file_size", "package_name")
    APP_NAME_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    ID_FIELD_NUMBER: _ClassVar[int]
    FILE_NAME_FIELD_NUMBER: _ClassVar[int]
    FILE_SIZE_FIELD_NUMBER: _ClassVar[int]
    PACKAGE_NAME_FIELD_NUMBER: _ClassVar[int]
    app_name: str
    size: int
    payload_id: _containers.RepeatedScalarFieldContainer[int]
    id: int
    file_name: _containers.RepeatedScalarFieldContainer[str]
    file_size: _containers.RepeatedScalarFieldContainer[int]
    package_name: str
    def __init__(self, app_name: _Optional[str] = ..., size: _Optional[int] = ..., payload_id: _Optional[_Iterable[int]] = ..., id: _Optional[int] = ..., file_name: _Optional[_Iterable[str]] = ..., file_size: _Optional[_Iterable[int]] = ..., package_name: _Optional[str] = ...) -> None: ...

class StreamMetadata(_message.Message):
    __slots__ = ("description", "package_name", "payload_id", "attributed_app_name")
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    PACKAGE_NAME_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    ATTRIBUTED_APP_NAME_FIELD_NUMBER: _ClassVar[int]
    description: str
    package_name: str
    payload_id: int
    attributed_app_name: str
    def __init__(self, description: _Optional[str] = ..., package_name: _Optional[str] = ..., payload_id: _Optional[int] = ..., attributed_app_name: _Optional[str] = ...) -> None: ...

class Frame(_message.Message):
    __slots__ = ("version", "v1")
    class Version(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_VERSION: _ClassVar[Frame.Version]
        V1: _ClassVar[Frame.Version]
    UNKNOWN_VERSION: Frame.Version
    V1: Frame.Version
    VERSION_FIELD_NUMBER: _ClassVar[int]
    V1_FIELD_NUMBER: _ClassVar[int]
    version: Frame.Version
    v1: V1Frame
    def __init__(self, version: _Optional[_Union[Frame.Version, str]] = ..., v1: _Optional[_Union[V1Frame, _Mapping]] = ...) -> None: ...

class V1Frame(_message.Message):
    __slots__ = ("type", "introduction", "connection_response", "paired_key_encryption", "paired_key_result", "certificate_info", "progress_update", "bindings")
    class FrameType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_FRAME_TYPE: _ClassVar[V1Frame.FrameType]
        INTRODUCTION: _ClassVar[V1Frame.FrameType]
        RESPONSE: _ClassVar[V1Frame.FrameType]
        PAIRED_KEY_ENCRYPTION: _ClassVar[V1Frame.FrameType]
        PAIRED_KEY_RESULT: _ClassVar[V1Frame.FrameType]
        CERTIFICATE_INFO: _ClassVar[V1Frame.FrameType]
        CANCEL: _ClassVar[V1Frame.FrameType]
        PROGRESS_UPDATE: _ClassVar[V1Frame.FrameType]
        BINDINGS: _ClassVar[V1Frame.FrameType]
    UNKNOWN_FRAME_TYPE: V1Frame.FrameType
    INTRODUCTION: V1Frame.FrameType
    RESPONSE: V1Frame.FrameType
    PAIRED_KEY_ENCRYPTION: V1Frame.FrameType
    PAIRED_KEY_RESULT: V1Frame.FrameType
    CERTIFICATE_INFO: V1Frame.FrameType
    CANCEL: V1Frame.FrameType
    PROGRESS_UPDATE: V1Frame.FrameType
    BINDINGS: V1Frame.FrameType
    TYPE_FIELD_NUMBER: _ClassVar[int]
    INTRODUCTION_FIELD_NUMBER: _ClassVar[int]
    CONNECTION_RESPONSE_FIELD_NUMBER: _ClassVar[int]
    PAIRED_KEY_ENCRYPTION_FIELD_NUMBER: _ClassVar[int]
    PAIRED_KEY_RESULT_FIELD_NUMBER: _ClassVar[int]
    CERTIFICATE_INFO_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_UPDATE_FIELD_NUMBER: _ClassVar[int]
    BINDINGS_FIELD_NUMBER: _ClassVar[int]
    type: V1Frame.FrameType
    introduction: IntroductionFrame
    connection_response: ConnectionResponseFrame
    paired_key_encryption: PairedKeyEncryptionFrame
    paired_key_result: PairedKeyResultFrame
    certificate_info: CertificateInfoFrame
    progress_update: ProgressUpdateFrame
    bindings: BindingFrame
    def __init__(self, type: _Optional[_Union[V1Frame.FrameType, str]] = ..., introduction: _Optional[_Union[IntroductionFrame, _Mapping]] = ..., connection_response: _Optional[_Union[ConnectionResponseFrame, _Mapping]] = ..., paired_key_encryption: _Optional[_Union[PairedKeyEncryptionFrame, _Mapping]] = ..., paired_key_result: _Optional[_Union[PairedKeyResultFrame, _Mapping]] = ..., certificate_info: _Optional[_Union[CertificateInfoFrame, _Mapping]] = ..., progress_update: _Optional[_Union[ProgressUpdateFrame, _Mapping]] = ..., bindings: _Optional[_Union[BindingFrame, _Mapping]] = ...) -> None: ...

class IntroductionFrame(_message.Message):
    __slots__ = ("file_metadata", "text_metadata", "required_package", "wifi_credentials_metadata", "app_metadata", "start_transfer", "stream_metadata", "use_case", "preview_payload_ids", "transfer_id")
    class SharingUseCase(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[IntroductionFrame.SharingUseCase]
        NEARBY_SHARE: _ClassVar[IntroductionFrame.SharingUseCase]
        REMOTE_COPY: _ClassVar[IntroductionFrame.SharingUseCase]
        TAP_TO_SHARE: _ClassVar[IntroductionFrame.SharingUseCase]
        FILE_SYNC: _ClassVar[IntroductionFrame.SharingUseCase]
    UNKNOWN: IntroductionFrame.SharingUseCase
    NEARBY_SHARE: IntroductionFrame.SharingUseCase
    REMOTE_COPY: IntroductionFrame.SharingUseCase
    TAP_TO_SHARE: IntroductionFrame.SharingUseCase
    FILE_SYNC: IntroductionFrame.SharingUseCase
    FILE_METADATA_FIELD_NUMBER: _ClassVar[int]
    TEXT_METADATA_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_PACKAGE_FIELD_NUMBER: _ClassVar[int]
    WIFI_CREDENTIALS_METADATA_FIELD_NUMBER: _ClassVar[int]
    APP_METADATA_FIELD_NUMBER: _ClassVar[int]
    START_TRANSFER_FIELD_NUMBER: _ClassVar[int]
    STREAM_METADATA_FIELD_NUMBER: _ClassVar[int]
    USE_CASE_FIELD_NUMBER: _ClassVar[int]
    PREVIEW_PAYLOAD_IDS_FIELD_NUMBER: _ClassVar[int]
    TRANSFER_ID_FIELD_NUMBER: _ClassVar[int]
    file_metadata: _containers.RepeatedCompositeFieldContainer[FileMetadata]
    text_metadata: _containers.RepeatedCompositeFieldContainer[TextMetadata]
    required_package: str
    wifi_credentials_metadata: _containers.RepeatedCompositeFieldContainer[WifiCredentialsMetadata]
    app_metadata: _containers.RepeatedCompositeFieldContainer[AppMetadata]
    start_transfer: bool
    stream_metadata: _containers.RepeatedCompositeFieldContainer[StreamMetadata]
    use_case: IntroductionFrame.SharingUseCase
    preview_payload_ids: _containers.RepeatedScalarFieldContainer[int]
    transfer_id: str
    def __init__(self, file_metadata: _Optional[_Iterable[_Union[FileMetadata, _Mapping]]] = ..., text_metadata: _Optional[_Iterable[_Union[TextMetadata, _Mapping]]] = ..., required_package: _Optional[str] = ..., wifi_credentials_metadata: _Optional[_Iterable[_Union[WifiCredentialsMetadata, _Mapping]]] = ..., app_metadata: _Optional[_Iterable[_Union[AppMetadata, _Mapping]]] = ..., start_transfer: _Optional[bool] = ..., stream_metadata: _Optional[_Iterable[_Union[StreamMetadata, _Mapping]]] = ..., use_case: _Optional[_Union[IntroductionFrame.SharingUseCase, str]] = ..., preview_payload_ids: _Optional[_Iterable[int]] = ..., transfer_id: _Optional[str] = ...) -> None: ...

class ProgressUpdateFrame(_message.Message):
    __slots__ = ("progress", "start_transfer")
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    START_TRANSFER_FIELD_NUMBER: _ClassVar[int]
    progress: float
    start_transfer: bool
    def __init__(self, progress: _Optional[float] = ..., start_transfer: _Optional[bool] = ...) -> None: ...

class BindingFrame(_message.Message):
    __slots__ = ("binding_request", "binding_response")
    BINDING_REQUEST_FIELD_NUMBER: _ClassVar[int]
    BINDING_RESPONSE_FIELD_NUMBER: _ClassVar[int]
    binding_request: BindingRequest
    binding_response: BindingResponse
    def __init__(self, binding_request: _Optional[_Union[BindingRequest, _Mapping]] = ..., binding_response: _Optional[_Union[BindingResponse, _Mapping]] = ...) -> None: ...

class BindingRequest(_message.Message):
    __slots__ = ("binding_id", "type", "cert_ids")
    class Type(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[BindingRequest.Type]
        FILESYNC: _ClassVar[BindingRequest.Type]
    UNKNOWN: BindingRequest.Type
    FILESYNC: BindingRequest.Type
    BINDING_ID_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    CERT_IDS_FIELD_NUMBER: _ClassVar[int]
    binding_id: str
    type: BindingRequest.Type
    cert_ids: _containers.RepeatedScalarFieldContainer[bytes]
    def __init__(self, binding_id: _Optional[str] = ..., type: _Optional[_Union[BindingRequest.Type, str]] = ..., cert_ids: _Optional[_Iterable[bytes]] = ...) -> None: ...

class BindingResponse(_message.Message):
    __slots__ = ("status", "join_binding_time", "cert_ids")
    class Status(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[BindingResponse.Status]
        SUCCESS: _ClassVar[BindingResponse.Status]
        FAILURE: _ClassVar[BindingResponse.Status]
    UNKNOWN: BindingResponse.Status
    SUCCESS: BindingResponse.Status
    FAILURE: BindingResponse.Status
    STATUS_FIELD_NUMBER: _ClassVar[int]
    JOIN_BINDING_TIME_FIELD_NUMBER: _ClassVar[int]
    CERT_IDS_FIELD_NUMBER: _ClassVar[int]
    status: BindingResponse.Status
    join_binding_time: _timestamp_pb2.Timestamp
    cert_ids: _containers.RepeatedScalarFieldContainer[bytes]
    def __init__(self, status: _Optional[_Union[BindingResponse.Status, str]] = ..., join_binding_time: _Optional[_Union[datetime.datetime, _timestamp_pb2.Timestamp, _Mapping]] = ..., cert_ids: _Optional[_Iterable[bytes]] = ...) -> None: ...

class ConnectionResponseFrame(_message.Message):
    __slots__ = ("status", "attachment_details", "stream_metadata")
    class Status(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[ConnectionResponseFrame.Status]
        ACCEPT: _ClassVar[ConnectionResponseFrame.Status]
        REJECT: _ClassVar[ConnectionResponseFrame.Status]
        NOT_ENOUGH_SPACE: _ClassVar[ConnectionResponseFrame.Status]
        UNSUPPORTED_ATTACHMENT_TYPE: _ClassVar[ConnectionResponseFrame.Status]
        TIMED_OUT: _ClassVar[ConnectionResponseFrame.Status]
    UNKNOWN: ConnectionResponseFrame.Status
    ACCEPT: ConnectionResponseFrame.Status
    REJECT: ConnectionResponseFrame.Status
    NOT_ENOUGH_SPACE: ConnectionResponseFrame.Status
    UNSUPPORTED_ATTACHMENT_TYPE: ConnectionResponseFrame.Status
    TIMED_OUT: ConnectionResponseFrame.Status
    class AttachmentDetailsEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: int
        value: AttachmentDetails
        def __init__(self, key: _Optional[int] = ..., value: _Optional[_Union[AttachmentDetails, _Mapping]] = ...) -> None: ...
    STATUS_FIELD_NUMBER: _ClassVar[int]
    ATTACHMENT_DETAILS_FIELD_NUMBER: _ClassVar[int]
    STREAM_METADATA_FIELD_NUMBER: _ClassVar[int]
    status: ConnectionResponseFrame.Status
    attachment_details: _containers.MessageMap[int, AttachmentDetails]
    stream_metadata: _containers.RepeatedCompositeFieldContainer[StreamMetadata]
    def __init__(self, status: _Optional[_Union[ConnectionResponseFrame.Status, str]] = ..., attachment_details: _Optional[_Mapping[int, AttachmentDetails]] = ..., stream_metadata: _Optional[_Iterable[_Union[StreamMetadata, _Mapping]]] = ...) -> None: ...

class AttachmentDetails(_message.Message):
    __slots__ = ("type", "file_attachment_details")
    class Type(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[AttachmentDetails.Type]
        FILE: _ClassVar[AttachmentDetails.Type]
        TEXT: _ClassVar[AttachmentDetails.Type]
        WIFI_CREDENTIALS: _ClassVar[AttachmentDetails.Type]
        APP: _ClassVar[AttachmentDetails.Type]
        STREAM: _ClassVar[AttachmentDetails.Type]
    UNKNOWN: AttachmentDetails.Type
    FILE: AttachmentDetails.Type
    TEXT: AttachmentDetails.Type
    WIFI_CREDENTIALS: AttachmentDetails.Type
    APP: AttachmentDetails.Type
    STREAM: AttachmentDetails.Type
    TYPE_FIELD_NUMBER: _ClassVar[int]
    FILE_ATTACHMENT_DETAILS_FIELD_NUMBER: _ClassVar[int]
    type: AttachmentDetails.Type
    file_attachment_details: FileAttachmentDetails
    def __init__(self, type: _Optional[_Union[AttachmentDetails.Type, str]] = ..., file_attachment_details: _Optional[_Union[FileAttachmentDetails, _Mapping]] = ...) -> None: ...

class FileAttachmentDetails(_message.Message):
    __slots__ = ("receiver_existing_file_size", "attachment_hash_payloads")
    class AttachmentHashPayloadsEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: int
        value: PayloadsDetails
        def __init__(self, key: _Optional[int] = ..., value: _Optional[_Union[PayloadsDetails, _Mapping]] = ...) -> None: ...
    RECEIVER_EXISTING_FILE_SIZE_FIELD_NUMBER: _ClassVar[int]
    ATTACHMENT_HASH_PAYLOADS_FIELD_NUMBER: _ClassVar[int]
    receiver_existing_file_size: int
    attachment_hash_payloads: _containers.MessageMap[int, PayloadsDetails]
    def __init__(self, receiver_existing_file_size: _Optional[int] = ..., attachment_hash_payloads: _Optional[_Mapping[int, PayloadsDetails]] = ...) -> None: ...

class PayloadsDetails(_message.Message):
    __slots__ = ("payload_details",)
    PAYLOAD_DETAILS_FIELD_NUMBER: _ClassVar[int]
    payload_details: _containers.RepeatedCompositeFieldContainer[PayloadDetails]
    def __init__(self, payload_details: _Optional[_Iterable[_Union[PayloadDetails, _Mapping]]] = ...) -> None: ...

class PayloadDetails(_message.Message):
    __slots__ = ("id", "creation_timestamp_millis", "size")
    ID_FIELD_NUMBER: _ClassVar[int]
    CREATION_TIMESTAMP_MILLIS_FIELD_NUMBER: _ClassVar[int]
    SIZE_FIELD_NUMBER: _ClassVar[int]
    id: int
    creation_timestamp_millis: int
    size: int
    def __init__(self, id: _Optional[int] = ..., creation_timestamp_millis: _Optional[int] = ..., size: _Optional[int] = ...) -> None: ...

class PairedKeyEncryptionFrame(_message.Message):
    __slots__ = ("signed_data", "secret_id_hash", "optional_signed_data", "qr_code_handshake_data")
    SIGNED_DATA_FIELD_NUMBER: _ClassVar[int]
    SECRET_ID_HASH_FIELD_NUMBER: _ClassVar[int]
    OPTIONAL_SIGNED_DATA_FIELD_NUMBER: _ClassVar[int]
    QR_CODE_HANDSHAKE_DATA_FIELD_NUMBER: _ClassVar[int]
    signed_data: bytes
    secret_id_hash: bytes
    optional_signed_data: bytes
    qr_code_handshake_data: bytes
    def __init__(self, signed_data: _Optional[bytes] = ..., secret_id_hash: _Optional[bytes] = ..., optional_signed_data: _Optional[bytes] = ..., qr_code_handshake_data: _Optional[bytes] = ...) -> None: ...

class PairedKeyResultFrame(_message.Message):
    __slots__ = ("status", "os_type")
    class Status(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[PairedKeyResultFrame.Status]
        SUCCESS: _ClassVar[PairedKeyResultFrame.Status]
        FAIL: _ClassVar[PairedKeyResultFrame.Status]
        UNABLE: _ClassVar[PairedKeyResultFrame.Status]
    UNKNOWN: PairedKeyResultFrame.Status
    SUCCESS: PairedKeyResultFrame.Status
    FAIL: PairedKeyResultFrame.Status
    UNABLE: PairedKeyResultFrame.Status
    STATUS_FIELD_NUMBER: _ClassVar[int]
    OS_TYPE_FIELD_NUMBER: _ClassVar[int]
    status: PairedKeyResultFrame.Status
    os_type: _sharing_enums_pb2.OSType
    def __init__(self, status: _Optional[_Union[PairedKeyResultFrame.Status, str]] = ..., os_type: _Optional[_Union[_sharing_enums_pb2.OSType, str]] = ...) -> None: ...

class CertificateInfoFrame(_message.Message):
    __slots__ = ("public_certificate",)
    PUBLIC_CERTIFICATE_FIELD_NUMBER: _ClassVar[int]
    public_certificate: _containers.RepeatedCompositeFieldContainer[PublicCertificate]
    def __init__(self, public_certificate: _Optional[_Iterable[_Union[PublicCertificate, _Mapping]]] = ...) -> None: ...

class PublicCertificate(_message.Message):
    __slots__ = ("secret_id", "authenticity_key", "public_key", "start_time", "end_time", "encrypted_metadata_bytes", "metadata_encryption_key_tag")
    SECRET_ID_FIELD_NUMBER: _ClassVar[int]
    AUTHENTICITY_KEY_FIELD_NUMBER: _ClassVar[int]
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    START_TIME_FIELD_NUMBER: _ClassVar[int]
    END_TIME_FIELD_NUMBER: _ClassVar[int]
    ENCRYPTED_METADATA_BYTES_FIELD_NUMBER: _ClassVar[int]
    METADATA_ENCRYPTION_KEY_TAG_FIELD_NUMBER: _ClassVar[int]
    secret_id: bytes
    authenticity_key: bytes
    public_key: bytes
    start_time: int
    end_time: int
    encrypted_metadata_bytes: bytes
    metadata_encryption_key_tag: bytes
    def __init__(self, secret_id: _Optional[bytes] = ..., authenticity_key: _Optional[bytes] = ..., public_key: _Optional[bytes] = ..., start_time: _Optional[int] = ..., end_time: _Optional[int] = ..., encrypted_metadata_bytes: _Optional[bytes] = ..., metadata_encryption_key_tag: _Optional[bytes] = ...) -> None: ...

class WifiCredentials(_message.Message):
    __slots__ = ("password", "hidden_ssid")
    PASSWORD_FIELD_NUMBER: _ClassVar[int]
    HIDDEN_SSID_FIELD_NUMBER: _ClassVar[int]
    password: str
    hidden_ssid: bool
    def __init__(self, password: _Optional[str] = ..., hidden_ssid: _Optional[bool] = ...) -> None: ...

class StreamDetails(_message.Message):
    __slots__ = ("input_stream_parcel_file_descriptor_bytes",)
    INPUT_STREAM_PARCEL_FILE_DESCRIPTOR_BYTES_FIELD_NUMBER: _ClassVar[int]
    input_stream_parcel_file_descriptor_bytes: bytes
    def __init__(self, input_stream_parcel_file_descriptor_bytes: _Optional[bytes] = ...) -> None: ...
