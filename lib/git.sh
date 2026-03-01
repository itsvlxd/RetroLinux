#!/bin/bash

REPO_DIR="$(dirname "$(readlink -f "$0")")"

rx_git_run() {
    git -C "$REPO_DIR" "$@" 2>/dev/null | xargs
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
    [[ -z "$version" ]] && version=$(rx_git_commit)
    [[ "$version" == "N/A" ]] && version="Latest"

    echo "$version"
}
