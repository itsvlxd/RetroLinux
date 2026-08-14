"""TCP + mDNS server glue: binds a listening socket, advertises it over mDNS
per mdns.py, accepts one connection at a time, drives the UKEY2 handshake,
and hands off to receive.ReceiveSession for the application-level flow.

Unlike real Quick Share devices, there is no BLE nudge in the bare protocol
engine itself -- see ble_nudge.py. On hosts with a Bluetooth adapter (e.g.
Intel AX211), run_receiver starts a BLE nudge broadcaster so this machine
behaves like a "visible to everyone" Quick Share device, plus a nudge scanner
that triggers an immediate mDNS re-announce when a sender starts looking.
google/nearby's platform backends rely on the BLE nudge to trigger a fresh
mDNS announcement when a phone comes looking; without BLE this project falls
back to a blind periodic re-announce on a fixed interval instead.
"""

from __future__ import annotations

import socket
import sys
import threading
import traceback
from pathlib import Path
from typing import Optional

import ifaddr
from tqdm import tqdm
from zeroconf import IPVersion, ServiceInfo, Zeroconf

from quickshare import color, debug, framing, mdns, ukey2
from quickshare import ble_nudge  # pylint: disable=import-error
from quickshare.proto import offline_wire_formats_pb2 as off_pb2
from quickshare.receive import SENDER_CANCELED, IncomingFile, ReceiveSession, TransferCancelled, build_connection_response_accept
from quickshare.secure_frame import SecureChannel

REANNOUNCE_INTERVAL_SECONDS = 60.0

# Extra re-announces right after startup -- see _reannounce_loop's docstring
# for why a peer's very first (QU/unicast) query can get a reply that's
# missing the mDNS cache-flush bit, and why a prompt real multicast broadcast
# works around it.
_STARTUP_REANNOUNCE_COUNT = 5
_STARTUP_REANNOUNCE_INTERVAL_SECONDS = 2.0

_VIRTUAL_IFACE_PREFIXES = ("vmnet", "docker", "br-", "veth", "virbr", "lo")


def pick_ipv4_address(preferred_iface: str | None) -> str:
    """Select a non-loopback, non-virtual IPv4 address to advertise.

    If preferred_iface is given, use its first IPv4 address. Otherwise probe
    the OS's default-route interface, then fall back to the first adapter
    whose name doesn't look virtual -- skipping vmnet/docker/bridge
    interfaces matters concretely on this host, which runs Docker and
    VMware alongside a single physical NIC, and a phone can't reach an
    address handed out on one of those.
    """
    if preferred_iface is not None:
        for adapter in ifaddr.get_adapters():
            if adapter.nice_name == preferred_iface:
                for ip in adapter.ips:
                    if ip.is_IPv4:
                        return ip.ip
        raise ValueError(f"interface {preferred_iface!r} not found or has no IPv4 address")

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            address = probe.getsockname()[0]
        for adapter in ifaddr.get_adapters():
            if any(ip.is_IPv4 and ip.ip == address for ip in adapter.ips):
                if not adapter.nice_name.startswith(_VIRTUAL_IFACE_PREFIXES):
                    return address
    except OSError:
        pass

    for adapter in ifaddr.get_adapters():
        if adapter.nice_name.startswith(_VIRTUAL_IFACE_PREFIXES):
            continue
        for ip in adapter.ips:
            if ip.is_IPv4:
                return ip.ip

    raise RuntimeError("no usable non-virtual IPv4 interface found")


def _read_offline_frame_plaintext(sock: socket.socket) -> off_pb2.OfflineFrame:
    frame = off_pb2.OfflineFrame()
    frame.ParseFromString(framing.recv_frame(sock))
    return frame


