"""mDNS discovery (client/browse side) for Quick Share, per Google's own
source at https://github.com/google/nearby.

This is the parse-direction mirror of mdns.py's build_* functions -- see that
module's docstring for the two layers involved (sharing.Advertisement in the
TXT record, connections.WifiLanServiceInfo in the instance name). Decoding
here follows:

- `WifiLanServiceInfo::WifiLanServiceInfo(const NsdServiceInfo&)`
  (connections/implementation/wifi_lan_service_info.cc) -- parses the
  instance-name bytes: 1 byte (version<<5 | pcp) + 4-byte endpoint_id +
  3-byte service_id_hash [+ optional UWB/WebRTC trailer, which we ignore].
- `sharing::Advertisement::FromEndpointInfo` (sharing/advertisement.{h,cc})
  -- parses the TXT record's "n" value: the inverse of mdns.build_endpoint_info.
"""

from __future__ import annotations

import base64
import binascii
import socket
import time
from dataclasses import dataclass

from zeroconf import IPVersion, ServiceBrowser, ServiceStateChange, Zeroconf

from quickshare import color, debug, mdns

_MIN_SERVICE_NAME_BYTES = 8  # 1 (version+pcp) + 4 (endpoint_id) + 3 (service_id_hash)
_VERSION_MASK = 0b111
_VERSION_SHIFT = 5


class DiscoverError(Exception):
    pass


def _web_safe_base64_decode(data: str) -> bytes:
    """internal/platform/base64_utils.cc: Base64Utils::Decode -> absl::WebSafeBase64Unescape.
    Tolerates missing padding, since not every real-world encoder includes it.

    data comes from an untrusted peer's mDNS advertisement, so malformed
    input (wrong length even after re-padding) is expected, not exceptional
    -- raise our own DiscoverError instead of letting binascii.Error escape,
    since this runs inside zeroconf's callback thread during passive
    discovery and one malformed advertisement must not crash discovery of
    every other, legitimate device on the network.
    """
    padded = data + "=" * (-len(data) % 4)
    try:
        return base64.urlsafe_b64decode(padded)
    except binascii.Error as exc:
        raise DiscoverError(f"malformed base64: {exc}") from None


def parse_service_instance_name(instance_name: str) -> tuple[bytes, bytes]:
    """Inverse of mdns.build_service_instance_name. Returns (endpoint_id, service_id_hash).

    Ignores the optional trailing UWB-address/WebRTC-state fields (we don't
    use either); only the fixed 8-byte prefix is meaningful to us.
    """
    raw = _web_safe_base64_decode(instance_name)
    if len(raw) < _MIN_SERVICE_NAME_BYTES:
        raise DiscoverError(f"service instance name too short: {len(raw)} bytes")

    version_and_pcp = raw[0]
    version = (version_and_pcp >> _VERSION_SHIFT) & _VERSION_MASK
    if version != mdns.WIFI_LAN_SERVICE_INFO_VERSION:
        raise DiscoverError(f"unsupported WifiLanServiceInfo version {version}")

    endpoint_id = raw[1:5]
    service_id_hash = raw[5:8]
    return endpoint_id, service_id_hash


@dataclass
class ParsedAdvertisement:
    device_name: str | None
    device_type: mdns.ShareTargetType


def parse_endpoint_info(endpoint_info: bytes) -> ParsedAdvertisement:
    """Inverse of mdns.build_endpoint_info. We only need device_name/device_type
    here (salt and the encrypted metadata key are for contact-certificate
    verification, which this project doesn't implement -- see
    receive.py's PairedKeyResultFrame.UNABLE, the same simplification)."""
    if not endpoint_info:
        raise DiscoverError("empty endpoint info")

    byte0 = endpoint_info[0]
    has_no_device_name = bool((byte0 >> 4) & 1)
    raw_device_type = (byte0 >> 1) & 0b111
    try:
        # 3 bits can encode 0-7, but ShareTargetType only defines 0-6 -- a
        # malicious/malformed advertisement setting this to 7 must not be
        # allowed to raise ValueError out of here uncaught, since this runs
        # inside zeroconf's own callback thread during passive discovery
        # (browse()), where an unhandled exception from one bad peer would
        # otherwise disrupt discovery of every other, legitimate device.
        device_type = mdns.ShareTargetType(raw_device_type)
    except ValueError:
        raise DiscoverError(f"unknown device type {raw_device_type}") from None

    device_name = None
    if not has_no_device_name:
        header_size = 1 + mdns.ADVERTISEMENT_SALT_SIZE + mdns.ADVERTISEMENT_METADATA_KEY_SIZE
        if len(endpoint_info) > header_size:
            name_len = endpoint_info[header_size]
            name_bytes = endpoint_info[header_size + 1 : header_size + 1 + name_len]
            device_name = name_bytes.decode("utf-8", errors="replace")

    return ParsedAdvertisement(device_name=device_name, device_type=device_type)


