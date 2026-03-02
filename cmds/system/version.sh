#!/bin/bash

cmd_version() {
    local version=$(rx_git_run describe --tags --abbrev=0 2>/dev/null)

    if [[ -z "$version" ]]; then
        version=$(rx_git_run rev-parse --short HEAD 2>/dev/null)
    fi

    if [[ -z "$version" ]]; then
        version="rolling-release"
    fi

    echo "$version"
}

register_command "SYSTEM" "-v|--version" "Display current version and system info" "cmd_version"
