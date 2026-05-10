#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

RETRO_REPO_URL="https://github.com/itsvlxd/RetroLinux.git"

rx_post_clone_repo() {
    rx_clear_logo
    rx_step "Deploying RetroLinux Framework..."

    local source_dir="/opt/retrolinux"
    local target_dir="/mnt/opt/retrolinux"

    if [[ -d "$target_dir/.git" ]]; then
        gum style --foreground 2 "RetroLinux repo already present on target"
        return 0
    fi

    mkdir -p "$target_dir"

    local iso_valid=false
    if [[ -d $source_dir ]]; then
        local item_count=$(ls -A "$source_dir" 2>/dev/null | wc -l)

        if [[ $item_count -ge 16 ]] && [[ -d "$source_dir/.git" ]]; then
            iso_valid=true
            gum style --foreground 7 "Found complete repo on ISO ($item_count items). Copying..."

            cp -rf "$source_dir/." "$target_dir/"
            find "$target_dir" -type f -name "*.sh" -exec chmod 755 {} \;

            gum style --foreground 2 "RetroLinux successfully deployed from ISO"
            return 0
        else
            gum style --foreground 3 "ISO repo incomplete."
        fi
    fi

    if [[ $iso_valid == "false" ]]; then
        gum style --foreground 5 "Falling back to GitHub..."

        if ! ping -c 1 1.1.1.1 &>/dev/null; then
            gum style --foreground 1 "ERROR: No internet connection. Cannot clone repository."
            return 1
        fi

        if git clone "$RETRO_REPO_URL" "$target_dir"; then
            find "$target_dir" -type f -name "*.sh" -exec chmod 755 {} \;
            gum style --foreground 2 "Successfully cloned $RETRO_BRANCH from GitHub"
            return 0
        else
            gum style --foreground 1 "ERROR: Failed to clone repository."
            return 1
        fi
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_clone_repo "$@"
fi
