#!/bin/bash

: "${RETRO_CONFIG:=$HOME/.config/retro}"

_VARS_FILE="$RETRO_CONFIG/variables.sh"

declare -A _RETRO_VARS_CACHE
_VARS_FILE_MTIME=0

_rx_get_file_mtime() {
    stat -c %Y "$_VARS_FILE" 2>/dev/null || echo 0
}

_rx_parse_vars_file() {
    local current_mtime
    current_mtime=$(_rx_get_file_mtime)
    [[ $current_mtime == "$_VARS_FILE_MTIME" ]] && return
    _VARS_FILE_MTIME=$current_mtime
    _RETRO_VARS_CACHE=()
    if [[ -f $_VARS_FILE ]]; then
        while IFS= read -r line; do
            if [[ $line =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                val="${val#\"}"
                val="${val%\"}"
                val="${val#\'}"
                val="${val%\'}"
                _RETRO_VARS_CACHE["$key"]="$val"
            fi
        done <"$_VARS_FILE"
    fi
}

get_var() {
    local key="$1"
    local default="${2:-}"
    _rx_parse_vars_file
    if [[ -n ${_RETRO_VARS_CACHE[$key]+isset} ]]; then
        echo "${_RETRO_VARS_CACHE[$key]}"
    else
        echo "$default"
    fi
}

set_var() {
    local key="$1"
    local value="$2"
    [[ -z $key ]] && return 1
    _RETRO_VARS_CACHE["$key"]="$value"
    [[ ! -d $RETRO_CONFIG ]] && mkdir -p "$RETRO_CONFIG"
    [[ ! -f $_VARS_FILE ]] && touch "$_VARS_FILE"
    if grep -q "^export $key=" "$_VARS_FILE" 2>/dev/null; then
        sed -i "s@^export $key=.*@export $key=\"$value\"@" "$_VARS_FILE"
    else
        echo "export $key=\"$value\"" >>"$_VARS_FILE"
    fi
}

reload_vars() {
    _VARS_FILE_MTIME=0
    _rx_parse_vars_file
}
