#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/wallpaper.sh"

cmd_wallpaper() {
    local wall_script="$RETRO_DIR/scripts/wallpaper_core.sh"
    local wall_dir="$RETRO_CONFIG/wallpapers"
    local action="${1,,}"
    shift
    local value="$*"

    case "$action" in
        "set")
            [[ -z $value ]] && rx_log "error" "Provide a wallpaper name or path." && return 1

            local resolved=""
            resolved=$(bash "$wall_script" --resolve-name "$value" 2>/dev/null)

            if [[ -n $resolved ]]; then
                value="$resolved"
            fi

            if bash "$wall_script" --set "$value"; then
                local display="${value##*/}"
                display="${display%.*}"
                display=$(rx_format_string "$display")
                rx_log "success" "Wallpaper set to: ${PINK}${display}${RESET}"
            else
                rx_log "error" "Wallpaper not found: ${PINK}${value}${RESET}"
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
            local mode=$(echo "$value" | awk '{print $1}')
            local interval=$(echo "$value" | awk '{print $2}')
            local current_state=$(get_var "WALL_SLIDESHOW_ACTIVE")
            local new_state="true"

            case "$mode" in
                "on" | "true") new_state="true" ;;
                "off" | "false") new_state="false" ;;
                "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
            esac

            set_var "WALL_SLIDESHOW_ACTIVE" "$new_state"

            if [[ -n $interval ]]; then
                set_var "WALL_SLIDESHOW_INTERVAL" "$interval"
                rx_log "info" "Slideshow interval set to: $interval"
            fi

            local status_text="${PINK}ENABLED${RESET}"
            [[ $new_state == "false" ]] && status_text="${MUTE}DISABLED${RESET}"
            rx_log "success" "Slideshow mode is now $status_text"
            ;;

        "static")
            local mode=$(echo "$value" | awk '{print $1}')
            local current_state=$(get_var "WALL_STATIC_FORCED")
            local new_state=""

            case "$mode" in
                "on" | "true") new_state="true" ;;
                "off" | "false") new_state="false" ;;
                "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
            esac

            set_var "WALL_STATIC_FORCED" "$new_state"

            if [[ $new_state == "true" ]]; then
                rx_wallpaper_pause
                rx_log "success" "Static mode ${PINK}ENABLED${RESET}"
            else
                rx_wallpaper_resume
                rx_log "success" "Static mode ${GRAY}DISABLED${RESET}"
            fi
            ;;

        "list")
            local theme=$(get_var "RETRO_THEME")
            [[ -z $theme || $theme == "null" ]] && theme="retro"

            local target_dir="$wall_dir/$theme"
            [[ ! -d $target_dir ]] && target_dir="$wall_dir"

            declare -a names
            declare -a resolutions
            declare -a icons
            local max_len=0

            while IFS='|' read -r file res; do
                [[ -z $file ]] && continue
                local icon="󰋫"
                [[ $file =~ \.(mp4|mkv|webm)$ ]] && icon="󰎁"
                local display_name="${file%.*}"
                display_name=$(rx_format_string "$display_name")

                local name_len=${#display_name}
                (( name_len > max_len )) && max_len=$name_len

                names+=("$display_name")
                resolutions+=("$res")
                icons+=("$icon")
            done < <(bash "$wall_script" --list-with-res 2>/dev/null)

            local col_width=$(( max_len + 2 ))

            rx_table_header "󰸉" "Your Wallpapers: $target_dir"
            for i in "${!names[@]}"; do
                printf " ${PINK}${icons[$i]}${RESET} ${RESET}%-${col_width}s${GRAY}%s${RESET}\n" "${names[$i]}" "${resolutions[$i]}"
            done
            rx_table_separator
            rx_table_spacer
            ;;

        "sync")
            rx_log "info" "Syncing wallpapers from repository..."
            local sync_result=$(bash "$wall_script" --sync)
            if echo "$sync_result" | grep -q "result=error"; then
                rx_log "error" "Sync failed."
                return 1
            fi
            local count=$(echo "$sync_result" | grep -oP 'synced=\K[0-9]+')
            local skipped=$(echo "$sync_result" | grep -oP 'skipped=\K[0-9]+')
            rx_log "success" "Sync complete: ${PINK}${count}${RESET} new, ${GRAY}${skipped}${RESET} already present."
            rx_log "info" "Optimizing wallpapers for your monitors..."
            bash "$wall_script" --optimize
            rx_log "success" "All wallpapers are now optimized."
            ;;

        "picker")
            bash "$wall_script" --picker
            ;;

        "cache")
            local cache_target=$(echo "$value" | awk '{print $1}')
            rx_log "info" "Building the frame cache... this might take a second."
            bash "$wall_script" --cache "$cache_target" && rx_log "success" "Cache is ready." || rx_log "error" "I couldn't build the cache."
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
            rx_log "info" "Scanning repository for missing optimized video feeds..."
            bash "$wall_script" --optimize
            rx_log "success" "All wallpapers are now optimized for your monitors."
            ;;

        "status")
            local current_wall=$(get_var "WALL_CURRENT")
            local engine=$(get_var "CLR_ENGINE")
            local theme=$(get_var "RETRO_THEME")
            local static_forced=$(get_var "WALL_STATIC_FORCED")
            local static_on_bat=$(get_var "WALL_STATIC_ON_BAT")
            local static_on_saver=$(get_var "WALL_STATIC_ON_SAVER")
            local static_on_fullscreen=$(get_var "WALL_STATIC_ON_FULLSCREEN")
            local pause_procs=$(get_var "WALL_PAUSE_PROCS")
            local saver_active=$(get_var "BAT_SAVER_ACTIVE")
            local wall_paused=$(get_var "WALL_PAUSED")
            local slideshow_active=$(get_var "WALL_SLIDESHOW_ACTIVE")

            : ${current_wall:="None"}
            : ${engine:="matugen"}
            : ${theme:="retro"}
            : ${static_forced:="false"}
            : ${static_on_bat:="false"}
            : ${static_on_saver:="true"}
            : ${static_on_fullscreen:="true"}
            : ${pause_procs:=""}
            : ${saver_active:="false"}
            : ${wall_paused:="false"}
            : ${slideshow_active:="false"}

            local wall_name="${current_wall%.*}"
            wall_name=$(basename "$wall_name")
            wall_name=$(echo "$wall_name" | sed 's/[-_]/ /g; s/\b\(.\)/\u\1/g')
            local type="Live"
            local type_icon="󰈫"
            local saver_static=false
            [[ $saver_active == "true" && $static_on_saver == "true" ]] && saver_static=true
            if [[ ! $current_wall =~ \.(mp4|mkv|webm)$ ]] || [[ $static_forced == "true" ]] || [[ $saver_static == "true" ]] || [[ $wall_paused == "true" ]]; then
                type="Static"
                type_icon="󰈟"
            fi

            local static_status="Off"
            local static_color="$MUTE"
            if [[ $static_forced == "true" ]]; then
                static_status="Forced"
                static_color="$PINK"
            elif [[ $saver_static == "true" ]]; then
                static_status="Battery Saver"
                static_color="$WARN"
            elif [[ $static_on_bat == "true" ]]; then
                static_status="On Battery"
                static_color="$WARN"
            fi

            local paused_status="No"
            local paused_color="$MUTE"
            if [[ $wall_paused == "true" ]]; then
                paused_status="Yes"
                paused_color="$WARN"
            fi

            local slide_status="Off"
            local slide_color="$MUTE"
            if [[ $slideshow_active == "true" ]]; then
                slide_status="On"
                slide_color="$PINK"
            fi

            rx_table_header "󰸉" "Wallpaper Status"
            rx_table_row "󰀻" "Name:" "$wall_name" "$PINK" "14"
            rx_table_row "󰏘" "Theme Pool:" "${theme^}" "$PINK" "14"
            rx_table_row "$type_icon" "Style:" "$type" "$PINK" "14"
            rx_table_row "󰓅" "Engine:" "${engine^^}" "$PINK" "14"
            rx_table_row "󰏤" "Paused:" "$paused_status" "$paused_color" "14"
            rx_table_row "󰏦" "Slideshow:" "$slide_status" "$slide_color" "14"
            if [[ -n $pause_procs && $pause_procs != "null" ]]; then
                rx_table_row "󰓅" "Pause Procs:" "$pause_procs" "$WARN" "14"
            fi
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
            rx_help_cmd "list" "List all wallpapers with resolution info"
            rx_help_cmd "sync" "Sync wallpapers from repository and optimize"
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
