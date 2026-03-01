#!/bin/bash

REPO_DIR="$(dirname "$(readlink -f "$0")")"

source "$REPO_DIR/lib/log.sh"

rx_link() {
    local source_in_repo=$(readlink -f "$1")
    local target_on_system="$2"

    mkdir -p "$(dirname "$target_on_system")"

    if [[ -e "$target_on_system" && ! -L "$target_on_system" ]]; then
        rx_log "warn" "Found existing data at $target_on_system. Creating backup..."
        mv "$target_on_system" "${target_on_system}.bak"
    fi

    if ln -sf "$source_in_repo" "$target_on_system"; then
        rx_log "success" "Linked to $target_on_system"
    else
        rx_log "error" "Failed to create link at $target_on_system"
    fi
}

rx_mirror_pull() {
    local system_path="$1"
    local repo_data_path="$2"

    rx_log "info" "Pulling system files to repository"

    mkdir -p "$repo_data_path"

    if [[ -d "$system_path" ]]; then
        rsync -av --delete \
            --exclude='**lock' --exclude='**Cache**' --exclude='**tmp**' \
            "$system_path/" "$repo_data_path/"
    else
        rsync -av "$system_path" "$repo_data_path/"
    fi
}

rx_mirror_install() {
    local repo_data_path="$1"
    local system_path="$2"

    rx_log "info" "Installing physical copies to $system_path"

    if [[ -L "$system_path" ]]; then
        rx_log "warn" "Removing existing symlink at $system_path"
        unlink "$system_path"
    elif [[ -e "$system_path" ]]; then
        rx_log "warn" "Found real data at $system_path. Creating backup..."
        mv "$system_path" "${system_path}.bak"
    fi

    mkdir -p "$(dirname "$system_path")"

    if [[ -d "$repo_data_path" ]]; then
        mkdir -p "$system_path"
        rsync -av --delete "$repo_data_path/" "$system_path/"
    else
        rsync -av "$repo_data_path" "$system_path"
    fi

    rx_sanitize "$system_path"
}

rx_link_bin() {
    local source_bin=$(readlink -f "$1")
    local bin_dir="$HOME/.local/bin"
    local cmd_name=$(basename "$1" .sh)
    local target="$bin_dir/$cmd_name"

    mkdir -p "$bin_dir"

    if [[ -L "$target" ]]; then
        rx_log "info" "Updating existing binary link: $target"
        rm "$target"
    fi

    ln -sf "$source_bin" "$target"
    chmod +x "$source_bin"

    rx_log "success" "Command '$PINK$cmd_name$RESET' is now available globally."
}

rx_sanitize() {
    local target_dir="$1"
    if [[ -f "$target_dir" ]]; then
        sed -i "s|/home/[^/]*|/home/$USER|g" "$target_dir" 2>/dev/null
    elif [[ -d "$target_dir" ]]; then
        rx_log "info" "Sanitizing user paths in $target_dir"
        find "$target_dir" -type f \( -name "*.json" -o -name "*.conf" -o -name "prefs.js" \) \
            -exec sed -i "s|/home/[^/]*|/home/$USER|g" {} + 2>/dev/null
    fi
}
