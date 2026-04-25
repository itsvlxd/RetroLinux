#!/bin/bash

set_tokyo_night_colors() {
    export GUM_CONFIRM_PROMPT_FOREGROUND="6"
    export GUM_CONFIRM_SELECTED_FOREGROUND="0"
    export GUM_CONFIRM_SELECTED_BACKGROUND="2"
    export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
    export GUM_CONFIRM_UNSELECTED_BACKGROUND="0"
}

if [[ -z ${RETRO_DIR:-} ]]; then
    export RETRO_DIR="/opt/retrolinux"
fi

if [[ -e /dev/tty ]]; then
    TERM_SIZE=$(stty size 2>/dev/null </dev/tty)
    if [[ -n $TERM_SIZE ]]; then
        export TERM_HEIGHT=$(echo "$TERM_SIZE" | cut -d' ' -f1)
        export TERM_WIDTH=$(echo "$TERM_SIZE" | cut -d' ' -f2)
    else
        export TERM_WIDTH=80
        export TERM_HEIGHT=24
    fi
else
    export TERM_WIDTH=80
    export TERM_HEIGHT=24
fi

export RETRO_PATH="/opt/retrolinux/bin"
export RETRO_INSTALL="$RETRO_PATH"
export RETRO_INSTALL_LOG_FILE="/var/log/retrolinux-install.log"

export LOGO_PATH="$RETRO_DIR/bin/logo.txt"

if [[ -f $LOGO_PATH ]]; then
    export LOGO_WIDTH=$(awk '{ if (length > max) max = length } END { print max+0 }' "$LOGO_PATH" 2>/dev/null || echo 0)
    export LOGO_HEIGHT=$(wc -l <"$LOGO_PATH" 2>/dev/null || echo 0)
else
    export LOGO_WIDTH=74
    export LOGO_HEIGHT=8
fi

export PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
export PADDING_LEFT_SPACES=$(printf "%*s" $PADDING_LEFT "")
export PADDING="0 0 0 $PADDING_LEFT"

export GUM_CHOOSE_PADDING="$PADDING"
export GUM_FILTER_PADDING="$PADDING"
export GUM_INPUT_PADDING="$PADDING"
export GUM_SPIN_PADDING="$PADDING"
export GUM_TABLE_PADDING="$PADDING"
export GUM_CONFIRM_PADDING="$PADDING"

clear_logo() {
    printf "\033[H\033[2J"
    gum style --foreground 5 --padding "1 0 0 $PADDING_LEFT" "$(<"$LOGO_PATH")"
}

