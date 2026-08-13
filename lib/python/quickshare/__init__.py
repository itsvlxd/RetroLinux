"""Native Android Quick Share (Nearby Share) protocol engine.

Vendored and adapted from ``adityatelange/quickshare-cli-py`` (MIT).

- https://github.com/adityatelange/quickshare-cli-py
- LICENSE: MIT (see ``lib/python/quickshare/LICENSE``)

This package speaks Google Quick Share over mDNS + TCP: Android's built-in
Quick Share discovers this machine and can send/receive files with it.
Retro wraps it with a daemon (scripts/python/quickshare_receive.py), a CLI
(cmds/tools/quickshare.sh) and the settings Quick Share page.
"""
