#!/bin/bash

rx_get_json() {
    local file="$1"
    local key="$2"
    local default="$3"

    if [[ -f $file ]] && command -v jq >/dev/null; then
        local val=$(jq -r ".$key // empty" "$file")
        val="${val/#\~/$HOME}"
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

rx_link() {
    local source_in_repo=$(readlink -f "$1")
    local target_on_system="$2"

    if [[ -L $target_on_system ]]; then
        if [[ "$(readlink -f "$target_on_system")" == "$source_in_repo" ]]; then
            return 0
        fi
    fi

    if [[ -e $target_on_system && ! -L $target_on_system ]]; then
        rx_log "warn" "Found existing data at $target_on_system. Creating backup..."
        mv "$target_on_system" "${target_on_system}.bak"
    fi

    mkdir -p "$(dirname "$target_on_system")"

    if ln -sfnT "$source_in_repo" "$target_on_system"; then
        rx_log "success" "Linked: ${PINK}$(basename "$target_on_system")${RESET}"
    else
        rx_log "error" "Failed to link $target_on_system"
    fi
}

rx_mirror_pull() {
    local system_path="$1"
    local repo_data_path="$2"

    [[ ! -e $system_path ]] && return 0

    rx_log "info" "Pulling system files to repository..."

    mkdir -p "$repo_data_path"

    if [[ -d $system_path ]]; then
        rsync -au --delete \
            --exclude='**lock' --exclude='**Cache**' --exclude='**tmp**' \
            "$system_path/" "$repo_data_path/"
    else
        rsync -au "$system_path" "$repo_data_path/"
    fi
}

rx_mirror_install() {
    local repo_data_path="$1"
    local system_path="$2"

    if [[ -e $system_path && ! -L $system_path ]]; then
        return 0
    fi

    rx_log "info" "Installing physical copies to $system_path"

    [[ -L $system_path ]] && unlink "$system_path"

    mkdir -p "$(dirname "$system_path")"

    if [[ -d $repo_data_path ]]; then
        mkdir -p "$system_path"
        rsync -a --delete "$repo_data_path/" "$system_path/"
    else
        rsync -a "$repo_data_path" "$system_path"
    fi

    rx_sanitize "$system_path"
}

rx_sanitize() {
    local target="$1"

    [[ ! -e $target ]] && return 0

    if [[ -f $target ]]; then
        sed -i "s|/home/[^/]*|/home/$USER|g" "$target" 2>/dev/null
    elif [[ -d $target ]]; then
        rx_log "info" "Sanitizing paths for $USER..."
        find "$target" -type f \( -name "*.json" -o -name "*.conf" -o -name "*.toml" -o -name "*.yaml" \) \
            -exec sed -i "s|/home/[^/]*|/home/$USER|g" {} + 2>/dev/null
    fi
}

rx_restore() {
    local target="$1"
    local backup="${target}.bak"

    if [[ -L $target || -e $target ]]; then
        rx_log "info" "Removing system files at $target"
        rm -rf "$target"
    fi

    if [[ -e $backup ]]; then
        mv "$backup" "$target"
        rx_log "success" "Backup restored to $target"
    else
        rx_log "warn" "No backup found for $(basename "$target"). System path is now clean."
    fi
}