def _run_handshake(sock: socket.socket) -> tuple[SecureChannel, str]:
    connection_request_frame = _read_offline_frame_plaintext(sock)
    if connection_request_frame.v1.type != off_pb2.V1Frame.FrameType.CONNECTION_REQUEST:
        raise ukey2.Ukey2Error("expected ConnectionRequest as the first frame")
    debug.log("server", "<- ConnectionRequest")

    client_init_bytes = framing.recv_frame(sock)

    def send_server_init(raw_server_init_bytes: bytes) -> None:
        framing.send_frame(sock, raw_server_init_bytes)

    def recv_client_finished() -> bytes:
        return framing.recv_frame(sock)

    result = ukey2.run_server_handshake(client_init_bytes, send_server_init, recv_client_finished)

    framing.send_frame(sock, build_connection_response_accept())
    debug.log("server", "-> ConnectionResponse ACCEPT")

    # The phone also sends its own plaintext ConnectionResponse back to us at
    # this point (location.nearby.connections.V1Frame.CONNECTION_RESPONSE) --
    # both sides exchange one. It carries nothing we need (accept/reject,
    # its OS info, a multiplex-socket bitmask we don't use), but it must be
    # read off the wire here or the receive loop below mistakes it for the
    # first encrypted SecureMessage.
    peer_connection_response = _read_offline_frame_plaintext(sock)
    if peer_connection_response.v1.type != off_pb2.V1Frame.FrameType.CONNECTION_RESPONSE:
        raise ukey2.Ukey2Error(
            f"expected peer ConnectionResponse, got frame type {peer_connection_response.v1.type}"
        )
    debug.log("server", "<- peer ConnectionResponse, secure channel established")

    keys = result.keys
    channel = SecureChannel(
        encrypt_key=keys.encrypt_key,
        decrypt_key=keys.decrypt_key,
        send_hmac_key=keys.send_hmac_key,
        recv_hmac_key=keys.recv_hmac_key,
    )
    return channel, keys.pin


class TransferOutcome:
    """Why _handle_connection ended, distinguishing an in-progress transfer
    getting cut off from it never having been accepted at all."""

    COMPLETED = "completed"
    DECLINED = "declined"
    CANCELED = "canceled"
    SENDER_DISCONNECTED = "sender_disconnected"
    SENDER_CANCELED = "sender_canceled"


def _handle_connection(
    sock: socket.socket,
    peer_ip: str,
    output_dir: Path,
    auto_accept: bool,
    on_offer,
    on_progress,
) -> tuple[str, list[Path] | None]:
    """Returns (outcome, completed_file_paths). completed_file_paths is only
    populated when outcome == TransferOutcome.COMPLETED."""
    with sock:
        channel, pin = _run_handshake(sock)
        # Announced only now, after a real ConnectionRequest + UKEY2 handshake:
        # Windows' discovery opens (and instantly drops) connections to us just
        # to check reachability while merely LISTING devices, and printing
        # "Connection from ..." for those made every probe look like a transfer
        # attempt. A probe never gets past the first frame read above (see
        # framing.ConnectionClosedImmediately and run_receiver's handling of it).
        print(f"Connection from {peer_ip} (Ctrl+C cancels this transfer)", file=sys.stderr)

        session = ReceiveSession(
            channel=channel,
            output_dir=output_dir,
            pin=pin,
            auto_accept=auto_accept,
            on_offer=on_offer,
            on_progress=on_progress,
            channel_send=lambda payload: framing.send_frame(sock, payload),
        )
        session.start()

        try:
            while True:
                try:
                    secure_message_bytes = framing.recv_frame(sock)
                except framing.FrameError as exc:
                    debug.log("server", f"connection ended while reading: {exc}")
                    if session.files_by_payload_id:
                        session.discard_incomplete()
                        return TransferOutcome.SENDER_DISCONNECTED, None
                    return TransferOutcome.DECLINED, None
                result = session.handle_encrypted_frame(secure_message_bytes)
                if result == SENDER_CANCELED:
                    return TransferOutcome.SENDER_CANCELED, None
                if result is not None:
                    return TransferOutcome.COMPLETED, result
        except TransferCancelled:
            print("\nCanceling transfer...", file=sys.stderr)
            session.cancel()
            return TransferOutcome.CANCELED, None
        except KeyboardInterrupt:
            print("\nCanceling transfer...", file=sys.stderr)
            session.cancel()
            return TransferOutcome.CANCELED, None


