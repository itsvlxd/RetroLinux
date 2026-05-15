#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "variable"

VARS_DIR="$RETRO_CONFIG"
VARS_FILE="$VARS_DIR/variables.sh"

[[ ! -d $VARS_DIR ]] && mkdir -p "$VARS_DIR"
[[ ! -f $VARS_FILE ]] && touch "$VARS_FILE"

get_var() {
    local key="$1"

    (
        source "$VARS_FILE" &>/dev/null
        if [[ -v $key ]]; then
            echo "${!key}"
            exit 0
        else
            exit 1
        fi
    )
}

set_var() {
    local key=$1
    local value=$2
    [[ -z $key ]] && return 1

    if grep -q "^export $key=" "$VARS_FILE"; then
        sed -i "s@^export $key=.*@export $key=\"$value\"@" "$VARS_FILE"
    else
        echo "export $key=\"$value\"" >>"$VARS_FILE"
    fi
}

del_var() {
    local key=$1
    [[ -z $key ]] && return 1

    local regex_key="${key//\*/.*}"

    if [[ $key == *"*"* ]]; then
        if ! grep -q "^export $regex_key=" "$VARS_FILE"; then
            return 0
        fi
    else
        if ! grep -q "^export ${key}=" "$VARS_FILE"; then
            return 1
        fi
    fi

    sed -i "/^export $regex_key=/d" "$VARS_FILE"
}

case $1 in
    "--get")
        get_var "$2"
        ;;

    "--set")
        set_var "$2" "$3"
        ;;
    "--del")
        del_var "$2"
        ;;
    "--toggle")
        current_val=$(get_var "$2")
        [[ $current_val == "true" ]] && set_var "$2" "false" || set_var "$2" "true"
        get_var "$2"
        ;;
    "--list")
        cat "$VARS_FILE" | sed 's/export //g'
        ;;
esac
