#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

# FIX: Fix the screenshot clipboard generating the screenshots and saving them twice
# in .cache and ~/Pictures/Screenshots

cmd_clipboard() {
    local action="$1"
    local selection="$2"
    local theme_file="$HOME/.config/rofi/themes/clipboard.rasi"
    local gallery_theme="$HOME/.config/rofi/themes/gallery.rasi"

    local CLIP_BITWARDEN=$(retro -var get CLIP_BITWARDEN 2>/dev/null || echo "false")
    local CLIP_WARDEN_DESTRUCT=$(retro -var get CLIP_WARDEN_DESTRUCT 2>/dev/null || echo "15")

    local alpha=$(get_opacity_hex "0.9")
    local alpha_alt=$(get_opacity_hex "0.6")
    local base_bg=$(grep "background:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[#;FF]//g')
    local base_bg_alt=$(grep "background-alt:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[#;FF]//g')
    local highlight_color=$(grep "highlight:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[;]//g')

    launch_gallery() {
        rofi -dmenu -i -p "󰄄 " -theme "$gallery_theme" -show-icons \
            -theme-str "
                window { background-color: #${base_bg}${alpha}; } 
                inputbar { background-color: #${base_bg}${alpha}; }  
                element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
            "
    }

    launch_rofi() {
        local mode="${1:-Clipboard}"

        local modes="Clipboard:retro -clip history,Emoji:retro -clip emoji"
        [[ $CLIP_BITWARDEN == "true" ]] && modes+=",Bitwarden:retro -clip bitwarden"

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
        "history")
            if [[ -z $selection ]]; then
                local list=$(cliphist list | grep -vE "\[\[.*binary.*data")

                if [[ -z $list ]]; then
                    echo "Clipboard history is empty..."
                else
                    echo "$list"
                fi
            else
                if echo "$selection" | cliphist decode | wl-copy 2>/dev/null; then
                    rx_log "success" "Item copied to clipboard." >&2
                else
                    echo -n "$selection" | wl-copy
                    rx_log "success" "Emoji/Text copied." >&2
                fi

                exit 0
            fi
            ;;

        "emoji")
            if [[ -z $selection ]]; then
                rofimoji --action copy
            else
                echo "$selection" | awk '{print $1}' | wl-copy
                exit 0
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
            local thumb_dir="$HOME/.cache/retro/clip_thumbs"
            mkdir -p "$thumb_dir"

            local result=$(cliphist list | grep -E "\[\[.*binary.*data" | while read -r line; do
                local id=$(echo "$line" | cut -f1 | awk '{print $1}')
                local thumb="$thumb_dir/${id}.png"

                if [[ ! -f $thumb ]]; then
                    if ! echo "$line" | cliphist decode >"$thumb" 2>/dev/null; then
                        rm -f "$thumb"
                        continue
                    fi

                    if ! file "$thumb" | grep -qE "image|graphics"; then
                        rm -f "$thumb"
                        continue
                    fi
                fi
                echo -en "${id} │ Preview\0icon\x1f${thumb}\n"
            done | launch_gallery)

            if [[ -n $result ]]; then
                local id=$(echo "$result" | awk '{print $1}')
                local restored_img="$thumb_dir/${id}.png"

                if cliphist list | grep -w "^$id" | cliphist decode | wl-copy; then
                    notify-send "Screenshot $id" "Image has been copied to the clipboard." -i "$restored_img"
                fi
            fi

            exit 0
            ;;

        *)
            launch_rofi "Clipboard"
            ;;
    esac
}

register_command "TOOLS" "-clip|--clipboard" "Search clipboard history with image previews (Use 'wipe' to clear)" "cmd_clipboard"
