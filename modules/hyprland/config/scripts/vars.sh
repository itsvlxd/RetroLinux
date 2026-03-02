#!/bin/bash

VARS_FILE="$HOME/.cache/retro_global_vars.sh"

if [ ! -f "$VARS_FILE" ]; then
    touch "$VARS_FILE"
fi

set_var() {
    local key=$1
    local value=$2

    if grep -q "^export $key=" "$VARS_FILE"; then
        sed -i "s|^export $key=.*|export $key=\"$value\"|" "$VARS_FILE"
    else
        echo "export $key=\"$value\"" >>"$VARS_FILE"
    fi
}

get_var() {
    local key=$1
    (source "$VARS_FILE" && echo "${!key}")
}

case $1 in
"toggle")
    current_val=$(get_var "$2")
    if [[ "$current_val" == "true" ]]; then
        set_var "$2" "false"
    else
        set_var "$2" "true"
    fi
    ;;
"set")
    set_var "$2" "$3"
    ;;
"get")
    get_var "$2"
    ;;
*)
    echo "Usage: vars.sh [set|get] [KEY] [VALUE]"
    exit 1
    ;;
esac
