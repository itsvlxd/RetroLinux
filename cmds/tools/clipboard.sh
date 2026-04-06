#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

cmd_clipboard() {
    local action="$1"
    local selection="$2"
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    if [[ $action == "history" ]]; then
        if [[ -z $selection ]]; then
            cliphist list | grep -vE "\[\[.*binary.*data" | head -n 150 || echo "Clipboard history is empty..."
            exit 0
        else
            if echo "$selection" | cliphist decode | wl-copy 2>/dev/null; then
                rx_log "success" "Item copied to clipboard." >&2
            else
                echo -n "$selection" | wl-copy
                rx_log "success" "Text copied." >&2
            fi
            exit 0
        fi
    elif [[ $action == "emoji" ]]; then
        local emoji_dir="$RETRO_DIR/cmds/tools/clipboard"

        if [[ -z $selection ]]; then
            if [[ -d $emoji_dir ]]; then
                cat "$emoji_dir/emojis_smileys_emotion.csv" \
                    "$emoji_dir/emojis_people_body.csv" \
                    "$emoji_dir/emojis_animals_nature.csv" \
                    "$emoji_dir/emojis_food_drink.csv" \
                    "$emoji_dir/emojis_travel_places.csv" \
                    "$emoji_dir/emojis_activities.csv" \
                    "$emoji_dir/emojis_objects.csv" \
                    "$emoji_dir/emojis_symbols.csv" \
                    "$emoji_dir/emojis_flags.csv" \
                    2>/dev/null | sed 's/,/  /'
            else
                echo -e "😀 Grinning Face\n(Error: Emoji directory not found in $emoji_dir)"
            fi
            exit 0
        else
            echo -n "$selection" | awk '{print $1}' | wl-copy
            rx_log "success" "Copied to clipboard!" >&2
            exit 0
        fi
    fi

    local theme_file="$HOME/.config/rofi/themes/clipboard.rasi"
    local gallery_theme="$HOME/.config/rofi/themes/gallery.rasi"

    local CLIP_BITWARDEN=$(bash "$var_script" --get "CLIP_BITWARDEN" 2>/dev/null || echo "false")
    local CLIP_WARDEN_DESTRUCT=$(bash "$var_script" --get "CLIP_WARDEN_DESTRUCT" 2>/dev/null || echo "15")

    local alpha=$(get_opacity_hex "0.9")
    local alpha_alt=$(get_opacity_hex "0.6")

    local color_file="$HOME/.cache/retro/themes/rofi-colors.rasi"
    local base_bg=$(grep "background:" "$color_file" 2>/dev/null | awk '{print $2}' | sed 's/[#;FF]//g')
    local base_bg_alt=$(grep "background-alt:" "$color_file" 2>/dev/null | awk '{print $2}' | sed 's/[#;FF]//g')
    local highlight_color=$(grep "highlight:" "$color_file" 2>/dev/null | awk '{print $2}' | sed 's/[;]//g')

    : ${base_bg:="1A1B26"}
    : ${base_bg_alt:="24283B"}
    : ${highlight_color:="7aa2f7"}

    launch_gallery() {
        rofi -dmenu -i -p "󰄄 " -theme "$gallery_theme" -show-icons \
            -theme-str "
                window { background-color: #${base_bg}; } 
                inputbar { background-color: #${base_bg}${alpha}; }  
                element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
            "
    }

    launch_rofi() {
        local mode="${1:-Clipboard}"

        # Pure Native Modes!
        local modes="Clipboard:retro clipboard history,Emoji:retro clipboard emoji"
        [[ $CLIP_BITWARDEN == "true" ]] && modes+=",Bitwarden:retro clipboard bitwarden"

        rofi -modi "$modes" \
            -show "$mode" \
            -theme "$theme_file" \
            -theme-str "
                window { background-color: #${base_bg}${alpha}; } 
                inputbar { background-color: #${base_bg}${alpha}; }  
                element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
            "
    }

    safe_copy() {
        local text="$1"
        local msg="$2"
        echo -n "$text" | wl-copy
        (sleep 0.1 && cliphist list | head -n 1 | cliphist delete) &
        (sleep "$CLIP_WARDEN_DESTRUCT" && [[ "$(wl-paste)" == "$text" ]] && wl-copy --clear) &
        notify-send "Retro Vault" "$msg\nThe copy will destruct in ${CLIP_WARDEN_DESTRUCT}s" -i "security-high"
        pkill -f rofi
    }

    case "$action" in
        "wipe" | "clear")
            rx_log "info" "Clear all clipboard history (including images)? ${PINK}[y/N]${RESET}: "
            read -r confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                cliphist wipe && rx_log "success" "Clipboard database wiped clean."
            else
                rx_log "info" "Wipe cancelled."
            fi
            ;;

        "bitwarden")
            if [[ -z $selection ]]; then
                if rbw unlocked 2>/dev/null; then
                    [[ $highlight_color != \#* ]] && highlight_color="#$highlight_color"
                    [[ $base_bg_alt != \#* ]] && base_bg_alt="#$base_bg_alt"

                    rbw list --fields type,name,user | sort -k2,2 | awk -F'\t' -v hl="$highlight_color" -v alt="$base_bg_alt" '
                        BEGIN { q = "\x27" } 
                        {
                            type = $1; name = $2; user = $3;
                            match_name = tolower(name);
                            icon = " "; 

                            if (type == "Card") icon = " ";
                            else if (type == "Note") icon = " ";
                            else if (type == "Identity") icon = "󰇮 ";
                            else {
                                if (match_name ~ /google|workspace/) icon = " ";
                                else if (match_name ~ /discord/) icon = " ";
                                else if (match_name ~ /github|gh/) icon = " ";
                                else if (match_name ~ /proton/) icon = "󰆦 ";
                                else if (match_name ~ /binance/) icon = " ";
                                else if (match_name ~ /cloudflare/) icon = " ";
                                else if (match_name ~ /steam/) icon = "󰓓 ";
                                else if (match_name ~ /twitch/) icon = " ";
                                else if (match_name ~ /spotify/) icon = " ";
                                else if (match_name ~ /whatsapp/) icon = "󰖣 ";
                                else if (match_name ~ /x.com|twitter/) icon = "󰕄 ";
                                else if (match_name ~ /3cx|telnyx/) icon = " ";
                                else if (match_name ~ /hpe/) icon = " ";
                                else if (match_name ~ /ebay/) icon = " ";
                                else if (match_name ~ /paypal/) icon = " ";
                                else if (match_name ~ /firefox/) icon = "󰈹 ";
                                else if (match_name ~ /bitwarden/) icon = " ";
                                else if (match_name ~ /huggingface/) icon = " ";
                                else if (match_name ~ /localhost|127.0.0.1/) icon = "󰒋 ";
                            }

                            if (user == "" || user == "null" || user == "no-user") 
                                printf "<span color=" q hl q ">%s</span>  %s\n", icon, name;
                            else 
                                printf "<span color=" q hl q ">%s</span>  %s %s\n", icon, name "<span color=" q alt q ">:</span>", user;
                        }'
                else
                    echo "<span color='$highlight_color'> </span> Unlock Bitwarden Vault"
                fi
            else
                if [[ $selection == *"Unlock Bitwarden Vault"* ]]; then
                    pkill rofi
                    rbw stop-agent

                    sleep 0.2
                    if rbw unlock; then
                        sleep 0.2
                        launch_rofi "Bitwarden"
                    fi
                    exit 0
                else
                    local clean_line=$(echo "$selection" | sed 's/<[^>]*>//g; s/^[^[:alnum:]]*//')
                    local entry=$(echo "$clean_line" | awk -F':' '{print $1}' | sed 's/[[:space:]]*$//')
                    local user=$(echo "$clean_line" | awk -F':' '{print $2}' | sed 's/^[[:space:]]*//')

                    local val=""
                    if [[ -n $user && $user != "null" ]]; then
                        val=$(rbw get "$entry" "$user" 2>/dev/null | tr -d '\n')
                    else
                        val=$(rbw get "$entry" 2>/dev/null | tr -d '\n')
                    fi

                    if [[ -n $val ]]; then
                        safe_copy "$val" "Credentials for $entry copied."
                    else
                        notify-send "Clipboard" "Entry '$entry' not found in vault." -i "dialog-error"
                    fi
                    exit 0
                fi
            fi
            ;;

        "screenshots")
            local screenshot_dir=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
            screenshot_dir="$screenshot_dir/Screenshots"

            if [[ ! -d $screenshot_dir ]]; then
                rx_log "error" "Screenshot folder not found: $screenshot_dir"
                return 1
            fi

            local list=""
            while IFS= read -r f; do
                [[ -z $f ]] && continue

                local filename=$(basename "$f")
                local display=$(echo "${filename%.*}" | sed -E 's/hyprshot-//gi')

                list+="${display}\0icon\x1f${f}\n"
            done < <(find "$screenshot_dir" -maxdepth 1 -type f -iname "*hyprshot*" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)

            if [[ -z $list ]]; then
                rx_log "info" "No Hyprshot screenshots found in $screenshot_dir"
                return 0
            fi

            local choice=$(echo -en "$list" | launch_gallery)

            if [[ -n $choice ]]; then
                local target_file=$(find "$screenshot_dir" -maxdepth 1 -type f -name "*${choice}*" -print -quit)

                if [[ -f $target_file ]]; then
                    wl-copy <"$target_file"
                    notify-send "Screenshot Copied" "The image is ready to paste." -i "$target_file"
                else
                    rx_log "error" "Could not find the selected image file."
                fi
            fi
            exit 0
            ;;

        "open")
            launch_rofi "Clipboard"
            ;;

        *)
            rx_log "info" "Usage: retro clipboard <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "history [item]" "View or restore clipboard history"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "emoji [emoji]" "Browse and copy emojis"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "wipe" "Clear clipboard history"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "bitwarden [entry]" "Access Bitwarden vault entries"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "screenshots" "Browse and copy screenshots"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "open" "Launch clipboard picker UI"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "clipboard" "Search clipboard history with image previews (Use 'wipe' to clear)" "cmd_clipboard"
