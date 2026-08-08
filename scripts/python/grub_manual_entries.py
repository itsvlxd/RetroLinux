#!/usr/bin/env python3
"""Parse /boot/grub/grub.cfg menu entries and splice manual overrides into it.

The GRUB boot menu editor in Retro Settings stores user-curated
``menuentry``/``submenu`` blocks in a manual-entries store. After every
deterministic regeneration (grub-mkconfig + the standard patches) this
script re-applies those blocks so manual edits survive regeneration.

Entry blocks are keyed by the entry's ``--id`` (or ``$menuentry_id_option``
argument) when present, falling back to ``kind|title`` for entries without
an id (shutdown/restart/memtest). Replacing by key means the template's
original block is swapped for the user's version, and blocks with no
matching template entry are appended at the end of grub.cfg.

Store format (written by the settings app, read here):

    ### RETRO_MANUAL_ENTRY: <key> ###
    menuentry '...' ... {
        ...
    }
    ### END RETRO_MANUAL_ENTRY ###

Modes:

    --parse CFG            Emit JSON list of top-level blocks.
    --parse-store STORE    Emit JSON list of {key, block} overrides.
    --apply CFG STORE      Emit CFG with manual overrides spliced in (stdout).
    --reorder CFG STORE    Emit CFG with the template menu reordered (stdout).
"""

import json
import re
import sys

_BEGIN_RE = re.compile(r"^### RETRO_MANUAL_ENTRY: (.+?) ###$")
_END_RE = re.compile(r"^### END RETRO_MANUAL_ENTRY ###$")
_ID_RE = re.compile(r"(?:--id|\$menuentry_id_option)\s+'([^']+)'")
_TITLE_RE = re.compile(r"([\"'])(.*?)\1")

_REGION_BEGIN = "### BEGIN /etc/grub.d/10_linux ###"
_REGION_END = "### END /etc/grub.d/10_linux ###"
_ORDER_BEGIN_RE = re.compile(r"^### RETRO_MENU_ORDER ###$")
_ORDER_END_RE = re.compile(r"^### END RETRO_MENU_ORDER ###$")


def _strip_quotes(text: str, i: int) -> bool:
    """Return True if text[i] is inside a single- or double-quoted string."""
    in_single = False
    in_double = False
    for ch in text[:i]:
        if in_single:
            if ch == "'":
                in_single = False
        elif in_double:
            if ch == '"':
                in_double = False
        else:
            if ch == "'":
                in_single = True
            elif ch == '"':
                in_double = True
    return in_single or in_double


def find_blocks(text: str) -> list[dict]:
    """Find top-level ``menuentry``/``submenu`` blocks in *text*.

    Returns a list of dicts with ``start``/``end`` byte offsets (into the
    original *text*), the full ``text`` of the block, ``kind``,
    ``title``, ``id`` (or ``None``), ``key`` and ``summary`` (first body
    command). Nested entries inside a submenu are consumed by their parent
    block and never reported here.
    """
    blocks: list[dict] = []
    n = len(text)
    i = 0
    while i < n:
        line_end = text.find("\n", i)
        if line_end == -1:
            line_end = n
        stripped = text[i:line_end].lstrip()
        if stripped.startswith("menuentry ") or stripped.startswith("submenu "):
            # Locate the opening brace on the header line, outside quotes.
            open_idx = -1
            for k in range(i, line_end):
                if text[k] == "{" and not _strip_quotes(text, k):
                    open_idx = k
                    break
            if open_idx != -1:
                depth = 1
                j = open_idx + 1
                in_single = False
                in_double = False
                while j < n and depth > 0:
                    ch = text[j]
                    if in_single:
                        if ch == "'":
                            in_single = False
                    elif in_double:
                        if ch == '"':
                            in_double = False
                    else:
                        if ch == "'":
                            in_single = True
                        elif ch == '"':
                            in_double = True
                        elif ch == "{":
                            depth += 1
                        elif ch == "}":
                            depth -= 1
                    j += 1
                close_idx = j - 1 if depth == 0 else n - 1
                header = text[i:line_end]
                block_text = text[i:close_idx + 1]
                kind = "submenu" if stripped.startswith("submenu ") else "menuentry"
                title = _TITLE_RE.search(header)
                title = title.group(2) if title else ""
                id_match = _ID_RE.search(header)
                entry_id = id_match.group(1) if id_match else None
                body_lines = block_text.splitlines()[1:-1]
                summary = next((ln.strip() for ln in body_lines if ln.strip()), "")
                blocks.append({
                    "start": i,
                    "end": close_idx + 1,
                    "text": block_text,
                    "kind": kind,
                    "title": title,
                    "id": entry_id,
                    "key": entry_id or f"{kind}|{title}",
                    "summary": summary[:120],
                })
                i = close_idx + 1
                continue
        i = line_end + 1
    return blocks


