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
        rx_log "warn" "Found existing config at $target_on_system (not a retro symlink)"
        rx_log "warn" "A backup will be created before installing the retro module"
        ! rx_confirm "Install retro module here anyway?" "Y" && return 0
        rx_log "info" "Creating backup at ${target_on_system}.bak"
        mv "$target_on_system" "${target_on_system}.bak"
    fi

    mkdir -p "$(dirname "$target_on_system")"

    if ln -sfnT "$source_in_repo" "$target_on_system"; then
        rx_log "success" "Configuration files linked for module ${PINK}$(basename "$target_on_system")${RESET}"
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

    rx_log "info" "Copying module files to ${PINK}$system_path${RESET}"

    [[ -L $system_path ]] && unlink "$system_path"

    mkdir -p "$(dirname "$system_path")"

    if [[ -d $system_path ]]; then
        rsync -a --delete "$repo_data_path/" "$system_path/"
    else
        if [[ -d $repo_data_path ]]; then
            mkdir -p "$system_path"
            rsync -a --delete "$repo_data_path/" "$system_path/"
        else
            rsync -a "$repo_data_path" "$system_path"
        fi
    fi

    rx_sanitize "$system_path"
}

rx_mirror_add_missing() {
    local repo_data_path="$1"
    local system_path="$2"

    [[ -d $repo_data_path ]] || return 0

    local added=0

    if [[ ! -d $system_path ]]; then
        mkdir -p "$system_path"
        rsync -a "$repo_data_path/" "$system_path/"
        added=1
    else
        local missing_files
        missing_files=$(cd "$repo_data_path" && find . -not -path '.' | while read -r item; do
            if [[ ! -e "$system_path/$item" ]]; then
                echo "$item"
            fi
        done)

        if [[ -n $missing_files ]]; then
            while IFS= read -r item; do
                local src_item="$repo_data_path/$item"
                local dest_item="$system_path/$item"
                if [[ -d $src_item ]]; then
                    mkdir -p "$dest_item"
                else
                    mkdir -p "$(dirname "$dest_item")"
                    cp "$src_item" "$dest_item"
                fi
                added=1
            done <<<"$missing_files"
        fi
    fi

    if [[ $added -eq 1 ]]; then
        rx_log "success" "Missing configuration files synced to ${PINK}$(basename "$system_path")${RESET}"
    fi
}

rx_sanitize() {
    local target="$1"

    [[ ! -e $target ]] && return 0

    if [[ -f $target ]]; then
        sed -i "s|/home/[^/]*|/home/$USER|g" "$target" 2>/dev/null
    elif [[ -d $target ]]; then
        rx_log "info" "Updating user paths to ${PINK}$USER${RESET}..."
        find "$target" -type f \( -name "*.json" -o -name "*.conf" -o -name "*.toml" -o -name "*.yaml" \) \
            -exec sed -i "s|/home/[^/]*|/home/$USER|g" {} + 2>/dev/null
    fi
}

rx_restore() {
    local target="$1"
    local backup="${target}.bak"

    if [[ -L $target || -e $target ]]; then
        rx_log "info" "Removing module configuration files from ${PINK}$target${RESET}"
        rm -rf "$target"
    fi

    if [[ -e $backup ]]; then
        mv "$backup" "$target"
        rx_log "success" "Previous configuration restored from backup for ${PINK}$(basename "$target")${RESET}"
    else
        rx_log "warn" "No backup found for ${PINK}$(basename "$target")${RESET}, system path cleaned"
    fi
}
