"""Opt-in debug logging, off by default and enabled with --debug (or by
setting QUICKSHARE_DEBUG=1 in the environment, which is what the env check
this module replaces in secure_frame.py used to do on its own).

Everything goes to stderr, alongside the rest of the CLI's user-facing
output, so debug lines never contaminate anything a caller might pipe on
stdout. Lines are dim-prefixed with a monotonic timestamp and the emitting
module so a protocol trace reads as a sequence:

  [  0.014s] send      connecting to 192.168.1.7:38455
  [  0.031s] ukey2     -> ClientInit (139 bytes)
  [  0.052s] ukey2     <- ServerInit (137 bytes)

The point of this is protocol debugging: Quick Share failures are usually
"the phone hung up and said nothing", and the only way to tell a bad
handshake from a rejected offer from a misparsed frame is to see the frame
sequence. So the calls added alongside this module trace exactly that --
frame types in and out, sizes, payload ids, state transitions -- not
application trivia.

Two rules for what may be logged, given this is a security protocol carrying
a user's files:

- Never log key material, and never log payload file contents. Handshake
  keys, the ECDH shared secret, and chunk bodies are all off limits. The one
  place raw HMAC/key bytes are printed (log_hmac_mismatch) is gated behind a
  separate, louder opt-in level, because diagnosing a key-derivation
  mismatch genuinely requires comparing the bytes.
- Peer-controlled strings (device names, offered filenames) must go through
  color.sanitize before being logged, exactly as they do when printed
  normally -- a debug line is still terminal output, and an attacker who can
  name a file can otherwise smuggle escape sequences into it.
"""

from __future__ import annotations

import os
import sys
import time
from typing import Any

from quickshare import color

# Levels, in increasing verbosity. OFF is the default; BASIC is what --debug
# turns on; TRACE (--debug-trace, or QUICKSHARE_DEBUG=trace) additionally
# permits per-chunk logging and the key-material dump in log_hmac_mismatch.
OFF = 0
BASIC = 1
TRACE = 2

_level = OFF
_started_at = time.monotonic()

_ENV_VAR = "QUICKSHARE_DEBUG"
_ENV_TRACE_VALUES = ("trace", "2")


def configure_from_args(debug: bool, trace: bool = False) -> None:
    """Wire up the level from parsed CLI flags, falling back to the
    QUICKSHARE_DEBUG environment variable when neither flag is given so the
    env var that predates these flags keeps working. An explicit flag always
    wins over the environment."""
    global _level, _started_at
    if trace:
        _level = TRACE
    elif debug:
        _level = BASIC
    else:
        env = os.environ.get(_ENV_VAR, "").strip().lower()
        if env in _ENV_TRACE_VALUES:
            _level = TRACE
        elif env and env not in ("0", "false", "no"):
            _level = BASIC
        else:
            _level = OFF
    _started_at = time.monotonic()


def set_level(level: int) -> None:
    """Direct level override, for tests and for library callers that don't go
    through the CLI's argument parsing."""
    global _level
    _level = level


def enabled(level: int = BASIC) -> bool:
    """True when `level` would be logged. Guard expensive-to-build debug
    arguments with this -- hex dumps, proto formatting -- so nothing is
    computed when debugging is off (the common case)."""
    return _level >= level


def log(module: str, message: str, *, level: int = BASIC) -> None:
    if _level < level:
        return
    elapsed = time.monotonic() - _started_at
    print(color.dim(f"[{elapsed:7.3f}s] {module:<9} {message}"), file=sys.stderr)


def trace(module: str, message: str) -> None:
    """Shorthand for the per-chunk-volume logging that would drown out a
    BASIC trace -- payload chunks, individual secure frames."""
    log(module, message, level=TRACE)


def log_frame(module: str, direction: str, name: str, size: int, **fields: Any) -> None:
    """One wire frame, in or out. direction is '->' for frames we send and
    '<-' for frames we read, matching the arrows in the module docstring's
    example trace. Extra keyword fields are appended as key=value pairs
    (payload ids, offsets, status enums)."""
    if _level < BASIC:
        return
    suffix = "".join(f" {k}={v}" for k, v in fields.items())
    log(module, f"{direction} {name} ({size} bytes){suffix}")


def log_hmac_mismatch(recv_hmac_key: bytes, header_and_body: bytes, got: bytes, computed: bytes) -> None:
    """The one place raw key bytes are printed, hence the TRACE gate: an HMAC
    mismatch means the two sides derived different keys, and the only way to
    tell a key-derivation bug from a genuinely corrupt/forged frame is to
    compare the actual bytes on both ends. Requires --debug-trace explicitly
    rather than riding along on --debug, so a user pasting ordinary debug
    output into a bug report never leaks session key material."""
    if _level < TRACE:
        return
    log(
        "secure",
        "HMAC verification failed\n"
        f"  recv_hmac_key   = {recv_hmac_key.hex()}\n"
        f"  header_and_body = {header_and_body.hex()[:120]}... ({len(header_and_body)} bytes)\n"
        f"  got signature   = {got.hex()}\n"
        f"  computed hmac   = {computed.hex()}",
        level=TRACE,
    )
