#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

cmd_font() {
    local font_core="$RETRO_DIR/scripts/font_core.sh"
    local action="$1"
    local type="$2"
    shift 2
    local value="$*"

    case "$action" in
        "install")
            [[ -z $type ]] && rx_log "error" "What font should I search for?" && return 1
            local helper=$(get_var "PKG_HELPER")

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

                echo -e "\n ${PINK} Remote Fonts: ${RESET}$type"
                echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

                for i in "${!results[@]}"; do
                    local p_name=$(echo "${results[$i]}" | awk '{print $1}')
                    local p_desc=$(echo "${results[$i]}" | cut -d' ' -f2-)

                    printf " ${PINK}%d)${RESET} %-30s ${GRAY}%s${RESET}\n" "$((i + 1))" "$p_name" "${p_desc:0:45}..."
                done

                echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

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
            [[ -z $value ]] && rx_log "error" "Usage: retro --font set [main|nerd|emoji] [Font Name]" && return 1

            if ! bash "$font_core" --list-installed | grep -Fxq "$value"; then
                rx_log "error" "Font '${value}' is not valid. Use 'retro -ft list' for exact names."
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

            echo -e "\n ${PINK} Fonts Installed: ${RESET}${font_count} families"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

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

                printf " ${PINK}%b${RESET} %-35s ${PINK}%-15s${RESET}\n" "$icon" "$font" "$tag"
            done <<<"$installed_list"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
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

            echo -e "\n ${PINK} Remote Fonts: ${RESET}$query ($total found)"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            for line in "${paginated[@]}"; do
                local p_name=$(echo "$line" | awk '{print $1}')
                local p_desc=$(echo "$line" | cut -d' ' -f2-)
                printf " ${PINK}${RESET} %-30s ${GRAY}%s${RESET}\n" "$p_name" "${p_desc:0:45}..."
            done

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            if ((total > skip + limit)); then
                echo -e " ${PINK}󰄾${RESET} Page $page | Next: ${PINK}retro -ft remote $query $((page + 1))${RESET}\n"
            else
                echo -e ""
            fi
            ;;

        "status")
            local count=$(bash "$font_core" --list-installed | wc -l)
            echo -e "\n ${PINK} Font Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}${RESET} %-14s %s\n" "Main Font:" "$(get_var RETRO_FONT_MAIN)"
            printf " ${PINK}󰊪${RESET} %-14s %s\n" "Nerd Font:" "$(get_var RETRO_FONT_NERD)"
            printf " ${PINK}󰞅${RESET} %-14s %s\n" "Emoji Set:" "$(get_var RETRO_FONT_EMOJI)"
            printf " ${PINK}󰉖${RESET} %-14s %s\n" "Unique Fonts:" "$count"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
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
                    rx_log "info" "Detected font family: ${PINK}$match${RESET}. Use this? [Y/n] "
                    read -r confirm
                    if [[ ! $confirm =~ ^[Nn]$ ]]; then
                        set_var "RETRO_FONT_MAIN" "$match"
                    else
                        rx_log "info" "Enter the exact font family name: "
                        read -r font_name
                        set_var "RETRO_FONT_MAIN" "${font_name:-$match}"
                    fi
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
                    rx_log "info" "Detected font family: ${PINK}$match${RESET}. Use this? [Y/n] "
                    read -r confirm
                    if [[ ! $confirm =~ ^[Nn]$ ]]; then
                        set_var "RETRO_FONT_NERD" "$match"
                    else
                        rx_log "info" "Enter the exact font family name: "
                        read -r font_name
                        set_var "RETRO_FONT_NERD" "${font_name:-$match}"
                    fi
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

        *) rx_log "info" "Usage: retro --font [install|set|edit|list|remote|status]" ;;
    esac
}

register_command "TOOLS" "-ft|--font" "System-wide typography and emoji management" "cmd_font"
