from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class EndpointType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_ENDPOINT: _ClassVar[EndpointType]
    CONNECTIONS_ENDPOINT: _ClassVar[EndpointType]
    PRESENCE_ENDPOINT: _ClassVar[EndpointType]
UNKNOWN_ENDPOINT: EndpointType
CONNECTIONS_ENDPOINT: EndpointType
PRESENCE_ENDPOINT: EndpointType

class OfflineFrame(_message.Message):
    __slots__ = ("version", "v1")
    class Version(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_VERSION: _ClassVar[OfflineFrame.Version]
        V1: _ClassVar[OfflineFrame.Version]
    UNKNOWN_VERSION: OfflineFrame.Version
    V1: OfflineFrame.Version
    VERSION_FIELD_NUMBER: _ClassVar[int]
    V1_FIELD_NUMBER: _ClassVar[int]
    version: OfflineFrame.Version
    v1: V1Frame
    def __init__(self, version: _Optional[_Union[OfflineFrame.Version, str]] = ..., v1: _Optional[_Union[V1Frame, _Mapping]] = ...) -> None: ...

class V1Frame(_message.Message):
    __slots__ = ("type", "connection_request", "connection_response", "payload_transfer", "bandwidth_upgrade_negotiation", "keep_alive", "disconnection", "paired_key_encryption", "authentication_message", "authentication_result", "auto_resume", "auto_reconnect", "bandwidth_upgrade_retry")
    class FrameType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_FRAME_TYPE: _ClassVar[V1Frame.FrameType]
        CONNECTION_REQUEST: _ClassVar[V1Frame.FrameType]
        CONNECTION_RESPONSE: _ClassVar[V1Frame.FrameType]
        PAYLOAD_TRANSFER: _ClassVar[V1Frame.FrameType]
        BANDWIDTH_UPGRADE_NEGOTIATION: _ClassVar[V1Frame.FrameType]
        KEEP_ALIVE: _ClassVar[V1Frame.FrameType]
        DISCONNECTION: _ClassVar[V1Frame.FrameType]
        PAIRED_KEY_ENCRYPTION: _ClassVar[V1Frame.FrameType]
        AUTHENTICATION_MESSAGE: _ClassVar[V1Frame.FrameType]
        AUTHENTICATION_RESULT: _ClassVar[V1Frame.FrameType]
        AUTO_RESUME: _ClassVar[V1Frame.FrameType]
        AUTO_RECONNECT: _ClassVar[V1Frame.FrameType]
        BANDWIDTH_UPGRADE_RETRY: _ClassVar[V1Frame.FrameType]
    UNKNOWN_FRAME_TYPE: V1Frame.FrameType
    CONNECTION_REQUEST: V1Frame.FrameType
    CONNECTION_RESPONSE: V1Frame.FrameType
    PAYLOAD_TRANSFER: V1Frame.FrameType
    BANDWIDTH_UPGRADE_NEGOTIATION: V1Frame.FrameType
    KEEP_ALIVE: V1Frame.FrameType
    DISCONNECTION: V1Frame.FrameType
    PAIRED_KEY_ENCRYPTION: V1Frame.FrameType
    AUTHENTICATION_MESSAGE: V1Frame.FrameType
    AUTHENTICATION_RESULT: V1Frame.FrameType
    AUTO_RESUME: V1Frame.FrameType
    AUTO_RECONNECT: V1Frame.FrameType
    BANDWIDTH_UPGRADE_RETRY: V1Frame.FrameType
    TYPE_FIELD_NUMBER: _ClassVar[int]
    CONNECTION_REQUEST_FIELD_NUMBER: _ClassVar[int]
    CONNECTION_RESPONSE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_TRANSFER_FIELD_NUMBER: _ClassVar[int]
    BANDWIDTH_UPGRADE_NEGOTIATION_FIELD_NUMBER: _ClassVar[int]
    KEEP_ALIVE_FIELD_NUMBER: _ClassVar[int]
    DISCONNECTION_FIELD_NUMBER: _ClassVar[int]
    PAIRED_KEY_ENCRYPTION_FIELD_NUMBER: _ClassVar[int]
    AUTHENTICATION_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    AUTHENTICATION_RESULT_FIELD_NUMBER: _ClassVar[int]
    AUTO_RESUME_FIELD_NUMBER: _ClassVar[int]
    AUTO_RECONNECT_FIELD_NUMBER: _ClassVar[int]
    BANDWIDTH_UPGRADE_RETRY_FIELD_NUMBER: _ClassVar[int]
    type: V1Frame.FrameType
    connection_request: ConnectionRequestFrame
    connection_response: ConnectionResponseFrame
    payload_transfer: PayloadTransferFrame
    bandwidth_upgrade_negotiation: BandwidthUpgradeNegotiationFrame
    keep_alive: KeepAliveFrame
    disconnection: DisconnectionFrame
    paired_key_encryption: PairedKeyEncryptionFrame
    authentication_message: AuthenticationMessageFrame
    authentication_result: AuthenticationResultFrame
    auto_resume: AutoResumeFrame
    auto_reconnect: AutoReconnectFrame
    bandwidth_upgrade_retry: BandwidthUpgradeRetryFrame
    def __init__(self, type: _Optional[_Union[V1Frame.FrameType, str]] = ..., connection_request: _Optional[_Union[ConnectionRequestFrame, _Mapping]] = ..., connection_response: _Optional[_Union[ConnectionResponseFrame, _Mapping]] = ..., payload_transfer: _Optional[_Union[PayloadTransferFrame, _Mapping]] = ..., bandwidth_upgrade_negotiation: _Optional[_Union[BandwidthUpgradeNegotiationFrame, _Mapping]] = ..., keep_alive: _Optional[_Union[KeepAliveFrame, _Mapping]] = ..., disconnection: _Optional[_Union[DisconnectionFrame, _Mapping]] = ..., paired_key_encryption: _Optional[_Union[PairedKeyEncryptionFrame, _Mapping]] = ..., authentication_message: _Optional[_Union[AuthenticationMessageFrame, _Mapping]] = ..., authentication_result: _Optional[_Union[AuthenticationResultFrame, _Mapping]] = ..., auto_resume: _Optional[_Union[AutoResumeFrame, _Mapping]] = ..., auto_reconnect: _Optional[_Union[AutoReconnectFrame, _Mapping]] = ..., bandwidth_upgrade_retry: _Optional[_Union[BandwidthUpgradeRetryFrame, _Mapping]] = ...) -> None: ...

class ConnectionRequestFrame(_message.Message):
    __slots__ = ("endpoint_id", "endpoint_name", "handshake_data", "nonce", "mediums", "endpoint_info", "medium_metadata", "keep_alive_interval_millis", "keep_alive_timeout_millis", "device_type", "device_info", "connections_device", "presence_device", "connection_mode", "location_hint")
    class Medium(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_MEDIUM: _ClassVar[ConnectionRequestFrame.Medium]
        MDNS: _ClassVar[ConnectionRequestFrame.Medium]
        BLUETOOTH: _ClassVar[ConnectionRequestFrame.Medium]
        WIFI_HOTSPOT: _ClassVar[ConnectionRequestFrame.Medium]
        BLE: _ClassVar[ConnectionRequestFrame.Medium]
        WIFI_LAN: _ClassVar[ConnectionRequestFrame.Medium]
        WIFI_AWARE: _ClassVar[ConnectionRequestFrame.Medium]
        NFC: _ClassVar[ConnectionRequestFrame.Medium]
        WIFI_DIRECT: _ClassVar[ConnectionRequestFrame.Medium]
        WEB_RTC: _ClassVar[ConnectionRequestFrame.Medium]
        BLE_L2CAP: _ClassVar[ConnectionRequestFrame.Medium]
        USB: _ClassVar[ConnectionRequestFrame.Medium]
        WEB_RTC_NON_CELLULAR: _ClassVar[ConnectionRequestFrame.Medium]
        AWDL: _ClassVar[ConnectionRequestFrame.Medium]
    UNKNOWN_MEDIUM: ConnectionRequestFrame.Medium
    MDNS: ConnectionRequestFrame.Medium
    BLUETOOTH: ConnectionRequestFrame.Medium
    WIFI_HOTSPOT: ConnectionRequestFrame.Medium
    BLE: ConnectionRequestFrame.Medium
    WIFI_LAN: ConnectionRequestFrame.Medium
    WIFI_AWARE: ConnectionRequestFrame.Medium
    NFC: ConnectionRequestFrame.Medium
    WIFI_DIRECT: ConnectionRequestFrame.Medium
    WEB_RTC: ConnectionRequestFrame.Medium
    BLE_L2CAP: ConnectionRequestFrame.Medium
    USB: ConnectionRequestFrame.Medium
    WEB_RTC_NON_CELLULAR: ConnectionRequestFrame.Medium
    AWDL: ConnectionRequestFrame.Medium
    class ConnectionMode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        LEGACY: _ClassVar[ConnectionRequestFrame.ConnectionMode]
        INSTANT: _ClassVar[ConnectionRequestFrame.ConnectionMode]
    LEGACY: ConnectionRequestFrame.ConnectionMode
    INSTANT: ConnectionRequestFrame.ConnectionMode
    ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
    ENDPOINT_NAME_FIELD_NUMBER: _ClassVar[int]
    HANDSHAKE_DATA_FIELD_NUMBER: _ClassVar[int]
    NONCE_FIELD_NUMBER: _ClassVar[int]
    MEDIUMS_FIELD_NUMBER: _ClassVar[int]
    ENDPOINT_INFO_FIELD_NUMBER: _ClassVar[int]
    MEDIUM_METADATA_FIELD_NUMBER: _ClassVar[int]
    KEEP_ALIVE_INTERVAL_MILLIS_FIELD_NUMBER: _ClassVar[int]
    KEEP_ALIVE_TIMEOUT_MILLIS_FIELD_NUMBER: _ClassVar[int]
    DEVICE_TYPE_FIELD_NUMBER: _ClassVar[int]
    DEVICE_INFO_FIELD_NUMBER: _ClassVar[int]
    CONNECTIONS_DEVICE_FIELD_NUMBER: _ClassVar[int]
    PRESENCE_DEVICE_FIELD_NUMBER: _ClassVar[int]
    CONNECTION_MODE_FIELD_NUMBER: _ClassVar[int]
    LOCATION_HINT_FIELD_NUMBER: _ClassVar[int]
    endpoint_id: str
    endpoint_name: str
    handshake_data: bytes
    nonce: int
    mediums: _containers.RepeatedScalarFieldContainer[ConnectionRequestFrame.Medium]
    endpoint_info: bytes
    medium_metadata: MediumMetadata
    keep_alive_interval_millis: int
    keep_alive_timeout_millis: int
    device_type: int
    device_info: bytes
    connections_device: ConnectionsDevice
    presence_device: PresenceDevice
    connection_mode: ConnectionRequestFrame.ConnectionMode
    location_hint: LocationHint
    def __init__(self, endpoint_id: _Optional[str] = ..., endpoint_name: _Optional[str] = ..., handshake_data: _Optional[bytes] = ..., nonce: _Optional[int] = ..., mediums: _Optional[_Iterable[_Union[ConnectionRequestFrame.Medium, str]]] = ..., endpoint_info: _Optional[bytes] = ..., medium_metadata: _Optional[_Union[MediumMetadata, _Mapping]] = ..., keep_alive_interval_millis: _Optional[int] = ..., keep_alive_timeout_millis: _Optional[int] = ..., device_type: _Optional[int] = ..., device_info: _Optional[bytes] = ..., connections_device: _Optional[_Union[ConnectionsDevice, _Mapping]] = ..., presence_device: _Optional[_Union[PresenceDevice, _Mapping]] = ..., connection_mode: _Optional[_Union[ConnectionRequestFrame.ConnectionMode, str]] = ..., location_hint: _Optional[_Union[LocationHint, _Mapping]] = ...) -> None: ...

class ConnectionResponseFrame(_message.Message):
    __slots__ = ("status", "handshake_data", "response", "os_info", "multiplex_socket_bitmask", "nearby_connections_version", "safe_to_disconnect_version", "location_hint", "keep_alive_timeout_millis", "wifi_direct_device_name")
    class ResponseStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_RESPONSE_STATUS: _ClassVar[ConnectionResponseFrame.ResponseStatus]
        ACCEPT: _ClassVar[ConnectionResponseFrame.ResponseStatus]
        REJECT: _ClassVar[ConnectionResponseFrame.ResponseStatus]
    UNKNOWN_RESPONSE_STATUS: ConnectionResponseFrame.ResponseStatus
    ACCEPT: ConnectionResponseFrame.ResponseStatus
    REJECT: ConnectionResponseFrame.ResponseStatus
    STATUS_FIELD_NUMBER: _ClassVar[int]
    HANDSHAKE_DATA_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_FIELD_NUMBER: _ClassVar[int]
    OS_INFO_FIELD_NUMBER: _ClassVar[int]
    MULTIPLEX_SOCKET_BITMASK_FIELD_NUMBER: _ClassVar[int]
    NEARBY_CONNECTIONS_VERSION_FIELD_NUMBER: _ClassVar[int]
    SAFE_TO_DISCONNECT_VERSION_FIELD_NUMBER: _ClassVar[int]
    LOCATION_HINT_FIELD_NUMBER: _ClassVar[int]
    KEEP_ALIVE_TIMEOUT_MILLIS_FIELD_NUMBER: _ClassVar[int]
    WIFI_DIRECT_DEVICE_NAME_FIELD_NUMBER: _ClassVar[int]
    status: int
    handshake_data: bytes
    response: ConnectionResponseFrame.ResponseStatus
    os_info: OsInfo
    multiplex_socket_bitmask: int
    nearby_connections_version: int
    safe_to_disconnect_version: int
    location_hint: LocationHint
    keep_alive_timeout_millis: int
    wifi_direct_device_name: str
    def __init__(self, status: _Optional[int] = ..., handshake_data: _Optional[bytes] = ..., response: _Optional[_Union[ConnectionResponseFrame.ResponseStatus, str]] = ..., os_info: _Optional[_Union[OsInfo, _Mapping]] = ..., multiplex_socket_bitmask: _Optional[int] = ..., nearby_connections_version: _Optional[int] = ..., safe_to_disconnect_version: _Optional[int] = ..., location_hint: _Optional[_Union[LocationHint, _Mapping]] = ..., keep_alive_timeout_millis: _Optional[int] = ..., wifi_direct_device_name: _Optional[str] = ...) -> None: ...

class PayloadTransferFrame(_message.Message):
    __slots__ = ("packet_type", "payload_header", "payload_chunk", "control_message")
    class PacketType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_PACKET_TYPE: _ClassVar[PayloadTransferFrame.PacketType]
        DATA: _ClassVar[PayloadTransferFrame.PacketType]
        CONTROL: _ClassVar[PayloadTransferFrame.PacketType]
        PAYLOAD_ACK: _ClassVar[PayloadTransferFrame.PacketType]
    UNKNOWN_PACKET_TYPE: PayloadTransferFrame.PacketType
    DATA: PayloadTransferFrame.PacketType
    CONTROL: PayloadTransferFrame.PacketType
    PAYLOAD_ACK: PayloadTransferFrame.PacketType
    class PayloadHeader(_message.Message):
        __slots__ = ("id", "type", "total_size", "is_sensitive", "file_name", "parent_folder", "last_modified_timestamp_millis")
        class PayloadType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
            __slots__ = ()
            UNKNOWN_PAYLOAD_TYPE: _ClassVar[PayloadTransferFrame.PayloadHeader.PayloadType]
            BYTES: _ClassVar[PayloadTransferFrame.PayloadHeader.PayloadType]
            FILE: _ClassVar[PayloadTransferFrame.PayloadHeader.PayloadType]
            STREAM: _ClassVar[PayloadTransferFrame.PayloadHeader.PayloadType]
        UNKNOWN_PAYLOAD_TYPE: PayloadTransferFrame.PayloadHeader.PayloadType
        BYTES: PayloadTransferFrame.PayloadHeader.PayloadType
        FILE: PayloadTransferFrame.PayloadHeader.PayloadType
        STREAM: PayloadTransferFrame.PayloadHeader.PayloadType
        ID_FIELD_NUMBER: _ClassVar[int]
        TYPE_FIELD_NUMBER: _ClassVar[int]
        TOTAL_SIZE_FIELD_NUMBER: _ClassVar[int]
        IS_SENSITIVE_FIELD_NUMBER: _ClassVar[int]
        FILE_NAME_FIELD_NUMBER: _ClassVar[int]
        PARENT_FOLDER_FIELD_NUMBER: _ClassVar[int]
        LAST_MODIFIED_TIMESTAMP_MILLIS_FIELD_NUMBER: _ClassVar[int]
        id: int
        type: PayloadTransferFrame.PayloadHeader.PayloadType
        total_size: int
        is_sensitive: bool
        file_name: str
        parent_folder: str
        last_modified_timestamp_millis: int
        def __init__(self, id: _Optional[int] = ..., type: _Optional[_Union[PayloadTransferFrame.PayloadHeader.PayloadType, str]] = ..., total_size: _Optional[int] = ..., is_sensitive: _Optional[bool] = ..., file_name: _Optional[str] = ..., parent_folder: _Optional[str] = ..., last_modified_timestamp_millis: _Optional[int] = ...) -> None: ...
    class PayloadChunk(_message.Message):
        __slots__ = ("flags", "offset", "body", "index")
        class Flags(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
            __slots__ = ()
            LAST_CHUNK: _ClassVar[PayloadTransferFrame.PayloadChunk.Flags]
        LAST_CHUNK: PayloadTransferFrame.PayloadChunk.Flags
        FLAGS_FIELD_NUMBER: _ClassVar[int]
        OFFSET_FIELD_NUMBER: _ClassVar[int]
        BODY_FIELD_NUMBER: _ClassVar[int]
        INDEX_FIELD_NUMBER: _ClassVar[int]
        flags: int
        offset: int
        body: bytes
        index: int
        def __init__(self, flags: _Optional[int] = ..., offset: _Optional[int] = ..., body: _Optional[bytes] = ..., index: _Optional[int] = ...) -> None: ...
    class ControlMessage(_message.Message):
        __slots__ = ("event", "offset")
        class EventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
            __slots__ = ()
            UNKNOWN_EVENT_TYPE: _ClassVar[PayloadTransferFrame.ControlMessage.EventType]
            PAYLOAD_ERROR: _ClassVar[PayloadTransferFrame.ControlMessage.EventType]
            PAYLOAD_CANCELED: _ClassVar[PayloadTransferFrame.ControlMessage.EventType]
            PAYLOAD_RECEIVED_ACK: _ClassVar[PayloadTransferFrame.ControlMessage.EventType]
        UNKNOWN_EVENT_TYPE: PayloadTransferFrame.ControlMessage.EventType
        PAYLOAD_ERROR: PayloadTransferFrame.ControlMessage.EventType
        PAYLOAD_CANCELED: PayloadTransferFrame.ControlMessage.EventType
        PAYLOAD_RECEIVED_ACK: PayloadTransferFrame.ControlMessage.EventType
        EVENT_FIELD_NUMBER: _ClassVar[int]
        OFFSET_FIELD_NUMBER: _ClassVar[int]
        event: PayloadTransferFrame.ControlMessage.EventType
        offset: int
        def __init__(self, event: _Optional[_Union[PayloadTransferFrame.ControlMessage.EventType, str]] = ..., offset: _Optional[int] = ...) -> None: ...
    PACKET_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_HEADER_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_CHUNK_FIELD_NUMBER: _ClassVar[int]
    CONTROL_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    packet_type: PayloadTransferFrame.PacketType
    payload_header: PayloadTransferFrame.PayloadHeader
    payload_chunk: PayloadTransferFrame.PayloadChunk
    control_message: PayloadTransferFrame.ControlMessage
    def __init__(self, packet_type: _Optional[_Union[PayloadTransferFrame.PacketType, str]] = ..., payload_header: _Optional[_Union[PayloadTransferFrame.PayloadHeader, _Mapping]] = ..., payload_chunk: _Optional[_Union[PayloadTransferFrame.PayloadChunk, _Mapping]] = ..., control_message: _Optional[_Union[PayloadTransferFrame.ControlMessage, _Mapping]] = ...) -> None: ...

class ServiceAddress(_message.Message):
    __slots__ = ("ip_address", "port")
    IP_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    PORT_FIELD_NUMBER: _ClassVar[int]
    ip_address: bytes
    port: int
    def __init__(self, ip_address: _Optional[bytes] = ..., port: _Optional[int] = ...) -> None: ...

class BandwidthUpgradeNegotiationFrame(_message.Message):
    __slots__ = ("event_type", "upgrade_path_info", "client_introduction", "client_introduction_ack", "safe_to_close_prior_channel")
    class EventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_EVENT_TYPE: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        UPGRADE_PATH_AVAILABLE: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        LAST_WRITE_TO_PRIOR_CHANNEL: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        SAFE_TO_CLOSE_PRIOR_CHANNEL: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        CLIENT_INTRODUCTION: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        UPGRADE_FAILURE: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        CLIENT_INTRODUCTION_ACK: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
        UPGRADE_PATH_REQUEST: _ClassVar[BandwidthUpgradeNegotiationFrame.EventType]
    UNKNOWN_EVENT_TYPE: BandwidthUpgradeNegotiationFrame.EventType
    UPGRADE_PATH_AVAILABLE: BandwidthUpgradeNegotiationFrame.EventType
    LAST_WRITE_TO_PRIOR_CHANNEL: BandwidthUpgradeNegotiationFrame.EventType
    SAFE_TO_CLOSE_PRIOR_CHANNEL: BandwidthUpgradeNegotiationFrame.EventType
    CLIENT_INTRODUCTION: BandwidthUpgradeNegotiationFrame.EventType
    UPGRADE_FAILURE: BandwidthUpgradeNegotiationFrame.EventType
    CLIENT_INTRODUCTION_ACK: BandwidthUpgradeNegotiationFrame.EventType
    UPGRADE_PATH_REQUEST: BandwidthUpgradeNegotiationFrame.EventType
    class UpgradePathInfo(_message.Message):
        __slots__ = ("medium", "wifi_hotspot_credentials", "wifi_lan_socket", "bluetooth_credentials", "wifi_aware_credentials", "wifi_direct_credentials", "web_rtc_credentials", "awdl_credentials", "supports_disabling_encryption", "supports_client_introduction_ack", "upgrade_path_request")
        class Medium(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
            __slots__ = ()
            UNKNOWN_MEDIUM: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            MDNS: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            BLUETOOTH: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            WIFI_HOTSPOT: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            BLE: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            WIFI_LAN: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            WIFI_AWARE: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            NFC: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            WIFI_DIRECT: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            WEB_RTC: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            USB: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            WEB_RTC_NON_CELLULAR: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            AWDL: _ClassVar[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
        UNKNOWN_MEDIUM: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        MDNS: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        BLUETOOTH: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        WIFI_HOTSPOT: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        BLE: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        WIFI_LAN: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        WIFI_AWARE: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        NFC: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        WIFI_DIRECT: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        WEB_RTC: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        USB: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        WEB_RTC_NON_CELLULAR: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        AWDL: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        class WifiHotspotCredentials(_message.Message):
            __slots__ = ("ssid", "password", "port", "gateway", "frequency", "address_candidates")
            SSID_FIELD_NUMBER: _ClassVar[int]
            PASSWORD_FIELD_NUMBER: _ClassVar[int]
            PORT_FIELD_NUMBER: _ClassVar[int]
            GATEWAY_FIELD_NUMBER: _ClassVar[int]
            FREQUENCY_FIELD_NUMBER: _ClassVar[int]
            ADDRESS_CANDIDATES_FIELD_NUMBER: _ClassVar[int]
            ssid: str
            password: str
            port: int
            gateway: str
            frequency: int
            address_candidates: _containers.RepeatedCompositeFieldContainer[ServiceAddress]
            def __init__(self, ssid: _Optional[str] = ..., password: _Optional[str] = ..., port: _Optional[int] = ..., gateway: _Optional[str] = ..., frequency: _Optional[int] = ..., address_candidates: _Optional[_Iterable[_Union[ServiceAddress, _Mapping]]] = ...) -> None: ...
        class WifiLanSocket(_message.Message):
            __slots__ = ("ip_address", "wifi_port", "address_candidates")
            IP_ADDRESS_FIELD_NUMBER: _ClassVar[int]
            WIFI_PORT_FIELD_NUMBER: _ClassVar[int]
            ADDRESS_CANDIDATES_FIELD_NUMBER: _ClassVar[int]
            ip_address: bytes
            wifi_port: int
            address_candidates: _containers.RepeatedCompositeFieldContainer[ServiceAddress]
            def __init__(self, ip_address: _Optional[bytes] = ..., wifi_port: _Optional[int] = ..., address_candidates: _Optional[_Iterable[_Union[ServiceAddress, _Mapping]]] = ...) -> None: ...
        class BluetoothCredentials(_message.Message):
            __slots__ = ("service_name", "mac_address")
            SERVICE_NAME_FIELD_NUMBER: _ClassVar[int]
            MAC_ADDRESS_FIELD_NUMBER: _ClassVar[int]
            service_name: str
            mac_address: str
            def __init__(self, service_name: _Optional[str] = ..., mac_address: _Optional[str] = ...) -> None: ...
        class WifiAwareCredentials(_message.Message):
            __slots__ = ("service_id", "service_info", "password")
            SERVICE_ID_FIELD_NUMBER: _ClassVar[int]
            SERVICE_INFO_FIELD_NUMBER: _ClassVar[int]
            PASSWORD_FIELD_NUMBER: _ClassVar[int]
            service_id: str
            service_info: bytes
            password: str
            def __init__(self, service_id: _Optional[str] = ..., service_info: _Optional[bytes] = ..., password: _Optional[str] = ...) -> None: ...
        class WifiDirectCredentials(_message.Message):
            __slots__ = ("ssid", "password", "port", "frequency", "gateway", "ip_v6_address", "service_name", "device_name", "pin")
            SSID_FIELD_NUMBER: _ClassVar[int]
            PASSWORD_FIELD_NUMBER: _ClassVar[int]
            PORT_FIELD_NUMBER: _ClassVar[int]
            FREQUENCY_FIELD_NUMBER: _ClassVar[int]
            GATEWAY_FIELD_NUMBER: _ClassVar[int]
            IP_V6_ADDRESS_FIELD_NUMBER: _ClassVar[int]
            SERVICE_NAME_FIELD_NUMBER: _ClassVar[int]
            DEVICE_NAME_FIELD_NUMBER: _ClassVar[int]
            PIN_FIELD_NUMBER: _ClassVar[int]
            ssid: str
            password: str
            port: int
            frequency: int
            gateway: str
            ip_v6_address: bytes
            service_name: str
            device_name: str
            pin: str
            def __init__(self, ssid: _Optional[str] = ..., password: _Optional[str] = ..., port: _Optional[int] = ..., frequency: _Optional[int] = ..., gateway: _Optional[str] = ..., ip_v6_address: _Optional[bytes] = ..., service_name: _Optional[str] = ..., device_name: _Optional[str] = ..., pin: _Optional[str] = ...) -> None: ...
        class WebRtcCredentials(_message.Message):
            __slots__ = ("peer_id", "location_hint")
            PEER_ID_FIELD_NUMBER: _ClassVar[int]
            LOCATION_HINT_FIELD_NUMBER: _ClassVar[int]
            peer_id: str
            location_hint: LocationHint
            def __init__(self, peer_id: _Optional[str] = ..., location_hint: _Optional[_Union[LocationHint, _Mapping]] = ...) -> None: ...
        class AwdlCredentials(_message.Message):
            __slots__ = ("service_name", "service_type", "password")
            SERVICE_NAME_FIELD_NUMBER: _ClassVar[int]
            SERVICE_TYPE_FIELD_NUMBER: _ClassVar[int]
            PASSWORD_FIELD_NUMBER: _ClassVar[int]
            service_name: str
            service_type: str
            password: str
            def __init__(self, service_name: _Optional[str] = ..., service_type: _Optional[str] = ..., password: _Optional[str] = ...) -> None: ...
        class UpgradePathRequest(_message.Message):
            __slots__ = ("mediums", "medium_meta_data")
            MEDIUMS_FIELD_NUMBER: _ClassVar[int]
            MEDIUM_META_DATA_FIELD_NUMBER: _ClassVar[int]
            mediums: _containers.RepeatedScalarFieldContainer[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium]
            medium_meta_data: MediumMetadata
            def __init__(self, mediums: _Optional[_Iterable[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium, str]]] = ..., medium_meta_data: _Optional[_Union[MediumMetadata, _Mapping]] = ...) -> None: ...
        MEDIUM_FIELD_NUMBER: _ClassVar[int]
        WIFI_HOTSPOT_CREDENTIALS_FIELD_NUMBER: _ClassVar[int]
        WIFI_LAN_SOCKET_FIELD_NUMBER: _ClassVar[int]
        BLUETOOTH_CREDENTIALS_FIELD_NUMBER: _ClassVar[int]
        WIFI_AWARE_CREDENTIALS_FIELD_NUMBER: _ClassVar[int]
        WIFI_DIRECT_CREDENTIALS_FIELD_NUMBER: _ClassVar[int]
        WEB_RTC_CREDENTIALS_FIELD_NUMBER: _ClassVar[int]
        AWDL_CREDENTIALS_FIELD_NUMBER: _ClassVar[int]
        SUPPORTS_DISABLING_ENCRYPTION_FIELD_NUMBER: _ClassVar[int]
        SUPPORTS_CLIENT_INTRODUCTION_ACK_FIELD_NUMBER: _ClassVar[int]
        UPGRADE_PATH_REQUEST_FIELD_NUMBER: _ClassVar[int]
        medium: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium
        wifi_hotspot_credentials: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials
        wifi_lan_socket: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket
        bluetooth_credentials: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials
        wifi_aware_credentials: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials
        wifi_direct_credentials: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials
        web_rtc_credentials: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials
        awdl_credentials: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials
        supports_disabling_encryption: bool
        supports_client_introduction_ack: bool
        upgrade_path_request: BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest
        def __init__(self, medium: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.Medium, str]] = ..., wifi_hotspot_credentials: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiHotspotCredentials, _Mapping]] = ..., wifi_lan_socket: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiLanSocket, _Mapping]] = ..., bluetooth_credentials: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.BluetoothCredentials, _Mapping]] = ..., wifi_aware_credentials: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiAwareCredentials, _Mapping]] = ..., wifi_direct_credentials: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WifiDirectCredentials, _Mapping]] = ..., web_rtc_credentials: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.WebRtcCredentials, _Mapping]] = ..., awdl_credentials: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.AwdlCredentials, _Mapping]] = ..., supports_disabling_encryption: _Optional[bool] = ..., supports_client_introduction_ack: _Optional[bool] = ..., upgrade_path_request: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo.UpgradePathRequest, _Mapping]] = ...) -> None: ...
    class SafeToClosePriorChannel(_message.Message):
        __slots__ = ("sta_frequency",)
        STA_FREQUENCY_FIELD_NUMBER: _ClassVar[int]
        sta_frequency: int
        def __init__(self, sta_frequency: _Optional[int] = ...) -> None: ...
    class ClientIntroduction(_message.Message):
        __slots__ = ("endpoint_id", "supports_disabling_encryption", "last_endpoint_id")
        ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
        SUPPORTS_DISABLING_ENCRYPTION_FIELD_NUMBER: _ClassVar[int]
        LAST_ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
        endpoint_id: str
        supports_disabling_encryption: bool
        last_endpoint_id: str
        def __init__(self, endpoint_id: _Optional[str] = ..., supports_disabling_encryption: _Optional[bool] = ..., last_endpoint_id: _Optional[str] = ...) -> None: ...
    class ClientIntroductionAck(_message.Message):
        __slots__ = ()
        def __init__(self) -> None: ...
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    UPGRADE_PATH_INFO_FIELD_NUMBER: _ClassVar[int]
    CLIENT_INTRODUCTION_FIELD_NUMBER: _ClassVar[int]
    CLIENT_INTRODUCTION_ACK_FIELD_NUMBER: _ClassVar[int]
    SAFE_TO_CLOSE_PRIOR_CHANNEL_FIELD_NUMBER: _ClassVar[int]
    event_type: BandwidthUpgradeNegotiationFrame.EventType
    upgrade_path_info: BandwidthUpgradeNegotiationFrame.UpgradePathInfo
    client_introduction: BandwidthUpgradeNegotiationFrame.ClientIntroduction
    client_introduction_ack: BandwidthUpgradeNegotiationFrame.ClientIntroductionAck
    safe_to_close_prior_channel: BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel
    def __init__(self, event_type: _Optional[_Union[BandwidthUpgradeNegotiationFrame.EventType, str]] = ..., upgrade_path_info: _Optional[_Union[BandwidthUpgradeNegotiationFrame.UpgradePathInfo, _Mapping]] = ..., client_introduction: _Optional[_Union[BandwidthUpgradeNegotiationFrame.ClientIntroduction, _Mapping]] = ..., client_introduction_ack: _Optional[_Union[BandwidthUpgradeNegotiationFrame.ClientIntroductionAck, _Mapping]] = ..., safe_to_close_prior_channel: _Optional[_Union[BandwidthUpgradeNegotiationFrame.SafeToClosePriorChannel, _Mapping]] = ...) -> None: ...

