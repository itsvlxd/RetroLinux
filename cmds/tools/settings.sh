#!/bin/bash

cmd_settings() {
    if [[ "$1" == "--debug" ]]; then
        PYTHONPATH="$RETRO_DIR/cmds/tools:$RETRO_DIR/scripts:$RETRO_DIR:$PYTHONPATH" \
            python -m settings "$@" &
    else
        PYTHONPATH="$RETRO_DIR/cmds/tools:$RETRO_DIR/scripts:$RETRO_DIR:$PYTHONPATH" \
            nohup python -m settings "$@" >/dev/null 2>&1 &
    fi
    disown
}

register_command "TOOLS" "settings" "Open the Retro Settings GUI" "cmd_settings"
