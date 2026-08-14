"""Sending (client) side of the protocol: connect, drive the UKEY2 handshake
as the client/initiator, run paired-key verification, offer files, and send
payload bytes.

Frame layering matches receive.py (see that module's docstring): OfflineFrame
(transport, offline_wire_formats.proto) carries payload_transfer chunks whose
bodies, once reassembled, are sharing.nearby Frame messages (wire_format.proto).

Sequence (connections/implementation/base_pcp_handler.cc, sharing/outgoing_share_session.cc,
sharing/paired_key_verification_runner.cc -- see ukey2.py and mdns.py for the
handshake/discovery pieces):

  ConnectionRequest (plaintext OfflineFrame)
  Ukey2ClientInit -> read Ukey2ServerInit -> Ukey2ClientFinished (plaintext)
  ConnectionResponse (plaintext, we send ACCEPT; also read the peer's)
  PairedKeyEncryptionFrame (encrypted) -> read peer's -> PairedKeyResultFrame -> read peer's
  IntroductionFrame (file offer, encrypted) -> read peer's connection-response (accept/reject)
  PayloadTransferFrame chunks per file, 64 KiB each (connections/implementation/
  flags/nearby_connections_feature_flags.h: kMediumDefaultMaxTransmitPacketSize),
  terminated by an empty LAST_CHUNK chunk per payload
  (connections/implementation/payload_manager.cc: CreatePayloadChunk).

PAYLOAD_RECEIVED_ACK is not required by the protocol here -- it's gated behind
safe_to_disconnect_version feature negotiation (payload_manager.cc:
IsPayloadReceivedAckEnabled) and we advertise version 0, so a spec-compliant
sender is never obligated to wait for one. We wait for it anyway (see
_wait_for_received_ack) purely as our own synchronization point before
closing the socket, so we don't tear down the connection while our own
receive.py peer may still be mid-write on the last chunk.
"""

from __future__ import annotations

import mimetypes
import select
import socket
import sys
import time
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from tqdm import tqdm

from quickshare import ble_nudge  # pylint: disable=import-error
from quickshare import color, crypto, debug, discover, framing, mdns, ukey2
from quickshare.proto import offline_wire_formats_pb2 as off_pb2
from quickshare.proto import wire_format_pb2 as wf_pb2
from quickshare.receive import (
    build_paired_key_encryption_frame,
    build_paired_key_result_frame,
    build_payload_canceled,
    wrap_offline_bytes_payload,
)
from quickshare.secure_frame import SecureChannel
from quickshare.server import pick_ipv4_address

CHUNK_SIZE = 64 * 1024  # connections/implementation/flags/nearby_connections_feature_flags.h

USER_CANCELED = "user_canceled"  # sentinel return value, mirrors receive.py's SENDER_CANCELED
RECEIVER_CANCELED = "receiver_canceled"  # peer sent PAYLOAD_CANCELED/PAYLOAD_ERROR, or hung up


class SendError(Exception):
    pass


def build_connection_request(endpoint_id: bytes, endpoint_info: bytes) -> bytes:
    """connections/implementation/offline_frames.cc: ForConnectionRequestConnections.
    Google's own encoder sets endpoint_name to the exact same bytes as
    endpoint_info ("for backward compatibility"), even though endpoint_info is
    arbitrary binary (a device-type byte, random salt, random metadata-key
    bytes, and only optionally a UTF-8 name suffix) and endpoint_name is a
    proto string field, which requires valid UTF-8. We round-trip those raw
    bytes through Latin-1 (a 1:1 byte<->codepoint mapping, so re-encoding to
    UTF-8 for the wire is lossless and a receiver decoding the string back to
    Latin-1 recovers the original bytes) rather than restricting endpoint_name
    to only the human-readable name.
    Bandwidth-upgrade/WiFi-Direct fields (medium_metadata contents, nonce) are
    informational only for a single WLAN-only transfer, so we send the
    zero-value defaults rather than actual link-quality data."""
    frame = off_pb2.OfflineFrame(
        version=off_pb2.OfflineFrame.Version.V1,
        v1=off_pb2.V1Frame(
            type=off_pb2.V1Frame.FrameType.CONNECTION_REQUEST,
            connection_request=off_pb2.ConnectionRequestFrame(
                endpoint_id=endpoint_id.decode("ascii"),
                endpoint_name=endpoint_info.decode("latin-1"),
                endpoint_info=endpoint_info,
                mediums=[off_pb2.ConnectionRequestFrame.Medium.WIFI_LAN],
            ),
        ),
    )
    return frame.SerializeToString()


