"""Dispatch from schema option dict to the appropriate ``OptionRow`` subclass."""

from settings.ui.options.base import OptionRow
from settings.ui.options.color import ColorOptionRow, GradientOptionRow
from settings.ui.options.combo import ComboOptionRow, SourceComboOptionRow
from settings.ui.options.keyboard import KeyboardLayoutsOptionRow
from settings.ui.options.multi import MultiSourceOptionRow
from settings.ui.options.numeric import (
    SpinFloatOptionRow,
    SpinIntOptionRow,
    SwitchOptionRow,
    Vec2OptionRow,
)
from settings.ui.options.text import EntryOptionRow

_ROW_CLASSES = {
    "bool": SwitchOptionRow,
    "int": SpinIntOptionRow,
    "float": SpinFloatOptionRow,
    "string": EntryOptionRow,
    "color": ColorOptionRow,
    "gradient": GradientOptionRow,
    "choice": ComboOptionRow,
    "vec2": Vec2OptionRow,
}


def create_option_row(
    option: dict, value, on_change, on_reset, on_discard=None
) -> OptionRow | None:
    """Create an OptionRow for the given schema option.

    Returns an OptionRow wrapper (access .row for the Gtk widget), or None if unsupported.
    """
    if option.get("type") == "keyboard_layouts":
        return KeyboardLayoutsOptionRow(option, value, on_change, on_reset, on_discard)
    if option.get("source") and option.get("multi"):
        return MultiSourceOptionRow(option, value, on_change, on_reset, on_discard)
    if option.get("source"):
        return SourceComboOptionRow(option, value, on_change, on_reset, on_discard)
    cls = _ROW_CLASSES.get(option.get("type", ""))
    if cls is None:
        return None
    return cls(option, value, on_change, on_reset, on_discard)
