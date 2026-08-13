"""mDNS advertisement for Quick Share, per Google's own source at
https://github.com/google/nearby.

Two layers are involved:

1. `sharing.Advertisement` (github.com/google/nearby: sharing/advertisement.{h,cc})
   -- the Quick Share-specific "endpoint info" payload: device type,
   optional device name, and (normally) an encrypted certificate-metadata
   key used for contact verification. Carried in the mDNS TXT record.

2. `connections.WifiLanServiceInfo`
   (github.com/google/nearby: connections/implementation/wifi_lan_service_info.{h,cc})
   -- the Nearby Connections transport envelope: PCP/version byte, endpoint
   id, and a truncated hash of the service id. Carried in the mDNS service
   instance name.

The mDNS service TYPE itself is computed, not a magic constant --
`WifiLan::GenerateServiceType` (mediums/wifi_lan.cc) hex-encodes the first
6 bytes of SHA-256("NearbySharing") uppercase, which is independently
verified here to equal "FC9F5ED42C8A". The service id hash embedded in the
instance name (3 bytes) is a shorter truncation of the same digest.
"""

from __future__ import annotations

import base64
import hashlib
import random
import socket
import string
from enum import IntEnum

# sharing/nearby_connections_manager_impl.cc: kServiceId = "NearbySharing"
_SERVICE_ID = b"NearbySharing"
_SERVICE_ID_DIGEST = hashlib.sha256(_SERVICE_ID).digest()

# connections/implementation/mediums/wifi_lan.cc: GenerateServiceType()
# internal/platform/nsd_service_info.h: kTypeFromServiceIdHashLength = 6, kNsdTypeFormat = "_%s._tcp."
SERVICE_TYPE_HASH_LENGTH = 6
SERVICE_TYPE = "_" + _SERVICE_ID_DIGEST[:SERVICE_TYPE_HASH_LENGTH].hex().upper() + "._tcp.local."
assert SERVICE_TYPE == "_FC9F5ED42C8A._tcp.local."

# connections/implementation/wifi_lan_service_info.h: kServiceIdHashLength = 3
_INSTANCE_SERVICE_ID_HASH_LENGTH = 3
_INSTANCE_SERVICE_ID_HASH = _SERVICE_ID_DIGEST[:_INSTANCE_SERVICE_ID_HASH_LENGTH]

# connections/implementation/wifi_lan_service_info.h: kKeyEndpointInfo = "n"
TXT_KEY_ENDPOINT_INFO = "n"

# internal/platform/implementation/windows/wifi_lan_medium.cc: kDeviceIpv4 = "IPv4".
# Read there as a fallback IP source on the discovery side when the OS-level
# mDNS resolution (System.Devices.IPAddress) doesn't yield one -- confirmed
# present (dotted-quad ASCII) in a live capture of a real Android phone's
# advertisement, which our own advertisement was missing.
TXT_KEY_IPV4 = "IPv4"

# connections/implementation/client_proxy.cc: kEndpointIdChars, kEndpointIdLength = 4
_ENDPOINT_ID_ALPHABET = string.ascii_uppercase + "1234567890"
_ENDPOINT_ID_LENGTH = 4

# connections/implementation/pcp.h
_PCP_P2P_POINT_TO_POINT = 3  # Pcp::kP2pPointToPoint -- matches a live-captured advertisement on this LAN
WIFI_LAN_SERVICE_INFO_VERSION = 1  # WifiLanServiceInfo::Version::kV1 -- shared with discover.py's parser


class ShareTargetType(IntEnum):
    """sharing/common/nearby_share_enums.h: ShareTargetType."""

    UNKNOWN = 0
    PHONE = 1
    TABLET = 2
    LAPTOP = 3
    CAR = 4
    FOLDABLE = 5
    XR = 6


def _web_safe_base64_encode(data: bytes) -> str:
    """internal/platform/base64_utils.cc: Base64Utils::Encode ->
    absl::WebSafeBase64Escape(bytes), which does NOT pad.

    The earlier revision of this function padded, on the mistaken belief that
    absl's web-safe variant pads like the standard one. It doesn't -- and the
    difference is visible on the wire from every real implementation (a
    live-captured Android phone and the Packet app both emit unpadded values,
    both for the service instance name and the TXT 'n' value). Android's own
    parser tolerated our stray '=' padding, but a literal '=' inside a DNS
    instance label is exactly the kind of thing a stricter stack (Windows)
    can silently choke on."""
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _machine_unique_seed() -> str:
    """A stable per-machine salt for endpoint-ID derivation.

    Hostname alone is not enough: two hosts cloned from the same image (or
    otherwise sharing a hostname, e.g. via DHCP) produce the same endpoint ID
    and therefore the same mDNS instance name. zeroconf then rejects the second
    advertiser with NonUniqueNameException. Mixing in the MAC address keeps the
    ID stable across restarts (the phone still recognizes this machine) while
    making colliding hostnames diverge.
    """
    hostname = socket.gethostname()
    try:
        with open("/sys/class/net/wlan0/address", encoding="utf-8") as f:
            mac = f.read().strip()
    except OSError:
        try:
            import uuid
            mac = uuid.getnode().to_bytes(6, "big").hex(":")
        except Exception:
            mac = "00:00:00:00:00:00"
    return f"{hostname}|{mac}"


