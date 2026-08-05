#!/usr/bin/env python3

import os
import sys

_RETRO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, _RETRO_DIR)
sys.path.insert(0, os.path.join(_RETRO_DIR, "cmds", "tools"))

from lib.python.variable import get_var  # noqa: E402
from settings.core import config  # noqa: E402
from hyprland_config import atomic_write  # noqa: E402

_INPUT_OPTION_KEYS = [
    ("INPUT_KB_LAYOUT", "input:kb_layout", "us"),
    ("INPUT_KB_VARIANT", "input:kb_variant", ""),
    ("INPUT_KB_MODEL", "input:kb_model", ""),
    ("INPUT_KB_OPTIONS", "input:kb_options", ""),
    ("INPUT_KB_RULES", "input:kb_rules", ""),
    ("INPUT_REPEAT_RATE", "input:repeat_rate", "50"),
    ("INPUT_REPEAT_DELAY", "input:repeat_delay", "300"),
    ("INPUT_MOUSE_SENSITIVITY", "input:sensitivity", "0"),
    ("INPUT_MOUSE_ACCEL_PROFILE", "input:accel_profile", "flat"),
    ("INPUT_TOUCHPAD_NATURAL_SCROLL", "input:touchpad:natural_scroll", "true"),
]


def _to_configsections(sections, rules):
    cs = config.ConfigSections()

    binds = config.collect_bind_section(sections)
    if binds:
        cs.binds = binds

    for attr, keys in [
        ("monitors", [config.KEYWORD_MONITOR]),
        ("workspaces", [config.KEYWORD_WORKSPACE]),
        ("animations", [config.KEYWORD_ANIMATION]),
        ("beziers", [config.KEYWORD_BEZIER]),
        ("env", [config.KEYWORD_ENV]),
        ("exec_", [config.KEYWORD_EXEC, config.KEYWORD_EXEC_ONCE]),
    ]:
        lines = config.collect_section(sections, *keys)
        if lines:
            setattr(cs, attr, lines)

    window_rules = [
        r for r in rules
        if r.kind in (config.KEYWORD_WINDOWRULE, config.KEYWORD_WINDOWRULEV2)
    ]
    layer_rules = [r for r in rules if r.kind == config.KEYWORD_LAYERRULE]
    if window_rules:
        cs.window_rules_nodes = window_rules
    if layer_rules:
        cs.layer_rules_nodes = layer_rules

    return cs


def _append_blocks(text):
    gesture = get_var("INPUT_GESTURE_FINGERS", "3")
    device = get_var("INPUT_DEVICE_NAME", "")

    extra = ""
    if gesture and gesture != "0":
        extra += (
            "\nhl.gesture({\n"
            f"    fingers = {gesture},\n"
            f'    direction = "{get_var("INPUT_GESTURE_DIRECTION", "horizontal")}",\n'
            f'    action = "{get_var("INPUT_GESTURE_ACTION", "workspace")}",\n'
            "})\n"
        )
    if device:
        extra += (
            "\nhl.device({\n"
            f'    name = "{device}",\n'
            f'    sensitivity = {get_var("INPUT_DEVICE_SENSITIVITY", "0")},\n'
            f'    accel_profile = "{get_var("INPUT_DEVICE_ACCEL_PROFILE", "flat")}",\n'
            "})\n"
        )
    return text + extra


def apply():
    opts, sections, rules = config.read_all_sections()

    for var, key, default in _INPUT_OPTION_KEYS:
        opts[key] = get_var(var, default)

    cs = _to_configsections(sections, rules)
    text = config.to_managed_text(opts, cs)
    text = _append_blocks(text)

    atomic_write(config.managed_path(), text)


def main(argv):
    if argv[:1] == ["--apply"]:
        apply()
        return 0
    print("Usage: input_config.py --apply", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
