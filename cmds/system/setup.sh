#!/bin/bash

RETRO_DIR="${RETRO_DIR:-/opt/retrolinux}"
RETRO_INSTALL="${RETRO_INSTALL:-$HOME/.retro_install}"

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

cmd_setup() {
    [[ ! -f $RETRO_INSTALL ]] && exit 1

    local setup_cmd="source $RETRO_INSTALL && source $RETRO_DIR/cmds/system/setup/run.sh && run_postinstall"

    if [[ -n ${KITTY_WINDOW_ID:-} ]]; then
        eval "$setup_cmd"
        return
    fi

    local terminal=""
    if command -v kitty >/dev/null 2>&1; then
        terminal="kitty"
    elif [[ -n ${TERMINAL:-} ]] && command -v "$TERMINAL" >/dev/null 2>&1; then
        terminal="$TERMINAL"
    fi

    if [[ -n $terminal ]]; then
        exec "$terminal" -e bash -c "$setup_cmd"
    else
        rx_log "warn" "No graphical terminal found, running setup in current shell"
        eval "$setup_cmd"
    fi
}

if [[ -f $RETRO_INSTALL ]]; then
    register_command "SYSTEM" "-s|--setup" "Run post-install setup" "cmd_setup"
fi