class _Advertiser:
    def __init__(self, device_name: str, port: int, address: str) -> None:
        self._device_name = device_name
        self._port = port
        self._address = address
        # Binding only the interface we're actually advertising on (instead of
        # every interface on the host) noticeably cuts zeroconf's startup time
        # on this host, which has 6 interfaces (physical NIC + docker0 + a
        # bridge + 3 VMware vmnets) that would otherwise all be bound.
        self._zeroconf = Zeroconf(interfaces=[address], ip_version=IPVersion.V4Only)
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        # Stable across restarts (derived from hostname) rather than random,
        # so the phone recognizes this machine as the same device each time
        # instead of listing a new one on every run.
        self._endpoint_id = mdns.stable_endpoint_id()

    @property
    def endpoint_id(self) -> bytes:
        return self._endpoint_id

    def _build_service_info(self) -> ServiceInfo:
        instance_name = mdns.build_service_instance_name(self._endpoint_id)
        txt_value = mdns.build_endpoint_info_txt_value(self._device_name, mdns.ShareTargetType.LAPTOP)
        return ServiceInfo(
            type_=mdns.SERVICE_TYPE,
            name=f"{instance_name}.{mdns.SERVICE_TYPE}",
            # A distinct host record, not the service instance name itself:
            # internal/platform/implementation/windows/wifi_lan_mdns.cc builds
            # the SRV target from the machine's own DNS hostname + ".local"
            # (GetDnsHostName()), separately from the SRV owner/instance name,
            # with an explicit comment that a real hostname is required "other-
            # wise A/AAAA records cannot be resolved". zeroconf.ServiceInfo
            # defaults `server` to the instance name when omitted, which made
            # our SRV target and A record self-referential -- unlike every
            # real implementation -- and lines up with a Windows Quick Share
            # peer that resolves an IP:port (so the TCP connect lands correctly)
            # but then aborts before sending any protocol bytes.
            server=f"{socket.gethostname()}.local.",
            addresses=[socket.inet_aton(self._address)],
            port=self._port,
            properties={
                mdns.TXT_KEY_ENDPOINT_INFO.encode(): txt_value,
                mdns.TXT_KEY_IPV4.encode(): self._address.encode("ascii"),
            },
        )

    def start(self) -> None:
        info = self._build_service_info()
        self._zeroconf.register_service(info, allow_name_change=False)
        self._thread = threading.Thread(target=self._reannounce_loop, args=(info,), daemon=True)
        self._thread.start()

    def _reannounce_loop(self, info: ServiceInfo) -> None:
        # A burst of extra multicast re-announces right after startup, before
        # settling into the steady-state interval below. This works around a
        # real gap in zeroconf's own query handling (verified against zeroconf
        # 0.150.0 source, _handlers/query_handler.py and _handlers/answers.py):
        # a peer's mDNS query with the "QU" (unicast-response) bit set -- which
        # Windows' Quick Share sends, confirmed by packet capture -- gets
        # answered via construct_outgoing_unicast_answers, which builds its
        # DNSOutgoing with multicast=False. _write_record_class then never
        # sets the cache-flush bit (it's gated on `record.unique is True and
        # self.multicast`), regardless of the record's own unique flag. So our
        # very first reply to a fresh Windows query -- a unicast one, since
        # that's what QU asks for -- carries SRV/TXT/A records Windows can't
        # trust as authoritative, and Windows silently drops the device from
        # its list without any error rather than wait for a later multicast
        # copy. update_service()'s broadcast is real multicast and does carry
        # the cache-flush bit correctly (confirmed by capture); the fix is
        # just making sure one lands soon after we start, rather than relying
        # solely on the 60s steady-state cadence below.
        for _ in range(_STARTUP_REANNOUNCE_COUNT):
            if self._stop_event.wait(_STARTUP_REANNOUNCE_INTERVAL_SECONDS):
                return
            try:
                self._zeroconf.update_service(info)
            except Exception:
                return
        while not self._stop_event.wait(REANNOUNCE_INTERVAL_SECONDS):
            try:
                self._zeroconf.update_service(info)
            except Exception:
                # zeroconf may already be mid-close() by the time this runs
                # (stop() no longer waits for this thread) -- harmless, the
                # process is shutting down either way.
                return

    def stop(self) -> None:
        # No thread join: the reannounce thread is a daemon that dies with the
        # process, and it may be mid-update_service() for up to a few hundred
        # ms -- waiting for it here would only slow shutdown down for no
        # correctness benefit, since we're tearing everything down anyway.
        self._stop_event.set()
        self._zeroconf.close()

    def reannounce(self) -> None:
        """Re-announce the mDNS service immediately (thread-safe).

        Called by the BLE nudge scanner when a sender's FE2C nudge is heard, so
        a hidden peer that just started looking for targets surfaces in this
        machine's mDNS advertisement right away instead of waiting for the next
        periodic re-announce."""
        try:
            self._zeroconf.update_service(self._build_service_info())
        except Exception:
            pass


