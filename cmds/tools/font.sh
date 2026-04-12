#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_font() {
    local font_core="$RETRO_DIR/scripts/font_core.sh"
    local action="${1,,}"
    local type="$2"
    shift 2
    local value="$*"

    case "$action" in
        "install")
            [[ -z $type ]] && rx_log "error" "What font should I search for?" && return 1
            local helper=$(get_var "PKG_HELPER")
            [[ -z $helper ]] && helper="yay"

            local val=""

            if [[ ! $type =~ (font|ttf|otf|woff|emoji) ]]; then
                rx_log "warn" "'$type' doesn't look like a font. Searching for alternatives..."
                val="1"
            else
                rx_log "info" "Attempting direct install of ${PINK}$type${RESET}..."
                $helper -S --noconfirm "$type" && exit_code=$? || exit_code=$?

                if [[ $exit_code -ne 0 ]]; then
                    rx_log "warn" "Direct install failed. Falling back to search..."
                    val="1"
                fi
            fi

            if [[ $val == "1" ]]; then
                mapfile -t results < <(bash "$font_core" --search-remote "$type" | head -n 10)

                if [[ ${#results[@]} -eq 0 ]]; then
                    rx_log "error" "No actual font packages matching '$type' found."
                    return 1
                fi

                rx_table_header "" "Remote Fonts: $type"

                for i in "${!results[@]}"; do
                    local p_name=$(echo "${results[$i]}" | awk '{print $1}')
                    local p_desc=$(echo "${results[$i]}" | cut -d' ' -f2-)
                    rx_table_simple "󰾰" "$p_name - ${p_desc:0:45}..." "$GRAY"
                done

                rx_table_separator
                rx_table_spacer

                echo -ne "\n ${PINK}󰄾 ${RESET}Selection [1-${#results[@]}]: "
                read -r choice

                if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#results[@]})); then
                    local selected=$(echo "${results[$((choice - 1))]}" | awk '{print $1}')
                    rx_log "info" "Installing ${PINK}$selected${RESET}..."
                    $helper -S --noconfirm "$selected"
                    bash "$font_core" --sync
                fi
            fi
            ;;

        "set")
            [[ -z $value ]] && rx_log "error" "Usage: retro font set [main|nerd|emoji] [Font Name]" && return 1

            if ! bash "$font_core" --list-installed | grep -Fxq "$value"; then
                rx_log "error" "Font '${value}' is not valid. Use 'retro font list' for exact names."
                return 1
            fi

            case "$type" in
                "main") set_var "RETRO_FONT_MAIN" "$value" ;;
                "nerd") set_var "RETRO_FONT_NERD" "$value" ;;
                "emoji") set_var "RETRO_FONT_EMOJI" "$value" ;;
                *) rx_log "error" "Invalid type. Use main, nerd, or emoji." && return 1 ;;
            esac

            bash "$font_core" --sync
            rx_log "success" "${PINK}$value${RESET} font has been successfully applied to your ${PINK}$type${RESET} profile."
            ;;

        "edit")
            local editor=$(get_var "EDITOR")
            [[ -z $editor ]] && editor="nano"

            $editor "$HOME/.config/fontconfig/conf.d/99-retro-fonts.conf"

            bash "$font_core" --sync
            rx_log "success" "Manual overrides applied and synced."
            ;;

        "list")
            local installed_list=$(bash "$font_core" --list-installed)
            local font_count=$(echo "$installed_list" | wc -l)

            rx_table_header "" "Fonts Installed: ${font_count} families"

            local m=$(get_var "RETRO_FONT_MAIN")
            local n=$(get_var "RETRO_FONT_NERD")
            local e=$(get_var "RETRO_FONT_EMOJI")

            while read -r line; do
                [[ -z $line ]] && continue
                local font="$line"
                local icon=""
                local tag=""

                if [[ $line == "$m" ]]; then
                    font="$line:"
                    tag="Active"
                    icon="󰛖"
                fi
                if [[ $line == "$n" ]]; then
                    font="$line:"
                    tag="Active"
                    icon="󰊪"
                fi
                if [[ $line == "$e" ]]; then
                    font="$line:"
                    tag="Active"
                    icon=""
                fi

                rx_table_row "$icon" "$font" "$tag" "$PINK"
            done <<<"$installed_list"

            rx_table_separator
            rx_table_spacer
            ;;

        "remote")
            local query="${type:-font}"
            local page="${val:-1}"
            local limit=10
            local skip=$(((page - 1) * limit))

            rx_log "info" "Fetching remote fonts (Page: $page)..."

            mapfile -t all_results < <(bash "$font_core" --search-remote "$query")
            local total=${#all_results[@]}
            local paginated=("${all_results[@]:skip:limit}")

            rx_table_header "" "Remote Fonts: $query ($total found)"

            for line in "${paginated[@]}"; do
                local p_name=$(echo "$line" | awk '{print $1}')
                local p_desc=$(echo "$line" | cut -d' ' -f2-)
                rx_table_simple "" "$p_name - ${p_desc:0:45}..." "$GRAY"
            done

            rx_table_separator

            if ((total > skip + limit)); then
                rx_table_simple "󰄾" "Page $page | Next: retro font remote $query $((page + 1))" "$GRAY"
                rx_table_spacer
            else
                rx_table_spacer
            fi
            ;;

        "status")
            local count=$(bash "$font_core" --list-installed | wc -l)
            rx_table_header "" "Font Status"
            rx_table_row "󰊪" "Main Font:" "$(get_var RETRO_FONT_MAIN)" "$PINK" "14"
            rx_table_row "󰊪" "Nerd Font:" "$(get_var RETRO_FONT_NERD)" "$PINK" "14"
            rx_table_row "󰞅" "Emoji Set:" "$(get_var RETRO_FONT_EMOJI)" "$PINK" "14"
            rx_table_row "󰉖" "Unique Fonts:" "$count" "$PINK" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            local helper=$(get_var "PKG_HELPER")
            [[ -z $helper ]] && helper="sudo pacman"

            if [[ -z $(get_var "RETRO_FONT_MAIN") ]]; then
                rx_log "info" "Enter the main font package name ${PINK}[Default: inter-font]${RESET}: "
                read -r input_pkg
                local main_pkg="${input_pkg:-inter-font}"

                cmd_font "install" "$main_pkg"

                local installed_fonts=$(bash "$font_core" --list-installed)
                local match=$(echo "$installed_fonts" | grep -i "inter" | head -1)
                [[ -z $match ]] && match=$(echo "$installed_fonts" | tail -1)

                if [[ -n $match ]]; then
                    rx_confirm "Detected font family: ${PINK}$match${RESET}. Use this?" "Y" || { rx_log "info" "Enter the exact font family name: "; read -r font_name; set_var "RETRO_FONT_MAIN" "${font_name:-$match}"; return 0; }
                    set_var "RETRO_FONT_MAIN" "$match"
                fi
            fi

            if [[ -z $(get_var "RETRO_FONT_NERD") ]]; then
                rx_log "info" "Enter the nerd font package name ${PINK}[Default: ttf-jetbrains-mono-nerd]${RESET}: "
                read -r input_pkg
                local nerd_pkg="${input_pkg:-ttf-jetbrains-mono-nerd}"

                cmd_font "install" "$nerd_pkg"

                local installed_fonts=$(bash "$font_core" --list-installed)
                local match=$(echo "$installed_fonts" | grep -i "jetbrains" | head -1)
                [[ -z $match ]] && match=$(echo "$installed_fonts" | tail -1)

                if [[ -n $match ]]; then
                    rx_confirm "Detected font family: ${PINK}$match${RESET}. Use this?" "Y" || { rx_log "info" "Enter the exact font family name: "; read -r font_name; set_var "RETRO_FONT_NERD" "${font_name:-$match}"; return 0; }
                    set_var "RETRO_FONT_NERD" "$match"
                fi
            fi

            if [[ -z $(get_var "RETRO_FONT_EMOJI") ]]; then
                local styles=(
                    "apple|ttf-apple-emoji|Apple Color Emoji|Glossy iOS vibe"
                    "google|noto-fonts-emoji|Noto Color Emoji|Flat Android vibe"
                    "twemoji|ttf-twemoji|Twemoji|Classic Discord look"
                    "fluent|ttf-fluentui-emoji|Fluent UI Emoji|3D Fluent style"
                    "joypixels|ttf-joypixels|JoyPixels|Vibrant and expressive"
                    "samsung|ttf-samsung-emojis|Samsung Color Emoji|Bubbly lines"
                    "openmoji|ttf-openmoji|OpenMoji|Artistic outlines"
                    "blob|noto-fonts-emoji-blob|Blobmoji|Noodle blobs"
                )

                rx_log "info" "Select Emoji Style:${RESET}"
                for i in "${!styles[@]}"; do
                    IFS='|' read -r k p n v <<<"${styles[$i]}"
                    printf "  ${PINK}%d)${RESET} %s\n" "$((i + 1))" "$n"
                done

                rx_log "info" "Choice ${PINK}[Default: 1]${RESET}: "
                read -r e_choice

                local idx=$((${e_choice:-1} - 1))
                [[ $idx -lt 0 || $idx -ge ${#styles[@]} ]] && idx=0

                IFS='|' read -r e_key e_pkg e_name e_vibe <<<"${styles[$idx]}"

                rx_log "info" "Installing $e_name..."
                $helper -S --noconfirm "$e_pkg"

                set_var "RETRO_FONT_EMOJI" "$e_name"
            fi

            bash "$font_core" --sync
            rx_log "success" "All fonts installed and configured"
            ;;

        *)
            rx_help_usage "retro font <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "install <pkg>" "Install a font package"
            rx_help_cmd "set [cat] <font>" "Set active font for category"
            rx_help_cmd "edit" "Edit fontconfig override file"
            rx_help_cmd "list" "List all installed fonts"
            rx_help_cmd "remote [query]" "Search remote font packages"
            rx_help_cmd "status" "Show active fonts and count"
            rx_help_cmd "setup" "Interactive font setup wizard"
            rx_help_examples
            rx_help_example "retro font status" "Show active fonts and count"
            rx_help_example "retro font list" "List all installed fonts"
            rx_help_example "retro font remote inter" "Search for Inter font"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "font" "System-wide typography and emoji management" "cmd_font"