@dataclass
class DiscoveredDevice:
    endpoint_id: bytes
    device_name: str
    device_type: mdns.ShareTargetType
    address: str
    port: int


def parse_discovered_service(instance_name: str, txt_records: dict[bytes, bytes | None], address: str, port: int, fallback_name: str | None = None) -> DiscoveredDevice:
    endpoint_id, _service_id_hash = parse_service_instance_name(instance_name)

    txt_value = txt_records.get(mdns.TXT_KEY_ENDPOINT_INFO.encode())
    if not txt_value:
        raise DiscoverError("TXT record missing endpoint info ('n' key)")
    try:
        txt_value_ascii = txt_value.decode("ascii")
    except UnicodeDecodeError as exc:
        raise DiscoverError(f"TXT endpoint info is not ASCII: {exc}") from None
    endpoint_info = _web_safe_base64_decode(txt_value_ascii)
    advertisement = parse_endpoint_info(endpoint_info)

    name = advertisement.device_name
    if not name and fallback_name:
        name = fallback_name
    if not name:
        name = "(unnamed device)"

    return DiscoveredDevice(
        endpoint_id=endpoint_id,
        device_name=name,
        device_type=advertisement.device_type,
        address=address,
        port=port,
    )


def browse(duration_seconds: float, address: str | None = None) -> list[DiscoveredDevice]:
    """Browse for SERVICE_TYPE for duration_seconds, returning every device
    seen (deduplicated by endpoint_id, keeping the most recent sighting).

    address restricts zeroconf to a single interface, same rationale as
    server.py's _Advertiser (binding every interface on a multi-NIC host
    noticeably slows zeroconf startup).
    """
    found: dict[bytes, DiscoveredDevice] = {}

    zc_kwargs = {"ip_version": IPVersion.V4Only}
    if address is not None:
        zc_kwargs["interfaces"] = [address]
    zeroconf = Zeroconf(**zc_kwargs)

    def on_state_change(*, zeroconf: Zeroconf, service_type: str, name: str, state_change: ServiceStateChange) -> None:
        if state_change != ServiceStateChange.Added:
            return
        info = zeroconf.get_service_info(service_type, name, timeout=3000)
        if info is None or not info.addresses:
            debug.log("discover", f"no usable service info for {name!r}")
            return
        instance_name = name[: -len("." + service_type)]
        hostname = (info.server or "").rstrip(".").removesuffix(".local")
        try:
            device = parse_discovered_service(
                instance_name,
                info.properties,
                socket.inet_ntoa(info.addresses[0]),
                info.port,
                fallback_name=hostname,
            )
        except DiscoverError as exc:
            # Skipped silently in normal operation (one unparseable peer must
            # not disrupt discovery of the rest), which makes "my phone never
            # shows up" impossible to diagnose without this line.
            debug.log("discover", f"skipping {name!r}: {exc}")
            return
        # device_name comes from the peer's advertisement -- sanitize before
        # it reaches the terminal, as everywhere else it's displayed.
        debug.log(
            "discover",
            f"found {color.sanitize(device.device_name)!r} at {device.address}:{device.port} "
            f"(type={device.device_type.name})",
        )
        found[device.endpoint_id] = device

    browser = ServiceBrowser(zeroconf, mdns.SERVICE_TYPE, handlers=[on_state_change])
    try:
        time.sleep(duration_seconds)
    finally:
        browser.cancel()
        zeroconf.close()

    return list(found.values())
