#!/bin/bash

rx_git_run() {
    git -C "$RETRO_DIR" "$@" 2>/dev/null | xargs
}

rx_git_branch() {
    local branch=$(rx_git_run rev-parse --abbrev-ref HEAD)
    echo "${branch:-N/A}"
}

rx_git_commit() {
    local commit=$(rx_git_run rev-parse --short HEAD)
    echo "${commit:-N/A}"
}

rx_git_version() {
    local version=$(rx_git_run describe --tags --abbrev=0)
    [[ -z $version ]] && version=$(rx_git_commit)
    [[ $version == "N/A" ]] && version="Latest"

    echo "$version"
}

rx_git_latest_tag() {
    local tag
    tag=$(git -C "$RETRO_DIR" describe --tags --abbrev=0 2>/dev/null)
    echo "${tag:-}"
}

rx_git_reset_hard() {
    rx_log "info" "Syncing with remote and performing hard reset..."

    git -C "$RETRO_DIR" fetch origin $(rx_git_branch)

    git -C "$RETRO_DIR" reset --hard "origin/$(rx_git_branch)"

    rx_log "success" "Git sync and hard reset completed"
}

rx_git_fix_owner() {
    local current_owner
    current_owner=$(stat -c '%U:%G' "$RETRO_DIR/.git" 2>/dev/null)
    local current_user_group="$(whoami):$(id -gn)"

    [[ $current_owner == "$current_user_group" ]] && return 0

    rx_log "info" "Fixing ownership from $current_owner to $current_user_group..."
    sudo chown -R "$(whoami):$(id -gn)" "$RETRO_DIR"
    rx_log "success" "Fixed ownership: $RETRO_DIR"
}
