#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
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

                    while IFS='|' read -r name path exists; do
                        [[ -z $name ]] && continue
                        local icon="󰉍"
                        local color="$PINK"
                        if [[ $exists == "no" ]]; then
                            icon="󰱼"
                            color="$WARN"
                            ((missing++))
                        fi
                        ((dir_count++))

                        local display_name=$(echo "$name" | sed 's/^[A-Z_]*//; s/_/ /g' | xargs)
                        [[ -z $display_name ]] && display_name="$name"

                        rx_table_row "$icon" "${display_name^}:" "$path" "$color" "14"
                    done < <(bash "$xdg_script" --list-dirs 2>/dev/null)

                    rx_table_header "󰉋" "XDG User Directories"
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
                    while IFS='|' read -r mime desktop app_name; do
                        [[ -z $mime ]] && continue
                        ((count++))
                        local mime_display=$(echo "$mime" | sed 's/x-scheme-handler/URL/' | sed 's/application\/x-/app:/' | sed 's/inode\/dir/Dir/')
                        rx_table_row "󰈔" "$mime_display:" "$app_name" "$PINK" "22"
                    done < <(bash "$xdg_script" --list-defaults 2>/dev/null)

                    rx_table_header "󰈔" "Default Applications"
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
            while IFS='|' read -r desktop name path; do
                [[ -z $desktop ]] && continue
                ((found++))
                rx_table_row "󰏔" "$name:" "$desktop" "$PINK" "22"
            done < <(bash "$xdg_script" --find-handlers "$mime" 2>/dev/null)

            rx_table_header "󰏔" "Handlers for: $mime"
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

                    local portal_count=0
                    while IFS='|' read -r name installed pg_running; do
                        [[ -z $name ]] && continue
                        ((portal_count++))
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
                    rx_log "info" "Available backends: ${PINK}hyprland${RESET}, ${PINK}gtk${RESET}, ${PINK}kde${RESET}, ${PINK}wlroots${RESET}"
                    rx_log "info" "Switch: ${PINK}retro xdg portal set <backend>${RESET}"
                    ;;
                "set")
                    local backend="${1,,}"
                    [[ -z $backend ]] && rx_log "error" "Provide a backend name (hyprland, gtk, kde, wlroots)" && return 1

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
                "list")
                    while IFS='|' read -r name installed pg_running; do
                        [[ -z $name ]] && continue
                        local status="not installed"
                        [[ $installed == "yes" ]] && status="installed"
                        [[ $pg_running == "yes" ]] && status="running"
                        echo "$name: $status"
                    done < <(bash "$xdg_script" --portal-list 2>/dev/null)
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

            local dirs_color="$PINK"
            [[ $dir_missing -gt 0 ]] && dirs_color="$WARN"

            local portal_color="$PINK"
            [[ $portal_backend == "none" ]] && portal_color="$WARN"
            [[ $portal_running == "no" ]] && portal_color="$WARN"

            rx_table_header "󰉋" "XDG Status"
            rx_table_row "󰉍" "Directories:" "$dir_count configured ($dir_missing missing)" "$dirs_color" "16"
            rx_table_row "󰈔" "Defaults:" "$default_count associations" "$PINK" "16"
            rx_table_row "󰂕" "Portal:" "${portal_backend^} (${portal_running})" "$portal_color" "16"
            rx_table_separator
            rx_table_spacer
            ;;

        *)
            rx_help_usage "retro xdg <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "dirs [list|set|reset]" "Manage XDG user directories"
            rx_help_cmd "defaults [list|set|reset]" "Manage default applications"
            rx_help_cmd "handlers <mime>" "Find apps that handle a MIME type"
            rx_help_cmd "portal [status|set|list]" "Manage XDG portal backend"
            rx_help_cmd "xdg-open" "Configure xdg-open for Hyprland"
            rx_help_cmd "status" "Show full XDG status"
            rx_help_examples
            rx_help_example "retro xdg dirs" "List XDG directories"
            rx_help_example "retro xdg dirs set downloads ~/dl" "Change downloads dir"
            rx_help_example "retro xdg defaults reset" "Regenerate defaults from settings"
            rx_help_example "retro xdg handlers image/png" "Find image viewers"
            rx_help_example "retro xdg portal set gtk" "Switch to GTK portal"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "xdg" "Manage XDG directories, defaults, and portals" "cmd_xdg"
