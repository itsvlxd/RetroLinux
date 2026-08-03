"""Python wrapper for the RetroShell keystore (``keystore.py`` + ``keys.db``).

The QML ``KeyStore`` singleton reads/writes XOR-encrypted API keys stored in
an SQLite database at ``Quickshell.dataPath("keys.db")`` via the
``keystore.py`` Python script. This module mirrors those operations so the
settings app can list, set and delete provider keys without touching the
QML layer.

Caveats
-------
- The keystore script encrypts keys with a per-machine XOR key derived
  from ``/etc/machine-id``. Keys set here are interchangeable with those set
  by the QML ``KeyStore`` — they use the same script and database.
- The Ollama "key" is a sentinel value ``"enabled"`` (the QML panel
  stores it as an API key to track whether Ollama is turned on).
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Any


def _find_script() -> str | None:
    candidates = [
        "~/.local/share/Quickshell/scripts/keystore.py",
        "~/.local/share/retroshell/scripts/keystore.py",
        "/opt/retrolinux/modules/retroshell/files/scripts/keystore.py",
    ]
    for c in candidates:
        p = Path(os.path.expanduser(c))
        if p.is_file():
            return str(p)
    return None


def _find_db() -> str | None:
    candidates = [
        "~/.local/share/Quickshell/keys.db",
        "~/.local/share/retroshell/keys.db",
    ]
    for c in candidates:
        p = Path(os.path.expanduser(c))
        if p.is_file():
            return str(p)
    return None


def _run(*args: str) -> dict[str, Any]:
    script = _find_script()
    db = _find_db()
    if not script or not db:
        return {}
    argv = ["python3", script, db, *args]
    result = subprocess.run(argv, capture_output=True, text=True, timeout=15,
                            stdin=subprocess.DEVNULL)
    if result.returncode == 0 and result.stdout.strip():
        try:
            return json.loads(result.stdout.strip())
        except json.JSONDecodeError:
            pass
    return {}


def list_keys() -> list[dict[str, str]]:
    """Return all stored keys as a list of ``{provider, api_key, endpoint, custom_curl}``."""
    result = _run("list")
    if isinstance(result, list):
        return result
    return []


def has_key(provider: str) -> bool:
    """True when *provider* has a stored key (or Ollama is enabled)."""
    return any(k.get("provider") == provider for k in list_keys())


def get_key(provider: str) -> str:
    """Return the decrypted API key for *provider*, or ``""``."""
    for k in list_keys():
        if k.get("provider") == provider:
            return str(k.get("api_key", ""))
    return ""


def set_key(provider: str, api_key: str, endpoint: str = "",
            custom_curl: str = "") -> None:
    """Store (or update) an API key for *provider*."""
    args = [provider, api_key]
    if endpoint:
        args.append(endpoint)
        if custom_curl:
            args.append(custom_curl)
    _run("set", *args)


def delete_key(provider: str) -> None:
    """Remove the stored key for *provider*."""
    _run("delete", provider)


def ollama_models() -> list[str]:
    """Return installed Ollama model names (empty list if Ollama is unreachable)."""
    try:
        result = subprocess.run(
            ["curl", "-s", "http://127.0.0.1:11434/api/tags"],
            capture_output=True, text=True, timeout=10,
            stdin=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout or "{}")
            models = data.get("models", [])
            return [m.get("name", "") for m in models if m.get("name")]
    except (json.JSONDecodeError, subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return []
