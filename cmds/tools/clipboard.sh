#!/bin/bash

get_opacity_hex() {
    local base_opacity=$(retro -var get RETRO_ACTIVE_OPACITY 2>/dev/null || echo "1.0")

    [[ $base_opacity == "1.0" ]] && {
        echo "FF"
        return
    }

    local multiplier="${1:-1.0}"

    local opacity_int=$(echo "($base_opacity * $multiplier * 255 + 0.5) / 1" | bc)

    # Clamp values
    ((opacity_int > 255)) && opacity_int=255
    ((opacity_int < 0)) && opacity_int=0

    printf "%02x" "$opacity_int"
}

cmd_clipboard() {
    local action="$1"
    local selection="$2"
    local theme_file="$HOME/.config/rofi/themes/clipboard.rasi"

    local alpha=$(get_opacity_hex "0.9")
    local alpha_alt=$(get_opacity_hex "0.4")
    local base_bg=$(grep "background:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[#;FF]//g')
    local base_bg_alt=$(grep "background-alt:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[#;FF]//g')

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
                if [[ -z $(cliphist list) ]]; then
                    echo "Clipboard history is empty..."
                else
                    cliphist list
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

        *)
            rofi -modi "Clipboard:retro -clip history,Emoji:retro -clip emoji" \
                -show "Clipboard" \
                -theme "$theme_file" \
                -theme-str "
                        window { background-color: #${base_bg}${alpha}; } 
                        inputbar { background-color: #${base_bg}${alpha}; }  
                        element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
                        element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
                        "
            ;;
    esac
}

register_command "TOOLS" "-clip|--clipboard" "Search clipboard history with image previews (Use 'wipe' to clear)" "cmd_clipboard"