class BandwidthUpgradeRetryFrame(_message.Message):
    __slots__ = ("supported_medium", "is_request")
    class Medium(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_MEDIUM: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        BLUETOOTH: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        WIFI_HOTSPOT: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        BLE: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        WIFI_LAN: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        WIFI_AWARE: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        NFC: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        WIFI_DIRECT: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        WEB_RTC: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        BLE_L2CAP: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        USB: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        WEB_RTC_NON_CELLULAR: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
        AWDL: _ClassVar[BandwidthUpgradeRetryFrame.Medium]
    UNKNOWN_MEDIUM: BandwidthUpgradeRetryFrame.Medium
    BLUETOOTH: BandwidthUpgradeRetryFrame.Medium
    WIFI_HOTSPOT: BandwidthUpgradeRetryFrame.Medium
    BLE: BandwidthUpgradeRetryFrame.Medium
    WIFI_LAN: BandwidthUpgradeRetryFrame.Medium
    WIFI_AWARE: BandwidthUpgradeRetryFrame.Medium
    NFC: BandwidthUpgradeRetryFrame.Medium
    WIFI_DIRECT: BandwidthUpgradeRetryFrame.Medium
    WEB_RTC: BandwidthUpgradeRetryFrame.Medium
    BLE_L2CAP: BandwidthUpgradeRetryFrame.Medium
    USB: BandwidthUpgradeRetryFrame.Medium
    WEB_RTC_NON_CELLULAR: BandwidthUpgradeRetryFrame.Medium
    AWDL: BandwidthUpgradeRetryFrame.Medium
    SUPPORTED_MEDIUM_FIELD_NUMBER: _ClassVar[int]
    IS_REQUEST_FIELD_NUMBER: _ClassVar[int]
    supported_medium: _containers.RepeatedScalarFieldContainer[BandwidthUpgradeRetryFrame.Medium]
    is_request: bool
    def __init__(self, supported_medium: _Optional[_Iterable[_Union[BandwidthUpgradeRetryFrame.Medium, str]]] = ..., is_request: _Optional[bool] = ...) -> None: ...

class KeepAliveFrame(_message.Message):
    __slots__ = ("ack", "seq_num")
    ACK_FIELD_NUMBER: _ClassVar[int]
    SEQ_NUM_FIELD_NUMBER: _ClassVar[int]
    ack: bool
    seq_num: int
    def __init__(self, ack: _Optional[bool] = ..., seq_num: _Optional[int] = ...) -> None: ...

class DisconnectionFrame(_message.Message):
    __slots__ = ("request_safe_to_disconnect", "ack_safe_to_disconnect")
    REQUEST_SAFE_TO_DISCONNECT_FIELD_NUMBER: _ClassVar[int]
    ACK_SAFE_TO_DISCONNECT_FIELD_NUMBER: _ClassVar[int]
    request_safe_to_disconnect: bool
    ack_safe_to_disconnect: bool
    def __init__(self, request_safe_to_disconnect: _Optional[bool] = ..., ack_safe_to_disconnect: _Optional[bool] = ...) -> None: ...

class PairedKeyEncryptionFrame(_message.Message):
    __slots__ = ("signed_data",)
    SIGNED_DATA_FIELD_NUMBER: _ClassVar[int]
    signed_data: bytes
    def __init__(self, signed_data: _Optional[bytes] = ...) -> None: ...

class AuthenticationMessageFrame(_message.Message):
    __slots__ = ("auth_message",)
    AUTH_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    auth_message: bytes
    def __init__(self, auth_message: _Optional[bytes] = ...) -> None: ...

class AuthenticationResultFrame(_message.Message):
    __slots__ = ("result",)
    RESULT_FIELD_NUMBER: _ClassVar[int]
    result: int
    def __init__(self, result: _Optional[int] = ...) -> None: ...

class AutoResumeFrame(_message.Message):
    __slots__ = ("event_type", "pending_payload_id", "next_payload_chunk_index", "version")
    class EventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_AUTO_RESUME_EVENT_TYPE: _ClassVar[AutoResumeFrame.EventType]
        PAYLOAD_RESUME_TRANSFER_START: _ClassVar[AutoResumeFrame.EventType]
        PAYLOAD_RESUME_TRANSFER_ACK: _ClassVar[AutoResumeFrame.EventType]
    UNKNOWN_AUTO_RESUME_EVENT_TYPE: AutoResumeFrame.EventType
    PAYLOAD_RESUME_TRANSFER_START: AutoResumeFrame.EventType
    PAYLOAD_RESUME_TRANSFER_ACK: AutoResumeFrame.EventType
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    PENDING_PAYLOAD_ID_FIELD_NUMBER: _ClassVar[int]
    NEXT_PAYLOAD_CHUNK_INDEX_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    event_type: AutoResumeFrame.EventType
    pending_payload_id: int
    next_payload_chunk_index: int
    version: int
    def __init__(self, event_type: _Optional[_Union[AutoResumeFrame.EventType, str]] = ..., pending_payload_id: _Optional[int] = ..., next_payload_chunk_index: _Optional[int] = ..., version: _Optional[int] = ...) -> None: ...

class AutoReconnectFrame(_message.Message):
    __slots__ = ("endpoint_id", "event_type", "last_endpoint_id")
    class EventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_EVENT_TYPE: _ClassVar[AutoReconnectFrame.EventType]
        CLIENT_INTRODUCTION: _ClassVar[AutoReconnectFrame.EventType]
        CLIENT_INTRODUCTION_ACK: _ClassVar[AutoReconnectFrame.EventType]
    UNKNOWN_EVENT_TYPE: AutoReconnectFrame.EventType
    CLIENT_INTRODUCTION: AutoReconnectFrame.EventType
    CLIENT_INTRODUCTION_ACK: AutoReconnectFrame.EventType
    ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    LAST_ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
    endpoint_id: str
    event_type: AutoReconnectFrame.EventType
    last_endpoint_id: str
    def __init__(self, endpoint_id: _Optional[str] = ..., event_type: _Optional[_Union[AutoReconnectFrame.EventType, str]] = ..., last_endpoint_id: _Optional[str] = ...) -> None: ...

class MediumMetadata(_message.Message):
    __slots__ = ("supports_5_ghz", "bssid", "ip_address", "supports_6_ghz", "mobile_radio", "ap_frequency", "available_channels", "wifi_direct_cli_usable_channels", "wifi_lan_usable_channels", "wifi_aware_usable_channels", "wifi_hotspot_sta_usable_channels", "medium_role", "supported_wifi_direct_auth_types")
    class WifiDirectAuthType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        WIFI_DIRECT_TYPE_UNKNOWN: _ClassVar[MediumMetadata.WifiDirectAuthType]
        WIFI_DIRECT_WITH_PASSWORD: _ClassVar[MediumMetadata.WifiDirectAuthType]
        WIFI_DIRECT_WITH_PIN: _ClassVar[MediumMetadata.WifiDirectAuthType]
        WIFI_DIRECT_WITH_DEVICE_NAME: _ClassVar[MediumMetadata.WifiDirectAuthType]
    WIFI_DIRECT_TYPE_UNKNOWN: MediumMetadata.WifiDirectAuthType
    WIFI_DIRECT_WITH_PASSWORD: MediumMetadata.WifiDirectAuthType
    WIFI_DIRECT_WITH_PIN: MediumMetadata.WifiDirectAuthType
    WIFI_DIRECT_WITH_DEVICE_NAME: MediumMetadata.WifiDirectAuthType
    SUPPORTS_5_GHZ_FIELD_NUMBER: _ClassVar[int]
    BSSID_FIELD_NUMBER: _ClassVar[int]
    IP_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_6_GHZ_FIELD_NUMBER: _ClassVar[int]
    MOBILE_RADIO_FIELD_NUMBER: _ClassVar[int]
    AP_FREQUENCY_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    WIFI_DIRECT_CLI_USABLE_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    WIFI_LAN_USABLE_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    WIFI_AWARE_USABLE_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    WIFI_HOTSPOT_STA_USABLE_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    MEDIUM_ROLE_FIELD_NUMBER: _ClassVar[int]
    SUPPORTED_WIFI_DIRECT_AUTH_TYPES_FIELD_NUMBER: _ClassVar[int]
    supports_5_ghz: bool
    bssid: str
    ip_address: bytes
    supports_6_ghz: bool
    mobile_radio: bool
    ap_frequency: int
    available_channels: AvailableChannels
    wifi_direct_cli_usable_channels: WifiDirectCliUsableChannels
    wifi_lan_usable_channels: WifiLanUsableChannels
    wifi_aware_usable_channels: WifiAwareUsableChannels
    wifi_hotspot_sta_usable_channels: WifiHotspotStaUsableChannels
    medium_role: MediumRole
    supported_wifi_direct_auth_types: _containers.RepeatedScalarFieldContainer[MediumMetadata.WifiDirectAuthType]
    def __init__(self, supports_5_ghz: _Optional[bool] = ..., bssid: _Optional[str] = ..., ip_address: _Optional[bytes] = ..., supports_6_ghz: _Optional[bool] = ..., mobile_radio: _Optional[bool] = ..., ap_frequency: _Optional[int] = ..., available_channels: _Optional[_Union[AvailableChannels, _Mapping]] = ..., wifi_direct_cli_usable_channels: _Optional[_Union[WifiDirectCliUsableChannels, _Mapping]] = ..., wifi_lan_usable_channels: _Optional[_Union[WifiLanUsableChannels, _Mapping]] = ..., wifi_aware_usable_channels: _Optional[_Union[WifiAwareUsableChannels, _Mapping]] = ..., wifi_hotspot_sta_usable_channels: _Optional[_Union[WifiHotspotStaUsableChannels, _Mapping]] = ..., medium_role: _Optional[_Union[MediumRole, _Mapping]] = ..., supported_wifi_direct_auth_types: _Optional[_Iterable[_Union[MediumMetadata.WifiDirectAuthType, str]]] = ...) -> None: ...

class AvailableChannels(_message.Message):
    __slots__ = ("channels",)
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    channels: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, channels: _Optional[_Iterable[int]] = ...) -> None: ...

