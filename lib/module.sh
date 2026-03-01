#!/bin/bash

REPO_DIR="$(dirname "$(readlink -f "$0")")"

source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/pkg.sh"

run_task() {
    local type="$1"
    local module="$2"

    if [[ "$module" == "all" || -z "$module" ]]; then
        for dir in "$REPO_DIR"/modules/*/; do
            [[ -d "$dir" ]] || continue
            local m_name=$(basename "$dir")
            execute_logic "$type" "$m_name"
        done
    else
        execute_logic "$type" "$module"
    fi
}

execute_logic() {
    local type="$1"
    local name="$2"
    local script="$REPO_DIR/modules/$name/${type}.sh"

    if [[ -f "$script" ]]; then
        rx_log "info" "Using custom $type script for $name"

        (cd "$REPO_DIR/modules/$name" && bash "./${type}.sh")
    else
        case "$type" in
        "install") rx_default_install "$name" ;;
        "pull") rx_default_pull "$name" ;;
        "mirror") rx_default_mirror "$name" ;;
        esac
    fi
}

get_target_path() {
    local mod_name="$1"
    local target_file="$REPO_DIR/modules/$mod_name/.target"
    local raw_path

    if [[ -f "$target_file" ]]; then
        raw_path=$(head -n 1 "$target_file" | xargs)
        echo "${raw_path/#\~/$HOME}"
    else
        echo "$HOME/.config/$mod_name"
    fi
}

rx_default_install() {
    local mod_name="$1"
    local mod_path="$REPO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Installing $mod_name"

    [[ -f "$mod_path/pkg.list" ]] && rx_pkg_install "$mod_path/pkg.list"

    if [[ -d "$mod_path/config" ]]; then
        rx_link "$mod_path/config" "$target_path"
    fi
}

rx_default_pull() {
    local mod_name="$1"
    local mod_path="$REPO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Backing up $mod_name"

    if [[ -d "$target_path" ]]; then
        if [[ -L "$target_path" ]]; then
            rx_log "success" "$mod_name is linked, nothing to pull"
        else
            rx_mirror_pull "$target_path" "$mod_path/config"
            rx_log "success" "$mod_name backed up to repository"
        fi
    else
        rx_log "error" "Target path not found: $target_path"
    fi
}

rx_default_mirror() {
    local mod_name="$1"
    local mod_path="$REPO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Mirroring $mod_name to $target_path"

    [[ -f "$mod_path/pkg.list" ]] && rx_pkg_install "$mod_path/pkg.list"

    if [[ -d "$mod_path/config" ]]; then
        rx_mirror_install "$mod_path/config" "$target_path"
    else
        rx_log "error" "No config folder found for $mod_name"
    fi
}
