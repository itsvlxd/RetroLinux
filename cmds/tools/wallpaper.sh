#!/bin/bash

cmd_wallpaper() {
    local wall_script="$RETRO_DIR/scripts/wallpaper_core.sh"
    local wall_dir="$HOME/.cache/retro/wallpapers"
    local action="$1"
    local value="$2"
    local options="$3"

    case "$action" in
        "set")
            [[ -z $value ]] && rx_log "error" "Provide a wallpaper name or path." && return 1

            if bash "$wall_script" --set "$value"; then
                rx_log "success" "Wallpaper set: ${PINK}${value}${RESET}"
            else
                rx_log "error" "Failed to set wallpaper: $value"
            fi
            ;;

        "list")
            echo -e "\n ${PINK}󰸉 Available Wallpapers: ${RESET}$wall_dir"
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
            rx_log "info" "Generating wallpaper frame cache..."
            bash "$wall_script" --cache "$value" && rx_log "success" "Cache ready." || rx_log "error" "Cache failed."
            ;;

        "restore")
            rx_log "info" "Restoring wallpaper state..."
            bash "$wall_script" --restore && rx_log "success" "Restored." || rx_log "error" "Nothing to restore."
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

            echo -e "\n ${PINK}󰸉 Wallpaper Engine${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}󰀻${RESET} %-14s %s\n" "Name:" "$wall_name"
            printf " ${PINK}${type_icon}${RESET} %-14s %s\n" "Type:" "$type"
            printf " ${PINK}󰉖${RESET} %-14s %s\n" "Location:" "${current_wall/$HOME/\~}"
            printf " ${PINK}󰓅${RESET} %-14s %s\n" "Engine:" "${engine^^}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *) rx_log "info" "Usage: retro --wallpaper [set|list|picker|cache|restore|status]" ;;
    esac
}

register_command "TOOLS" "-wall|--wallpaper" "Dynamic wallpaper and theme utility" "cmd_wallpaper"