def build_connection_response_accept() -> bytes:
    """Plaintext OfflineFrame -- sent BEFORE the secure channel is used, same
    shape as receive.py's build_connection_response_accept (the connections-layer
    ConnectionResponse is auto-accepted by both sides unconditionally; the real
    user-facing accept/reject gate is the sharing-layer response in
    parse_connection_response below). safe_to_disconnect_version=0 signals we
    never expect/send PAYLOAD_RECEIVED_ACK (see module docstring)."""
    frame = off_pb2.OfflineFrame(
        version=off_pb2.OfflineFrame.Version.V1,
        v1=off_pb2.V1Frame(
            type=off_pb2.V1Frame.FrameType.CONNECTION_RESPONSE,
            connection_response=off_pb2.ConnectionResponseFrame(
                response=off_pb2.ConnectionResponseFrame.ResponseStatus.ACCEPT,
                os_info=off_pb2.OsInfo(type=off_pb2.OsInfo.OsType.LINUX),
                safe_to_disconnect_version=0,
            ),
        ),
    )
    return frame.SerializeToString()


def parse_offline_frame(data: bytes) -> off_pb2.OfflineFrame:
    frame = off_pb2.OfflineFrame()
    frame.ParseFromString(data)
    return frame


@dataclass
class FileToSend:
    path: Path
    payload_id: int
    attachment_id: int


_TYPE_BY_SUFFIX = {
    ".jpg": wf_pb2.FileMetadata.Type.IMAGE,
    ".jpeg": wf_pb2.FileMetadata.Type.IMAGE,
    ".png": wf_pb2.FileMetadata.Type.IMAGE,
    ".gif": wf_pb2.FileMetadata.Type.IMAGE,
    ".webp": wf_pb2.FileMetadata.Type.IMAGE,
    ".mp4": wf_pb2.FileMetadata.Type.VIDEO,
    ".mov": wf_pb2.FileMetadata.Type.VIDEO,
    ".mkv": wf_pb2.FileMetadata.Type.VIDEO,
    ".mp3": wf_pb2.FileMetadata.Type.AUDIO,
    ".wav": wf_pb2.FileMetadata.Type.AUDIO,
    ".flac": wf_pb2.FileMetadata.Type.AUDIO,
    ".apk": wf_pb2.FileMetadata.Type.ANDROID_APP,
    ".pdf": wf_pb2.FileMetadata.Type.DOCUMENT,
    ".doc": wf_pb2.FileMetadata.Type.DOCUMENT,
    ".docx": wf_pb2.FileMetadata.Type.DOCUMENT,
    ".txt": wf_pb2.FileMetadata.Type.DOCUMENT,
}


def _guess_file_type(path: Path) -> "wf_pb2.FileMetadata.Type":
    return _TYPE_BY_SUFFIX.get(path.suffix.lower(), wf_pb2.FileMetadata.Type.UNKNOWN)


def _guess_mime_type(path: Path) -> str:
    guessed, _ = mimetypes.guess_type(path.name)
    return guessed or "application/octet-stream"


