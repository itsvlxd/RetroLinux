#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

setup_editors() {
    if [[ -n $EDITOR ]] || grep -q "EDITOR=" /etc/environment 2>/dev/null; then
        return 0
    fi

    rx_log "info" "Which text editor do you want to use:"
    rx_help_section "�편집" "Editor Selection"
    rx_table_simple "1)" "Neovim"
    rx_table_simple "2)" "Vim"
    rx_table_simple "3)" "Vi"
    rx_table_simple "4)" "Nano"

    rx_log "info" "Selection ${PINK}[1-4]${RESET}: "
    read -r ed_choice

    local target_editor=""
    case "$ed_choice" in
        1) target_editor="nvim" ;;
        2) target_editor="vim" ;;
        3) target_editor="vi" ;;
        4) target_editor="nano" ;;
        *) rx_log "error" "Invalid selection. Defaulting to Nano for safety." && target_editor="nano" ;;
    esac

    if ! command -v "$target_editor" &>/dev/null; then
        local helper=$(get_var "PKG_HELPER")
        [[ -z $helper || $helper == "null" ]] && helper="sudo pacman"

        rx_log "info" "Binary missing. Pulling ${PINK}$target_editor${RESET} via $helper..."
        $helper -S --noconfirm "$target_editor"
    fi

    sudo bash -c "cat <<EOF >> /etc/environment
EDITOR=$target_editor
VISUAL=$target_editor
SUDO_EDITOR=$target_editor
EOF"

    # 5. Live session sync
    export EDITOR="$target_editor"
    export VISUAL="$target_editor"
    export SUDO_EDITOR="$target_editor"

    rx_log "success" "System standard established: ${PINK}$target_editor${RESET}"
}
