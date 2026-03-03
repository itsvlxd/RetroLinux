#!/bin/bash

VARS_DIR="$RETRO_CACHE"
VARS_FILE="$VARS_DIR/variables.sh"

[[ ! -d "$VARS_DIR" ]] && mkdir -p "$VARS_DIR"
[[ ! -f "$VARS_FILE" ]] && touch "$VARS_FILE"

get_var() {
    local key=$1
    (source "$VARS_FILE" &>/dev/null && echo "${!key}")
}

set_var() {
    local key=$1
    local value=$2
    [[ -z "$key" ]] && return 1

    if grep -q "^export $key=" "$VARS_FILE"; then
        sed -i "s|^export $key=.*|export $key=\"$value\"|" "$VARS_FILE"
    else
        echo "export $key=\"$value\"" >>"$VARS_FILE"
    fi
}

del_var() {
    local key=$1

    [[ -z "$key" ]] && return 1

    sed -i "/^export $key=/d" "$VARS_FILE"
}

case $1 in
"get")
    get_var "$2"
    ;;

"set")
    set_var "$2" "$3"
    ;;
"del")
    del_var "$2"
    ;;
"toggle")
    current_val=$(get_var "$2")
    [[ "$current_val" == "true" ]] && set_var "$2" "false" || set_var "$2" "true"
    get_var "$2"
    ;;
"list")
    cat "$VARS_FILE" | sed 's/export //g'
    ;;
esac
