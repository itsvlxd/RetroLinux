#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

if [[ -z $RETRO_CACHE ]]; then
    export RETRO_CACHE="$HOME/.cache/retro"
else
    export RETRO_CACHE="$RETRO_CACHE"
fi

mkdir -p $RETRO_CACHE

declare -a CMDS_HELP
declare -A CMDS_EXEC

source "$RETRO_DIR/lib/fs.sh"
source "$RETRO_DIR/lib/git.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/pkg.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/module.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/pkg_manager.sh"

export SKIP_PROMPT=false
SETUP_MODE=false
CLEAN_ARGS=()

for arg in "$@"; do
    case "$arg" in
        -y | --yes) SKIP_PROMPT=true ;;
        --setup) SETUP_MODE=true ;;
        *) CLEAN_ARGS+=("$arg") ;;
    esac
done

CMD="${CLEAN_ARGS[0]}"
TARGET="${CLEAN_ARGS[1]}"

register_command() {
    local group="$1"
    local aliases="$2"
    local desc="$3"
    local func="$4"

    local primary_alias="${aliases%%|*}"

    [[ -n ${CMDS_EXEC[$primary_alias]} ]] && return 0

    CMDS_HELP+=("$group|$aliases|$desc")

    IFS='|' read -ra ADDR <<<"$aliases"
    for alias in "${ADDR[@]}"; do
        CMDS_EXEC["$alias"]="$func"
    done
}

if [ -d "$RETRO_DIR/cmds" ]; then
    shopt -s globstar
    for f in "$RETRO_DIR/cmds"/**/*.sh; do
        [[ -f $f ]] || continue
        source "$f"
    done
    shopt -u globstar
fi

if [[ $SETUP_MODE == true ]]; then
    if [[ -n ${CMDS_EXEC[setup]} ]]; then
        ${CMDS_EXEC[setup]}
    elif [[ -n ${CMDS_EXEC[--setup]} ]]; then
        ${CMDS_EXEC[--setup]}
    elif [[ -n ${CMDS_EXEC[-s]} ]]; then
        ${CMDS_EXEC[-s]}
    else
        rx_log "error" "Setup command not found"
        rx_log "info" "Available: ${!CMDS_EXEC[@]}"
        exit 1
    fi
fi

if [[ -z $CMD || $CMD == "-h" || $CMD == "--help" ]]; then
    if command -v show_usage >/dev/null; then
        show_usage
    else
        rx_log "error" "help.sh module not loaded from cmds/ folder."
    fi
    exit 0
fi

if [[ -n ${CMDS_EXEC[$CMD]} ]]; then
    ${CMDS_EXEC[$CMD]} "${CLEAN_ARGS[@]:1}"
else
    rx_log "error" "Unrecognized option: $CMD"
    rx_log "info" "Try 'retro --help' for a list of valid commands."
    exit 1
fi