def stable_endpoint_id() -> bytes:
    """Deterministic endpoint ID derived from the machine (hostname + MAC), so
    this machine keeps the same identity across restarts instead of appearing
    as a new device to the phone on every run.

    Hashed rather than using the seed directly, since it must fit the same
    4-character alphabet (connections/implementation/client_proxy.cc:
    kEndpointIdChars, [A-Z1-9 0]) that a real endpoint ID uses.
    """
    digest = hashlib.sha256(_machine_unique_seed().encode("utf-8")).digest()
    alphabet_len = len(_ENDPOINT_ID_ALPHABET)
    return "".join(_ENDPOINT_ID_ALPHABET[b % alphabet_len] for b in digest[:_ENDPOINT_ID_LENGTH]).encode("ascii")


def build_service_instance_name(endpoint_id: bytes) -> str:
    """WifiLanServiceInfo::operator NsdServiceInfo() (wifi_lan_service_info.cc).

    [1 byte: (version&0b111)<<5 | (pcp&0b11111)] + endpoint_id(4) + service_id_hash(3)
    + two trailing zero bytes, then base64(WebSafe, unpadded).

    The two trailing zeros are the empty-UWB-address / WebRTC-state trailer.
    An earlier revision omitted them ("only appended when present"), which
    Android's parser accepted -- but every real advertiser writes them: a
    live-captured Android phone and the Packet app both produce 10-byte
    payloads (14 base64 chars ending 'AAA'). Windows' stricter
    WifiLanServiceInfo parser is the consumer that cares: with the 8-byte
    form, Windows resolved our records and reachability-probed us but never
    listed the device.
    """
    if len(endpoint_id) != _ENDPOINT_ID_LENGTH:
        raise ValueError(f"endpoint_id must be exactly {_ENDPOINT_ID_LENGTH} bytes")
    version_and_pcp = ((WIFI_LAN_SERVICE_INFO_VERSION & 0b111) << 5) | (_PCP_P2P_POINT_TO_POINT & 0b11111)
    payload = bytes([version_and_pcp]) + endpoint_id + _INSTANCE_SERVICE_ID_HASH + b"\x00\x00"
    return _web_safe_base64_encode(payload)


# sharing/advertisement.h / advertisement.cc -- shared with discover.py's parser
ADVERTISEMENT_SALT_SIZE = 2
ADVERTISEMENT_METADATA_KEY_SIZE = 14
_ADVERTISEMENT_VERSION = 0
_TLV_TYPE_VENDOR_ID = 2
_TLV_TYPE_CAPABILITIES = 3


def build_endpoint_info(device_name: str | None, device_type: ShareTargetType) -> bytes:
    """sharing::Advertisement::ToEndpointInfo (sharing/advertisement.cc).

    byte0 = (version&0b111)<<5 | (has_no_device_name)<<4 | (device_type&0b111)<<1
            (bit 0 reserved)
    Note ConvertHasDeviceName is inverted: bit4 is 1 when the device name is
    ABSENT (contacts-only visibility) and 0 when PRESENT (visible to everyone).
    Then: salt(2) + encrypted_metadata_key(14) [+ name_len(1) + name(UTF-8)].

    salt/encrypted_metadata_key are normally derived from a private
    certificate (sharing/nearby_sharing_service_impl.cc: CreateEndpointInfo);
    we have no certificate/contacts system, so -- exactly like that function's
    own fallback when the caller isn't signed in -- we fill them with random
    bytes. This is Everyone-visibility with an always-visible device name,
    so has_no_device_name is always 0 here.
    """
    has_device_name = device_name is not None
    byte0 = (
        ((_ADVERTISEMENT_VERSION & 0b111) << 5)
        | ((0 if has_device_name else 1) << 4)
        | ((int(device_type) & 0b111) << 1)
    )
    endpoint_info = bytearray([byte0])
    endpoint_info += random.randbytes(ADVERTISEMENT_SALT_SIZE)
    endpoint_info += random.randbytes(ADVERTISEMENT_METADATA_KEY_SIZE)

    if has_device_name:
        name_bytes = device_name.encode("utf-8")
        if len(name_bytes) > 255:
            raise ValueError("device_name too long for 1-byte length prefix")
        endpoint_info.append(len(name_bytes))
        endpoint_info += name_bytes

    return bytes(endpoint_info)


def build_endpoint_info_txt_value(device_name: str | None, device_type: ShareTargetType) -> bytes:
    """base64(WebSafe, padded) of build_endpoint_info's output, for the TXT record's 'n' key."""
    return _web_safe_base64_encode(build_endpoint_info(device_name, device_type)).encode("ascii")


def default_device_name() -> str:
    return socket.gethostname()
