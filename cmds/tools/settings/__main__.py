"""Allow ``python -m settings`` to launch the app."""

import sys
import time as _time

def _dbg(msg: str) -> None:
    if "--debug" in sys.argv or "-d" in sys.argv:
        print(f"[settings.__main__] {msg}", file=sys.stderr, flush=True)

_dbg(f"__main__ entered ({_time.monotonic():.3f})")

from settings.main import main

_dbg(f"main imported, calling main() ({_time.monotonic():.3f})")
main()
