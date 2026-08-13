from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from typing import ClassVar as _ClassVar

DESCRIPTOR: _descriptor.FileDescriptor

class EventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_EVENT_TYPE: _ClassVar[EventType]
    ACCEPT_AGREEMENTS: _ClassVar[EventType]
    ENABLE_NEARBY_SHARING: _ClassVar[EventType]
    SET_VISIBILITY: _ClassVar[EventType]
    DESCRIBE_ATTACHMENTS: _ClassVar[EventType]
    SCAN_FOR_SHARE_TARGETS_START: _ClassVar[EventType]
    SCAN_FOR_SHARE_TARGETS_END: _ClassVar[EventType]
    ADVERTISE_DEVICE_PRESENCE_START: _ClassVar[EventType]
    ADVERTISE_DEVICE_PRESENCE_END: _ClassVar[EventType]
    SEND_FAST_INITIALIZATION: _ClassVar[EventType]
    RECEIVE_FAST_INITIALIZATION: _ClassVar[EventType]
    DISCOVER_SHARE_TARGET: _ClassVar[EventType]
    SEND_INTRODUCTION: _ClassVar[EventType]
    RECEIVE_INTRODUCTION: _ClassVar[EventType]
    RESPOND_TO_INTRODUCTION: _ClassVar[EventType]
    SEND_ATTACHMENTS_START: _ClassVar[EventType]
    SEND_ATTACHMENTS_END: _ClassVar[EventType]
    RECEIVE_ATTACHMENTS_START: _ClassVar[EventType]
    RECEIVE_ATTACHMENTS_END: _ClassVar[EventType]
    CANCEL_SENDING_ATTACHMENTS: _ClassVar[EventType]
    CANCEL_RECEIVING_ATTACHMENTS: _ClassVar[EventType]
    OPEN_RECEIVED_ATTACHMENTS: _ClassVar[EventType]
    LAUNCH_SETUP_ACTIVITY: _ClassVar[EventType]
    ADD_CONTACT: _ClassVar[EventType]
    REMOVE_CONTACT: _ClassVar[EventType]
    FAST_SHARE_SERVER_RESPONSE: _ClassVar[EventType]
    SEND_START: _ClassVar[EventType]
    ACCEPT_FAST_INITIALIZATION: _ClassVar[EventType]
    SET_DATA_USAGE: _ClassVar[EventType]
    DISMISS_FAST_INITIALIZATION: _ClassVar[EventType]
    CANCEL_CONNECTION: _ClassVar[EventType]
    LAUNCH_ACTIVITY: _ClassVar[EventType]
    DISMISS_PRIVACY_NOTIFICATION: _ClassVar[EventType]
    TAP_PRIVACY_NOTIFICATION: _ClassVar[EventType]
    TAP_HELP: _ClassVar[EventType]
    TAP_FEEDBACK: _ClassVar[EventType]
    ADD_QUICK_SETTINGS_TILE: _ClassVar[EventType]
    REMOVE_QUICK_SETTINGS_TILE: _ClassVar[EventType]
    LAUNCH_PHONE_CONSENT: _ClassVar[EventType]
    DISPLAY_PHONE_CONSENT: _ClassVar[EventType]
    TAP_QUICK_SETTINGS_TILE: _ClassVar[EventType]
    INSTALL_APK: _ClassVar[EventType]
    VERIFY_APK: _ClassVar[EventType]
    LAUNCH_CONSENT: _ClassVar[EventType]
    PROCESS_RECEIVED_ATTACHMENTS_END: _ClassVar[EventType]
    TOGGLE_SHOW_NOTIFICATION: _ClassVar[EventType]
    SET_DEVICE_NAME: _ClassVar[EventType]
    DECLINE_AGREEMENTS: _ClassVar[EventType]
    REQUEST_SETTING_PERMISSIONS: _ClassVar[EventType]
    ESTABLISH_CONNECTION: _ClassVar[EventType]
    DEVICE_SETTINGS: _ClassVar[EventType]
    AUTO_DISMISS_FAST_INITIALIZATION: _ClassVar[EventType]
    APP_CRASH: _ClassVar[EventType]
    TAP_QUICK_SETTINGS_FILE_SHARE: _ClassVar[EventType]
    DISPLAY_PRIVACY_NOTIFICATION: _ClassVar[EventType]
    PREFERENCES_USAGE: _ClassVar[EventType]
    DEFAULT_OPT_IN: _ClassVar[EventType]
    SETUP_WIZARD: _ClassVar[EventType]
    TAP_QR_CODE: _ClassVar[EventType]
    QR_CODE_LINK_SHOWN: _ClassVar[EventType]
    PARSING_FAILED_ENDPOINT_ID: _ClassVar[EventType]
    FAST_INIT_DISCOVER_DEVICE: _ClassVar[EventType]
    SEND_DESKTOP_NOTIFICATION: _ClassVar[EventType]
    SET_ACCOUNT: _ClassVar[EventType]
    DECRYPT_CERTIFICATE_FAILURE: _ClassVar[EventType]
    SHOW_ALLOW_PERMISSION_AUTO_ACCESS: _ClassVar[EventType]
    SEND_DESKTOP_TRANSFER_EVENT: _ClassVar[EventType]
    WAITING_FOR_ACCEPT: _ClassVar[EventType]
    HIGH_QUALITY_MEDIUM_SETUP: _ClassVar[EventType]
    RPC_CALL_STATUS: _ClassVar[EventType]
    START_QR_CODE_SESSION: _ClassVar[EventType]
    QR_CODE_OPENED_IN_WEB_CLIENT: _ClassVar[EventType]
    HATS_JOINT_EVENT: _ClassVar[EventType]
    RECEIVE_PREVIEWS: _ClassVar[EventType]
    CLOUD_CREATE_SHARING_REQUEST: _ClassVar[EventType]
    CLOUD_REGISTER_RECEIVER: _ClassVar[EventType]
    CLOUD_UPLOAD_START: _ClassVar[EventType]
    CLOUD_UPLOAD_END: _ClassVar[EventType]
    CLOUD_DOWNLOAD_START: _ClassVar[EventType]
    CLOUD_DOWNLOAD_END: _ClassVar[EventType]
    CLOUD_SHARING_RPC_RESULT: _ClassVar[EventType]
    PROVIDER_CONNECTED: _ClassVar[EventType]