def format_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if size < 1024 or unit == "GiB":
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GiB"


class _ReceiveProgressPrinter:
    """Stateful on_progress callback: one tqdm bar per incoming file, reused
    across the many on_progress(incoming) calls that arrive as its chunks
    write in. tqdm handles fitting the bar to the current terminal width
    (and redrawing cleanly on resize) itself, which a hand-rolled \\r-based
    bar doesn't -- narrower terminals used to leave stray characters behind
    on redraw when the bar's line length changed between updates."""

    def __init__(self) -> None:
        self._bar: Optional[tqdm] = None
        self._payload_id: Optional[int] = None
        self._lock = threading.RLock()

    def __call__(self, incoming: IncomingFile) -> None:
        with self._lock:
            if self._payload_id != incoming.payload_id:
                if self._bar is not None:
                    self._bar.close()
                self._bar = tqdm(
                    total=incoming.size,
                    desc=color.sanitize(incoming.name),
                    unit="B",
                    unit_scale=True,
                    unit_divisor=1024,
                    file=sys.stderr,
                    leave=True,
                    dynamic_ncols=True,
                )
                self._payload_id = incoming.payload_id
            self._bar.n = incoming.bytes_written
            self._bar.refresh()
            if incoming.complete:
                self.reset()

    def reset(self) -> None:
        """Close and drop any bar left open by a file that never reached
        incoming.complete -- a canceled or disconnected transfer. Call this
        after every connection, complete or not, so a stale bar never lingers
        into the next one."""
        with self._lock:
            if self._bar is not None:
                self._bar.close()
                self._bar = None
            self._payload_id = None


_print_progress = _ReceiveProgressPrinter()


def _interactive_confirm(file_metadata: list, pin: str) -> bool:
    print(f"\nIncoming transfer, confirmation code: {color.bold(color.yellow(pin))}", file=sys.stderr)
    print("Confirm this code matches what your phone shows before accepting.", file=sys.stderr)
    for meta in file_metadata:
        print(f"  {color.sanitize(meta.name)}  ({format_size(meta.size)})", file=sys.stderr)
    sys.stderr.flush()
    try:
        answer = input("Accept? [y/N] ").strip().lower()
    except EOFError:
        print(color.yellow("(no input available -- declining)"), file=sys.stderr)
        return False
    accepted = answer in ("y", "yes")
    print(color.green("Accepted.") if accepted else color.yellow("Declined."), file=sys.stderr)
    return accepted