def parse_store(store: str) -> list[dict]:
    """Parse the manual-entries store into ``[{key, block}]`` in file order."""
    overrides: list[dict] = []
    try:
        with open(store, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return overrides

    key = None
    body: list[str] = []
    for line in lines:
        begin = _BEGIN_RE.match(line)
        end = _END_RE.match(line)
        if begin:
            key = begin.group(1).strip()
            body = []
        elif end:
            if key is not None:
                overrides.append({"key": key, "block": "\n".join(body).rstrip()})
            key = None
            body = []
        elif key is not None:
            body.append(line)
    return overrides


def apply_manual(text: str, overrides: list[dict]) -> str:
    """Return *text* with manual *overrides* spliced in."""
    if not overrides:
        return text
    index: dict[str, dict] = {}
    for b in find_blocks(text):
        index.setdefault(b["key"], b)

    replacements: list[tuple[int, int, str]] = []
    appended: list[str] = []
    for override in overrides:
        target = index.get(override["key"])
        if target is not None:
            replacements.append((target["start"], target["end"], override["block"]))
        else:
            appended.append(override["block"])

    out = text
    for start, end, block in sorted(replacements, reverse=True):
        out = out[:start] + block.rstrip("\n") + out[end:]

    if appended:
        out = out.rstrip("\n")
        for block in appended:
            out += "\n\n" + block.rstrip("\n")
        out += "\n"
    return out


def parse_order(store: str) -> list[str]:
    """Parse the persisted menu order (key list) from the store."""
    order: list[str] = []
    try:
        with open(store, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return order

    in_order = False
    for line in lines:
        if _ORDER_BEGIN_RE.match(line):
            in_order = True
        elif _ORDER_END_RE.match(line):
            in_order = False
        elif in_order:
            key = line.strip()
            if key:
                order.append(key)
    return order


def reorder_blocks(text: str, order: list[str]) -> str:
    """Return *text* with the template menu region reordered by *order*.

    Only the top-level ``menuentry``/``submenu`` blocks inside the
    ``### BEGIN /etc/grub.d/10_linux ###`` region are reordered; everything
    else (00_header, os-prober, custom.cfg sources, ...) is left untouched.
    Keys not listed in *order* keep their relative positions after the listed
    ones, so an incomplete order never drops entries.
    """
    if not order:
        return text
    begin = text.find(_REGION_BEGIN)
    if begin == -1:
        return text
    end = text.find(_REGION_END, begin)
    if end == -1:
        return text

    region_start = begin
    region_end = end + len(_REGION_END)
    region = text[region_start:region_end]
    blocks = find_blocks(region)
    if not blocks:
        return text

    by_key = {b["key"]: b for b in blocks}
    current = [b["key"] for b in blocks]
    ordered: list[dict] = []
    seen: set[str] = set()
    for key in order:
        if key in by_key and key not in seen:
            ordered.append(by_key[key])
            seen.add(key)
    ordered += [b for b in blocks if b["key"] not in seen]
    if [b["key"] for b in ordered] == current:
        return text

    pre = region[:blocks[0]["start"]]
    post = region[blocks[-1]["end"]:]
    body = "\n\n".join(b["text"].rstrip("\n") for b in ordered)
    new_region = pre.rstrip("\n") + "\n\n" + body + "\n\n" + post.lstrip("\n")
    return text[:region_start] + new_region + text[region_end:]


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "--parse":
        cfg = argv[2]
        try:
            with open(cfg, "r", encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        json.dump(find_blocks(text), sys.stdout)
        sys.stdout.write("\n")
        return 0

    if len(argv) >= 3 and argv[1] == "--parse-store":
        json.dump(parse_store(argv[2]), sys.stdout)
        sys.stdout.write("\n")
        return 0

    if len(argv) >= 4 and argv[1] == "--apply":
        try:
            with open(argv[2], "r", encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        out = apply_manual(text, parse_store(argv[3]))
        sys.stdout.write(out)
        return 0

    if len(argv) >= 4 and argv[1] == "--reorder":
        try:
            with open(argv[2], "r", encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        out = reorder_blocks(text, parse_order(argv[3]))
        sys.stdout.write(out)
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
