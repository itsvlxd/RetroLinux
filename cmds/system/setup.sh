#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

RETRO_INSTALL="$HOME/.retro_install"

cmd_setup() {
    [[ ! -f $RETRO_INSTALL ]] && exit 1

    exec kitty -e bash -c "source $RETRO_INSTALL && source $RETRO_DIR/cmds/system/setup/run.sh && run_postinstall"
}

if [[ -f $RETRO_INSTALL ]]; then
    register_command "SYSTEM" "-s|--setup" "Run post-install setup" "cmd_setup"
fi
