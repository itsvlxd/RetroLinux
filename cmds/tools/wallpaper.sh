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
            local theme=$(bash "$var_script" --get "RETRO_THEME")
            [[ -z $theme || $theme == "null" ]] && theme="retro"

            local target_dir="$wall_dir/$theme"
            [[ ! -d $target_dir ]] && target_dir="$wall_dir"

            echo -e "\n ${PINK}󰸉 Your Wallpapers: ${RESET}$target_dir"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            while read -r file; do
                local icon="${PINK}󰋫${RESET}"
                [[ $file =~ \.(mp4|mkv|webm)$ ]] && icon="${PINK}󰎁${RESET}"
                echo -e " $icon $file"
            done < <(ls -1 "$target_dir" 2>/dev/null)
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

        "res")
            local active_mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
            local mon_info=$(hyprctl monitors -j | jq -r --arg m "$active_mon" '.[] | select(.name==$m)')

            local mon_desc=$(echo "$mon_info" | jq -r '.description')
            local current_w=$(echo "$mon_info" | jq -r '.width')
            local current_h=$(echo "$mon_info" | jq -r '.height')

            local res_map=$(bash "$var_script" --get "WALL_RES_MAP")
            local custom_res=""

            if [[ -n $res_map && $res_map != "null" ]]; then
                custom_res=$(echo "$res_map" | tr ',' '\n' | grep -F "$mon_desc|" | cut -d'|' -f2)
            fi

            local active_res="${current_w}x${current_h}"
            local active_tag="${MUTE}(Native)${RESET}"

            if [[ -n $custom_res ]]; then
                active_res="$custom_res"
                active_tag="${PINK}(Optimized)${RESET}"
            fi

            rx_log "info" "Configuring the display this terminal is running on:"
            echo -e " ${PINK}󰍹${RESET} Hardware: $mon_desc"
            echo -e " ${PINK}󰊘${RESET} Native Resolution: ${current_w}x${current_h}"
            echo -e " ${PINK}${RESET} Current Resolution: ${PINK}${active_res}${RESET} ${active_tag}"
            rx_log "info" "Enter your desired render resolution (e.g., ${PINK}1920x1080${RESET}) or type '${PINK}reset${RESET}' to use native scaling ${PINK}[Default: $active_res]${RESET}:"
            read user_res

            if [[ -z $user_res ]]; then
                if [[ -n $res_map && $res_map != "null" ]]; then
                    rx_log "info" "No changes made. Keeping your optimized configuration."
                    return 0
                else
                    rx_log "info" "Already running at native scale. No optimization needed."
                    return 0
                fi
            fi

            local res_map=$(bash "$var_script" --get "WALL_RES_MAP")

            local new_map=""
            if [[ -n $res_map && $res_map != "null" ]]; then
                new_map=$(echo "$res_map" | tr ',' '\n' | grep -vF "$mon_desc|" | paste -sd, -)
            fi

            if [[ $user_res == "reset" ]]; then
                rx_log "success" "monitor reset to native rendering scale."
            else
                if [[ ! $user_res =~ ^[0-9]+x[0-9]+$ ]]; then
                    rx_log "error" "invalid format! you must use wxh (e.g. 1280x720)."
                    return 1
                fi

                local u_w="${user_res%x*}"
                local u_h="${user_res#*x}"

                if ((u_w < 1280 || u_h < 720)); then
                    rx_log "error" "scale too low! minimum supported resolution is 1280x720."
                    return 1
                fi

                local entry="${mon_desc}|${user_res}"
                if [[ -z $new_map ]]; then
                    new_map="$entry"
                else
                    new_map="${new_map},${entry}"
                fi
                rx_log "success" "monitor capped at ${pink}${user_res}${reset}."
            fi

            bash "$var_script" --set "WALL_RES_MAP" "$new_map"

            rx_log "info" "Analyzing repository and generating optimized video feeds..."
            bash "$wall_script" --optimize

            rx_log "info" "Restarting wallpaper engine to apply changes..."
            bash "$wall_script" --restore
            ;;

        "optimize")
            local res_map=$(bash "$var_script" --get "WALL_RES_MAP")

            if [[ -z $res_map || $res_map == "null" ]]; then
                rx_log "error" "No custom monitor resolutions are set. Run '${PINK}retro -wal res${RESET}' first."
                return 1
            fi

            rx_log "info" "Scanning repository for missing optimized video feeds..."
            bash "$wall_script" --optimize
            rx_log "success" "All wallpapers are now optimized for your monitors."
            ;;

        "status")
            local current_wall=$(bash "$var_script" --get "WALL_CURRENT")
            local engine=$(bash "$var_script" --get "CLR_ENGINE")
            local theme=$(bash "$var_script" --get "RETRO_THEME")

            : ${current_wall:="None"}
            : ${engine:="matugen"}
            : ${theme:="retro"}

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
            printf " ${PINK}󰏘${RESET} %-14s %s\n" "Theme Pool:" "${theme^}"
            printf " ${PINK}${type_icon}${RESET} %-14s %s\n" "Style:" "$type"
            printf " ${PINK}󰉖${RESET} %-14s %s\n" "Path:" "${current_wall/$HOME/\~}"
            printf " ${PINK}󰓅${RESET} %-14s %s\n" "Engine:" "${engine^^}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *) rx_log "info" "Usage: retro --wallpaper [set|static|list|picker|cache|restore|res|optimize|status]" ;;
    esac
}

register_command "TOOLS" "-wal|--wallpaper" "Manage your wallpaper and theme" "cmd_wallpaper"