def build_introduction_frame(files: list[FileToSend]) -> list[bytes]:
    """sharing/outgoing_share_session.cc: FillIntroductionFrame. id (attachment
    id) and payload_id are separate namespaces -- id is our own arbitrary
    per-transfer identifier, payload_id is what later PayloadTransferFrame
    chunks reference.

    Like receive.py's paired-key/response frames, this is a small
    application-level message and so is itself carried as a one-shot BYTES
    PayloadTransferFrame (data chunk + empty LAST_CHUNK terminator), NOT sent
    as raw Frame bytes -- see wrap_offline_bytes_payload.
    """
    file_metadata = [
        wf_pb2.FileMetadata(
            name=f.path.name,
            type=_guess_file_type(f.path),
            payload_id=f.payload_id,
            size=f.path.stat().st_size,
            mime_type=_guess_mime_type(f.path),
            id=f.attachment_id,
        )
        for f in files
    ]
    frame = wf_pb2.Frame(
        version=wf_pb2.Frame.Version.V1,
        v1=wf_pb2.V1Frame(
            type=wf_pb2.V1Frame.FrameType.INTRODUCTION,
            introduction=wf_pb2.IntroductionFrame(
                file_metadata=file_metadata,
                start_transfer=True,
            ),
        ),
    )
    return wrap_offline_bytes_payload(frame.SerializeToString())


def build_payload_chunk(payload_id: int, offset: int, body: bytes, *, total_size: int, file_name: str, is_last: bool) -> bytes:
    """connections/implementation/payload_manager.cc: CreatePayloadHeader/CreatePayloadChunk
    -- the full PayloadHeader (not just the id) is resent with every chunk,
    matching the reference sender's behavior. The final chunk is an empty
    body with the LAST_CHUNK flag set, rather than inferring EOF from offset."""
    return off_pb2.OfflineFrame(
        version=off_pb2.OfflineFrame.Version.V1,
        v1=off_pb2.V1Frame(
            type=off_pb2.V1Frame.FrameType.PAYLOAD_TRANSFER,
            payload_transfer=off_pb2.PayloadTransferFrame(
                packet_type=off_pb2.PayloadTransferFrame.PacketType.DATA,
                payload_header=off_pb2.PayloadTransferFrame.PayloadHeader(
                    id=payload_id,
                    type=off_pb2.PayloadTransferFrame.PayloadHeader.PayloadType.FILE,
                    total_size=total_size,
                    file_name=file_name,
                ),
                payload_chunk=off_pb2.PayloadTransferFrame.PayloadChunk(
                    flags=off_pb2.PayloadTransferFrame.PayloadChunk.Flags.LAST_CHUNK if is_last else 0,
                    offset=offset,
                    body=body,
                ),
            ),
        ),
    ).SerializeToString()


def parse_connection_response(sharing_frame_bytes: bytes) -> "wf_pb2.ConnectionResponseFrame.Status":
    frame = wf_pb2.Frame()
    frame.ParseFromString(sharing_frame_bytes)
    if frame.v1.type != wf_pb2.V1Frame.FrameType.RESPONSE:
        raise SendError(f"expected sharing-layer RESPONSE frame, got {frame.v1.type}")
    return frame.v1.connection_response.status


def _run_client_handshake(sock: socket.socket, endpoint_id: bytes, endpoint_info: bytes) -> tuple[SecureChannel, str]:
    framing.send_frame(sock, build_connection_request(endpoint_id, endpoint_info))

    def send_client_init(raw: bytes) -> None:
        framing.send_frame(sock, raw)

    def recv_server_init() -> bytes:
        return framing.recv_frame(sock)

    def send_client_finished(raw: bytes) -> None:
        framing.send_frame(sock, raw)

    result = ukey2.run_client_handshake(send_client_init, recv_server_init, send_client_finished)

    framing.send_frame(sock, build_connection_response_accept())

    # Symmetric to receive.py's peer-ConnectionResponse read: the receiver
    # also sends back its own plaintext ConnectionResponse, which must be
    # consumed here or the encrypted-frame loop below would misparse it.
    peer_response_bytes = framing.recv_frame(sock)
    peer_response = parse_offline_frame(peer_response_bytes)
    if peer_response.v1.type != off_pb2.V1Frame.FrameType.CONNECTION_RESPONSE:
        raise SendError(f"expected peer ConnectionResponse, got frame type {peer_response.v1.type}")

    keys = result.keys
    channel = SecureChannel(
        encrypt_key=keys.encrypt_key,
        decrypt_key=keys.decrypt_key,
        send_hmac_key=keys.send_hmac_key,
        recv_hmac_key=keys.recv_hmac_key,
    )
    return channel, keys.pin


