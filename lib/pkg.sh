#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

rx_pkg_installed() {
    local pkg="$1"
    [[ -z $pkg ]] && return 1
    pacman -Qq "$pkg" >/dev/null 2>&1
}

rx_pkg_uninstall() {
    local list_file="$1"
    [[ ! -f $list_file ]] && return 0

    local all_pkgs=$(grep -v '^#' "$list_file" | xargs)
    [[ -z $all_pkgs ]] && return 0

    local installed_pkgs=()
    for pkg in $all_pkgs; do
        rx_pkg_installed "$pkg" && installed_pkgs+=("$pkg")
    done

    [[ ${#installed_pkgs[@]} -eq 0 ]] && return 0

    rx_log "info" "Removing packages: ${PINK}${installed_pkgs[*]}${RESET}"

    local remove_cmd="pacman -Rns --noconfirm"
    if [[ $EUID -ne 0 ]]; then
        remove_cmd="sudo pacman -Rns --noconfirm"
    fi
    $remove_cmd "${installed_pkgs[@]}"

    rx_log "success" "Packages removed successfully: ${PINK}${installed_pkgs[*]}${RESET}"
}

rx_pkg_install() {
    local list_file="$1"
    local sudo_run="${2:-false}"
    [[ ! -f $list_file ]] && return 0

    local all_pkgs=$(grep -v '^#' "$list_file" | xargs)
    [[ -z $all_pkgs ]] && return 0

    local missing_pkgs=()
    local skipped_pkgs=()
    for pkg in $all_pkgs; do
        if rx_pkg_installed "$pkg"; then
            continue
        fi

        if [[ $RETRO_CHROOT == "true" ]]; then
            if pacman -Si "$pkg" >/dev/null 2>&1; then
                missing_pkgs+=("$pkg")
            else
                skipped_pkgs+=("$pkg")
            fi
        elif ! _pkg_resolves "$pkg"; then
            skipped_pkgs+=("$pkg")
        else
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#skipped_pkgs[@]} -gt 0 ]]; then
        rx_log "warn" "Skipping unavailable packages (target not found): ${PINK}${skipped_pkgs[*]}${RESET}"
    fi

    [[ ${#missing_pkgs[@]} -eq 0 ]] && return 0

    rx_log "info" "Installing missing packages: ${PINK}${missing_pkgs[*]}${RESET}"

    local install_cmd=""
    if [[ $RETRO_CHROOT == "true" ]]; then
        install_cmd="pacman -S --needed --noconfirm"
    elif [[ $EUID -eq 0 ]]; then
        install_cmd="pacman -S --needed --noconfirm"
    else
        local helper
        helper=$(get_var "PKG_HELPER" "yay")
        if command -v "$helper" >/dev/null 2>&1; then
            install_cmd="$helper -S --needed --noconfirm"
        else
            if ! command -v pacman >/dev/null 2>&1; then
                rx_log "error" "No package manager available"
                return 1
            fi
            rx_log "warn" "Using pacman (no AUR helper found, AUR packages will fail)"
            install_cmd="sudo pacman -S --needed --noconfirm"
        fi
    fi

    if _rx_pkg_run "$install_cmd" "$sudo_run" "${missing_pkgs[@]}"; then
        rx_log "success" "Successfully installed ${PINK}${#missing_pkgs[@]}${RESET} packages"
        return 0
    fi

    rx_log "warn" "Batch install failed; retrying with a targeted overwrite for overlapping package files"
    if _rx_pkg_run "$install_cmd --overwrite \"$_RX_OVERWRITE_GLOBS\"" "$sudo_run" "${missing_pkgs[@]}"; then
        rx_log "success" "Successfully installed ${PINK}${#missing_pkgs[@]}${RESET} packages"
        return 0
    fi

    rx_log "warn" "Overwrite batch still failing; retrying per-package so one bad package cannot abort the rest"
    local failed=()
    local pkg
    for pkg in "${missing_pkgs[@]}"; do
        if rx_pkg_installed "$pkg"; then
            continue
        fi
        if ! _rx_pkg_install_one "$install_cmd" "$sudo_run" "$pkg"; then
            failed+=("$pkg")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        rx_log "warn" "Some packages failed to install: ${PINK}${failed[*]}${RESET}"
    else
        rx_log "success" "Successfully installed ${PINK}${#missing_pkgs[@]}${RESET} packages"
    fi
}

_RX_OVERWRITE_GLOBS="/usr/include/libdex-1/*,/usr/lib/libdex-1.so*,/usr/lib/pkgconfig/libdex-1.pc,/usr/lib/girepository-1.0/Dex-1.typelib,/usr/lib/python3.14/site-packages/gi/overrides/Dex.py*,/usr/share/gir-1.0/Dex-1.gir,/usr/share/vala/vapi/libdex-1.*"

_rx_pkg_run() {
    local cmd="$1" sudo_run="$2"
    shift 2
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    if [[ $sudo_run == "true" && $EUID -ne 0 ]]; then
        sudo bash -c "$cmd ${pkgs[*]}"
    else
        $cmd "${pkgs[@]}"
    fi
}

_rx_pkg_install_one() {
    local cmd="$1" sudo_run="$2" pkg="$3"
    if _rx_pkg_run "$cmd" "$sudo_run" "$pkg"; then
        return 0
    fi
    _rx_pkg_run "$cmd --overwrite \"$_RX_OVERWRITE_GLOBS\"" "$sudo_run" "$pkg"
}

_pkg_resolves() {
    local pkg="$1"
    if [[ $RETRO_CHROOT == "true" || $EUID -eq 0 ]]; then
        pacman -Si "$pkg" >/dev/null 2>&1
        return $?
    fi
    local helper
    helper=$(get_var "PKG_HELPER" "yay")
    if command -v "$helper" >/dev/null 2>&1; then
        $helper -Si "$pkg" >/dev/null 2>&1
    else
        pacman -Si "$pkg" >/dev/null 2>&1
    fi
}
