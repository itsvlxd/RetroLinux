#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

AXCTL_BIN="/usr/local/bin/axctl"

axctl_works() {
    command -v axctl >/dev/null 2>&1 || return 1
    axctl --version >/dev/null 2>&1
}

install_axctl() {
    if axctl_works; then
        rx_log "success" "axctl already available: $(axctl --version 2>/dev/null)"
        return 0
    fi

    if ! command -v go >/dev/null 2>&1; then
        rx_log "error" "Go is required to build axctl (install the 'go' package first)"
        return 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        rx_log "error" "git is required to clone axctl"
        return 1
    fi

    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    rx_log "info" "Cloning axctl from GitHub..."
    if ! git clone --depth 1 https://github.com/Axenide/axctl.git "$tmp/axctl"; then
        rx_log "error" "Failed to clone axctl repository"
        return 1
    fi

    rx_log "info" "Building axctl..."
    if ! (cd "$tmp/axctl" && go build -o axctl .); then
        rx_log "error" "Failed to build axctl"
        return 1
    fi

    rx_log "info" "Installing axctl to $AXCTL_BIN ..."
    if [[ $EUID -eq 0 ]]; then
        install -Dm755 "$tmp/axctl/axctl" "$AXCTL_BIN"
    else
        sudo install -Dm755 "$tmp/axctl/axctl" "$AXCTL_BIN"
    fi

    if "$AXCTL_BIN" --version >/dev/null 2>&1; then
        rx_log "success" "axctl installed and working: $("$AXCTL_BIN" --version 2>/dev/null)"
    else
        rx_log "error" "axctl install verification failed"
        return 1
    fi
}

install_axctl