def _recv_sharing_frame(sock: socket.socket, channel: SecureChannel) -> bytes:
    """Reads (possibly several) encrypted BYTES PayloadTransferFrame chunks
    until a LAST_CHUNK is seen, and returns the reassembled sharing.nearby
    Frame bytes. Mirrors receive.py's bytes-payload reassembly."""
    reassembly = bytearray()
    while True:
        offline_bytes = channel.decrypt(framing.recv_frame(sock))
        frame = parse_offline_frame(offline_bytes)
        if frame.v1.type != off_pb2.V1Frame.FrameType.PAYLOAD_TRANSFER:
            continue
        pt = frame.v1.payload_transfer
        if pt.packet_type != off_pb2.PayloadTransferFrame.PacketType.DATA:
            continue
        chunk = pt.payload_chunk
        if chunk.body:
            reassembly.extend(chunk.body)
        if chunk.flags & off_pb2.PayloadTransferFrame.PayloadChunk.Flags.LAST_CHUNK:
            return bytes(reassembly)


def _wait_for_received_ack(sock: socket.socket, channel: SecureChannel, payload_id: int) -> None:
    """Waits (briefly) for the receiver's PAYLOAD_RECEIVED_ACK control frame
    for payload_id (receive.py sends one after each file finishes writing --
    see build_payload_received_ack). PAYLOAD_RECEIVED_ACK is only meaningful
    when safe_to_disconnect_version negotiation enables it, which we don't
    use, so a real Nearby Share peer is under no obligation to send one at
    all -- confirmed against a real Android device, which simply closes the
    connection once it has what it needs instead. So a closed connection or
    unparseable frame here just means the peer is done, not an error: we
    already know our own last chunk made it onto the wire successfully by
    the time this is called."""
    try:
        while True:
            offline_bytes = channel.decrypt(framing.recv_frame(sock))
            frame = parse_offline_frame(offline_bytes)
            if frame.v1.type != off_pb2.V1Frame.FrameType.PAYLOAD_TRANSFER:
                continue
            pt = frame.v1.payload_transfer
            if pt.packet_type != off_pb2.PayloadTransferFrame.PacketType.CONTROL:
                continue
            if pt.payload_header.id != payload_id:
                continue
            if pt.control_message.event == off_pb2.PayloadTransferFrame.ControlMessage.EventType.PAYLOAD_RECEIVED_ACK:
                debug.log("send", f"<- PAYLOAD_RECEIVED_ACK payload_id={payload_id}")
                return
    except framing.FrameError:
        debug.log("send", "peer closed without PAYLOAD_RECEIVED_ACK (expected; not an error)")
        return


def _check_receiver_canceled(sock: socket.socket, channel: SecureChannel) -> bool:
    """Non-blocking check for a PAYLOAD_CANCELED/PAYLOAD_ERROR CONTROL frame
    (or a closed connection) from the receiver, called between chunks during
    the payload-send loop. Without this, a one-directional send loop that
    never reads would only discover the receiver gave up when the next
    sock.sendall() itself fails with ECONNRESET -- by then we may have
    already burned through a large chunk of the file for nothing."""
    readable, _, _ = select.select([sock], [], [], 0)
    if not readable:
        return False
    try:
        offline_bytes = channel.decrypt(framing.recv_frame(sock))
    except (framing.FrameError, OSError):
        return True  # connection closed/reset -- treat as the receiver bailing
    frame = parse_offline_frame(offline_bytes)
    if frame.v1.type != off_pb2.V1Frame.FrameType.PAYLOAD_TRANSFER:
        return False
    pt = frame.v1.payload_transfer
    if pt.packet_type != off_pb2.PayloadTransferFrame.PacketType.CONTROL:
        return False
    return pt.control_message.event in (
        off_pb2.PayloadTransferFrame.ControlMessage.EventType.PAYLOAD_CANCELED,
        off_pb2.PayloadTransferFrame.ControlMessage.EventType.PAYLOAD_ERROR,
    )


@dataclass
class SendProgress:
    file_name: str
    bytes_sent: int
    total_bytes: int
    speed_bps: float = 0.0