class WifiDirectCliUsableChannels(_message.Message):
    __slots__ = ("channels",)
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    channels: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, channels: _Optional[_Iterable[int]] = ...) -> None: ...

class WifiLanUsableChannels(_message.Message):
    __slots__ = ("channels",)
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    channels: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, channels: _Optional[_Iterable[int]] = ...) -> None: ...

class WifiAwareUsableChannels(_message.Message):
    __slots__ = ("channels",)
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    channels: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, channels: _Optional[_Iterable[int]] = ...) -> None: ...

class WifiHotspotStaUsableChannels(_message.Message):
    __slots__ = ("channels",)
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    channels: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, channels: _Optional[_Iterable[int]] = ...) -> None: ...

class MediumRole(_message.Message):
    __slots__ = ("support_wifi_direct_group_owner", "support_wifi_direct_group_client", "support_wifi_hotspot_host", "support_wifi_hotspot_client", "support_wifi_aware_publisher", "support_wifi_aware_subscriber", "support_awdl_publisher", "support_awdl_subscriber")
    SUPPORT_WIFI_DIRECT_GROUP_OWNER_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_WIFI_DIRECT_GROUP_CLIENT_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_WIFI_HOTSPOT_HOST_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_WIFI_HOTSPOT_CLIENT_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_WIFI_AWARE_PUBLISHER_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_WIFI_AWARE_SUBSCRIBER_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_AWDL_PUBLISHER_FIELD_NUMBER: _ClassVar[int]
    SUPPORT_AWDL_SUBSCRIBER_FIELD_NUMBER: _ClassVar[int]
    support_wifi_direct_group_owner: bool
    support_wifi_direct_group_client: bool
    support_wifi_hotspot_host: bool
    support_wifi_hotspot_client: bool
    support_wifi_aware_publisher: bool
    support_wifi_aware_subscriber: bool
    support_awdl_publisher: bool
    support_awdl_subscriber: bool
    def __init__(self, support_wifi_direct_group_owner: _Optional[bool] = ..., support_wifi_direct_group_client: _Optional[bool] = ..., support_wifi_hotspot_host: _Optional[bool] = ..., support_wifi_hotspot_client: _Optional[bool] = ..., support_wifi_aware_publisher: _Optional[bool] = ..., support_wifi_aware_subscriber: _Optional[bool] = ..., support_awdl_publisher: _Optional[bool] = ..., support_awdl_subscriber: _Optional[bool] = ...) -> None: ...

