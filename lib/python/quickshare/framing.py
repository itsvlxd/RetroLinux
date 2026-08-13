"""Wire framing: 4-byte big-endian length prefix + payload, used for every
message on the Quick Share TCP socket (handshake and encrypted alike)."""

from __future__ import annotations

import socket

from quickshare import debug

# Not part of the protocol spec -- our own guard against a malicious/corrupt
# length prefix causing an oversized allocation. Same name and value as
# grishka/NearDrop's SANE_FRAME_LENGTH (NearbyShare/NearbyConnection.swift).
# Cited here only as prior art for this defensive bound, not as a source for
# protocol logic.
MAX_FRAME_LENGTH = 5 * 1024 * 1024


class FrameError(Exception):
    pass


class ConnectionClosedImmediately(FrameError):
    """Raised instead of the plain FrameError when the peer closed the
    connection before sending a single byte. Windows' Quick Share discovery
    does this on purpose -- WifiLanMedium::IsConnectableIpAddress opens a
    real TCP connection to the advertised address purely to check
    reachability before it will list a device, then closes it immediately
    without writing anything (internal/platform/implementation/windows/
    wifi_lan.cc: TestConnection) -- so callers on the first read of a new
    connection should treat this as a benign liveness probe, not a failed
    transfer."""


def pack_frame(payload: bytes) -> bytes:
    return len(payload).to_bytes(4, "big") + payload


def send_frame(sock: socket.socket, payload: bytes) -> None:
    debug.trace("framing", f"-> frame ({len(payload)} bytes)")
    sock.sendall(pack_frame(payload))


def _recv_exact(sock: socket.socket, n: int) -> bytes:
    chunks = []
    remaining = n
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            if not chunks and remaining == n:
                raise ConnectionClosedImmediately("connection closed without sending any data")
            raise FrameError("connection closed while reading frame")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def recv_frame(sock: socket.socket) -> bytes:
    length = int.from_bytes(_recv_exact(sock, 4), "big")
    if length > MAX_FRAME_LENGTH:
        debug.log("framing", f"rejecting oversized frame: {length} bytes > max {MAX_FRAME_LENGTH}")
        raise FrameError(f"frame length {length} exceeds max {MAX_FRAME_LENGTH}")
    debug.trace("framing", f"<- frame ({length} bytes)")
    return _recv_exact(sock, length)
