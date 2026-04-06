#!/bin/bash

get_terminal_child() {
    local title="$1"
    local t_cmd="${title%% *}"

    if [[ $t_cmd =~ ^(/|~|\.) ]] || [[ $t_cmd =~ ^(bash|zsh|fish|sh|tmux|kitty|kitten)$ ]]; then
        return
    fi

    if [[ $t_cmd =~ ^(hyprctl|ps|grep|awk|sudo|su|clear|cat|ls|cd|rm|cp|mv|retro)$ ]]; then
        return
    fi

    if command -v "$t_cmd" &>/dev/null; then
        echo "$t_cmd"
    fi
}

get_client_cwd() {
    local pid="$1"
    local class="$2"
    local term_cmd="$3"
    local cwd=""

    if [[ ${class,,} == "${term_cmd,,}" ]]; then
        cwd=$(kitty @ --to="unix:/tmp/kitty-$pid" ls 2>/dev/null | grep -m 1 '"cwd":' | cut -d'"' -f4)
    fi

    if [[ -z $cwd ]]; then
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
    fi

    echo "${cwd:-$HOME}"
}

handle_kitty_padding() {
    local pid="$1"
    local is_fullscreen="$2"
    local rule=$(get_var "KITTY_SHRINK_PADDING_FULLSCREEN")
    local default_pd=$(get_var "KITTY_PADDING")

    if [[ $rule == "true" ]]; then
        if [[ $is_fullscreen == "0" || $is_fullscreen == "false" ]]; then
            kitty @ --to="unix:/tmp/kitty-$pid" set-spacing \
                padding-top=1 padding-bottom=1 padding-left=1 padding-right=1 2>/dev/null
        else
            kitty @ --to="unix:/tmp/kitty-$pid" set-spacing \
                padding-top="$default_pd" padding-bottom="$default_pd" \
                padding-left="$default_pd" padding-right="$default_pd" 2>/dev/null
        fi
    fi
}

save_session() {
    rx_log "info" "Capturing system-wide session state..."
    local session_data=""
    local terminal_cmd=$(get_var "RETRO_TERMINAL_CMD" "kitty")
    local fm_cmd=$(get_var "RETRO_FILEMANAGER_CMD")

    local raw_vars=$(bash "$RETRO_DIR/scripts/variable_core.sh" --list 2>/dev/null)
    local mapped_vars=$(echo "$raw_vars" | awk -F'=' '/RETRO_.*_CMD/ {gsub(/^RETRO_|_CMD$/, "", $1); gsub(/"/, "", $2); print tolower($1) "=" tolower($2)}')

    while read -r class ws_id pid is_floating is_fs title; do
        if [[ $is_floating == "true" && $is_fs != "1" && $is_fs != "2" && $is_fs != "true" ]]; then
            continue
        fi

        [[ -z $class || $class == "null" ]] && continue

        local final_app_name=""
        local display_sub=""

        local cwd=$(get_client_cwd "$pid" "$class" "$terminal_cmd")

        if [[ ${class,,} == "${terminal_cmd,,}" ]]; then
            final_app_name="terminal"
            display_sub=$(get_terminal_child "$title")
        else
            local binary_name="${class,,}"
            if [[ -n $fm_cmd && $binary_name == "${fm_cmd,,}" ]]; then
                final_app_name="filemanager"
            else
                local var_match=$(echo "$mapped_vars" | grep -i "$binary_name" | cut -d'=' -f1 | head -n 1)

                if [[ -n $var_match ]]; then
                    final_app_name="$var_match"
                else
                    case "$binary_name" in
                        "terminal" | "bash" | "zsh" | "sh") final_app_name="terminal" ;;
                        "ps" | "grep" | "awk" | "retro" | "kitten" | "rofi") continue ;;
                        *) final_app_name="$binary_name" ;;
                    esac
                fi
            fi
        fi

        if [[ -n $final_app_name ]]; then
            local entry="${final_app_name}|${display_sub}|${cwd}|${is_fs}:${ws_id}"

            if [[ -z $session_data ]]; then
                session_data="$entry"
            else
                session_data="${session_data},${entry}"
            fi
        fi
    done < <(hyprctl clients -j | jq -r 'sort_by(.workspace.id, .at[1], .at[0]) | .[] | "\(.initialClass // .class) \(.workspace.id) \(.pid) \(.floating) \(.fullscreen) \(.title)"')

    if [[ -n $session_data ]]; then
        set_var "RETRO_SESSION_STATE" "$session_data"
        set_var "RETRO_SESSION_TIMESTAMP" "$(date +%s)"
        rx_log "success" "Session state cached: ${MUTE}${session_data}${RESET}"
    else
        rx_log "error" "No tiled applications found to save."
    fi
}

