#!/bin/bash

rx_bootstrap_pkg_manager() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    local saved_helper=$(bash "$var_script" --get "PKG_HELPER")

    local has_yay=false
    command -v yay >/dev/null 2>&1 && has_yay=true
    local has_paru=false
    command -v paru >/dev/null 2>&1 && has_paru=true

    if [[ -n $saved_helper ]]; then
        if command -v "$saved_helper" >/dev/null 2>&1; then
            return 0
        fi
    fi

    if [[ $has_yay == true && $has_paru == false ]]; then
        bash "$var_script" --set "PKG_HELPER" "yay"
        return 0
    elif [[ $has_yay == false && $has_paru == true ]]; then
        bash "$var_script" --set "PKG_HELPER" "paru"
        return 0
    fi

    rx_log "info" "No AUR helper configured. Let's pick one."

    echo -e "   ${PINK}1)${RESET} yay ${GRAY}(Go - Most Popular)${RESET}"
    echo -e "   ${PINK}2)${RESET} paru ${GRAY}(Rust - Feature Rich)${RESET}"
    echo -e "   ${PINK}3)${RESET} Skip / Manual"

    echo -ne "\n ${PINK}󰄾 ${RESET}Select: "
    read -r choice

    local selected=""
    case "$choice" in
        1) selected="yay" ;;
        2) selected="paru" ;;
        *)
            rx_log "info" "Skipping AUR helper setup."
            return 0
            ;;
    esac

    if ! command -v "$selected" >/dev/null 2>&1; then
        rx_install_helper "$selected"
    fi

    bash "$var_script" --set "PKG_HELPER" "$selected"
    rx_log "success" "Package helper set to ${PINK}$selected${RESET}."
}

rx_install_helper() {
    local target="$1"
    rx_log "info" "Building ${PINK}${target}${RESET} from source..."

    sudo pacman -S --needed --noconfirm base-devel git

    local temp_dir=$(mktemp -d)
    if git clone "https://aur.archlinux.org/${target}-bin.git" "$temp_dir" 2>/dev/null ||
        git clone "https://aur.archlinux.org/${target}.git" "$temp_dir"; then
        (
            cd "$temp_dir" || exit 1
            makepkg -si --noconfirm
        )
        rm -rf "$temp_dir"
    else
        rx_log "error" "Could not connect to AUR."
        rm -rf "$temp_dir"
        return 1
    fi
}
