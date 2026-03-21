#!/bin/bash

setup_file_manager() {
    local existing_fm=$(get_var "RETRO_FILEMANAGER_CMD")
    if [[ -n $existing_fm && $existing_fm != "null" ]]; then
        return 0
    fi

    if ! command -v xdg-mime &>/dev/null; then
        local helper=$(get_var "PKG_HELPER")
        [[ -z $helper || $helper == "null" ]] && helper="sudo pacman"
        rx_log "info" "The xdg-utils package is required for system integration. Installation is starting."
        $helper -S --noconfirm xdg-utils
    fi

    rx_log "info" "Select the primary file manager to be used as the system standard:"
    echo -e "  ${PINK}1)${RESET} Thunar (Fast, XFCE style)"
    echo -e "  ${PINK}2)${RESET} Nemo (Cinnamon style, feature-rich)"
    echo -e "  ${PINK}3)${RESET} Nautilus (GNOME style, clean)"
    echo -e "  ${PINK}4)${RESET} Yazi (Terminal-based, Blazing fast)"

    rx_log "info" "Enter selection ${PINK}[1-4]${RESET}: "
    read -r fm_choice

    local target_fm=""
    local desktop_file=""

    case "$fm_choice" in
        1)
            target_fm="thunar"
            desktop_file="thunar.desktop"
            ;;
        2)
            target_fm="nemo"
            desktop_file="nemo.desktop"
            ;;
        3)
            target_fm="nautilus"
            desktop_file="org.gnome.Nautilus.desktop"
            ;;
        4)
            target_fm="yazi"
            desktop_file="yazi.desktop"
            ;;
        *)
            rx_log "error" "Invalid selection detected. The file manager setup has been terminated."
            return 1
            ;;
    esac

    if ! command -v "$target_fm" &>/dev/null; then
        local helper=$(get_var "PKG_HELPER")
        [[ -z $helper || $helper == "null" ]] && helper="sudo pacman"
        rx_log "info" "The ${PINK}$target_fm${RESET} binary was not found. Installation is proceeding via $helper."
        $helper -S --noconfirm "$target_fm"
    fi

    set_var "RETRO_FILEMANAGER_CMD" "$target_fm"
    xdg-mime default "$desktop_file" inode/directory
    xdg-settings set default-url-scheme-handler file "$desktop_file"

    rx_log "success" "The system file manager has been standardized to ${PINK}$target_fm${RESET} and saved to the configuration."
}