restore_session() {
    local data=$(get_var "RETRO_SESSION_STATE")
    local terminal_cmd=$(get_var "RETRO_TERMINAL_CMD" "kitty")

    if [[ -z $data || $data == "null" ]]; then
        rx_log "error" "No session payload found in Retro variables."
        return 1
    fi

    rx_log "info" "Rebuilding workspace layout..."

    local current_clients=","
    local mapped_vars=$(bash "$RETRO_DIR/scripts/variable_core.sh" --list | awk -F'=' '/RETRO_.*_CMD/ {gsub(/^RETRO_|_CMD$/, "", $1); gsub(/"/, "", $2); print tolower($1) "=" tolower($2)}')

    while read -r class ws_id pid is_floating is_fs title; do
        if [[ $is_floating == "true" && $is_fs != "1" && $is_fs != "2" && $is_fs != "true" ]]; then
            continue
        fi

        local app_name=""
        local display_sub=""

        if [[ ${class,,} == "${terminal_cmd,,}" ]]; then
            app_name="terminal"
            display_sub=$(get_terminal_child "$title")
        else
            local bin="${class,,}"
            local var_match=$(echo "$mapped_vars" | grep -i "$bin" | cut -d'=' -f1 | head -n 1)

            if [[ -n $var_match ]]; then
                app_name="$var_match"
            else
                app_name="$bin"
            fi
        fi

        current_clients="${current_clients}${app_name}|${display_sub}:${ws_id},"
    done < <(hyprctl clients -j | jq -r 'sort_by(.workspace.id, .at[1], .at[0]) | .[] | "\(.initialClass // .class) \(.workspace.id) \(.pid) \(.floating) \(.fullscreen) \(.title)"')

    IFS=',' read -ra ENTRIES <<<"$data"
    for entry in "${ENTRIES[@]}"; do
        local full_payload="${entry%%:*}"
        local ws="${entry#*:}"

        local app=$(echo "$full_payload" | cut -d'|' -f1)
        local sub=$(echo "$full_payload" | cut -d'|' -f2)
        local cwd=$(echo "$full_payload" | cut -d'|' -f3)
        local is_fs=$(echo "$full_payload" | cut -d'|' -f4)

        local check_str="${app}|${sub}:${ws}"

        if [[ $current_clients == *",$check_str,"* ]]; then
            current_clients="${current_clients/,$check_str,/,}"

            local skip_name="${app^}"
            [[ $app != "$sub" && -n $sub ]] && skip_name="$skip_name ($sub)"
            rx_log "info" "Skipping $skip_name: Already present on Workspace $ws."
            continue
        fi

        local rest_name="${app^}"
        [[ $app != "$sub" && -n $sub ]] && rest_name="$rest_name ($sub)"
        rx_log "info" "Restoring $rest_name to Workspace $ws..."

        hyprctl dispatch workspace "$ws" >/dev/null

        export RETRO_CWD="$cwd"

        # 󱗼 FIXED: Isolate App Manager from Native Apps
        local is_core="false"
        case "$app" in
            terminal | filemanager | browser | editor) is_core="true" ;;
        esac

        if [[ $is_core == "true" ]]; then
            if [[ $app != "$sub" && -n $sub ]]; then
                cmd_apps "$app" "open" "$sub"
            else
                cmd_apps "$app" "open"
            fi
        else
            local exe_cmd="$app"
            # Hardcoded quirks for apps with weird classes
            case "${app,,}" in
                zen) exe_cmd="zen-browser" ;;
                code-url-handler) exe_cmd="code" ;;
            esac
            (setsid "$exe_cmd" >/dev/null 2>&1 &)
        fi

        unset RETRO_CWD

        if [[ $is_fs == "1" || $is_fs == "2" || $is_fs == "true" ]]; then
            (sleep 0.8 && hyprctl dispatch fullscreen 0 >/dev/null 2>&1) &
        fi

        sleep 0.4
    done

    sleep 0.5

    hyprctl dispatch workspace 1 >/dev/null

    rx_log "success" "System state fully restored."
}

