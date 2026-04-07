#!/bin/bash

rx_get_icon() {
    local name="${1,,}"

    local base_dir="${RETRO_DIR:-.}"
    local icon_dir="$base_dir/icons"
    local icon_path=""

    case "$name" in
        *"xbox"*"wireless"*) icon_path="$icon_dir/xbox_wireless_controller.png" ;;
        *"nothing"*"headphone"*) icon_path="$icon_dir/nothing_headphone_1.png" ;;
        *"at"*"over"*"ear"*) icon_path="$icon_dir/at_over_ear.png" ;;
        *) icon_path="bluetooth" ;;
    esac

    if [[ $icon_path == *.png ]] && [[ ! -f $icon_path ]]; then
        echo "bluetooth-active"
    else
        echo "$icon_path"
    fi
}
