#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_font() {
    local font_core="$RETRO_DIR/scripts/font_core.sh"
    local action="${1,,}"
    local type="$2"
    shift 2
    local value="$*"

    case "$action" in
        "install")
            [[ -z $type ]] && rx_log "error" "What font should I search for?" && return 1

            local input_path="$type"
            if [[ -n $value ]]; then
                input_path="$type/$value"
            fi

            local is_file=false
            local is_glob=false

            if [[ $input_path == *\** ]]; then
                is_glob=true
            elif [[ -f $input_path ]]; then
                is_file=true
                input_path="$(cd "$(dirname "$input_path")" 2>/dev/null && pwd)/$(basename "$input_path")"
            elif [[ -f "$(readlink -f "$input_path")" ]]; then
                is_file=true
                input_path="$(readlink -f "$input_path")"
            fi

            if [[ $is_file == "true" || $is_glob == "true" ]]; then
                local ext="${input_path##*.}"
                ext="${ext,,}"
                case "$ext" in
                    ttf | otf | woff | woff2 | ttc)
                        ;;
                    *)
                        rx_log "error" "Unsupported font file extension: ${PINK}$ext${RESET}"
                        rx_log "info" "Supported formats: TTF, OTF, WOFF, WOFF2, TTC"
                        return 1
                        ;;
                esac

                rx_log "info" "Installing font from ${PINK}$input_path${RESET}..."

                local result
                result=$(bash "$font_core" --install-file "$input_path" 2>&1)

                local first_word
                first_word=$(echo "$result" | head -1 | awk -F'|' '{print $1}')

                if [[ $first_word == "FILE_NOT_FOUND" ]]; then
                    rx_log "error" "File not found: ${PINK}$input_path${RESET}"
                    return 1
                elif [[ $first_word == "INVALID_EXT" ]]; then
                    local inv_file
                    inv_file=$(echo "$result" | head -1 | awk -F'|' '{print $2}')
                    rx_log "error" "Invalid font file: ${PINK}$inv_file${RESET}"
                    return 1
                elif [[ $first_word == "DIRECTORY_EMPTY" ]]; then
                    rx_log "error" "Directory is empty: ${PINK}$input_path${RESET}"
                    return 1
                fi

                local exists_line
                exists_line=$(echo "$result" | grep "^EXISTS|" | head -1)

                local needs_confirm="false"
                local filename="${input_path##*/}"
                local font_display="${filename%.*}"
                local target_path="$HOME/.local/share/fonts/$filename"
                local is_identical="false"

                if [[ -n $exists_line ]]; then
                    needs_confirm="true"
                    filename=$(echo "$exists_line" | awk -F'|' '{print $2}')
                    font_display=$(echo "$exists_line" | awk -F'|' '{print $3}')
                    target_path=$(echo "$exists_line" | awk -F'|' '{print $4}')
                    is_identical=$(echo "$exists_line" | awk -F'|' '{print $5}' | grep -q "true" && echo "true" || echo "false")
                fi

                if [[ $needs_confirm == "true" ]]; then
                    if [[ $is_identical == "true" ]]; then
                        rx_log "info" "Font ${PINK}${font_display}${RESET} is already installed (identical file)"
                    else
                        rx_log "info" "Font ${PINK}${font_display}${RESET} already exists with different content"
                    fi

                    local choice
                    choice=$(rx_menu "󰅸" "Font ${PINK}${font_display}${RESET} exists. Choose action:" \
                        "Overwrite" \
                        "Skip" \
                        "Keep both (rename)")

                    case "$choice" in
                        "Overwrite")
                            bash "$font_core" --install-file-overwrite "$input_path" "$target_path" >/dev/null
                            bash "$font_core" --install-file-cache >/dev/null
                            rx_log "success" "Font ${PINK}$font_display${RESET} overwritten"
                            ;;
                        "Skip")
                            rx_log "info" "Font skipped"
                            ;;
                        "Keep both (rename)")
                            local new_result
                            new_result=$(bash "$font_core" --install-file-rename "$input_path" "$HOME/.local/share/fonts" 2>/dev/null)
                            local new_name
                            new_name=$(echo "$new_result" | awk -F'|' '{print $2}')
                            bash "$font_core" --install-file-cache >/dev/null
                            rx_log "success" "Font installed as ${PINK}$new_name${RESET}"
                            ;;
                        *)
                            rx_log "info" "No changes made"
                            ;;
                    esac
                else
                    local result_line
                    result_line=$(echo "$result" | grep "^RESULT|" | head -1)
                    local installed
                    installed=$(echo "$result_line" | grep -oP 'installed=\K\d+' || echo "0")
                    local skipped
                    skipped=$(echo "$result_line" | grep -oP 'skipped=\K\d+' || echo "0")

                    if [[ $installed -gt 0 ]]; then
                        rx_log "success" "Font ${PINK}$font_display${RESET} installed"
                    elif [[ $skipped -gt 0 ]]; then
                        rx_log "info" "Font already installed"
                    fi
                    bash "$font_core" --install-file-cache >/dev/null
                fi

                bash "$font_core" --sync
                return 0
            fi

            local helper=$(get_var "PKG_HELPER")
            [[ -z $helper ]] && helper="yay"

            local val=""

            if [[ ! $type =~ (font|ttf|otf|woff|emoji) ]]; then
                rx_log "warn" "'$type' doesn't look like a font. Searching for alternatives..."
                val="1"
            else
                local needed_flag=""
                [[ $RX_SETUP_NEEDED == true ]] && needed_flag="--needed"
                rx_log "info" "Attempting direct install of ${PINK}$type${RESET}..."
                $helper -S --noconfirm $needed_flag "$type" && exit_code=$? || exit_code=$?

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
            rx_setup_parse "$type" $value

            local helper=$(get_var "PKG_HELPER")
            [[ -z $helper ]] && helper="sudo pacman"

            if [[ $flag == "--yes" || $flag == "-y" ]]; then
                export SKIP_PROMPT=true
            fi

            local main_conf=$(get_var "RETRO_FONT_MAIN")
            local nerd_conf=$(get_var "RETRO_FONT_NERD")
            local emoji_conf=$(get_var "RETRO_FONT_EMOJI")
            local config_exists=false
            [[ -n $main_conf && -n $nerd_conf && -n $emoji_conf ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            if [[ $config_exists == true && $SKIP_PROMPT != "true" ]]; then
                rx_setup_current "󰄈" "Current Font Configuration" \
                    "Main" "$main_conf" \
                    "Nerd" "$nerd_conf" \
                    "Emoji" "$emoji_conf" || true

                if ! rx_confirm "Reconfigure?" "N"; then
                    rx_log "info" "Setup cancelled."
                    return 0
                fi
            fi

            if [[ $SKIP_PROMPT == "true" ]]; then
                cmd_font "install" "inter-font"
                cmd_font "install" "ttf-jetbrains-mono-nerd"
                cmd_font "install" "ttf-apple-emoji"

                set_var "RETRO_FONT_MAIN" "Inter"
                set_var "RETRO_FONT_NERD" "JetBrainsMono Nerd Font"
                set_var "RETRO_FONT_EMOJI" "Apple Color Emoji"

                bash "$font_core" --sync
                rx_log "success" "Fonts installed with defaults"
                return 0
            fi

            local main_name="" nerd_name="" emoji_name=""

            if [[ -n $main_conf ]]; then
                main_name=$(rx_input "Which main font would you like to use?" "$main_conf")
                set_var "RETRO_FONT_MAIN" "$main_name"
            else
                local main_pkg=$(rx_input "Main font package" "inter-font")
                cmd_font "install" "$main_pkg"
                local installed_fonts=$(bash "$font_core" --list-installed)
                local match=$(echo "$installed_fonts" | grep -i "inter" | head -1)
                [[ -z $match ]] && match=$(echo "$installed_fonts" | tail -1)
                if [[ -n $match ]]; then
                    rx_confirm "Detected font family: ${PINK}$match${RESET}. Use this?" "Y" || {
                        main_name=$(rx_input "Exact font family name" "$match")
                    }
                    [[ -z $main_name ]] && main_name="$match"
                    set_var "RETRO_FONT_MAIN" "$main_name"
                fi
            fi

            if [[ -n $nerd_conf ]]; then
                nerd_name=$(rx_input "Which nerd font would you like to use?" "$nerd_conf")
                set_var "RETRO_FONT_NERD" "$nerd_name"
            else
                local nerd_pkg=$(rx_input "Nerd font package" "ttf-jetbrains-mono-nerd")
                cmd_font "install" "$nerd_pkg"
                local installed_fonts=$(bash "$font_core" --list-installed)
                local match=$(echo "$installed_fonts" | grep -i "jetbrains" | head -1)
                [[ -z $match ]] && match=$(echo "$installed_fonts" | tail -1)
                if [[ -n $match ]]; then
                    rx_confirm "Detected font family: ${PINK}$match${RESET}. Use this?" "Y" || {
                        nerd_name=$(rx_input "Exact font family name" "$match")
                    }
                    [[ -z $nerd_name ]] && nerd_name="$match"
                    set_var "RETRO_FONT_NERD" "$nerd_name"
                fi
            fi
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

            local e_labels=()
            for s in "${styles[@]}"; do
                IFS='|' read -r k p n v <<<"$s"
                e_labels+=("$n - $v")
            done

            local e_selection=$(rx_input_choice "󰄾" "Select Emoji Style" "1" "${e_labels[@]}")
            local e_idx=0
            for i in "${!e_labels[@]}"; do
                [[ "${e_labels[$i]}" == "$e_selection" ]] && e_idx=$i && break
            done

            IFS='|' read -r e_key e_pkg e_name e_vibe <<<"${styles[$e_idx]}"

            rx_log "info" "Installing ${PINK}$e_name${RESET}..."
            local needed_flag=""
            [[ $RX_SETUP_NEEDED == true ]] && needed_flag="--needed"
            $helper -S --noconfirm $needed_flag "$e_pkg"
            set_var "RETRO_FONT_EMOJI" "$e_name"
            emoji_name="$e_name"

            bash "$font_core" --sync

            rx_setup_success "󰄈" "Fonts Configured" \
                "Main" "${main_name:-Inter}" \
                "Nerd" "${nerd_name:-JetBrainsMono Nerd Font}" \
                "Emoji" "${emoji_name:-Apple Color Emoji}"
            ;;

        *)
            rx_help_usage "retro font <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "install <pkg|file>" "Install font package or local file"
            rx_help_cmd "set [cat] <font>" "Set active font for category"
            rx_help_cmd "edit" "Edit fontconfig override file"
            rx_help_cmd "list" "List all installed fonts"
            rx_help_cmd "remote [query]" "Search remote font packages"
            rx_help_cmd "status" "Show active fonts and count"
            rx_help_cmd "setup [--yes|-y]" "Interactive font setup wizard"
            rx_help_examples
            rx_help_example "retro font install ttf-jetbrains" "Install from package"
            rx_help_example "retro font install ~/Fonts/Roboto.ttf" "Install from file"
            rx_help_example "retro font install ~/Downloads/*.otf" "Install multiple files"
            rx_help_example "retro font list" "List all installed fonts"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "font" "System-wide typography and emoji management" "cmd_font"