def send_files(
    address: str,
    port: int,
    endpoint_id: bytes,
    endpoint_info: bytes,
    paths: list[Path],
    on_pin: Optional[Callable[[str], None]] = None,
    on_progress: Optional[Callable[[SendProgress], None]] = None,
) -> "wf_pb2.ConnectionResponseFrame.Status | str":
    """Connects to (address, port), runs the full handshake + paired-key +
    introduction flow, and if the receiver accepts, sends every file's bytes.

    on_pin(pin) lets the caller display the confirmation code once it's known
    (matching real Quick Share UX: the sender shows the PIN right after the
    handshake completes, same moment receive.py's own PIN becomes available --
    there's no separate accept/reject gate on the sender's side at this point,
    since ClientFinished has already been sent by the time the PIN exists).
    Returns the receiver's ConnectionResponseFrame.Status, or the USER_CANCELED
    sentinel if interrupted (Ctrl+C) while payload bytes were in flight.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    with sock:
        debug.log("send", f"connecting to {address}:{port}")
        sock.connect((address, port))
        channel, pin = _run_client_handshake(sock, endpoint_id, endpoint_info)
        if on_pin:
            on_pin(pin)

        def channel_send(payload: bytes) -> None:
            framing.send_frame(sock, channel.encrypt(payload))

        # Paired-key verification: both sides send PairedKeyEncryptionFrame
        # immediately and independently (paired_key_verification_runner.cc:
        # Run), then both send PairedKeyResultFrame after reading the peer's
        # encryption frame. We have no certificate store, so our own
        # encryption frame carries random bytes and we always report UNABLE --
        # same simplification receive.py already makes (see its
        # build_paired_key_encryption_frame docstring).
        for frame_bytes in build_paired_key_encryption_frame():
            channel_send(frame_bytes)
        debug.log("send", "-> PairedKeyEncryption")
        _recv_sharing_frame(sock, channel)  # peer's PairedKeyEncryptionFrame
        debug.log("send", "<- PairedKeyEncryption")
        for frame_bytes in build_paired_key_result_frame():
            channel_send(frame_bytes)
        debug.log("send", "-> PairedKeyResult (UNABLE)")
        _recv_sharing_frame(sock, channel)  # peer's PairedKeyResultFrame
        debug.log("send", "<- PairedKeyResult")

        # Payload/attachment ids are int64s on the wire; derive them from
        # random bytes rather than a counter, matching the reference
        # sender's fully-random 64-bit ids (outgoing_share_session.cc).
        files = [
            FileToSend(
                path=p,
                payload_id=int.from_bytes(crypto.random_bytes(8), "big", signed=True),
                attachment_id=i,
            )
            for i, p in enumerate(paths)
        ]

        for frame_bytes in build_introduction_frame(files):
            channel_send(frame_bytes)
        if debug.enabled():
            for f in files:
                debug.log("send", f"-> offering {f.path.name!r} ({f.path.stat().st_size} bytes, payload_id={f.payload_id})")
        response_bytes = _recv_sharing_frame(sock, channel)
        status = parse_connection_response(response_bytes)
        debug.log("send", f"<- RESPONSE {wf_pb2.ConnectionResponseFrame.Status.Name(status)}")

        if status != wf_pb2.ConnectionResponseFrame.Status.ACCEPT:
            return status

        total_bytes = sum(f.path.stat().st_size for f in files)
        sent_so_far = 0
        started_at = time.monotonic()
        try:
            for f in files:
                size = f.path.stat().st_size
                debug.log("send", f"sending {f.path.name!r} ({size} bytes, payload_id={f.payload_id})")
                with open(f.path, "rb") as fh:
                    offset = 0
                    while True:
                        if _check_receiver_canceled(sock, channel):
                            debug.log("send", f"receiver canceled at offset {offset}")
                            return RECEIVER_CANCELED
                        chunk = fh.read(CHUNK_SIZE)
                        is_last = len(chunk) == 0
                        try:
                            channel_send(
                                build_payload_chunk(
                                    f.payload_id, offset, chunk, total_size=size, file_name=f.path.name, is_last=is_last
                                )
                            )
                        except OSError as exc:
                            # The receiver hung up mid-write without sending
                            # an explicit CONTROL cancel frame first -- treat
                            # a broken connection here the same as one.
                            debug.log("send", f"write failed at offset {offset}: {exc}")
                            return RECEIVER_CANCELED
                        debug.trace(
                            "send",
                            f"-> FILE chunk payload_id={f.payload_id} offset={offset} "
                            f"len={len(chunk)}{' LAST' if is_last else ''}",
                        )
                        offset += len(chunk)
                        sent_so_far += len(chunk)
                        # The empty LAST_CHUNK terminator carries no new bytes --
                        # skip its progress callback so 100% isn't reported twice.
                        if chunk and on_progress:
                            elapsed = time.monotonic() - started_at
                            speed_bps = sent_so_far / elapsed if elapsed > 0 else 0.0
                            on_progress(
                                SendProgress(
                                    file_name=f.path.name,
                                    bytes_sent=sent_so_far,
                                    total_bytes=total_bytes,
                                    speed_bps=speed_bps,
                                )
                            )
                        if is_last:
                            break
        except KeyboardInterrupt:
            # Tell the receiver we're bailing on this payload -- symmetric to
            # receive.py's cancel(), which sends the same PAYLOAD_CANCELED
            # control frame in the other direction. Best-effort: the receiver
            # may already be gone, in which case there's nothing to notify.
            debug.log("send", f"user canceled, notifying receiver (payload_id={f.payload_id})")
            try:
                channel_send(build_payload_canceled(f.payload_id))
            except OSError:
                pass
            return USER_CANCELED

        # Only wait for (or tolerate the absence of) an ack after the very
        # last file: a real Nearby Share peer may simply close the connection
        # once done rather than send PAYLOAD_RECEIVED_ACK (see
        # _wait_for_received_ack), and treating that as benign is only safe
        # once there's nothing left for us to send afterwards.
        _wait_for_received_ack(sock, channel, files[-1].payload_id)

        return status


_DISCOVERY_SECONDS = 2.0


class _SendProgressPrinter:
    """Stateful on_progress callback backing a single tqdm bar for the whole
    (possibly multi-file) transfer -- bytes_sent/total_bytes in SendProgress
    are already cumulative across every file being sent. tqdm handles fitting
    the bar to the current terminal width itself, unlike the old hand-rolled
    \\r-based bar, which left stray characters behind on redraw whenever the
    line length changed between updates on a narrow terminal."""

    def __init__(self) -> None:
        self._bar: Optional[tqdm] = None

    def __call__(self, progress: SendProgress) -> None:
        if self._bar is None:
            self._bar = tqdm(
                total=progress.total_bytes,
                unit="B",
                unit_scale=True,
                unit_divisor=1024,
                file=sys.stderr,
                dynamic_ncols=True,
            )
        self._bar.set_description(color.sanitize(progress.file_name))
        self._bar.n = progress.bytes_sent
        self._bar.refresh()
        if progress.bytes_sent >= progress.total_bytes:
            self.reset()

    def reset(self) -> None:
        """Close and drop the bar -- call once the transfer is done, canceled,
        or disconnected, so a stale bar never lingers into the next send."""
        if self._bar is not None:
            self._bar.close()
            self._bar = None


_print_send_progress = _SendProgressPrinter()


def _interactive_pick_device(devices: list["discover.DiscoveredDevice"]) -> Optional["discover.DiscoveredDevice"]:
    print(file=sys.stderr)
    for i, device in enumerate(devices):
        print(f"  [{i + 1}] {color.sanitize(device.device_name)}  ({device.address}:{device.port})", file=sys.stderr)
    sys.stderr.flush()
    try:
        answer = input(f"Send to which device? [1-{len(devices)}, empty to cancel] ").strip()
    except EOFError:
        return None
    if not answer:
        return None
    try:
        index = int(answer) - 1
    except ValueError:
        return None
    if not (0 <= index < len(devices)):
        return None
    return devices[index]


def run_sender(
    paths: list[str],
    device_name: str,
    iface: Optional[str] = None,
    target: Optional[str] = None,
) -> int:
    """CLI entry point: browse for nearby receivers, let the user pick one
    (or connect directly to target if given as "host:port"), then send every
    path in paths. Returns a process exit code."""
    print(color.dim("Minimal Quick Share CLI client for Linux\n"), file=sys.stderr)

    file_paths = [Path(p).resolve() for p in paths]
    missing = [p for p in file_paths if not p.is_file()]
    if missing:
        for p in missing:
            print(color.red(f"Not a file: {p}"), file=sys.stderr)
        return 1

    try:
        if target:
            host, _, port_str = target.partition(":")
            address, port = host, int(port_str)
        else:
            address_for_browse = None
            try:
                address_for_browse = pick_ipv4_address(iface)
            except (ValueError, RuntimeError):
                pass  # fall back to zeroconf's default (all-interfaces) browsing

            # Broadcast the BLE nudge while browsing so hidden-mode Quick Share
            # receivers (phone visibility set to "hidden") wake up and start
            # advertising mDNS -- the only way they'd otherwise surface. Safe
            # no-op when no Bluetooth adapter is present.
            nudge = ble_nudge.NudgeManager(advertise=True, scan=False)
            nudge.start()

            print(color.cyan(f"Looking for nearby devices ({_DISCOVERY_SECONDS:.0f}s)..."), file=sys.stderr)
            devices = discover.browse(_DISCOVERY_SECONDS, address_for_browse)

            nudge.stop()

            debug.log("send", f"discovery finished, {len(devices)} device(s) found")
            if not devices:
                print(color.yellow("No devices found."), file=sys.stderr)
                return 1

            device = _interactive_pick_device(devices)
            if device is None:
                print(color.yellow("Canceled."), file=sys.stderr)
                return 1
            address, port = device.address, device.port
    except KeyboardInterrupt:
        print("\nCanceled.", file=sys.stderr)
        return 1

    endpoint_id = mdns.stable_endpoint_id()
    endpoint_info = mdns.build_endpoint_info(device_name, mdns.ShareTargetType.LAPTOP)

    def on_pin(pin: str) -> None:
        print(f"\nConfirmation code: {color.bold(color.yellow(pin))}", file=sys.stderr)
        print("Confirm this code matches what the receiver shows.", file=sys.stderr)

    print(color.cyan(f"Connecting to {address}:{port}..."), file=sys.stderr)
    try:
        status = send_files(address, port, endpoint_id, endpoint_info, file_paths, on_pin=on_pin, on_progress=_print_send_progress)
    except KeyboardInterrupt:
        print(color.yellow("\nCanceled."), file=sys.stderr)
        return 1
    except (OSError, SendError, ukey2.Ukey2Error) as exc:
        print(color.red(f"Send failed: {exc}"), file=sys.stderr)
        if debug.enabled():
            traceback.print_exc(file=sys.stderr)  # the message alone rarely says where it failed
        return 1
    finally:
        _print_send_progress.reset()  # close any bar left open by a canceled/failed transfer

    if status == USER_CANCELED:
        print(color.yellow("\nTransfer canceled."), file=sys.stderr)
        return 1
    elif status == RECEIVER_CANCELED:
        print(color.yellow("\nReceiver canceled the transfer."), file=sys.stderr)
        return 1
    elif status == wf_pb2.ConnectionResponseFrame.Status.ACCEPT:
        print(color.green("Transfer finished."), file=sys.stderr)
        return 0
    elif status == wf_pb2.ConnectionResponseFrame.Status.REJECT:
        print(color.yellow("Transfer declined."), file=sys.stderr)
    elif status == wf_pb2.ConnectionResponseFrame.Status.NOT_ENOUGH_SPACE:
        print(color.red("Receiver reported not enough space."), file=sys.stderr)
    elif status == wf_pb2.ConnectionResponseFrame.Status.TIMED_OUT:
        print(color.red("Receiver timed out."), file=sys.stderr)
    else:
        print(color.red(f"Transfer failed: {wf_pb2.ConnectionResponseFrame.Status.Name(status)}"), file=sys.stderr)
    return 1
