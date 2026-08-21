#!/bin/bash

cmd_settings() {
    if [[ "$1" == "--compile" ]]; then
        shift
        echo "Clearing stale cache..."
        find "$RETRO_DIR/cmds/tools/settings" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null
        echo "Compiling settings package..."
        python -m compileall "$RETRO_DIR/cmds/tools/settings"
        echo "Done."
        return
    fi

    if [[ "$1" == "--debug" ]]; then
        shift
        echo "[settings.sh] RETRO_DIR=$RETRO_DIR" >&2
        echo "[settings.sh] Launching python -m settings $*" >&2
        PYTHONUNBUFFERED=1 \
        PYTHONPATH="$RETRO_DIR/cmds/tools:$RETRO_DIR/scripts:$RETRO_DIR:$PYTHONPATH" \
            python -m settings "$@"
        echo "[settings.sh] Python exited with code $?" >&2
    else
        PYTHONPATH="$RETRO_DIR/cmds/tools:$RETRO_DIR/scripts:$RETRO_DIR:$PYTHONPATH" \
            nohup python -m settings "$@" >/dev/null 2>&1 &
        disown
    fi
}

register_command "TOOLS" "settings" "Open the Retro Settings GUI" "cmd_settings"
