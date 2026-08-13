from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class AppleDeviceDiagonalMils(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    APPLE_PHONE: _ClassVar[AppleDeviceDiagonalMils]
    APPLE_PAD: _ClassVar[AppleDeviceDiagonalMils]

class DeviceType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN: _ClassVar[DeviceType]
    ANDROID: _ClassVar[DeviceType]
    CHROME: _ClassVar[DeviceType]
    IOS: _ClassVar[DeviceType]
    BROWSER: _ClassVar[DeviceType]
    OSX: _ClassVar[DeviceType]

class SoftwareFeature(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_FEATURE: _ClassVar[SoftwareFeature]
    BETTER_TOGETHER_HOST: _ClassVar[SoftwareFeature]
    BETTER_TOGETHER_CLIENT: _ClassVar[SoftwareFeature]
    EASY_UNLOCK_HOST: _ClassVar[SoftwareFeature]
    EASY_UNLOCK_CLIENT: _ClassVar[SoftwareFeature]
    MAGIC_TETHER_HOST: _ClassVar[SoftwareFeature]
    MAGIC_TETHER_CLIENT: _ClassVar[SoftwareFeature]
    SMS_CONNECT_HOST: _ClassVar[SoftwareFeature]
    SMS_CONNECT_CLIENT: _ClassVar[SoftwareFeature]

class InvocationReason(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    REASON_UNKNOWN: _ClassVar[InvocationReason]
    REASON_INITIALIZATION: _ClassVar[InvocationReason]
    REASON_PERIODIC: _ClassVar[InvocationReason]
    REASON_SLOW_PERIODIC: _ClassVar[InvocationReason]
    REASON_FAST_PERIODIC: _ClassVar[InvocationReason]
    REASON_EXPIRATION: _ClassVar[InvocationReason]
    REASON_FAILURE_RECOVERY: _ClassVar[InvocationReason]
    REASON_NEW_ACCOUNT: _ClassVar[InvocationReason]
    REASON_CHANGED_ACCOUNT: _ClassVar[InvocationReason]
    REASON_FEATURE_TOGGLED: _ClassVar[InvocationReason]
    REASON_SERVER_INITIATED: _ClassVar[InvocationReason]
    REASON_ADDRESS_CHANGE: _ClassVar[InvocationReason]
    REASON_SOFTWARE_UPDATE: _ClassVar[InvocationReason]
    REASON_MANUAL: _ClassVar[InvocationReason]
    REASON_CUSTOM_KEY_INVALIDATION: _ClassVar[InvocationReason]
    REASON_PROXIMITY_PERIODIC: _ClassVar[InvocationReason]

class Type(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ENROLLMENT: _ClassVar[Type]
    TICKLE: _ClassVar[Type]
    TX_REQUEST: _ClassVar[Type]
    TX_REPLY: _ClassVar[Type]
    TX_SYNC_REQUEST: _ClassVar[Type]
    TX_SYNC_RESPONSE: _ClassVar[Type]
    TX_PING: _ClassVar[Type]
    DEVICE_INFO_UPDATE: _ClassVar[Type]
    TX_CANCEL_REQUEST: _ClassVar[Type]
    PROXIMITYAUTH_PAIRING: _ClassVar[Type]
    GCMV1_IDENTITY_ASSERTION: _ClassVar[Type]
    DEVICE_TO_DEVICE_RESPONDER_HELLO_PAYLOAD: _ClassVar[Type]
    DEVICE_TO_DEVICE_MESSAGE: _ClassVar[Type]
    DEVICE_PROXIMITY_CALLBACK: _ClassVar[Type]
    UNLOCK_KEY_SIGNED_CHALLENGE: _ClassVar[Type]
    LOGIN_NOTIFICATION: _ClassVar[Type]
APPLE_PHONE: AppleDeviceDiagonalMils
APPLE_PAD: AppleDeviceDiagonalMils
UNKNOWN: DeviceType
ANDROID: DeviceType
CHROME: DeviceType
IOS: DeviceType
BROWSER: DeviceType
OSX: DeviceType
UNKNOWN_FEATURE: SoftwareFeature
BETTER_TOGETHER_HOST: SoftwareFeature
BETTER_TOGETHER_CLIENT: SoftwareFeature
EASY_UNLOCK_HOST: SoftwareFeature
EASY_UNLOCK_CLIENT: SoftwareFeature
MAGIC_TETHER_HOST: SoftwareFeature
MAGIC_TETHER_CLIENT: SoftwareFeature
SMS_CONNECT_HOST: SoftwareFeature
SMS_CONNECT_CLIENT: SoftwareFeature
REASON_UNKNOWN: InvocationReason
REASON_INITIALIZATION: InvocationReason
REASON_PERIODIC: InvocationReason
REASON_SLOW_PERIODIC: InvocationReason
REASON_FAST_PERIODIC: InvocationReason
REASON_EXPIRATION: InvocationReason
REASON_FAILURE_RECOVERY: InvocationReason
REASON_NEW_ACCOUNT: InvocationReason
REASON_CHANGED_ACCOUNT: InvocationReason
REASON_FEATURE_TOGGLED: InvocationReason
REASON_SERVER_INITIATED: InvocationReason
REASON_ADDRESS_CHANGE: InvocationReason
REASON_SOFTWARE_UPDATE: InvocationReason
REASON_MANUAL: InvocationReason
REASON_CUSTOM_KEY_INVALIDATION: InvocationReason
REASON_PROXIMITY_PERIODIC: InvocationReason
ENROLLMENT: Type
TICKLE: Type
TX_REQUEST: Type
TX_REPLY: Type
TX_SYNC_REQUEST: Type
TX_SYNC_RESPONSE: Type
TX_PING: Type
DEVICE_INFO_UPDATE: Type
TX_CANCEL_REQUEST: Type
PROXIMITYAUTH_PAIRING: Type
GCMV1_IDENTITY_ASSERTION: Type
DEVICE_TO_DEVICE_RESPONDER_HELLO_PAYLOAD: Type
DEVICE_TO_DEVICE_MESSAGE: Type
DEVICE_PROXIMITY_CALLBACK: Type
UNLOCK_KEY_SIGNED_CHALLENGE: Type
LOGIN_NOTIFICATION: Type

class GcmDeviceInfo(_message.Message):
    __slots__ = ("android_device_id", "gcm_registration_id", "apn_registration_id", "notification_enabled", "bluetooth_mac_address", "device_master_key_hash", "user_public_key", "device_model", "locale", "key_handle", "counter", "device_os_version", "device_os_version_code", "device_os_release", "device_os_codename", "device_software_version", "device_software_version_code", "device_software_package", "device_display_diagonal_mils", "device_authzen_version", "long_device_id", "device_manufacturer", "device_type", "using_secure_screenlock", "auto_unlock_screenlock_supported", "auto_unlock_screenlock_enabled", "bluetooth_radio_supported", "bluetooth_radio_enabled", "mobile_data_supported", "tethering_supported", "ble_radio_supported", "pixel_experience", "arc_plus_plus", "is_screenlock_state_flaky", "supported_software_features", "enabled_software_features", "enrollment_session_id", "oauth_token")
    ANDROID_DEVICE_ID_FIELD_NUMBER: _ClassVar[int]
    GCM_REGISTRATION_ID_FIELD_NUMBER: _ClassVar[int]
    APN_REGISTRATION_ID_FIELD_NUMBER: _ClassVar[int]
    NOTIFICATION_ENABLED_FIELD_NUMBER: _ClassVar[int]
    BLUETOOTH_MAC_ADDRESS_FIELD_NUMBER: _ClassVar[int]
    DEVICE_MASTER_KEY_HASH_FIELD_NUMBER: _ClassVar[int]
    USER_PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    DEVICE_MODEL_FIELD_NUMBER: _ClassVar[int]
    LOCALE_FIELD_NUMBER: _ClassVar[int]
    KEY_HANDLE_FIELD_NUMBER: _ClassVar[int]
    COUNTER_FIELD_NUMBER: _ClassVar[int]
    DEVICE_OS_VERSION_FIELD_NUMBER: _ClassVar[int]
    DEVICE_OS_VERSION_CODE_FIELD_NUMBER: _ClassVar[int]
    DEVICE_OS_RELEASE_FIELD_NUMBER: _ClassVar[int]
    DEVICE_OS_CODENAME_FIELD_NUMBER: _ClassVar[int]
    DEVICE_SOFTWARE_VERSION_FIELD_NUMBER: _ClassVar[int]
    DEVICE_SOFTWARE_VERSION_CODE_FIELD_NUMBER: _ClassVar[int]
    DEVICE_SOFTWARE_PACKAGE_FIELD_NUMBER: _ClassVar[int]
    DEVICE_DISPLAY_DIAGONAL_MILS_FIELD_NUMBER: _ClassVar[int]
    DEVICE_AUTHZEN_VERSION_FIELD_NUMBER: _ClassVar[int]
    LONG_DEVICE_ID_FIELD_NUMBER: _ClassVar[int]
    DEVICE_MANUFACTURER_FIELD_NUMBER: _ClassVar[int]
    DEVICE_TYPE_FIELD_NUMBER: _ClassVar[int]
    USING_SECURE_SCREENLOCK_FIELD_NUMBER: _ClassVar[int]
    AUTO_UNLOCK_SCREENLOCK_SUPPORTED_FIELD_NUMBER: _ClassVar[int]
    AUTO_UNLOCK_SCREENLOCK_ENABLED_FIELD_NUMBER: _ClassVar[int]
    BLUETOOTH_RADIO_SUPPORTED_FIELD_NUMBER: _ClassVar[int]
    BLUETOOTH_RADIO_ENABLED_FIELD_NUMBER: _ClassVar[int]
    MOBILE_DATA_SUPPORTED_FIELD_NUMBER: _ClassVar[int]
    TETHERING_SUPPORTED_FIELD_NUMBER: _ClassVar[int]
    BLE_RADIO_SUPPORTED_FIELD_NUMBER: _ClassVar[int]
    PIXEL_EXPERIENCE_FIELD_NUMBER: _ClassVar[int]
    ARC_PLUS_PLUS_FIELD_NUMBER: _ClassVar[int]
    IS_SCREENLOCK_STATE_FLAKY_FIELD_NUMBER: _ClassVar[int]
    SUPPORTED_SOFTWARE_FEATURES_FIELD_NUMBER: _ClassVar[int]
    ENABLED_SOFTWARE_FEATURES_FIELD_NUMBER: _ClassVar[int]
    ENROLLMENT_SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    OAUTH_TOKEN_FIELD_NUMBER: _ClassVar[int]
    android_device_id: int
    gcm_registration_id: bytes
    apn_registration_id: bytes
    notification_enabled: bool
    bluetooth_mac_address: str
    device_master_key_hash: bytes
    user_public_key: bytes
    device_model: str
    locale: str
    key_handle: bytes
    counter: int
    device_os_version: str
    device_os_version_code: int
    device_os_release: str
    device_os_codename: str
    device_software_version: str
    device_software_version_code: int
    device_software_package: str
    device_display_diagonal_mils: int
    device_authzen_version: int
    long_device_id: bytes
    device_manufacturer: str
    device_type: DeviceType
    using_secure_screenlock: bool
    auto_unlock_screenlock_supported: bool
    auto_unlock_screenlock_enabled: bool
    bluetooth_radio_supported: bool
    bluetooth_radio_enabled: bool
    mobile_data_supported: bool
    tethering_supported: bool
    ble_radio_supported: bool
    pixel_experience: bool
    arc_plus_plus: bool
    is_screenlock_state_flaky: bool
    supported_software_features: _containers.RepeatedScalarFieldContainer[SoftwareFeature]
    enabled_software_features: _containers.RepeatedScalarFieldContainer[SoftwareFeature]
    enrollment_session_id: bytes
    oauth_token: str
    def __init__(self, android_device_id: _Optional[int] = ..., gcm_registration_id: _Optional[bytes] = ..., apn_registration_id: _Optional[bytes] = ..., notification_enabled: _Optional[bool] = ..., bluetooth_mac_address: _Optional[str] = ..., device_master_key_hash: _Optional[bytes] = ..., user_public_key: _Optional[bytes] = ..., device_model: _Optional[str] = ..., locale: _Optional[str] = ..., key_handle: _Optional[bytes] = ..., counter: _Optional[int] = ..., device_os_version: _Optional[str] = ..., device_os_version_code: _Optional[int] = ..., device_os_release: _Optional[str] = ..., device_os_codename: _Optional[str] = ..., device_software_version: _Optional[str] = ..., device_software_version_code: _Optional[int] = ..., device_software_package: _Optional[str] = ..., device_display_diagonal_mils: _Optional[int] = ..., device_authzen_version: _Optional[int] = ..., long_device_id: _Optional[bytes] = ..., device_manufacturer: _Optional[str] = ..., device_type: _Optional[_Union[DeviceType, str]] = ..., using_secure_screenlock: _Optional[bool] = ..., auto_unlock_screenlock_supported: _Optional[bool] = ..., auto_unlock_screenlock_enabled: _Optional[bool] = ..., bluetooth_radio_supported: _Optional[bool] = ..., bluetooth_radio_enabled: _Optional[bool] = ..., mobile_data_supported: _Optional[bool] = ..., tethering_supported: _Optional[bool] = ..., ble_radio_supported: _Optional[bool] = ..., pixel_experience: _Optional[bool] = ..., arc_plus_plus: _Optional[bool] = ..., is_screenlock_state_flaky: _Optional[bool] = ..., supported_software_features: _Optional[_Iterable[_Union[SoftwareFeature, str]]] = ..., enabled_software_features: _Optional[_Iterable[_Union[SoftwareFeature, str]]] = ..., enrollment_session_id: _Optional[bytes] = ..., oauth_token: _Optional[str] = ...) -> None: ...

class GcmMetadata(_message.Message):
    __slots__ = ("type", "version")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    type: Type
    version: int
    def __init__(self, type: _Optional[_Union[Type, str]] = ..., version: _Optional[int] = ...) -> None: ...

class Tickle(_message.Message):
    __slots__ = ("expiry_time",)
    EXPIRY_TIME_FIELD_NUMBER: _ClassVar[int]
    expiry_time: int
    def __init__(self, expiry_time: _Optional[int] = ...) -> None: ...

class LoginNotificationInfo(_message.Message):
    __slots__ = ("creation_time", "email", "host", "source", "event_type")
    CREATION_TIME_FIELD_NUMBER: _ClassVar[int]
    EMAIL_FIELD_NUMBER: _ClassVar[int]
    HOST_FIELD_NUMBER: _ClassVar[int]
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    creation_time: int
    email: str
    host: str
    source: str
    event_type: str
    def __init__(self, creation_time: _Optional[int] = ..., email: _Optional[str] = ..., host: _Optional[str] = ..., source: _Optional[str] = ..., event_type: _Optional[str] = ...) -> None: ...
