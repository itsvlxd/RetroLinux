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

    if [[ $target_fm == "yazi" ]]; then
        local term_cmd=$(get_var "RETRO_TERMINAL_CMD")
        [[ -z $term_cmd || $term_cmd == "null" ]] && term_cmd="kitty"

        rx_log "info" "Generating terminal wrapper for Yazi to ensure GUI compatibility."
        mkdir -p "$HOME/.local/share/applications"
        cat <<EOF >"$HOME/.local/share/applications/retro-yazi.desktop"
[Desktop Entry]
Type=Application
Name=Yazi (Retro)
Exec=$term_cmd -e yazi %u
Icon=yazi
Terminal=true
Categories=System;FileManagement;
MimeType=inode/directory;application/x-directory;
EOF
    fi

    set_var "RETRO_FILEMANAGER_CMD" "$target_fm"

    local mime_types=("inode/directory" "application/x-directory" "x-scheme-handler/file" "x-scheme-handler/trash")
    for type in "${mime_types[@]}"; do
        xdg-mime default "$desktop_file" "$type"
    done

    for mime_file in "$HOME/.config/mimeapps.list" "$HOME/.local/share/applications/mimeapps.list"; do
        if [[ -f $mime_file ]]; then
            sed -i '/inode\/directory/d; /application\/x-directory/d; /x-scheme-handler\/file/d' "$mime_file"
            sed -i "/\[Default Applications\]/a inode/directory=$desktop_file\napplication/x-directory=$desktop_file\nx-scheme-handler/file=$desktop_file" "$mime_file"
        fi
    done

    [[ -x $(command -v update-desktop-database) ]] && update-desktop-database ~/.local/share/applications &>/dev/null

    if command -v gsettings &>/dev/null; then
        local term_cmd=$(get_var "RETRO_TERMINAL_CMD")
        [[ -z $term_cmd || $term_cmd == "null" ]] && term_cmd="kitty"
        gsettings set org.gnome.desktop.default-applications.terminal exec "$term_cmd"
        gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'
    fi

    rx_log "success" "The system file manager has been standardized to ${PINK}$target_fm${RESET} and saved to the configuration."
}
