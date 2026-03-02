#!/bin/bash

REPO_DIR="$(dirname "$(readlink -f "$0")")"

declare -a CMDS_HELP
declare -A CMDS_EXEC

source "$REPO_DIR/lib/fs.sh"
source "$REPO_DIR/lib/git.sh"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/logo.sh"
source "$REPO_DIR/lib/module.sh"
source "$REPO_DIR/lib/manager.sh"

CMD=$1
TARGET=$2

PINK='\033[38;5;201m'
RESET='\033[0m'

if ! command -v retro >/dev/null 2>&1; then
    if [[ "$CMD" != "-s" && "$CMD" != "--setup" ]]; then
        rx_logo
        rx_log "warn" "The 'retro' command is not linked to your system PATH."
        rx_log "info" "Run ${PINK}./retro.sh --setup${RESET} to enable global access."
        echo -e ""
    fi
fi

register_command() {
    local group="$1"
    local aliases="$2"
    local desc="$3"
    local func="$4"

    CMDS_HELP+=("$group|$aliases|$desc")

    IFS='|' read -ra ADDR <<<"$aliases"
    for alias in "${ADDR[@]}"; do
        CMDS_EXEC["$alias"]="$func"
    done
}

if [ -d "$REPO_DIR/cmds" ]; then
    shopt -s globstar
    for f in "$REPO_DIR/cmds"/**/*.sh; do
        [[ -f "$f" ]] || continue
        source "$f"
    done
    shopt -u globstar
fi

if [[ -z "$CMD" || "$CMD" == "-h" || "$CMD" == "--help" ]]; then
    if command -v show_usage >/dev/null; then
        show_usage
    else
        rx_log "error" "help.sh module not loaded from cmds/ folder."
    fi
    exit 0
fi

if [[ -n "${CMDS_EXEC[$CMD]}" ]]; then
    ${CMDS_EXEC[$CMD]} "$TARGET"
else
    rx_log "error" "Unrecognized option: $CMD"
    rx_log "info" "Try 'retro --help' for a list of valid commands."
    exit 1
fi
