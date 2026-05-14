#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_wallpaper() {
    local wall_script="$RETRO_DIR/scripts/wallpaper_core.sh"
    local wall_dir="$RETRO_CONFIG/wallpapers"
    local action="${1,,}"
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

        "add")
            [[ -z $value ]] && rx_log "error" "Please provide the path to the image/video." && return 1

            rx_log "info" "Importing wallpaper into the current theme cache..."
            local add_result=$(bash "$wall_script" --add "$value")

            if echo "$add_result" | grep -q "result=error"; then
                local reason=$(echo "$add_result" | grep -oP "reason=\K[^|]+")
                case "$reason" in
                    "file_not_found") rx_log "error" "File not found: $value" ;;
                    "unsupported_format") rx_log "error" "Unsupported file format! Please use a standard image or video." ;;
                    *) rx_log "error" "Failed to add wallpaper." ;;
                esac
                return 1
            fi

            rx_log "success" "Wallpaper added and applied!"
            ;;

        "slideshow")
            local current_state=$(get_var "WALL_SLIDESHOW_ACTIVE")
            local new_state="true"

            case "$value" in
                "on" | "true") new_state="true" ;;
                "off" | "false") new_state="false" ;;
                "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
            esac

            set_var "WALL_SLIDESHOW_ACTIVE" "$new_state"

            if [[ -n $options ]]; then
                set_var "WALL_SLIDESHOW_INTERVAL" "$options"
                rx_log "info" "Slideshow interval set to: $options"
            fi

            local status_text="${PINK}ENABLED${RESET}"
            [[ $new_state == "false" ]] && status_text="${MUTE}DISABLED${RESET}"
            rx_log "success" "Slideshow mode is now $status_text"
            ;;

        "static")
            local current_state=$(get_var "WALL_STATIC_FORCED")
            local new_state=""

            case "$value" in
                "on" | "true") new_state="true" ;;
                "off" | "false") new_state="false" ;;
                "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
            esac

            set_var "WALL_STATIC_FORCED" "$new_state"

            local status_text="${PINK}ENABLED${RESET}"
            [[ $new_state == "false" ]] && status_text="${MUTE}DISABLED${RESET}"

            rx_log "success" "Static mode is now $status_text"
            rx_log "info" "Updating the wallpaper..."
            bash "$wall_script" --restore
            ;;

        "list")
            local theme=$(get_var "RETRO_THEME")
            [[ -z $theme || $theme == "null" ]] && theme="retro"

            local target_dir="$wall_dir/$theme"
            [[ ! -d $target_dir ]] && target_dir="$wall_dir"

            rx_table_header "󰸉" "Your Wallpapers: $target_dir"
            while read -r file; do
                local icon="󰋫"
                [[ $file =~ \.(mp4|mkv|webm)$ ]] && icon="󰎁"
                rx_table_simple "$icon" "$file" "$GRAY"
            done < <(ls -1 "$target_dir" 2>/dev/null)
            rx_table_separator
            rx_table_spacer
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

            local res_map=$(get_var "WALL_RES_MAP")
            local custom_res=""

            if [[ -n $res_map && $res_map != "null" ]]; then
                custom_res=$(echo "$res_map" | tr ',' '\n' | grep -F "$mon_desc|" | cut -d'|' -f2)
            fi

            local active_res="${current_w}x${current_h}"

            if [[ -n $custom_res ]]; then
                active_res="$custom_res"
            fi

            rx_log "info" "Configuring the display this terminal is running on:"
            rx_table_header "󰍹" "Monitor: $mon_desc"
            rx_table_row "󰊘" "Native Resolution:" "${current_w}x${current_h}" "$PINK" "20"
            rx_table_row "󰈐" "Current Resolution:" "${active_res}" "$PINK" "20"
            rx_table_separator
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

            local res_map=$(get_var "WALL_RES_MAP")

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
                rx_log "success" "Wallpapers resolution have been capped at ${PINK}${user_res}${RESET}."
            fi

            set_var "WALL_RES_MAP" "$new_map"

            rx_log "info" "Analyzing repository and generating optimized video feeds..."
            bash "$wall_script" --optimize

            rx_log "info" "Restarting wallpaper engine to apply changes..."
            bash "$wall_script" --restore
            ;;

        "optimize")
            #local res_map=$(get_var "WALL_RES_MAP")

            #if [[ -z $res_map || $res_map == "null" ]]; then
            #    rx_log "error" "No custom monitor resolutions are set. Run '${PINK}retro wallpaper res${RESET}' first."
            #    return 1
            #fi

            rx_log "info" "Scanning repository for missing optimized video feeds..."
            bash "$wall_script" --optimize
            rx_log "success" "All wallpapers are now optimized for your monitors."
            ;;

        "status")
            local current_wall=$(get_var "WALL_CURRENT")
            local engine=$(get_var "CLR_ENGINE")
            local theme=$(get_var "RETRO_THEME")

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

            rx_table_header "󰸉" "Wallpaper Status"
            rx_table_row "󰀻" "Active:" "$wall_name" "$PINK" "14"
            rx_table_row "󰏘" "Theme Pool:" "${theme^}" "$PINK" "14"
            rx_table_row "$type_icon" "Style:" "$type" "$PINK" "14"
            rx_table_row "󰉖" "Path:" "${current_wall/$HOME/\~}" "$PINK" "14"
            rx_table_row "󰓅" "Engine:" "${engine^^}" "$PINK" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        *)
            rx_help_usage "retro wallpaper <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "set <name|path>" "Set the wallpaper"
            rx_help_cmd "add <path>" "Import image to wallpaper cache"
            rx_help_cmd "slideshow [mode]" "Toggle slideshow mode"
            rx_help_cmd "static [mode]" "Toggle static wallpaper mode"
            rx_help_cmd "list" "List all wallpapers in theme"
            rx_help_cmd "picker" "Launch interactive wallpaper picker"
            rx_help_cmd "cache [value]" "Build animated wallpaper cache"
            rx_help_cmd "restore" "Restore previous wallpaper"
            rx_help_cmd "res" "Set wallpaper render resolution"
            rx_help_cmd "optimize" "Optimize video feeds for resolution"
            rx_help_cmd "status" "Show active wallpaper info"
            rx_help_examples
            rx_help_example "retro wallpaper set bmw-m760" "Set wallpaper by name"
            rx_help_example "retro wallpaper slideshow on 300" "Enable slideshow 5min"
            rx_help_example "retro wallpaper res" "Set render resolution"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "wallpaper" "Manage your wallpaper and theme" "cmd_wallpaper"
