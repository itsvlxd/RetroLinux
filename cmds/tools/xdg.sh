#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/setup.sh"
source "$RETRO_DIR/lib/xdg.sh"

cmd_xdg() {
    local xdg_script="$RETRO_DIR/scripts/xdg_core.sh"
    local action="${1,,}"
    shift 2>/dev/null || true

    case "$action" in
        "dirs")
            local sub="${1:-list}"
            shift 2>/dev/null || true

            case "$sub" in
                "list"|"")
                    local dir_count=0
                    local missing=0
                    declare -a d_names d_paths d_exists

                    while IFS='|' read -r name path exists; do
                        [[ -z $name ]] && continue
                        d_names+=("$name")
                        d_paths+=("$path")
                        d_exists+=("$exists")
                        ((dir_count++))
                        [[ $exists == "no" ]] && ((missing++))
                    done < <(bash "$xdg_script" --list-dirs 2>/dev/null)

                    rx_table_header "󰉋" "XDG User Directories"
                    for i in "${!d_names[@]}"; do
                        local display_name=$(echo "${d_names[$i]}" | sed 's/^[A-Z_]*//; s/_/ /g' | xargs)
                        [[ -z $display_name ]] && display_name="${d_names[$i]}"
                        local icon="󰉍"
                        local color="$PINK"
                        if [[ ${d_exists[$i]} == "no" ]]; then
                            icon="󰱼"
                            color="$WARN"
                        fi
                        rx_table_row "$icon" "${display_name^}:" "${d_paths[$i]}" "$color" "14"
                    done
                    rx_table_separator
                    rx_table_spacer
                    [[ $missing -gt 0 ]] && rx_log "warn" "$missing director${missing}y/ies missing on disk"
                    ;;
                "set")
                    local name="${1^^}"
                    local path="$2"
                    [[ -z $name || -z $path ]] && rx_log "error" "Usage: retro xdg dirs set <name> <path>" && return 1

                    local result=$(bash "$xdg_script" --set-dir "$name" "$path" 2>&1)
                    if echo "$result" | grep -q "^OK|"; then
                        local resolved=$(echo "$result" | sed 's/^OK|//')
                        rx_log "success" "${name^} directory set to: ${PINK}$resolved${RESET}"
                    else
                        rx_log "error" "Failed to set directory."
                        return 1
                    fi
                    ;;
                "reset")
                    bash "$xdg_script" --ensure-dirs >/dev/null 2>&1
                    rx_log "success" "XDG directories reset to defaults"
                    ;;
                *)
                    rx_log "error" "Unknown dirs action: $sub"
                    return 1
                    ;;
            esac
            ;;

        "defaults")
            local sub="${1:-list}"
            shift 2>/dev/null || true

            case "$sub" in
                "list"|"")
                    local count=0
                    declare -a d_mimes d_apps

                    while IFS='|' read -r mime desktop app_name; do
                        [[ -z $mime ]] && continue
                        d_mimes+=("$mime")
                        d_apps+=("$app_name")
                        ((count++))
                    done < <(bash "$xdg_script" --list-defaults 2>/dev/null)

                    rx_table_header "󰈔" "Default Applications"
                    for i in "${!d_mimes[@]}"; do
                        rx_table_row "󰈔" "${d_mimes[$i]}:" "${d_apps[$i]}" "$PINK" "28"
                    done
                    rx_table_separator
                    rx_table_spacer
                    [[ $count -eq 0 ]] && rx_log "info" "No default applications configured. Run ${PINK}retro xdg defaults reset${RESET}"
                    ;;
                "set")
                    local mime="$1"
                    local app="$2"
                    [[ -z $mime || -z $app ]] && rx_log "error" "Usage: retro xdg defaults set <mime> <app.desktop>" && return 1

                    [[ ! $app == *.desktop ]] && app="${app}.desktop"

                    local result=$(bash "$xdg_script" --set-default "$mime" "$app" 2>&1)
                    if echo "$result" | grep -q "^OK|"; then
                        rx_log "success" "Default set: ${PINK}$mime${RESET} → ${PINK}$app${RESET}"
                    elif echo "$result" | grep -q "desktop_file_not_found"; then
                        rx_log "error" "Desktop file not found: ${PINK}$app${RESET}"
                        return 1
                    else
                        rx_log "error" "Failed to set default."
                        return 1
                    fi
                    ;;
                "reset")
                    local result=$(bash "$xdg_script" --reset-defaults 2>&1)
                    if echo "$result" | grep -q "^OK|"; then
                        rx_log "success" "Default applications regenerated from current settings"
                    else
                        rx_log "error" "Failed to reset defaults."
                        return 1
                    fi
                    ;;
                *)
                    rx_log "error" "Unknown defaults action: $sub"
                    return 1
                    ;;
            esac
            ;;

        "handlers")
            local mime="$1"
            [[ -z $mime ]] && rx_log "error" "Provide a MIME type (e.g., image/png, text/plain, video/mp4)" && return 1

            local found=0
            declare -a h_names h_desktops

            while IFS='|' read -r desktop name path; do
                [[ -z $desktop ]] && continue
                h_names+=("$name")
                h_desktops+=("$desktop")
                ((found++))
            done < <(bash "$xdg_script" --find-handlers "$mime" 2>/dev/null)

            rx_table_header "󰏔" "Handlers for: $mime"
            for i in "${!h_names[@]}"; do
                rx_table_row "󰏔" "${h_names[$i]}:" "${h_desktops[$i]}" "$PINK" "22"
            done
            rx_table_separator
            rx_table_spacer
            [[ $found -eq 0 ]] && rx_log "warn" "No applications found for ${PINK}$mime${RESET}"
            ;;

        "portal")
            local sub="${1:-status}"
            shift 2>/dev/null || true

            case "$sub" in
                "status")
                    local portal_result=$(bash "$xdg_script" --portal-status)
                    local backend=$(echo "$portal_result" | grep -oP 'backend=\K[^|]+')
                    local running=$(echo "$portal_result" | grep -oP 'running=\K[^|]+')

                    : ${backend:="none"}
                    : ${running:="no"}

                    local backend_display="${backend^}"
                    local backend_color="$PINK"
                    [[ $backend == "none" ]] && backend_color="$WARN"

                    local running_display="No"
                    local running_color="$MUTE"
                    if [[ $running == "yes" ]]; then
                        running_display="Yes"
                        running_color="$PINK"
                    fi

                    rx_table_header "󰂕" "XDG Portal Status"
                    rx_table_row "󰂕" "Active Backend:" "$backend_display" "$backend_color" "16"
                    rx_table_row "󰓅" "Running:" "$running_display" "$running_color" "16"
                    rx_table_separator

                    while IFS='|' read -r name installed pg_running; do
                        [[ -z $name ]] && continue
                        local icon="󰱼"
                        local color="$MUTE"
                        local status="Not installed"
                        if [[ $installed == "yes" ]]; then
                            icon="󰄲"
                            color="$PINK"
                            status="Installed"
                            if [[ $pg_running == "yes" ]]; then
                                icon="󰄲"
                                color="$SUCCESS"
                                status="Running"
                            fi
                        fi
                        local is_active=""
                        [[ $name == "$backend" ]] && is_active=" ${GRAY}(active)${RESET}"
                        rx_table_row "$icon" "${name^}:" "${status}${is_active}" "$color" "16"
                    done < <(bash "$xdg_script" --portal-list 2>/dev/null)

                    rx_table_separator
                    rx_table_spacer
                    ;;
                "set")
                    local backend="${1,,}"
                    [[ -z $backend ]] && rx_log "error" "Provide a backend name (hyprland, gtk)" && return 1

                    local result=$(bash "$xdg_script" --portal-set "$backend" 2>&1)
                    if echo "$result" | grep -q "^OK|"; then
                        rx_log "success" "Portal backend set to: ${PINK}${backend^}${RESET}"
                        rx_log "info" "Restart your session for changes to take effect"
                    elif echo "$result" | grep -q "package_not_installed"; then
                        local pkg=$(echo "$result" | grep -oP 'package=\K[^|]+')
                        rx_log "error" "Package not installed: ${PINK}$pkg${RESET}"
                        rx_log "info" "Install with: ${PINK}sudo pacman -S $pkg${RESET}"
                        return 1
                    else
                        rx_log "error" "Failed to set portal backend."
                        return 1
                    fi
                    ;;
                "inject")
                    systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null

                    local backend=$(bash "$xdg_script" --portal-status 2>/dev/null | grep -oP 'backend=\K[^|]+')
                    : ${backend:="none"}

                    if [[ $backend != "none" ]]; then
                        systemctl --user restart --wait xdg-desktop-portal "xdg-desktop-portal-${backend}" 2>/dev/null
                        rx_log "success" "Session env injected, portal restarted (${backend^})"
                    else
                        systemctl --user restart --wait xdg-desktop-portal 2>/dev/null
                        rx_log "success" "Session env injected, base portal restarted"
                    fi
                    ;;
                *)
                    rx_log "error" "Unknown portal action: $sub"
                    return 1
                    ;;
            esac
            ;;

        "xdg-open")
            local result=$(bash "$xdg_script" --configure-xdg-open 2>&1)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "xdg-open wrapper configured for Hyprland"
                rx_log "info" "New terminals will use the wrapper automatically"
            else
                rx_log "error" "Failed to configure xdg-open."
                return 1
            fi
            ;;

        "flatpak")
            if ! command -v flatpak >/dev/null 2>&1; then
                rx_log "error" "Flatpak is not installed on this system"
                return 1
            fi
            local result=$(bash "$xdg_script" --bridge-flatpak 2>&1)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Host MIME defaults bridged into Flatpak sandbox"
                rx_log "info" "Flatpak apps will now respect your default application choices"
            else
                rx_log "error" "Failed to apply Flatpak MIME bridge."
                return 1
            fi
            ;;

        "status")
            local dir_count=0
            local dir_missing=0
            while IFS='|' read -r name path exists; do
                [[ -z $name ]] && continue
                ((dir_count++))
                [[ $exists == "no" ]] && ((dir_missing++))
            done < <(bash "$xdg_script" --list-dirs 2>/dev/null)

            local default_count=0
            while IFS='|' read -r mime desktop app; do
                [[ -z $mime ]] && continue
                ((default_count++))
            done < <(bash "$xdg_script" --list-defaults 2>/dev/null)

            local portal_result=$(bash "$xdg_script" --portal-status)
            local portal_backend=$(echo "$portal_result" | grep -oP 'backend=\K[^|]+')
            local portal_running=$(echo "$portal_result" | grep -oP 'running=\K[^|]+')

            : ${portal_backend:="none"}
            : ${portal_running:="no"}

            local health_result=$(bash "$xdg_script" --health 2>/dev/null)
            local ghost_desktop=$(echo "$health_result" | grep -oP 'ghost_desktop=\K[0-9]+')
            local ghost_binary=$(echo "$health_result" | grep -oP 'ghost_binary=\K[0-9]+')
            local health_total=$(echo "$health_result" | grep -oP 'total=\K[0-9]+')
            local health_valid=$(echo "$health_result" | grep -oP 'valid=\K[0-9]+')

            : ${ghost_desktop:=0}
            : ${ghost_binary:=0}
            : ${health_total:=0}
            : ${health_valid:=0}

            local dirs_color="$PINK"
            [[ $dir_missing -gt 0 ]] && dirs_color="$WARN"

            local portal_color="$PINK"
            [[ $portal_backend == "none" ]] && portal_color="$WARN"
            [[ $portal_running == "no" ]] && portal_color="$WARN"

            local health_color="$SUCCESS"
            local health_text="Healthy"
            if [[ $ghost_desktop -gt 0 || $ghost_binary -gt 0 ]]; then
                health_color="$WARN"
                health_text="Issues Found"
            fi

            rx_table_header "󰉋" "XDG Status"
            rx_table_row "󰉍" "Directories:" "$dir_count configured ($dir_missing missing)" "$dirs_color" "16"
            rx_table_row "󰈔" "Defaults:" "$default_count associations" "$PINK" "16"
            rx_table_row "󰂕" "Portal:" "${portal_backend^} (${portal_running})" "$portal_color" "16"
            rx_table_row "󰏗" "Handlers:" "$health_valid/$health_total valid" "$health_color" "16"
            if [[ $ghost_desktop -gt 0 ]]; then
                rx_table_row "󰱼" "Dead .desktop:" "$ghost_desktop" "$WARN" "16"
            fi
            if [[ $ghost_binary -gt 0 ]]; then
                rx_table_row "󰱼" "Dead binary:" "$ghost_binary" "$WARN" "16"
            fi
            rx_table_separator
            rx_table_spacer

            if [[ $ghost_desktop -gt 0 || $ghost_binary -gt 0 ]]; then
                rx_log "info" "Fix with: ${PINK}retro xdg defaults reset${RESET} or remove dead entries manually"
            fi
            ;;

        "query")
            local target="$1"
            [[ -z $target ]] && rx_log "error" "Provide a file path or extension (e.g., invoice.pdf, .mp4)" && return 1

            local result=$(bash "$xdg_script" --query "$target" 2>&1)
            if echo "$result" | grep -q "result=error"; then
                rx_log "error" "Could not determine MIME type for: ${PINK}$target${RESET}"
                return 1
            fi

            local file=$(echo "$result" | grep -oP 'file=\K[^|]+')
            local mime=$(echo "$result" | grep -oP 'mime=\K[^|]+')
            local default=$(echo "$result" | grep -oP 'default=\K[^|]+')
            local app_name=$(echo "$result" | grep -oP 'app_name=\K[^|]+')
            local handlers=$(echo "$result" | grep -oP 'handlers=\K[^|]+')

            : ${file:="$target"}
            : ${mime:="unknown"}
            : ${default:="none"}
            : ${app_name:="No default set"}
            : ${handlers:="0"}

            local default_color="$PINK"
            [[ $default == "none" ]] && default_color="$WARN"

            rx_table_header "󰈔" "File Association"
            rx_table_row "󰈔" "File:" "$file" "$PINK" "14"
            rx_table_row "󰓅" "MIME Type:" "$mime" "$PINK" "14"
            rx_table_row "󰏔" "Opens With:" "$app_name" "$default_color" "14"
            rx_table_row "󰏔" "Available:" "$handlers handler(s)" "$PINK" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        "autostart")
            local sub="${1:-list}"
            shift 2>/dev/null || true

            case "$sub" in
                "toggle"|"enable"|"disable")
                    local name="$1"
                    [[ -z $name ]] && rx_log "error" "Provide a .desktop file name (e.g., discord.desktop)" && return 1
                    [[ ! $name == *.desktop ]] && name="${name}.desktop"

                    local action="$sub"
                    [[ $action == "toggle" ]] && action="toggle"

                    local result=$(bash "$xdg_script" --autostart-toggle "$name" "$action" 2>&1)
                    if echo "$result" | grep -q "^OK|"; then
                        local state=$(echo "$result" | sed 's/^OK|//')
                        rx_log "success" "$name ${PINK}${state}${RESET}"
                    elif echo "$result" | grep -q "not_found"; then
                        rx_log "error" "Autostart entry not found: ${PINK}$name${RESET}"
                        return 1
                    else
                        rx_log "error" "Failed to toggle autostart."
                        return 1
                    fi
                    ;;
                "clean")
                    local result=$(bash "$xdg_script" --autostart-clean 2>&1)
                    local cleaned=$(echo "$result" | grep -oP 'cleaned=\K[0-9]+')
                    if [[ ${cleaned:-0} -gt 0 ]]; then
                        rx_log "success" "Removed ${PINK}$cleaned${RESET} broken autostart entries"
                    else
                        rx_log "info" "No broken autostart entries found"
                    fi
                    ;;
                *)
                    local total=0
                    local enabled_count=0
                    local broken=0
                    declare -a a_names a_enabled a_binary a_scope

                    while IFS='|' read -r name path enabled binary_exists scope; do
                        [[ -z $name ]] && continue
                        a_names+=("$name")
                        a_enabled+=("$enabled")
                        a_binary+=("$binary_exists")
                        a_scope+=("$scope")
                        ((total++))
                        [[ $enabled == "true" ]] && ((enabled_count++))
                        [[ $binary_exists == "no" ]] && ((broken++))
                    done < <(bash "$xdg_script" --autostart-list 2>/dev/null)

                    rx_table_header "󰀓" "Autostart Applications"
                    for i in "${!a_names[@]}"; do
                        local icon="󰄾"
                        local color="$PINK"
                        if [[ ${a_enabled[$i]} == "false" ]]; then
                            icon="󰄽"
                            color="$MUTE"
                        elif [[ ${a_binary[$i]} == "no" ]]; then
                            icon="󰱼"
                            color="$WARN"
                        fi

                        local scope_tag=""
                        [[ ${a_scope[$i]} == "user" ]] && scope_tag=" ${GRAY}(user)${RESET}"

                        rx_table_row "$icon" "${a_names[$i]}:" "$scope_tag" "$color" "28"
                    done
                    rx_table_separator
                    rx_table_spacer
                    [[ $broken -gt 0 ]] && rx_log "warn" "$broken entr${broken}y/ies point to missing binaries"
                    [[ $total -eq 0 ]] && rx_log "info" "No autostart entries found"
                    ;;
            esac
            ;;

        "setup")
            rx_setup_parse "$@"
            rx_setup_validate "editor,browser,filemanager,fm,image,video" || return 1

            local default_count=0
            while IFS='|' read -r mime desktop app; do
                [[ -z $mime ]] && continue
                ((default_count++))
            done < <(bash "$xdg_script" --list-defaults 2>/dev/null)
            local config_exists=false
            [[ $default_count -gt 0 ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            local editor_input=""
            local browser_input=""
            local fm_input=""
            local image_input=""
            local video_input=""

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                editor_input=$(rx_setup_get_opt "editor")
                browser_input=$(rx_setup_get_opt "browser")
                fm_input=$(rx_setup_get_opt "filemanager")
                [[ -z $fm_input ]] && fm_input=$(rx_setup_get_opt "fm")
                image_input=$(rx_setup_get_opt "image")
                video_input=$(rx_setup_get_opt "video")
            else
                local cur_editor=$(get_var "RETRO_EDITOR_CMD" "nvim")
                local cur_fm=$(get_var "RETRO_FILEMANAGER_CMD" "thunar")

                local detected_browser="firefox"
                for b in zen firefox chromium floorp; do
                    if rx_xdg_validate_desktop "${b}.desktop"; then
                        detected_browser="$b"
                        break
                    fi
                done

                local detected_image="loupe"
                rx_xdg_validate_desktop "loupe.desktop" || detected_image="viewnior"
                rx_xdg_validate_desktop "$detected_image.desktop" || detected_image="feh"

                local detected_video="mpv"

                if [[ $config_exists == true ]]; then
                    rx_setup_current "󱗼" "Current Default Applications" \
                        "Editor" "$cur_editor" \
                        "Browser" "$detected_browser" \
                        "File Manager" "$cur_fm" \
                        "Image Viewer" "$detected_image" \
                        "Video Player" "$detected_video" || true

                    if ! rx_confirm "Reconfigure?" "N"; then
                        rx_log "info" "Setup cancelled."
                        return 0
                    fi
                fi

                _rx_xdg_desktop_input() {
                    local icon="$1" label="$2" default="$3"
                    while true; do
                        local input
                        input=$(rx_input "$label" "$default")
                        local desktop
                        desktop=$(rx_xdg_resolve_desktop "$input")
                        if [[ -n $desktop ]]; then
                            echo "$input"
                            return 0
                        fi
                        rx_log "warn" "Desktop file not found: ${PINK}${input}${RESET}"
                        rx_log "info" "Try again or press Enter for default (${PINK}${default}${RESET})"
                    done
                }

                editor_input=$(_rx_xdg_desktop_input "󰓅" "What editor would you like to use?" "$cur_editor")
                browser_input=$(_rx_xdg_desktop_input "󰤨" "What browser would you like to use?" "$detected_browser")
                fm_input=$(_rx_xdg_desktop_input "󰉋" "What file manager would you like to use?" "$cur_fm")
                image_input=$(_rx_xdg_desktop_input "󰋩" "What image viewer would you like to use?" "$detected_image")
                video_input=$(_rx_xdg_desktop_input "󰎁" "What video player would you like to use?" "$detected_video")
            fi

            local editor_desktop=$(rx_xdg_resolve_desktop "$editor_input")
            local browser_desktop=$(rx_xdg_resolve_desktop "$browser_input")
            local fm_desktop=$(rx_xdg_resolve_desktop "$fm_input")
            local image_desktop=$(rx_xdg_resolve_desktop "$image_input")
            local video_desktop=$(rx_xdg_resolve_desktop "$video_input")

            local editor_count=45
            local browser_count=11
            local fm_count=4
            local image_count=13
            local video_count=11

            if [[ $RX_SETUP_MODE == "interactive" ]]; then
                rx_setup_summary "󰈔" "Summary" \
                    "Editor" "$editor_input (${editor_count} types)" \
                    "Browser" "$browser_input (${browser_count} types)" \
                    "File Manager" "$fm_input (${fm_count} types)" \
                    "Image Viewer" "$image_input (${image_count} types)" \
                    "Video Player" "$video_input (${video_count} types)" \
                    "Terminal" "kitty.desktop (1 type)"

                rx_setup_confirm || return 0
            fi

            bash "$xdg_script" --ensure-dirs >/dev/null 2>&1 || true

            local result=$(bash "$xdg_script" --setup "$editor_input" "$browser_input" "$fm_input" "$image_input" "$video_input" 2>&1)
            if echo "$result" | grep -q "^OK|"; then
                check_dep "xdg-terminal-exec" "xdg-terminal-exec" 2>/dev/null || true
                mkdir -p "$HOME/.config/xdg-terminal-exec" 2>/dev/null || true
                cat > "$HOME/.config/xdg-terminal-exec/config" 2>/dev/null << EOF || true
[General]
terminal=kitty.desktop
EOF
                if [[ -f $HOME/.config/xdg-terminal-exec/config ]]; then
                    rx_log "success" "Terminal executor configured (kitty)"
                else
                    rx_log "warn" "Could not write terminal executor config"
                fi

                rx_setup_success "󱗼" "XDG Defaults Configured" \
                    "Editor" "$editor_desktop (${editor_count} types)" \
                    "Browser" "$browser_desktop (${browser_count} types)" \
                    "File Manager" "$fm_desktop (${fm_count} types)" \
                    "Image Viewer" "$image_desktop (${image_count} types)" \
                    "Video Player" "$video_desktop (${video_count} types)" \
                    "Terminal" "kitty.desktop (1 type)"
            else
                rx_log "error" "Failed to configure XDG defaults."
                return 1
            fi
            ;;

        *)
            rx_help_usage "retro xdg <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "dirs [list|set|reset]" "Manage XDG user directories" "40"
            rx_help_cmd "defaults [list|set|reset]" "Manage default applications" "40"
            rx_help_cmd "handlers <mime>" "Find apps that handle a MIME type" "40"
            rx_help_cmd "portal [status|set|inject]" "Manage XDG portal backend" "40"
            rx_help_cmd "xdg-open" "Configure xdg-open for Hyprland" "40"
            rx_help_cmd "flatpak" "Bridge host defaults into Flatpak sandbox" "40"
            rx_help_cmd "query <file|ext>" "Reverse lookup: find app for a file or extension" "40"
            rx_help_cmd "autostart [toggle|clean]" "Manage XDG autostart entries" "40"
            rx_help_cmd "setup [-o options]" "Interactive or scripted XDG default configuration" "40"
            rx_help_cmd "status" "Show full XDG status with health metrics" "40"
            rx_help_examples
            rx_help_example "retro xdg dirs" "List XDG directories" "38"
            rx_help_example "retro xdg dirs set downloads ~/dl" "Change downloads dir" "38"
            rx_help_example "retro xdg defaults reset" "Regenerate defaults from settings" "38"
            rx_help_example "retro xdg handlers image/png" "Find image viewers" "38"
            rx_help_example "retro xdg portal set gtk" "Switch to GTK portal" "38"
            rx_help_example "retro xdg flatpak" "Bridge defaults to Flatpak" "38"
            rx_help_example "retro xdg query invoice.pdf" "Find what opens PDFs" "38"
            rx_help_example "retro xdg autostart disable discord.desktop" "Disable Discord autostart" "38"
            rx_help_example "retro xdg setup" "Interactive configuration wizard" "38"
            rx_help_example "retro xdg setup -o editor=nvim,browser=zen,filemanager=thunar,image=loupe,video=mpv" "Non-interactive setup" "38"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "xdg" "Manage XDG directories, defaults, and portals" "cmd_xdg"