class EventCategory(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_EVENT_CATEGORY: _ClassVar[EventCategory]
    SENDING_EVENT: _ClassVar[EventCategory]
    RECEIVING_EVENT: _ClassVar[EventCategory]
    SETTINGS_EVENT: _ClassVar[EventCategory]
    RPC_EVENT: _ClassVar[EventCategory]

class NearbySharingStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_NEARBY_SHARING_STATUS: _ClassVar[NearbySharingStatus]
    ON: _ClassVar[NearbySharingStatus]
    OFF: _ClassVar[NearbySharingStatus]

class Visibility(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_VISIBILITY: _ClassVar[Visibility]
    CONTACTS_ONLY: _ClassVar[Visibility]
    EVERYONE: _ClassVar[Visibility]
    SELECTED_CONTACTS_ONLY: _ClassVar[Visibility]
    HIDDEN: _ClassVar[Visibility]
    SELF_SHARE: _ClassVar[Visibility]
    FAMILY: _ClassVar[Visibility]

class DataUsage(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_DATA_USAGE: _ClassVar[DataUsage]
    ONLINE: _ClassVar[DataUsage]
    WIFI_ONLY: _ClassVar[DataUsage]
    OFFLINE: _ClassVar[DataUsage]

class EstablishConnectionStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CONNECTION_STATUS_UNKNOWN: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_SUCCESS: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_FAILURE: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_CANCELLATION: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_MEDIA_UNAVAILABLE_ATTACHMENT: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_FAILED_PAIRED_KEYHANDSHAKE: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_FAILED_WRITE_INTRODUCTION: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_FAILED_NULL_CONNECTION: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_FAILED_NO_TRANSFER_UPDATE_CALLBACK: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_LOST_CONNECTIVITY: _ClassVar[EstablishConnectionStatus]
    CONNECTION_STATUS_INVALID_ADVERTISEMENT: _ClassVar[EstablishConnectionStatus]

class AttachmentTransmissionStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    COMPLETE_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    CANCELED_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    FAILED_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    REJECTED_ATTACHMENT: _ClassVar[AttachmentTransmissionStatus]
    TIMED_OUT_ATTACHMENT: _ClassVar[AttachmentTransmissionStatus]
    AWAITING_REMOTE_ACCEPTANCE_FAILED_ATTACHMENT: _ClassVar[AttachmentTransmissionStatus]
    NOT_ENOUGH_SPACE_ATTACHMENT: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NO_TRANSFER_UPDATE_CALLBACK: _ClassVar[AttachmentTransmissionStatus]
    MEDIA_UNAVAILABLE_ATTACHMENT: _ClassVar[AttachmentTransmissionStatus]
    UNSUPPORTED_ATTACHMENT_TYPE_ATTACHMENT: _ClassVar[AttachmentTransmissionStatus]
    NO_ATTACHMENT_FOUND: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NO_SHARE_TARGET_ENDPOINT: _ClassVar[AttachmentTransmissionStatus]
    FAILED_PAIRED_KEYHANDSHAKE: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NULL_CONNECTION: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NO_PAYLOAD: _ClassVar[AttachmentTransmissionStatus]
    FAILED_WRITE_INTRODUCTION: _ClassVar[AttachmentTransmissionStatus]
    FAILED_UNKNOWN_REMOTE_RESPONSE: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NULL_CONNECTION_INIT_OUTGOING: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NULL_CONNECTION_DISCONNECTED: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NULL_CONNECTION_LOST_CONNECTIVITY: _ClassVar[AttachmentTransmissionStatus]
    FAILED_NULL_CONNECTION_FAILURE: _ClassVar[AttachmentTransmissionStatus]
    REJECTED_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    TIMED_OUT_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    NOT_ENOUGH_SPACE_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    UNSUPPORTED_ATTACHMENT_TYPE_ATTACHMENT_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    FAILED_UNKNOWN_REMOTE_RESPONSE_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    NO_RESPONSE_FRAME_CONNECTION_CLOSED_LOST_CONNECTIVITY_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    NO_RESPONSE_FRAME_CONNECTION_CLOSED_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    LOST_CONNECTIVITY_TRANSMISSION_STATUS: _ClassVar[AttachmentTransmissionStatus]
    FAILED_DISALLOWED_MEDIUM: _ClassVar[AttachmentTransmissionStatus]

class ConnectionLayerStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CONNECTION_LAYER_STATUS_UNKNOWN: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_SUCCESS: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_ERROR: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_OUT_OF_ORDER_API_CALL: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_ALREADY_HAVE_ACTIVE_STRATEGY: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_ALREADY_ADVERTISING: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_ALREADY_DISCOVERING: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_ALREADY_LISTENING: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_END_POINT_IO_ERROR: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_END_POINT_UNKNOWN: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_CONNECTION_REJECTED: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_ALREADY_CONNECTED_TO_END_POINT: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_NOT_CONNECTED_TO_END_POINT: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_BLUETOOTH_ERROR: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_BLE_ERROR: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_WIFI_LAN_ERROR: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_PAYLOAD_UNKNOWN: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_RESET: _ClassVar[ConnectionLayerStatus]
    CONNECTION_LAYER_STATUS_TIMEOUT: _ClassVar[ConnectionLayerStatus]

class ProcessReceivedAttachmentsStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PROCESSING_STATUS_UNKNOWN: _ClassVar[ProcessReceivedAttachmentsStatus]
    PROCESSING_STATUS_COMPLETE_PROCESSING_ATTACHMENTS: _ClassVar[ProcessReceivedAttachmentsStatus]
    PROCESSING_STATUS_FAILED_MOVING_FILES: _ClassVar[ProcessReceivedAttachmentsStatus]
    PROCESSING_STATUS_FAILED_RECEIVING_APK: _ClassVar[ProcessReceivedAttachmentsStatus]
    PROCESSING_STATUS_FAILED_RECEIVING_TEXT: _ClassVar[ProcessReceivedAttachmentsStatus]
    PROCESSING_STATUS_FAILED_RECEIVING_WIFI_CREDENTIALS: _ClassVar[ProcessReceivedAttachmentsStatus]

class SessionStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_SESSION_STATUS: _ClassVar[SessionStatus]
    SUCCEEDED_SESSION_STATUS: _ClassVar[SessionStatus]
    FAILED_SESSION_STATUS: _ClassVar[SessionStatus]

class ResponseToIntroduction(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_RESPONSE_TO_INTRODUCTION: _ClassVar[ResponseToIntroduction]
    ACCEPT_INTRODUCTION: _ClassVar[ResponseToIntroduction]
    REJECT_INTRODUCTION: _ClassVar[ResponseToIntroduction]
    FAIL_INTRODUCTION: _ClassVar[ResponseToIntroduction]

class DeviceType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_DEVICE_TYPE: _ClassVar[DeviceType]
    PHONE: _ClassVar[DeviceType]
    TABLET: _ClassVar[DeviceType]
    LAPTOP: _ClassVar[DeviceType]
    CAR: _ClassVar[DeviceType]
    FOLDABLE: _ClassVar[DeviceType]
    XR: _ClassVar[DeviceType]

class OSType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_OS_TYPE: _ClassVar[OSType]
    ANDROID: _ClassVar[OSType]
    CHROME_OS: _ClassVar[OSType]
    IOS: _ClassVar[OSType]
    WINDOWS: _ClassVar[OSType]
    MACOS: _ClassVar[OSType]

class DeviceRelationship(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_DEVICE_RELATIONSHIP: _ClassVar[DeviceRelationship]
    IS_SELF: _ClassVar[DeviceRelationship]
    IS_CONTACT: _ClassVar[DeviceRelationship]
    IS_STRANGER: _ClassVar[DeviceRelationship]

class LogSource(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNSPECIFIED_SOURCE: _ClassVar[LogSource]
    LAB_DEVICES: _ClassVar[LogSource]
    INTERNAL_DEVICES: _ClassVar[LogSource]
    BETA_TESTER_DEVICES: _ClassVar[LogSource]
    OEM_DEVICES: _ClassVar[LogSource]
    DEBUG_DEVICES: _ClassVar[LogSource]
    NEARBY_MODULE_FOOD_DEVICES: _ClassVar[LogSource]
    BETO_DOGFOOD_DEVICES: _ClassVar[LogSource]
    NEARBY_DOGFOOD_DEVICES: _ClassVar[LogSource]
    NEARBY_TEAMFOOD_DEVICES: _ClassVar[LogSource]

class ServerActionName(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_SERVER_ACTION: _ClassVar[ServerActionName]
    UPLOAD_CERTIFICATES: _ClassVar[ServerActionName]
    DOWNLOAD_CERTIFICATES: _ClassVar[ServerActionName]
    CHECK_REACHABILITY: _ClassVar[ServerActionName]
    UPLOAD_CONTACTS: _ClassVar[ServerActionName]
    UPDATE_DEVICE_NAME: _ClassVar[ServerActionName]
    UPLOAD_SENDER_CERTIFICATES: _ClassVar[ServerActionName]
    DOWNLOAD_SENDER_CERTIFICATES: _ClassVar[ServerActionName]
    UPLOAD_CONTACTS_AND_CERTIFICATES: _ClassVar[ServerActionName]
    LIST_REACHABLE_PHONE_NUMBERS: _ClassVar[ServerActionName]
    LIST_MY_DEVICES: _ClassVar[ServerActionName]
    LIST_CONTACT_PEOPLE: _ClassVar[ServerActionName]
    DOWNLOAD_CERTIFICATES_INFO: _ClassVar[ServerActionName]

class ServerResponseState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_SERVER_RESPONSE_STATE: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_SUCCESS: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_UNKNOWN_FAILURE: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_STATUS_OTHER_FAILURE: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_STATUS_DEADLINE_EXCEEDED: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_STATUS_PERMISSION_DENIED: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_STATUS_UNAVAILABLE: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_STATUS_UNAUTHENTICATED: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_STATUS_INVALID_ARGUMENT: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_GOOGLE_AUTH_FAILURE: _ClassVar[ServerResponseState]
    SERVER_RESPONSE_NOT_CONNECTED_TO_INTERNET: _ClassVar[ServerResponseState]

class SyncPurpose(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SYNC_PURPOSE_UNKNOWN: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_ON_DEMAND_SYNC: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_CHIME_NOTIFICATION: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_DAILY_SYNC: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_OPT_IN_FIRST_SYNC: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_CHECK_DEFAULT_OPT_IN: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_NEARBY_SHARE_ENABLED: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_SYNC_AT_FAST_INIT: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_SYNC_AT_DISCOVERY: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_SYNC_AT_LOAD_PRIVATE_CERTIFICATE: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_SYNC_AT_ADVERTISEMENT: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_CONTACT_LIST_CHANGE: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_SHOW_C11N_VIEW: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_REGULAR_CHECK_CONTACT_REACHABILITY: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_VISIBILITY_SELECTED_CONTACT_CHANGE: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_ACCOUNT_CHANGE: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_REGENERATE_CERTIFICATES: _ClassVar[SyncPurpose]
    SYNC_PURPOSE_DEVICE_CONTACTS_CONSENT_CHANGE: _ClassVar[SyncPurpose]
    SYNC_EXHAUST_SALT: _ClassVar[SyncPurpose]
    SYNC_QUICKSHARE_IDENTITY_PROVIDER_QUERY: _ClassVar[SyncPurpose]

class ClientRole(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CLIENT_ROLE_UNKNOWN: _ClassVar[ClientRole]
    CLIENT_ROLE_SENDER: _ClassVar[ClientRole]
    CLIENT_ROLE_RECEIVER: _ClassVar[ClientRole]

class ScanType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_SCAN_TYPE: _ClassVar[ScanType]
    FOREGROUND_SCAN: _ClassVar[ScanType]
    FOREGROUND_RETRY_SCAN: _ClassVar[ScanType]
    DIRECT_SHARE_SCAN: _ClassVar[ScanType]
    BACKGROUND_SCAN: _ClassVar[ScanType]

class ParsingFailedType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    FAILED_UNKNOWN_TYPE: _ClassVar[ParsingFailedType]
    FAILED_PARSE_ADVERTISEMENT: _ClassVar[ParsingFailedType]
    FAILED_CONVERT_SHARE_TARGET: _ClassVar[ParsingFailedType]

class AdvertisingMode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_ADVERTISING_MODE: _ClassVar[AdvertisingMode]
    SCREEN_OFF_ADVERTISING_MODE: _ClassVar[AdvertisingMode]
    BACKGROUND_ADVERTISING_MODE: _ClassVar[AdvertisingMode]
    MIDGROUND_ADVERTISING_MODE: _ClassVar[AdvertisingMode]
    FOREGROUND_ADVERTISING_MODE: _ClassVar[AdvertisingMode]
    SUSPENDED_ADVERTISING_MODE: _ClassVar[AdvertisingMode]

class DiscoveryMode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_DISCOVERY_MODE: _ClassVar[DiscoveryMode]
    SCREEN_OFF_DISCOVERY_MODE: _ClassVar[DiscoveryMode]
    BACKGROUND_DISCOVERY_MODE: _ClassVar[DiscoveryMode]
    MIDGROUND_DISCOVERY_MODE: _ClassVar[DiscoveryMode]
    FOREGROUND_DISCOVERY_MODE: _ClassVar[DiscoveryMode]
    SUSPENDED_DISCOVERY_MODE: _ClassVar[DiscoveryMode]

class ActivityName(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_ACTIVITY: _ClassVar[ActivityName]
    SHARE_SHEET_ACTIVITY: _ClassVar[ActivityName]
    SETTINGS_ACTIVITY: _ClassVar[ActivityName]
    RECEIVE_SURFACE_ACTIVITY: _ClassVar[ActivityName]
    SETUP_ACTIVITY: _ClassVar[ActivityName]
    DEVICE_VISIBILITY_ACTIVITY: _ClassVar[ActivityName]
    CONSENTS_ACTIVITY: _ClassVar[ActivityName]
    SET_DEVICE_NAME_DIALOG: _ClassVar[ActivityName]
    SET_DATA_USAGE_DIALOG: _ClassVar[ActivityName]
    QUICK_SETTINGS_ACTIVITY: _ClassVar[ActivityName]
    REMOTE_COPY_SHARE_SHEET_ACTIVITY: _ClassVar[ActivityName]
    SETUP_WIZARD_ACTIVITY: _ClassVar[ActivityName]
    SETTINGS_REVIEW_ACTIVITY: _ClassVar[ActivityName]

class ConsentType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CONSENT_TYPE_UNKNOWN: _ClassVar[ConsentType]
    CONSENT_TYPE_C11N: _ClassVar[ConsentType]
    CONSENT_TYPE_DEVICE_CONTACT: _ClassVar[ConsentType]

class ConsentAcceptanceStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CONSENT_UNKNOWN_ACCEPT_STATUS: _ClassVar[ConsentAcceptanceStatus]
    CONSENT_ACCEPTED: _ClassVar[ConsentAcceptanceStatus]
    CONSENT_DECLINED: _ClassVar[ConsentAcceptanceStatus]
    CONSENT_UNABLE_TO_ENABLE: _ClassVar[ConsentAcceptanceStatus]

class ApkSource(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_APK_SOURCE: _ClassVar[ApkSource]
    APK_FROM_SD_CARD: _ClassVar[ApkSource]
    INSTALLED_APP: _ClassVar[ApkSource]

class InstallAPKStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_INSTALL_APK_STATUS: _ClassVar[InstallAPKStatus]
    FAIL_INSTALLATION: _ClassVar[InstallAPKStatus]
    SUCCESS_INSTALLATION: _ClassVar[InstallAPKStatus]

class VerifyAPKStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_VERIFY_APK_STATUS: _ClassVar[VerifyAPKStatus]
    NOT_INSTALLABLE: _ClassVar[VerifyAPKStatus]
    INSTALLABLE: _ClassVar[VerifyAPKStatus]
    ALREADY_INSTALLED: _ClassVar[VerifyAPKStatus]

class ShowNotificationStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    UNKNOWN_SHOW_NOTIFICATION_STATUS: _ClassVar[ShowNotificationStatus]
    SHOW: _ClassVar[ShowNotificationStatus]
    NOT_SHOW: _ClassVar[ShowNotificationStatus]

class PermissionRequestResult(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PERMISSION_UNKNOWN_REQUEST_RESULT: _ClassVar[PermissionRequestResult]
    PERMISSION_GRANTED: _ClassVar[PermissionRequestResult]
    PERMISSION_REJECTED: _ClassVar[PermissionRequestResult]
    PERMISSION_UNABLE_TO_GRANT: _ClassVar[PermissionRequestResult]

class PermissionRequestType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PERMISSION_UNKNOWN_TYPE: _ClassVar[PermissionRequestType]
    PERMISSION_AIRPLANE_MODE_OFF: _ClassVar[PermissionRequestType]
    PERMISSION_WIFI: _ClassVar[PermissionRequestType]
    PERMISSION_BLUETOOTH: _ClassVar[PermissionRequestType]
    PERMISSION_LOCATION: _ClassVar[PermissionRequestType]
    PERMISSION_WIFI_HOTSPOT: _ClassVar[PermissionRequestType]

class SharingUseCase(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    USE_CASE_UNKNOWN: _ClassVar[SharingUseCase]
    USE_CASE_NEARBY_SHARE: _ClassVar[SharingUseCase]
    USE_CASE_REMOTE_COPY_PASTE: _ClassVar[SharingUseCase]
    USE_CASE_WIFI_CREDENTIAL: _ClassVar[SharingUseCase]
    USE_CASE_APP_SHARE: _ClassVar[SharingUseCase]
    USE_CASE_QUICK_SETTING_FILE_SHARE: _ClassVar[SharingUseCase]
    USE_CASE_SETUP_WIZARD: _ClassVar[SharingUseCase]
    USE_CASE_NEARBY_SHARE_WITH_QR_CODE: _ClassVar[SharingUseCase]
    USE_CASE_REDIRECTED_FROM_BLUETOOTH_SHARE: _ClassVar[SharingUseCase]
    USE_CASE_TAP_TO_SHARE: _ClassVar[SharingUseCase]
    USE_CASE_FILE_SYNC: _ClassVar[SharingUseCase]

class SharingSurface(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SURFACE_UNKNOWN: _ClassVar[SharingSurface]
    SURFACE_QUICK_SHARE: _ClassVar[SharingSurface]
    SURFACE_APP: _ClassVar[SharingSurface]
    SURFACE_SYSTEM_SHARE_SHEET: _ClassVar[SharingSurface]

class AppCrashReason(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    APP_CRASH_REASON_UNKNOWN: _ClassVar[AppCrashReason]

class AttachmentSourceType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ATTACHMENT_SOURCE_UNKNOWN: _ClassVar[AttachmentSourceType]
    ATTACHMENT_SOURCE_CONTEXT_MENU: _ClassVar[AttachmentSourceType]
    ATTACHMENT_SOURCE_DRAG_AND_DROP: _ClassVar[AttachmentSourceType]
    ATTACHMENT_SOURCE_SELECT_FILES_BUTTON: _ClassVar[AttachmentSourceType]
    ATTACHMENT_SOURCE_PASTE: _ClassVar[AttachmentSourceType]
    ATTACHMENT_SOURCE_SELECT_FOLDERS_BUTTON: _ClassVar[AttachmentSourceType]
    ATTACHMENT_SOURCE_SHARE_ACTIVATION: _ClassVar[AttachmentSourceType]

class PreferencesAction(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PREFERENCES_ACTION_UNKNOWN: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_NO_ACTION: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_LOAD_PREFERENCES: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_SAVE_PREFERENCESS: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_ATTEMPT_LOAD: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_RESTORE_FROM_BACKUP: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_CREATE_PREFERENCES_PATH: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_MAKE_PREFERENCES_BACKUP_FILE: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_CHECK_IF_PREFERENCES_PATH_EXISTS: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_CHECK_IF_PREFERENCES_INPUT_STREAM_STATUS: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_CHECK_IF_PREFERENCES_FILE_IS_CORRUPTED: _ClassVar[PreferencesAction]
    PREFERENCES_ACTION_CHECK_IF_PREFERENCES_BACKUP_FILE_EXISTS: _ClassVar[PreferencesAction]

class PreferencesActionStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PREFERENCES_ACTION_STATUS_UNKNOWN: _ClassVar[PreferencesActionStatus]
    PREFERENCES_ACTION_STATUS_SUCCESS: _ClassVar[PreferencesActionStatus]
    PREFERENCES_ACTION_STATUS_FAIL: _ClassVar[PreferencesActionStatus]

class FastInitState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    FAST_INIT_UNKNOWN_STATE: _ClassVar[FastInitState]
    FAST_INIT_CLOSE_STATE: _ClassVar[FastInitState]
    FAST_INIT_FAR_STATE: _ClassVar[FastInitState]
    FAST_INIT_LOST_STATE: _ClassVar[FastInitState]

class FastInitType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    FAST_INIT_UNKNOWN_TYPE: _ClassVar[FastInitType]
    FAST_INIT_NOTIFY_TYPE: _ClassVar[FastInitType]
    FAST_INIT_SILENT_TYPE: _ClassVar[FastInitType]

class DesktopNotification(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DESKTOP_NOTIFICATION_UNKNOWN: _ClassVar[DesktopNotification]
    DESKTOP_NOTIFICATION_CONNECTING: _ClassVar[DesktopNotification]
    DESKTOP_NOTIFICATION_PROGRESS: _ClassVar[DesktopNotification]
    DESKTOP_NOTIFICATION_ACCEPT: _ClassVar[DesktopNotification]
    DESKTOP_NOTIFICATION_RECEIVED: _ClassVar[DesktopNotification]
    DESKTOP_NOTIFICATION_ERROR: _ClassVar[DesktopNotification]

class DesktopTransferEventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DESKTOP_TRANSFER_EVENT_TYPE_UNKNOWN: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_ACCEPT: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_PROGRESS: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_RECEIVED: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_ERROR: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_SEND_TYPE_START: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_SEND_TYPE_SELECT_A_DEVICE: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_SEND_TYPE_PROGRESS: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_SEND_TYPE_SENT: _ClassVar[DesktopTransferEventType]
    DESKTOP_TRANSFER_EVENT_SEND_TYPE_ERROR: _ClassVar[DesktopTransferEventType]

class DecryptCertificateFailureStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DECRYPT_CERT_UNKNOWN_FAILURE: _ClassVar[DecryptCertificateFailureStatus]
    DECRYPT_CERT_NO_SUCH_ALGORITHM_FAILURE: _ClassVar[DecryptCertificateFailureStatus]
    DECRYPT_CERT_NO_SUCH_PADDING_FAILURE: _ClassVar[DecryptCertificateFailureStatus]
    DECRYPT_CERT_INVALID_KEY_FAILURE: _ClassVar[DecryptCertificateFailureStatus]
    DECRYPT_CERT_INVALID_ALGORITHM_PARAMETER_FAILURE: _ClassVar[DecryptCertificateFailureStatus]
    DECRYPT_CERT_ILLEGAL_BLOCK_SIZE_FAILURE: _ClassVar[DecryptCertificateFailureStatus]
    DECRYPT_CERT_BAD_PADDING_FAILURE: _ClassVar[DecryptCertificateFailureStatus]

class ContactAccess(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CONTACT_ACCESS_UNKNOWN: _ClassVar[ContactAccess]
    CONTACT_ACCESS_NO_CONTACT_UPLOADED: _ClassVar[ContactAccess]
    CONTACT_ACCESS_ONLY_UPLOAD_GOOGLE_CONTACT: _ClassVar[ContactAccess]
    CONTACT_ACCESS_UPLOAD_CONTACT_FOR_DEVICE_CONTACT_CONSENT: _ClassVar[ContactAccess]
    CONTACT_ACCESS_UPLOAD_CONTACT_FOR_QUICK_SHARE_CONSENT: _ClassVar[ContactAccess]

class IdentityVerification(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    IDENTITY_VERIFICATION_UNKNOWN: _ClassVar[IdentityVerification]
    IDENTITY_VERIFICATION_NO_PHONE_NUMBER_VERIFIED: _ClassVar[IdentityVerification]
    IDENTITY_VERIFICATION_PHONE_NUMBER_VERIFIED_NOT_LINKED_TO_GAIA: _ClassVar[IdentityVerification]
    IDENTITY_VERIFICATION_PHONE_NUMBER_VERIFIED_LINKED_TO_QS_GAIA: _ClassVar[IdentityVerification]

class ButtonStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    BUTTON_STATUS_UNKNOWN: _ClassVar[ButtonStatus]
    BUTTON_STATUS_CLICK_ACCEPT: _ClassVar[ButtonStatus]
    BUTTON_STATUS_CLICK_REJECT: _ClassVar[ButtonStatus]
    BUTTON_STATUS_IGNORE: _ClassVar[ButtonStatus]

class CloudCreateSharingResult(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CLOUD_CREATE_SHARING_RESULT_UNKNOWN: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_SUCCESS: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_SIGN_IN_REQUIRE: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_ALREADY_EXIST: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_ALREADY_STARTED: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_NETWORK_ERROR: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_INVALID_ARGUMENT: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_REMOTE_ERROR: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_FILE_LIMIT_EXCEED_COUNT: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_FILE_LIMIT_EXCEED_SIZE: _ClassVar[CloudCreateSharingResult]
    CLOUD_CREATE_SHARING_RESULT_SUCCESS_NO_NOTIFICATION: _ClassVar[CloudCreateSharingResult]

class CloudRegisterReceiverResult(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CLOUD_REGISTER_RECEIVER_RESULT_UNKNOWN: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_SUCCESS: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_INVALID_ARGUMENT: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_DEADLINE_EXCEEDED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_INTERNAL: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_RESOURCE_EXHAUSTED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_UNAVAILABLE: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_PERMISSION_DENIED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_NOT_FOUND: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_ALREADY_EXISTS: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_UNAUTHENTICATED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_CANCELLED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_FAILED_PRECONDITION: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_ABORTED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_OUT_OF_RANGE: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_UNIMPLEMENTED: _ClassVar[CloudRegisterReceiverResult]
    CLOUD_REGISTER_RECEIVER_RESULT_DATA_LOSS: _ClassVar[CloudRegisterReceiverResult]

class CloudActionType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CLOUD_ACTION_TYPE_UNKNOWN: _ClassVar[CloudActionType]
    CLOUD_ACTION_TYPE_NORMAL: _ClassVar[CloudActionType]
    CLOUD_ACTION_TYPE_RETRY: _ClassVar[CloudActionType]

class PowerStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    POWER_STATUS_UNKNOWN: _ClassVar[PowerStatus]
    POWER_STATUS_BATTERY: _ClassVar[PowerStatus]
    POWER_STATUS_AC: _ClassVar[PowerStatus]
    POWER_STATUS_BATTERY_AND_AC: _ClassVar[PowerStatus]
UNKNOWN_EVENT_TYPE: EventType
ACCEPT_AGREEMENTS: EventType
ENABLE_NEARBY_SHARING: EventType
SET_VISIBILITY: EventType
DESCRIBE_ATTACHMENTS: EventType
SCAN_FOR_SHARE_TARGETS_START: EventType
SCAN_FOR_SHARE_TARGETS_END: EventType
ADVERTISE_DEVICE_PRESENCE_START: EventType
ADVERTISE_DEVICE_PRESENCE_END: EventType
SEND_FAST_INITIALIZATION: EventType
RECEIVE_FAST_INITIALIZATION: EventType
DISCOVER_SHARE_TARGET: EventType
SEND_INTRODUCTION: EventType
RECEIVE_INTRODUCTION: EventType
RESPOND_TO_INTRODUCTION: EventType
SEND_ATTACHMENTS_START: EventType
SEND_ATTACHMENTS_END: EventType
RECEIVE_ATTACHMENTS_START: EventType
RECEIVE_ATTACHMENTS_END: EventType
CANCEL_SENDING_ATTACHMENTS: EventType
CANCEL_RECEIVING_ATTACHMENTS: EventType
OPEN_RECEIVED_ATTACHMENTS: EventType
LAUNCH_SETUP_ACTIVITY: EventType
ADD_CONTACT: EventType
REMOVE_CONTACT: EventType
FAST_SHARE_SERVER_RESPONSE: EventType
SEND_START: EventType
ACCEPT_FAST_INITIALIZATION: EventType
SET_DATA_USAGE: EventType
DISMISS_FAST_INITIALIZATION: EventType
CANCEL_CONNECTION: EventType
LAUNCH_ACTIVITY: EventType
DISMISS_PRIVACY_NOTIFICATION: EventType
TAP_PRIVACY_NOTIFICATION: EventType
TAP_HELP: EventType
TAP_FEEDBACK: EventType
ADD_QUICK_SETTINGS_TILE: EventType
REMOVE_QUICK_SETTINGS_TILE: EventType
LAUNCH_PHONE_CONSENT: EventType
DISPLAY_PHONE_CONSENT: EventType
TAP_QUICK_SETTINGS_TILE: EventType
INSTALL_APK: EventType
VERIFY_APK: EventType
LAUNCH_CONSENT: EventType
PROCESS_RECEIVED_ATTACHMENTS_END: EventType
TOGGLE_SHOW_NOTIFICATION: EventType
SET_DEVICE_NAME: EventType
DECLINE_AGREEMENTS: EventType
REQUEST_SETTING_PERMISSIONS: EventType
ESTABLISH_CONNECTION: EventType
DEVICE_SETTINGS: EventType
AUTO_DISMISS_FAST_INITIALIZATION: EventType
APP_CRASH: EventType
TAP_QUICK_SETTINGS_FILE_SHARE: EventType
DISPLAY_PRIVACY_NOTIFICATION: EventType
PREFERENCES_USAGE: EventType
DEFAULT_OPT_IN: EventType
SETUP_WIZARD: EventType
TAP_QR_CODE: EventType
QR_CODE_LINK_SHOWN: EventType
PARSING_FAILED_ENDPOINT_ID: EventType
FAST_INIT_DISCOVER_DEVICE: EventType
SEND_DESKTOP_NOTIFICATION: EventType
SET_ACCOUNT: EventType
DECRYPT_CERTIFICATE_FAILURE: EventType
SHOW_ALLOW_PERMISSION_AUTO_ACCESS: EventType
SEND_DESKTOP_TRANSFER_EVENT: EventType
WAITING_FOR_ACCEPT: EventType
HIGH_QUALITY_MEDIUM_SETUP: EventType
RPC_CALL_STATUS: EventType
START_QR_CODE_SESSION: EventType
QR_CODE_OPENED_IN_WEB_CLIENT: EventType
HATS_JOINT_EVENT: EventType
RECEIVE_PREVIEWS: EventType
CLOUD_CREATE_SHARING_REQUEST: EventType
CLOUD_REGISTER_RECEIVER: EventType
CLOUD_UPLOAD_START: EventType
CLOUD_UPLOAD_END: EventType
CLOUD_DOWNLOAD_START: EventType
CLOUD_DOWNLOAD_END: EventType
CLOUD_SHARING_RPC_RESULT: EventType
PROVIDER_CONNECTED: EventType
UNKNOWN_EVENT_CATEGORY: EventCategory
SENDING_EVENT: EventCategory
RECEIVING_EVENT: EventCategory
SETTINGS_EVENT: EventCategory
RPC_EVENT: EventCategory
UNKNOWN_NEARBY_SHARING_STATUS: NearbySharingStatus
ON: NearbySharingStatus
OFF: NearbySharingStatus
UNKNOWN_VISIBILITY: Visibility
CONTACTS_ONLY: Visibility
EVERYONE: Visibility
SELECTED_CONTACTS_ONLY: Visibility
HIDDEN: Visibility
SELF_SHARE: Visibility
FAMILY: Visibility
UNKNOWN_DATA_USAGE: DataUsage
ONLINE: DataUsage
WIFI_ONLY: DataUsage
OFFLINE: DataUsage
CONNECTION_STATUS_UNKNOWN: EstablishConnectionStatus
CONNECTION_STATUS_SUCCESS: EstablishConnectionStatus
CONNECTION_STATUS_FAILURE: EstablishConnectionStatus
CONNECTION_STATUS_CANCELLATION: EstablishConnectionStatus
CONNECTION_STATUS_MEDIA_UNAVAILABLE_ATTACHMENT: EstablishConnectionStatus
CONNECTION_STATUS_FAILED_PAIRED_KEYHANDSHAKE: EstablishConnectionStatus
CONNECTION_STATUS_FAILED_WRITE_INTRODUCTION: EstablishConnectionStatus
CONNECTION_STATUS_FAILED_NULL_CONNECTION: EstablishConnectionStatus
CONNECTION_STATUS_FAILED_NO_TRANSFER_UPDATE_CALLBACK: EstablishConnectionStatus
CONNECTION_STATUS_LOST_CONNECTIVITY: EstablishConnectionStatus
CONNECTION_STATUS_INVALID_ADVERTISEMENT: EstablishConnectionStatus
UNKNOWN_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
COMPLETE_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
CANCELED_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
FAILED_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
REJECTED_ATTACHMENT: AttachmentTransmissionStatus
TIMED_OUT_ATTACHMENT: AttachmentTransmissionStatus
AWAITING_REMOTE_ACCEPTANCE_FAILED_ATTACHMENT: AttachmentTransmissionStatus
NOT_ENOUGH_SPACE_ATTACHMENT: AttachmentTransmissionStatus
FAILED_NO_TRANSFER_UPDATE_CALLBACK: AttachmentTransmissionStatus
MEDIA_UNAVAILABLE_ATTACHMENT: AttachmentTransmissionStatus
UNSUPPORTED_ATTACHMENT_TYPE_ATTACHMENT: AttachmentTransmissionStatus
NO_ATTACHMENT_FOUND: AttachmentTransmissionStatus
FAILED_NO_SHARE_TARGET_ENDPOINT: AttachmentTransmissionStatus
FAILED_PAIRED_KEYHANDSHAKE: AttachmentTransmissionStatus
FAILED_NULL_CONNECTION: AttachmentTransmissionStatus
FAILED_NO_PAYLOAD: AttachmentTransmissionStatus
FAILED_WRITE_INTRODUCTION: AttachmentTransmissionStatus
FAILED_UNKNOWN_REMOTE_RESPONSE: AttachmentTransmissionStatus
FAILED_NULL_CONNECTION_INIT_OUTGOING: AttachmentTransmissionStatus
FAILED_NULL_CONNECTION_DISCONNECTED: AttachmentTransmissionStatus
FAILED_NULL_CONNECTION_LOST_CONNECTIVITY: AttachmentTransmissionStatus
FAILED_NULL_CONNECTION_FAILURE: AttachmentTransmissionStatus
REJECTED_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
TIMED_OUT_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
NOT_ENOUGH_SPACE_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
UNSUPPORTED_ATTACHMENT_TYPE_ATTACHMENT_TRANSMISSION_STATUS: AttachmentTransmissionStatus
FAILED_UNKNOWN_REMOTE_RESPONSE_TRANSMISSION_STATUS: AttachmentTransmissionStatus
NO_RESPONSE_FRAME_CONNECTION_CLOSED_LOST_CONNECTIVITY_TRANSMISSION_STATUS: AttachmentTransmissionStatus
NO_RESPONSE_FRAME_CONNECTION_CLOSED_TRANSMISSION_STATUS: AttachmentTransmissionStatus
LOST_CONNECTIVITY_TRANSMISSION_STATUS: AttachmentTransmissionStatus
FAILED_DISALLOWED_MEDIUM: AttachmentTransmissionStatus
CONNECTION_LAYER_STATUS_UNKNOWN: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_SUCCESS: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_ERROR: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_OUT_OF_ORDER_API_CALL: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_ALREADY_HAVE_ACTIVE_STRATEGY: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_ALREADY_ADVERTISING: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_ALREADY_DISCOVERING: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_ALREADY_LISTENING: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_END_POINT_IO_ERROR: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_END_POINT_UNKNOWN: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_CONNECTION_REJECTED: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_ALREADY_CONNECTED_TO_END_POINT: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_NOT_CONNECTED_TO_END_POINT: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_BLUETOOTH_ERROR: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_BLE_ERROR: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_WIFI_LAN_ERROR: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_PAYLOAD_UNKNOWN: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_RESET: ConnectionLayerStatus
CONNECTION_LAYER_STATUS_TIMEOUT: ConnectionLayerStatus
PROCESSING_STATUS_UNKNOWN: ProcessReceivedAttachmentsStatus
PROCESSING_STATUS_COMPLETE_PROCESSING_ATTACHMENTS: ProcessReceivedAttachmentsStatus
PROCESSING_STATUS_FAILED_MOVING_FILES: ProcessReceivedAttachmentsStatus
PROCESSING_STATUS_FAILED_RECEIVING_APK: ProcessReceivedAttachmentsStatus
PROCESSING_STATUS_FAILED_RECEIVING_TEXT: ProcessReceivedAttachmentsStatus
PROCESSING_STATUS_FAILED_RECEIVING_WIFI_CREDENTIALS: ProcessReceivedAttachmentsStatus
UNKNOWN_SESSION_STATUS: SessionStatus
SUCCEEDED_SESSION_STATUS: SessionStatus
FAILED_SESSION_STATUS: SessionStatus
UNKNOWN_RESPONSE_TO_INTRODUCTION: ResponseToIntroduction
ACCEPT_INTRODUCTION: ResponseToIntroduction
REJECT_INTRODUCTION: ResponseToIntroduction
FAIL_INTRODUCTION: ResponseToIntroduction
UNKNOWN_DEVICE_TYPE: DeviceType
PHONE: DeviceType
TABLET: DeviceType
LAPTOP: DeviceType
CAR: DeviceType
FOLDABLE: DeviceType
XR: DeviceType
UNKNOWN_OS_TYPE: OSType
ANDROID: OSType
CHROME_OS: OSType
IOS: OSType
WINDOWS: OSType
MACOS: OSType
UNKNOWN_DEVICE_RELATIONSHIP: DeviceRelationship
IS_SELF: DeviceRelationship
IS_CONTACT: DeviceRelationship
IS_STRANGER: DeviceRelationship
UNSPECIFIED_SOURCE: LogSource
LAB_DEVICES: LogSource
INTERNAL_DEVICES: LogSource
BETA_TESTER_DEVICES: LogSource
OEM_DEVICES: LogSource
DEBUG_DEVICES: LogSource
NEARBY_MODULE_FOOD_DEVICES: LogSource
BETO_DOGFOOD_DEVICES: LogSource
NEARBY_DOGFOOD_DEVICES: LogSource
NEARBY_TEAMFOOD_DEVICES: LogSource
UNKNOWN_SERVER_ACTION: ServerActionName
UPLOAD_CERTIFICATES: ServerActionName
DOWNLOAD_CERTIFICATES: ServerActionName
CHECK_REACHABILITY: ServerActionName
UPLOAD_CONTACTS: ServerActionName
UPDATE_DEVICE_NAME: ServerActionName
UPLOAD_SENDER_CERTIFICATES: ServerActionName
DOWNLOAD_SENDER_CERTIFICATES: ServerActionName
UPLOAD_CONTACTS_AND_CERTIFICATES: ServerActionName
LIST_REACHABLE_PHONE_NUMBERS: ServerActionName
LIST_MY_DEVICES: ServerActionName
LIST_CONTACT_PEOPLE: ServerActionName
DOWNLOAD_CERTIFICATES_INFO: ServerActionName
UNKNOWN_SERVER_RESPONSE_STATE: ServerResponseState
SERVER_RESPONSE_SUCCESS: ServerResponseState
SERVER_RESPONSE_UNKNOWN_FAILURE: ServerResponseState
SERVER_RESPONSE_STATUS_OTHER_FAILURE: ServerResponseState
SERVER_RESPONSE_STATUS_DEADLINE_EXCEEDED: ServerResponseState
SERVER_RESPONSE_STATUS_PERMISSION_DENIED: ServerResponseState
SERVER_RESPONSE_STATUS_UNAVAILABLE: ServerResponseState
SERVER_RESPONSE_STATUS_UNAUTHENTICATED: ServerResponseState
SERVER_RESPONSE_STATUS_INVALID_ARGUMENT: ServerResponseState
SERVER_RESPONSE_GOOGLE_AUTH_FAILURE: ServerResponseState
SERVER_RESPONSE_NOT_CONNECTED_TO_INTERNET: ServerResponseState
SYNC_PURPOSE_UNKNOWN: SyncPurpose
SYNC_PURPOSE_ON_DEMAND_SYNC: SyncPurpose
SYNC_PURPOSE_CHIME_NOTIFICATION: SyncPurpose
SYNC_PURPOSE_DAILY_SYNC: SyncPurpose
SYNC_PURPOSE_OPT_IN_FIRST_SYNC: SyncPurpose
SYNC_PURPOSE_CHECK_DEFAULT_OPT_IN: SyncPurpose
SYNC_PURPOSE_NEARBY_SHARE_ENABLED: SyncPurpose
SYNC_PURPOSE_SYNC_AT_FAST_INIT: SyncPurpose
SYNC_PURPOSE_SYNC_AT_DISCOVERY: SyncPurpose
SYNC_PURPOSE_SYNC_AT_LOAD_PRIVATE_CERTIFICATE: SyncPurpose
SYNC_PURPOSE_SYNC_AT_ADVERTISEMENT: SyncPurpose
SYNC_PURPOSE_CONTACT_LIST_CHANGE: SyncPurpose
SYNC_PURPOSE_SHOW_C11N_VIEW: SyncPurpose
SYNC_PURPOSE_REGULAR_CHECK_CONTACT_REACHABILITY: SyncPurpose
SYNC_PURPOSE_VISIBILITY_SELECTED_CONTACT_CHANGE: SyncPurpose
SYNC_PURPOSE_ACCOUNT_CHANGE: SyncPurpose
SYNC_PURPOSE_REGENERATE_CERTIFICATES: SyncPurpose
SYNC_PURPOSE_DEVICE_CONTACTS_CONSENT_CHANGE: SyncPurpose
SYNC_EXHAUST_SALT: SyncPurpose
SYNC_QUICKSHARE_IDENTITY_PROVIDER_QUERY: SyncPurpose
CLIENT_ROLE_UNKNOWN: ClientRole
CLIENT_ROLE_SENDER: ClientRole
CLIENT_ROLE_RECEIVER: ClientRole
UNKNOWN_SCAN_TYPE: ScanType
FOREGROUND_SCAN: ScanType
FOREGROUND_RETRY_SCAN: ScanType
DIRECT_SHARE_SCAN: ScanType
BACKGROUND_SCAN: ScanType
FAILED_UNKNOWN_TYPE: ParsingFailedType
FAILED_PARSE_ADVERTISEMENT: ParsingFailedType
FAILED_CONVERT_SHARE_TARGET: ParsingFailedType
UNKNOWN_ADVERTISING_MODE: AdvertisingMode
SCREEN_OFF_ADVERTISING_MODE: AdvertisingMode
BACKGROUND_ADVERTISING_MODE: AdvertisingMode
MIDGROUND_ADVERTISING_MODE: AdvertisingMode
FOREGROUND_ADVERTISING_MODE: AdvertisingMode
SUSPENDED_ADVERTISING_MODE: AdvertisingMode
UNKNOWN_DISCOVERY_MODE: DiscoveryMode
SCREEN_OFF_DISCOVERY_MODE: DiscoveryMode
BACKGROUND_DISCOVERY_MODE: DiscoveryMode
MIDGROUND_DISCOVERY_MODE: DiscoveryMode
FOREGROUND_DISCOVERY_MODE: DiscoveryMode
SUSPENDED_DISCOVERY_MODE: DiscoveryMode
UNKNOWN_ACTIVITY: ActivityName
SHARE_SHEET_ACTIVITY: ActivityName
SETTINGS_ACTIVITY: ActivityName
RECEIVE_SURFACE_ACTIVITY: ActivityName
SETUP_ACTIVITY: ActivityName
DEVICE_VISIBILITY_ACTIVITY: ActivityName
CONSENTS_ACTIVITY: ActivityName
SET_DEVICE_NAME_DIALOG: ActivityName
SET_DATA_USAGE_DIALOG: ActivityName
QUICK_SETTINGS_ACTIVITY: ActivityName
REMOTE_COPY_SHARE_SHEET_ACTIVITY: ActivityName
SETUP_WIZARD_ACTIVITY: ActivityName
SETTINGS_REVIEW_ACTIVITY: ActivityName
CONSENT_TYPE_UNKNOWN: ConsentType
CONSENT_TYPE_C11N: ConsentType
CONSENT_TYPE_DEVICE_CONTACT: ConsentType
CONSENT_UNKNOWN_ACCEPT_STATUS: ConsentAcceptanceStatus
CONSENT_ACCEPTED: ConsentAcceptanceStatus
CONSENT_DECLINED: ConsentAcceptanceStatus
CONSENT_UNABLE_TO_ENABLE: ConsentAcceptanceStatus
UNKNOWN_APK_SOURCE: ApkSource
APK_FROM_SD_CARD: ApkSource
INSTALLED_APP: ApkSource
UNKNOWN_INSTALL_APK_STATUS: InstallAPKStatus
FAIL_INSTALLATION: InstallAPKStatus
SUCCESS_INSTALLATION: InstallAPKStatus
UNKNOWN_VERIFY_APK_STATUS: VerifyAPKStatus
NOT_INSTALLABLE: VerifyAPKStatus
INSTALLABLE: VerifyAPKStatus
ALREADY_INSTALLED: VerifyAPKStatus
UNKNOWN_SHOW_NOTIFICATION_STATUS: ShowNotificationStatus
SHOW: ShowNotificationStatus
NOT_SHOW: ShowNotificationStatus
PERMISSION_UNKNOWN_REQUEST_RESULT: PermissionRequestResult
PERMISSION_GRANTED: PermissionRequestResult
PERMISSION_REJECTED: PermissionRequestResult
PERMISSION_UNABLE_TO_GRANT: PermissionRequestResult
PERMISSION_UNKNOWN_TYPE: PermissionRequestType
PERMISSION_AIRPLANE_MODE_OFF: PermissionRequestType
PERMISSION_WIFI: PermissionRequestType
PERMISSION_BLUETOOTH: PermissionRequestType
PERMISSION_LOCATION: PermissionRequestType
PERMISSION_WIFI_HOTSPOT: PermissionRequestType
USE_CASE_UNKNOWN: SharingUseCase
USE_CASE_NEARBY_SHARE: SharingUseCase
USE_CASE_REMOTE_COPY_PASTE: SharingUseCase
USE_CASE_WIFI_CREDENTIAL: SharingUseCase
USE_CASE_APP_SHARE: SharingUseCase
USE_CASE_QUICK_SETTING_FILE_SHARE: SharingUseCase
USE_CASE_SETUP_WIZARD: SharingUseCase
USE_CASE_NEARBY_SHARE_WITH_QR_CODE: SharingUseCase
USE_CASE_REDIRECTED_FROM_BLUETOOTH_SHARE: SharingUseCase
USE_CASE_TAP_TO_SHARE: SharingUseCase
USE_CASE_FILE_SYNC: SharingUseCase
SURFACE_UNKNOWN: SharingSurface
SURFACE_QUICK_SHARE: SharingSurface
SURFACE_APP: SharingSurface
SURFACE_SYSTEM_SHARE_SHEET: SharingSurface
APP_CRASH_REASON_UNKNOWN: AppCrashReason
ATTACHMENT_SOURCE_UNKNOWN: AttachmentSourceType
ATTACHMENT_SOURCE_CONTEXT_MENU: AttachmentSourceType
ATTACHMENT_SOURCE_DRAG_AND_DROP: AttachmentSourceType
ATTACHMENT_SOURCE_SELECT_FILES_BUTTON: AttachmentSourceType
ATTACHMENT_SOURCE_PASTE: AttachmentSourceType
ATTACHMENT_SOURCE_SELECT_FOLDERS_BUTTON: AttachmentSourceType
ATTACHMENT_SOURCE_SHARE_ACTIVATION: AttachmentSourceType
PREFERENCES_ACTION_UNKNOWN: PreferencesAction
PREFERENCES_ACTION_NO_ACTION: PreferencesAction
PREFERENCES_ACTION_LOAD_PREFERENCES: PreferencesAction
PREFERENCES_ACTION_SAVE_PREFERENCESS: PreferencesAction
PREFERENCES_ACTION_ATTEMPT_LOAD: PreferencesAction
PREFERENCES_ACTION_RESTORE_FROM_BACKUP: PreferencesAction
PREFERENCES_ACTION_CREATE_PREFERENCES_PATH: PreferencesAction
PREFERENCES_ACTION_MAKE_PREFERENCES_BACKUP_FILE: PreferencesAction
PREFERENCES_ACTION_CHECK_IF_PREFERENCES_PATH_EXISTS: PreferencesAction
PREFERENCES_ACTION_CHECK_IF_PREFERENCES_INPUT_STREAM_STATUS: PreferencesAction
PREFERENCES_ACTION_CHECK_IF_PREFERENCES_FILE_IS_CORRUPTED: PreferencesAction
PREFERENCES_ACTION_CHECK_IF_PREFERENCES_BACKUP_FILE_EXISTS: PreferencesAction
PREFERENCES_ACTION_STATUS_UNKNOWN: PreferencesActionStatus
PREFERENCES_ACTION_STATUS_SUCCESS: PreferencesActionStatus
PREFERENCES_ACTION_STATUS_FAIL: PreferencesActionStatus
FAST_INIT_UNKNOWN_STATE: FastInitState
FAST_INIT_CLOSE_STATE: FastInitState
FAST_INIT_FAR_STATE: FastInitState
FAST_INIT_LOST_STATE: FastInitState
FAST_INIT_UNKNOWN_TYPE: FastInitType
FAST_INIT_NOTIFY_TYPE: FastInitType
FAST_INIT_SILENT_TYPE: FastInitType
DESKTOP_NOTIFICATION_UNKNOWN: DesktopNotification
DESKTOP_NOTIFICATION_CONNECTING: DesktopNotification
DESKTOP_NOTIFICATION_PROGRESS: DesktopNotification
DESKTOP_NOTIFICATION_ACCEPT: DesktopNotification
DESKTOP_NOTIFICATION_RECEIVED: DesktopNotification
DESKTOP_NOTIFICATION_ERROR: DesktopNotification
DESKTOP_TRANSFER_EVENT_TYPE_UNKNOWN: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_ACCEPT: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_PROGRESS: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_RECEIVED: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_RECEIVE_TYPE_ERROR: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_SEND_TYPE_START: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_SEND_TYPE_SELECT_A_DEVICE: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_SEND_TYPE_PROGRESS: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_SEND_TYPE_SENT: DesktopTransferEventType
DESKTOP_TRANSFER_EVENT_SEND_TYPE_ERROR: DesktopTransferEventType
DECRYPT_CERT_UNKNOWN_FAILURE: DecryptCertificateFailureStatus
DECRYPT_CERT_NO_SUCH_ALGORITHM_FAILURE: DecryptCertificateFailureStatus
DECRYPT_CERT_NO_SUCH_PADDING_FAILURE: DecryptCertificateFailureStatus
DECRYPT_CERT_INVALID_KEY_FAILURE: DecryptCertificateFailureStatus
DECRYPT_CERT_INVALID_ALGORITHM_PARAMETER_FAILURE: DecryptCertificateFailureStatus
DECRYPT_CERT_ILLEGAL_BLOCK_SIZE_FAILURE: DecryptCertificateFailureStatus
DECRYPT_CERT_BAD_PADDING_FAILURE: DecryptCertificateFailureStatus
CONTACT_ACCESS_UNKNOWN: ContactAccess
CONTACT_ACCESS_NO_CONTACT_UPLOADED: ContactAccess
CONTACT_ACCESS_ONLY_UPLOAD_GOOGLE_CONTACT: ContactAccess
CONTACT_ACCESS_UPLOAD_CONTACT_FOR_DEVICE_CONTACT_CONSENT: ContactAccess
CONTACT_ACCESS_UPLOAD_CONTACT_FOR_QUICK_SHARE_CONSENT: ContactAccess
IDENTITY_VERIFICATION_UNKNOWN: IdentityVerification
IDENTITY_VERIFICATION_NO_PHONE_NUMBER_VERIFIED: IdentityVerification
IDENTITY_VERIFICATION_PHONE_NUMBER_VERIFIED_NOT_LINKED_TO_GAIA: IdentityVerification
IDENTITY_VERIFICATION_PHONE_NUMBER_VERIFIED_LINKED_TO_QS_GAIA: IdentityVerification
BUTTON_STATUS_UNKNOWN: ButtonStatus
BUTTON_STATUS_CLICK_ACCEPT: ButtonStatus
BUTTON_STATUS_CLICK_REJECT: ButtonStatus
BUTTON_STATUS_IGNORE: ButtonStatus
CLOUD_CREATE_SHARING_RESULT_UNKNOWN: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_SUCCESS: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_SIGN_IN_REQUIRE: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_ALREADY_EXIST: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_ALREADY_STARTED: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_NETWORK_ERROR: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_INVALID_ARGUMENT: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_REMOTE_ERROR: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_FILE_LIMIT_EXCEED_COUNT: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_FILE_LIMIT_EXCEED_SIZE: CloudCreateSharingResult
CLOUD_CREATE_SHARING_RESULT_SUCCESS_NO_NOTIFICATION: CloudCreateSharingResult
CLOUD_REGISTER_RECEIVER_RESULT_UNKNOWN: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_SUCCESS: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_INVALID_ARGUMENT: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_DEADLINE_EXCEEDED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_INTERNAL: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_RESOURCE_EXHAUSTED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_UNAVAILABLE: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_PERMISSION_DENIED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_NOT_FOUND: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_ALREADY_EXISTS: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_UNAUTHENTICATED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_CANCELLED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_FAILED_PRECONDITION: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_ABORTED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_OUT_OF_RANGE: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_UNIMPLEMENTED: CloudRegisterReceiverResult
CLOUD_REGISTER_RECEIVER_RESULT_DATA_LOSS: CloudRegisterReceiverResult
CLOUD_ACTION_TYPE_UNKNOWN: CloudActionType
CLOUD_ACTION_TYPE_NORMAL: CloudActionType
CLOUD_ACTION_TYPE_RETRY: CloudActionType
POWER_STATUS_UNKNOWN: PowerStatus
POWER_STATUS_BATTERY: PowerStatus
POWER_STATUS_AC: PowerStatus
POWER_STATUS_BATTERY_AND_AC: PowerStatus