class LocationHint(_message.Message):
    __slots__ = ("location", "format")
    LOCATION_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    location: str
    format: LocationStandard.Format
    def __init__(self, location: _Optional[str] = ..., format: _Optional[_Union[LocationStandard.Format, str]] = ...) -> None: ...

class LocationStandard(_message.Message):
    __slots__ = ()
    class Format(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[LocationStandard.Format]
        E164_CALLING: _ClassVar[LocationStandard.Format]
        ISO_3166_1_ALPHA_2: _ClassVar[LocationStandard.Format]
    UNKNOWN: LocationStandard.Format
    E164_CALLING: LocationStandard.Format
    ISO_3166_1_ALPHA_2: LocationStandard.Format
    def __init__(self) -> None: ...

class OsInfo(_message.Message):
    __slots__ = ("type",)
    class OsType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN_OS_TYPE: _ClassVar[OsInfo.OsType]
        ANDROID: _ClassVar[OsInfo.OsType]
        CHROME_OS: _ClassVar[OsInfo.OsType]
        WINDOWS: _ClassVar[OsInfo.OsType]
        APPLE: _ClassVar[OsInfo.OsType]
        LINUX: _ClassVar[OsInfo.OsType]
    UNKNOWN_OS_TYPE: OsInfo.OsType
    ANDROID: OsInfo.OsType
    CHROME_OS: OsInfo.OsType
    WINDOWS: OsInfo.OsType
    APPLE: OsInfo.OsType
    LINUX: OsInfo.OsType
    TYPE_FIELD_NUMBER: _ClassVar[int]
    type: OsInfo.OsType
    def __init__(self, type: _Optional[_Union[OsInfo.OsType, str]] = ...) -> None: ...

class ConnectionsDevice(_message.Message):
    __slots__ = ("endpoint_id", "endpoint_type", "connectivity_info_list", "endpoint_info")
    ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
    ENDPOINT_TYPE_FIELD_NUMBER: _ClassVar[int]
    CONNECTIVITY_INFO_LIST_FIELD_NUMBER: _ClassVar[int]
    ENDPOINT_INFO_FIELD_NUMBER: _ClassVar[int]
    endpoint_id: str
    endpoint_type: EndpointType
    connectivity_info_list: bytes
    endpoint_info: bytes
    def __init__(self, endpoint_id: _Optional[str] = ..., endpoint_type: _Optional[_Union[EndpointType, str]] = ..., connectivity_info_list: _Optional[bytes] = ..., endpoint_info: _Optional[bytes] = ...) -> None: ...

class PresenceDevice(_message.Message):
    __slots__ = ("endpoint_id", "endpoint_type", "connectivity_info_list", "device_id", "device_name", "device_type", "device_image_url", "discovery_medium", "actions", "identity_type")
    class DeviceType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
        __slots__ = ()
        UNKNOWN: _ClassVar[PresenceDevice.DeviceType]
        PHONE: _ClassVar[PresenceDevice.DeviceType]
        TABLET: _ClassVar[PresenceDevice.DeviceType]
        DISPLAY: _ClassVar[PresenceDevice.DeviceType]
        LAPTOP: _ClassVar[PresenceDevice.DeviceType]
        TV: _ClassVar[PresenceDevice.DeviceType]
        WATCH: _ClassVar[PresenceDevice.DeviceType]
    UNKNOWN: PresenceDevice.DeviceType
    PHONE: PresenceDevice.DeviceType
    TABLET: PresenceDevice.DeviceType
    DISPLAY: PresenceDevice.DeviceType
    LAPTOP: PresenceDevice.DeviceType
    TV: PresenceDevice.DeviceType
    WATCH: PresenceDevice.DeviceType
    ENDPOINT_ID_FIELD_NUMBER: _ClassVar[int]
    ENDPOINT_TYPE_FIELD_NUMBER: _ClassVar[int]
    CONNECTIVITY_INFO_LIST_FIELD_NUMBER: _ClassVar[int]
    DEVICE_ID_FIELD_NUMBER: _ClassVar[int]
    DEVICE_NAME_FIELD_NUMBER: _ClassVar[int]
    DEVICE_TYPE_FIELD_NUMBER: _ClassVar[int]
    DEVICE_IMAGE_URL_FIELD_NUMBER: _ClassVar[int]
    DISCOVERY_MEDIUM_FIELD_NUMBER: _ClassVar[int]
    ACTIONS_FIELD_NUMBER: _ClassVar[int]
    IDENTITY_TYPE_FIELD_NUMBER: _ClassVar[int]
    endpoint_id: str
    endpoint_type: EndpointType
    connectivity_info_list: bytes
    device_id: int
    device_name: str
    device_type: PresenceDevice.DeviceType
    device_image_url: str
    discovery_medium: _containers.RepeatedScalarFieldContainer[ConnectionRequestFrame.Medium]
    actions: _containers.RepeatedScalarFieldContainer[int]
    identity_type: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, endpoint_id: _Optional[str] = ..., endpoint_type: _Optional[_Union[EndpointType, str]] = ..., connectivity_info_list: _Optional[bytes] = ..., device_id: _Optional[int] = ..., device_name: _Optional[str] = ..., device_type: _Optional[_Union[PresenceDevice.DeviceType, str]] = ..., device_image_url: _Optional[str] = ..., discovery_medium: _Optional[_Iterable[_Union[ConnectionRequestFrame.Medium, str]]] = ..., actions: _Optional[_Iterable[int]] = ..., identity_type: _Optional[_Iterable[int]] = ...) -> None: ...
