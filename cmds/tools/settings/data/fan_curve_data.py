"""Fan curve data management — named curves for fan control."""

import functools
import json
from pathlib import Path

from settings.core.config import RETRO_SETTINGS_DIR

FAN_CURVES_PATH = RETRO_SETTINGS_DIR / "fan_curves.json"

BUILTIN_CURVES: dict[str, list[tuple[int, int]]] = {
    "quiet":        [(30, 20), (50, 40), (70, 60), (85, 80)],
    "balanced":     [(30, 30), (50, 50), (70, 75), (85, 100)],
    "performance":  [(30, 40), (50, 70), (70, 90), (85, 100)],
}


def curve_to_str(points: list[tuple[int, int]]) -> str:
    return ",".join(f"{t}:{p}" for t, p in points)


def curve_from_str(s: str) -> list[tuple[int, int]]:
    if not s:
        return []
    result = []
    for pair in s.split(","):
        pair = pair.strip()
        if ":" in pair:
            t, p = pair.split(":", 1)
            result.append((int(t), int(p)))
    return sorted(result, key=lambda x: x[0])


class FanCurveStore:
    """Manages named fan curves (user-defined + builtins)."""

    def __init__(self, path: Path):
        self._path = path
        self._user_curves: dict[str, list[tuple[int, int]]] | None = None

    def _ensure(self) -> dict[str, list[tuple[int, int]]]:
        if self._user_curves is None:
            self._user_curves = self._read()
        return self._user_curves

    def _read(self) -> dict[str, list[tuple[int, int]]]:
        if self._path.exists():
            try:
                raw = json.loads(self._path.read_text())
                return {k: [(t, p) for t, p in v] for k, v in raw.items()}
            except (json.JSONDecodeError, TypeError, ValueError):
                pass
        return {}

    def _save(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        data = {k: [[t, p] for t, p in v] for k, v in self._ensure().items()}
        self._path.write_text(json.dumps(data, indent=2) + "\n")

    def get_user_curve_names(self) -> list[str]:
        return sorted(self._ensure().keys())

    def get_all_curve_names(self) -> list[str]:
        return list(BUILTIN_CURVES.keys()) + self.get_user_curve_names()

    def get_curve_points(self, name: str) -> list[tuple[int, int]]:
        if name in BUILTIN_CURVES:
            return list(BUILTIN_CURVES[name])
        return self._ensure().get(name, [])

    def is_builtin(self, name: str) -> bool:
        return name in BUILTIN_CURVES

    def save_user_curve(self, name: str, points: list[tuple[int, int]]) -> None:
        self._ensure()[name] = sorted(points, key=lambda x: x[0])
        self._save()

    def delete_user_curve(self, name: str) -> None:
        self._ensure().pop(name, None)
        self._save()

    def rename_user_curve(self, old: str, new: str) -> None:
        curves = self._ensure()
        if old in curves:
            curves[new] = curves.pop(old)
            self._save()

    def next_custom_name(self) -> str:
        existing = set(self.get_all_curve_names())
        for i in range(1, 1000):
            name = f"Custom {i}"
            if name not in existing:
                return name
        return "Custom 1"


@functools.lru_cache(maxsize=1)
def get_fan_curve_store() -> FanCurveStore:
    return FanCurveStore(FAN_CURVES_PATH)