def run_receiver(
    output_dir: str,
    device_name: str,
    iface: str | None,
    auto_accept: bool,
    on_offer=None,
    on_progress=None,
    on_connection_end=None,
) -> int:
    print(color.dim("Minimal Quick Share CLI client for Linux\n"), file=sys.stderr)
    if on_progress is None:
        on_progress = _print_progress
    if on_offer is None and not auto_accept:
        on_offer = _interactive_confirm
    output_path = Path(output_dir).resolve()
    output_path.mkdir(parents=True, exist_ok=True)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("0.0.0.0", 0))
    # Windows' Quick Share discovery opens and immediately closes its own TCP
    # connection to us on every mDNS re-announcement, just to test reachability
    # before it'll list this device at all (see run_receiver's handling of
    # framing.ConnectionClosedImmediately below) -- a backlog of 1 lets such a
    # probe collide with the real transfer connection that follows once a
    # human actually picks this device.
    listener.listen(5)
    port = listener.getsockname()[1]

    address = pick_ipv4_address(iface)

    advertiser = _Advertiser(device_name=device_name, port=port, address=address)
    advertiser.start()
    debug.log(
        "server",
        f"listening on {address}:{port}, endpoint_id={advertiser.endpoint_id.decode('ascii', 'replace')}, "
        f"re-announcing every {REANNOUNCE_INTERVAL_SECONDS:.0f}s",
    )

    # BLE discovery nudge (best-effort): advertise the Nearby Share FE2C
    # service so phones/Windows list this machine instantly, and scan for
    # senders' nudges to re-announce mDNS the moment one starts looking. Both
    # degrade silently to mDNS-only if the adapter/D-Bus is unavailable.
    nudge = ble_nudge.NudgeManager(
        advertise=True,
        scan=True,
        on_nudge=advertiser.reannounce,
    )
    nudge.start()

    print(color.cyan(f"Advertising as {device_name!r} on {address}:{port}, saving to {output_path}"), file=sys.stderr)
    print(color.cyan("Waiting for an incoming transfer (Ctrl+C to stop)..."), file=sys.stderr)

    def serve(conn, peer_ip):
        try:
            try:
                outcome, completed = _handle_connection(conn, peer_ip, output_path, auto_accept, on_offer, on_progress)
            except framing.ConnectionClosedImmediately:
                # Windows' Quick Share opens and instantly closes a connection
                # to us purely to test reachability before it'll list this
                # device -- see WifiLanMedium::IsConnectableIpAddress in
                # google/nearby's Windows backend. Expected background noise,
                # not a failed transfer: no error banner, and no per-connection
                # churn, since nothing user-visible happened.
                debug.log("server", "peer closed immediately without sending data (Windows reachability probe)")
                return
            debug.log("server", f"connection finished, outcome={outcome}")
            if on_connection_end is not None:
                on_connection_end(outcome, completed)
            if isinstance(on_progress, _ReceiveProgressPrinter):
                on_progress.reset()  # close any bar left open by a canceled/disconnected transfer
            print(file=sys.stderr)  # end whatever progress line was mid-print
            if outcome == TransferOutcome.COMPLETED:
                print(color.green("Transfer finished. Saved:"), file=sys.stderr)
                for path in completed:
                    print(f"  {path}", file=sys.stderr)
            elif outcome == TransferOutcome.DECLINED:
                print(color.yellow("Transfer declined."), file=sys.stderr)
            elif outcome == TransferOutcome.CANCELED:
                print(color.yellow("Transfer canceled."), file=sys.stderr)
            elif outcome == TransferOutcome.SENDER_DISCONNECTED:
                print(color.red("Sender stopped the transfer before it finished."), file=sys.stderr)
            elif outcome == TransferOutcome.SENDER_CANCELED:
                print(color.yellow("Sender canceled the transfer."), file=sys.stderr)
        except Exception as exc:
            print(color.red(f"\nTransfer failed: {exc}"), file=sys.stderr)
            # The message alone rarely says where a protocol failure came
            # from; the traceback does, so surface it when debugging.
            if debug.enabled():
                traceback.print_exc(file=sys.stderr)

    try:
        while True:
            conn, peer_addr = listener.accept()
            debug.log("server", f"accepted connection from {peer_addr[0]}:{peer_addr[1]}")
            # Each connection is handled on its own daemon thread so the accept
            # loop never blocks on a slow peer. A pending offer waits up to
            # 120s for a human decision; if connections were handled inline,
            # a second (stacked) transfer would sit unhandled in the listen
            # backlog the whole time and never raise its accept notification.
            threading.Thread(target=serve, args=(conn, peer_addr[0]), daemon=True).start()
    except KeyboardInterrupt:
        print("\nStopping.", file=sys.stderr)
    finally:
        advertiser.stop()
        nudge.stop()
        listener.close()

    return 0