cmd_wm() {
    local action="$1"
    shift
    local args="$@"

    case "$action" in
        "fullscreen")
            local active=$(hyprctl activewindow -j)
            local class=$(echo "$active" | jq -r '.class')
            local pid=$(echo "$active" | jq -r '.pid')
            local fs_state=$(echo "$active" | jq -r '.fullscreen | tostring')

            if [[ ${class,,} == "kitty" ]]; then
                handle_kitty_padding "$pid" "$fs_state"
            fi
            hyprctl dispatch fullscreen 0
            ;;

        "save") save_session ;;
        "restore") restore_session ;;

        "clear")
            set_var "RETRO_SESSION_STATE" "null"
            set_var "RETRO_SESSION_TIMESTAMP" "null"
            rx_log "success" "Saved session state has been deleted."
            ;;

        "toggle-autosave")
            local current_state=$(get_var "RETRO_SESSION_AUTOSAVE")
            if [[ $current_state == "true" ]]; then
                set_var "RETRO_SESSION_AUTOSAVE" "false"
                rx_log "success" "Retro Session auto-save disabled."
            else
                set_var "RETRO_SESSION_AUTOSAVE" "true"
                rx_log "success" "Retro Session auto-save enabled."
            fi
            ;;

        "status")
            local data=$(get_var "RETRO_SESSION_STATE")
            local ts=$(get_var "RETRO_SESSION_TIMESTAMP")

            if [[ -z $data || $data == "null" ]]; then
                rx_log "error" "No session snapshot found in system variables."
                return 1
            fi

            local diff=$(($(date +%s) - ts))
            local ago_str="$((diff / 60))m $((diff % 60))s ago"
            local human_time=$(date -d "@$ts" "+%H:%M:%S")

            echo -e "\n ${PINK}󰨇 Session Snapshot: ${RESET}$ago_str at $human_time ${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────"

            declare -A ws_groups
            IFS=',' read -ra ENTRIES <<<"$data"

            for entry in "${ENTRIES[@]}"; do
                local full_payload="${entry%%:*}"
                local ws="${entry#*:}"

                local app=$(echo "$full_payload" | cut -d'|' -f1)
                local sub=$(echo "$full_payload" | cut -d'|' -f2)
                local is_fs=$(echo "$full_payload" | cut -d'|' -f4)

                local display="${app^}"
                [[ $app != "$sub" && -n $sub ]] && display="$display ${MUTE}($sub)${RESET}"
                [[ $is_fs == "1" || $is_fs == "2" || $is_fs == "true" ]] && display="$display ${PINK}[FS]${RESET}"

                if [[ -z ${ws_groups[$ws]} ]]; then
                    ws_groups[$ws]="$display"
                else
                    ws_groups[$ws]="${ws_groups[$ws]}, $display"
                fi
            done

            local sorted_workspaces=$(for k in "${!ws_groups[@]}"; do echo "$k"; done | sort -n)

            for ws in $sorted_workspaces; do
                printf " ${PINK}󰄾${RESET} %-18s %b\n" "Workspace $ws:" "${ws_groups[$ws]}"
            done

            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────${RESET}\n"
            ;;

        *)
            rx_log "info" "Usage: retro window <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "fullscreen" "Toggle fullscreen on active window"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "save" "Capture current workspace layout"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "restore" "Rebuild workspace from saved layout"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "clear" "Delete saved session state"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "toggle-autosave" "Toggle session autosave"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show saved session snapshot"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "window" "Window manager utilities and rules" "cmd_wm"
