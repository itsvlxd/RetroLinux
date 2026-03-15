#!/bin/bash

source "$RETRO_DIR/cmds/tools/bitwarden.sh"

rx_setup_bitwarden() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    local current_state=$(bash "$var_script" --get "CLIP_BITWARDEN")
    [[ -n $current_state && $current_state != "null" ]] && return 0

    rx_log "info" "Would you like to setup the bitwarden? ${PINK}[y/N]${RESET}: "
    read -r allow
    [[ ! $allow =~ ^[Yy]$ ]] && bash "$var_script" --set "CLIP_BITWARDEN" false && return 0

    cmd_bw "setup"
}
