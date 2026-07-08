import re
from collections.abc import Callable

import gi
gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst

Gst.init(None)

_LOG_BAND_EDGES = [
    50, 97, 188, 365, 708, 1373, 2663, 5164, 10000,
]

_FREQUENCY_WEIGHTS = [
    0.45, 0.70, 0.95, 1.10, 1.30, 1.75, 2.50, 3.80,
]

_DEFAULT_SAMPLE_RATE = 48000

_MAGNITUDE_RE = re.compile(r"magnitude=\(float\)\{([^}]+)\}")


class SpectrumEngine:
    def __init__(self, on_data: Callable[[list[float]], None], pipeline_str: str,
                 db_floor: float = -55.0, noise_gate: float = 0.04, scale_floor: float = 0.08):
        self._on_data = on_data
        self._pipeline_str = pipeline_str
        self._pipeline: Gst.Element | None = None
        self._running = False
        self._peak_buffer = 0.5
        self._db_floor = db_floor
        self._noise_gate = noise_gate
        self._scale_floor = scale_floor

    def start(self) -> None:
        if self._running:
            return
        try:
            self._pipeline = Gst.parse_launch(self._pipeline_str)
        except Exception as e:
            print(f"[spectrum] Failed to create pipeline: {e}", file=__import__("sys").stderr)
            return

        bus = self._pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message::element", self._on_element_message)
        self._pipeline.set_state(Gst.State.PLAYING)
        self._running = True

    def stop(self) -> None:
        self._running = False
        if self._pipeline:
            self._pipeline.set_state(Gst.State.NULL)
            self._pipeline = None

    def _on_element_message(self, _bus, message: Gst.Message) -> None:
        if not self._running:
            return
        struct = message.get_structure()
        if not struct or struct.get_name() != "spectrum":
            return
        m = _MAGNITUDE_RE.search(struct.to_string())
        if not m:
            return

        magnitudes = [float(x.strip()) for x in m.group(1).split(",")]

        raw_8_bars = self._map_to_bars(magnitudes)
        true_hardware_peak = max(raw_8_bars) if raw_8_bars else 0.0
        is_silent = true_hardware_peak < self._noise_gate

        if is_silent:
            self._peak_buffer = self._peak_buffer * 0.95 + 0.1 * 0.05
            GLib.idle_add(self._on_data, [0.0] * 16)
            return

        weighted_8_bars = [raw_8_bars[i] * _FREQUENCY_WEIGHTS[i] for i in range(len(raw_8_bars))]
        mirrored_bars = weighted_8_bars[::-1] + weighted_8_bars

        smoothed_bars = mirrored_bars[:]
        for i in range(1, len(smoothed_bars)):
            if smoothed_bars[i] < smoothed_bars[i - 1] * 0.74:
                smoothed_bars[i] = smoothed_bars[i - 1] * 0.74
        for i in range(len(smoothed_bars) - 2, -1, -1):
            if smoothed_bars[i] < smoothed_bars[i + 1] * 0.74:
                smoothed_bars[i] = smoothed_bars[i + 1] * 0.74

        frame_max = max(smoothed_bars) if smoothed_bars else 0.0
        if frame_max > self._peak_buffer:
            self._peak_buffer = frame_max
        else:
            self._peak_buffer = self._peak_buffer * 0.96 + frame_max * 0.04

        scale = max(self._scale_floor, self._peak_buffer)
        scaled_bars = [min(1.0, b / scale) for b in smoothed_bars]

        GLib.idle_add(self._on_data, scaled_bars)

    def _map_to_bars(self, magnitudes: list[float]) -> list[float]:
        n = len(magnitudes)
        if n == 0:
            return [0.0] * (len(_LOG_BAND_EDGES) - 1)

        nyquist = _DEFAULT_SAMPLE_RATE / 2
        bin_width = nyquist / n
        edges = _LOG_BAND_EDGES
        result = []

        for i in range(len(edges) - 1):
            lo = max(0, int(edges[i] / bin_width))
            hi = min(n - 1, int(edges[i + 1] / bin_width))

            if hi < lo:
                hi = lo

            band_max = max(magnitudes[lo:hi + 1])
            db_floor = self._db_floor
            normalized = max(0.0, min(1.0, (band_max - db_floor) / (-db_floor)))
            result.append(normalized)

        return result