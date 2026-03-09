#!/bin/bash

cmd_wallpaper() {
    local wall_script="$RETRO_DIR/scripts/wallpaper_core.sh"
    local var_script="$RETRO_DIR/scripts/variable_core.sh"
    local wall_dir="$HOME/.cache/retro/wallpapers"
    local action="$1"
    local value="$2"
    local options="$3"

    case "$action" in
        "set")
            [[ -z $value ]] && rx_log "error" "I need a wallpaper name or a path to set it." && return 1

            if bash "$wall_script" --set "$value"; then
                rx_log "success" "Wallpaper's all set to: ${PINK}${value}${RESET}"
            else
                rx_log "error" "I couldn't set that wallpaper: $value"
            fi
            ;;
        "static")
            local current_state=$(bash "$var_script" --get "WALL_STATIC_FORCED")
            local new_state=""

            case "$value" in
                "on" | "true") new_state="true" ;;
                "off" | "false") new_state="false" ;;
                "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
            esac

            bash "$var_script" --set "WALL_STATIC_FORCED" "$new_state"

            local status_text="${PINK}ENABLED${RESET}"
            [[ $new_state == "false" ]] && status_text="${MUTE}DISABLED${RESET}"

            rx_log "success" "Static mode is now $status_text"
            rx_log "info" "Updating the wallpaper..."
            bash "$wall_script" --restore
            ;;

        "list")
            echo -e "\n ${PINK}󰸉 Your Wallpapers: ${RESET}$wall_dir"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            while read -r file; do
                local icon="${PINK}󰋫${RESET}"
                [[ $file =~ \.(mp4|mkv|webm)$ ]] && icon="${PINK}󰎁${RESET}"
                echo -e " $icon $file"
            done < <(bash "$wall_script" --list)
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "picker")
            bash "$wall_script" --picker
            ;;

        "cache")
            rx_log "info" "Building the frame cache... this might take a second."
            bash "$wall_script" --cache "$value" && rx_log "success" "Cache is ready." || rx_log "error" "I couldn't build the cache."
            ;;

        "restore")
            rx_log "info" "Putting the wallpaper back how it was..."
            bash "$wall_script" --restore && rx_log "success" "Wallpaper restored." || rx_log "error" "Nothing to restore."
            ;;

        "status")
            local current_wall=$(bash "$RETRO_DIR/scripts/variable_core.sh" get "WALL_CURRENT")
            local engine=$(bash "$RETRO_DIR/scripts/variable_core.sh" get "CLR_ENGINE")

            : ${current_wall:="None"}
            : ${engine:="matugen"}

            local wall_name=$(basename "$current_wall")
            local type="Static"
            local type_icon="󰈟"
            if [[ $wall_name =~ \.(mp4|mkv|webm)$ ]]; then
                type="Live"
                type_icon="󰈫"
            fi

            echo -e "\n ${PINK}󰸉 Wallpaper Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}󰀻${RESET} %-14s %s\n" "Active:" "$wall_name"
            printf " ${PINK}${type_icon}${RESET} %-14s %s\n" "Style:" "$type"
            printf " ${PINK}󰉖${RESET} %-14s %s\n" "Path:" "${current_wall/$HOME/\~}"
            printf " ${PINK}󰓅${RESET} %-14s %s\n" "Engine:" "${engine^^}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *) rx_log "info" "Usage: retro --wallpaper [set|static|list|picker|cache|restore|status]" ;;
    esac
}

register_command "TOOLS" "-wal|--wallpaper" "Manage your wallpaper and theme" "cmd_wallpaper"
