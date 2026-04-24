set_tokyo_night_colors() {
    export GUM_CONFIRM_PROMPT_FOREGROUND="6"
    export GUM_CONFIRM_SELECTED_FOREGROUND="0"
    export GUM_CONFIRM_SELECTED_BACKGROUND="2"
    export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
    export GUM_CONFIRM_UNSELECTED_BACKGROUND="0"
    export PADDING="0 0 0 $PADDING_LEFT"
    export GUM_CHOOSE_PADDING="$PADDING"
    export GUM_FILTER_PADDING="$PADDING"
    export GUM_INPUT_PADDING="$PADDING"
    export GUM_SPIN_PADDING="$PADDING"
    export GUM_TABLE_PADDING="$PADDING"
    export GUM_CONFIRM_PADDING="$PADDING"
}

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

export RETRO_PATH="/root/retro-install"
export RETRO_INSTALL="$RETRO_PATH"
export RETRO_INSTALL_LOG_FILE="/var/log/retrolinux-install.log"

export PINK="\[\033[38;5;5m\]"
export WHITE="\[\033[38;5;255m\]"
export RESET="\[\033[0m\]"
export PINK_FG='\033[38;5;5m'
export WHITE_FG='\033[38;5;255m'

export LOGO_PATH="$RETRO_INSTALL/logo.sh"
export LOGO_WIDTH=100
export LOGO_HEIGHT=60

export PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
export PADDING_LEFT_SPACES=$(printf "%*s" $PADDING_LEFT "")

clear_logo() {
    printf "\033[H\033[2J"
    bash "$LOGO_PATH"
    echo
}

show_progress() {
    local current=$1
    local total=$2
    local message=$3
    clear_logo
    echo
    gum style --foreground 5 "$current/$total"
    gum style --foreground 255 "$message"
    echo
}

