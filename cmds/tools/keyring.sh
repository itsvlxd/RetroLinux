#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_keyring() {
    local action="${1,,}"
    shift
    local core="$RETRO_DIR/scripts/keyring_core.sh"

    case "$action" in
        "status")
            local data
            data=$(bash "$core" --status 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "Failed to get keyring status" && return 1

            local service_gk pam_auth
            local keyring_state item_count pam_file

            while IFS='=' read -r key val; do
                case "$key" in
                    service_gnome_keyring) service_gk="$val" ;;
                    pam_auth) pam_auth="$val" ;;
                    keyring_state) keyring_state="$val" ;;
                    item_count) item_count="$val" ;;
                    pam_file) pam_file="$val" ;;
                esac
            done <<<"$data"

            local gk_color="$MUTE"
            [[ $service_gk == "active" ]] && gk_color="$SUCCESS"

            local gk_status="${service_gk^}"
            [[ $service_gk == "active" ]] && gk_status="● Active" || gk_status="○ Inactive"

            local pam_auth_display="${pam_auth^}"
            local pam_auth_color="$MUTE"
            [[ $pam_auth == "configured" ]] && pam_auth_color="$SUCCESS"

            local vault_color="$MUTE"
            local vault_display="${keyring_state^}"
            [[ $keyring_state == "unlocked" ]] && vault_color="$SUCCESS" && vault_display="● Unlocked"
            [[ $keyring_state == "locked" ]] && vault_color="$WARN" && vault_display="○ Locked"

            rx_table_header "󰒓" "Keyring Infrastructure Status"
            rx_table_row "󰒋" "GNOME Keyring:" "$gk_status" "$gk_color" "24"
            rx_table_row "󱂷" "PAM Module:" "${pam_auth_display} (${pam_file})" "$pam_auth_color" "24"
            rx_table_row "󰌊" "Vault State:" "$vault_display" "$vault_color" "24"
            rx_table_row "󰋚" "Stored Credentials:" "${item_count} items" "$GRAY" "24"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "$@"

            local config_exists=false
            local status_data
            status_data=$(bash "$core" --status 2>/dev/null)
            local current_service_gk current_pam_auth
            while IFS='=' read -r key val; do
                case "$key" in
                    service_gnome_keyring) current_service_gk="$val" ;;
                    pam_auth) current_pam_auth="$val" ;;
                esac
            done <<<"$status_data"

            [[ $current_service_gk == "active" || $current_pam_auth == "configured" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                check_dep "gnome-keyring-daemon" "gnome-keyring" || return 1
                check_dep "secret-tool" "libsecret" || return 1

                systemctl --user enable --now gnome-keyring-daemon.service 2>&1 | tail -3

                bash "$core" --pam-configure 2>/dev/null || rx_log "warn" "PAM configuration failed"
            else
                if [[ $config_exists == true ]]; then
                    local gk_display="${current_service_gk^}"
                    [[ $current_service_gk == "active" ]] && gk_display="Active" || gk_display="Inactive"
                    local pam_display="${current_pam_auth^}"

                    rx_setup_current "󰒓" "Current Keyring Configuration" \
                        "Service" "$gk_display" \
                        "PAM" "$pam_display" || true

                    if ! rx_confirm "Reconfigure?" "N"; then
                        rx_log "info" "Setup cancelled."
                        return 0
                    fi
                fi

                rx_log "info" "Installing GNOME Keyring and libsecret..."
                check_dep "gnome-keyring-daemon" "gnome-keyring" || return 1
                check_dep "secret-tool" "libsecret" || return 1

                rx_log "info" "Enabling keyring services..."
                systemctl --user enable --now gnome-keyring-daemon.service 2>&1 | tail -3

                local dm_pam_file=$(bash "$core" --pam-status 2>/dev/null | grep "^pam_file=" | cut -d= -f2-)
                if grep -q "pam_gnome_keyring.so" "$dm_pam_file" 2>/dev/null; then
                    rx_log "success" "PAM auto-unlock already configured ($dm_pam_file)"
                else
                    if rx_confirm "Configure PAM auto-unlock for seamless keyring login?" "Y"; then
                        if bash "$core" --pam-configure >/dev/null 2>&1; then
                            rx_log "success" "PAM auto-unlock configured ($dm_pam_file)"
                        else
                            rx_log "warn" "PAM configuration failed - you may see unlock prompts on next login"
                        fi
                    fi
                fi

                local result_data
                result_data=$(bash "$core" --status 2>/dev/null)
                local result_pam result_gk result_state result_count
                while IFS='=' read -r key val; do
                    case "$key" in
                        service_gnome_keyring) result_gk="$val" ;;
                        pam_auth) result_pam="$val" ;;
                        keyring_state) result_state="$val" ;;
                        item_count) result_count="$val" ;;
                    esac
                done <<<"$result_data"

                rx_setup_summary "󰒓" "Keyring Setup Summary" \
                    "GNOME Keyring" "${result_gk^}" \
                    "PAM" "${result_pam^}" \
                    "Vault" "${result_state^}" \
                    "Items" "${result_count} stored"

                rx_setup_confirm || return 0

                rx_setup_success "󰒓" "Keyring Configured" \
                    "GNOME Keyring" "${result_gk^}" \
                    "PAM" "${result_pam^}" \
                    "Vault" "${result_state^}" \
                    "Items" "${result_count} stored"
            fi
            ;;

        "lock")
            local result
            result=$(bash "$core" --lock 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Keyring locked"
            else
                rx_log "error" "Failed to lock keyring"
                return 1
            fi
            ;;

        "unlock")
            local result
            result=$(bash "$core" --unlock 2>/dev/null)

            if echo "$result" | grep -q "^OK|unlocked"; then
                rx_log "success" "Keyring unlocked"
            else
                rx_log "error" "Failed to unlock keyring (try logging in via your display manager)"
                return 1
            fi
            ;;

        "list")
            local data
            data=$(bash "$core" --list 2>/dev/null)
            if [[ -z $data ]]; then
                rx_log "info" "No credentials stored in keyring"
                return 0
            fi

            rx_table_header "🔐" "Stored Credentials"

            local count=0
            local current_label=""
            local current_attrs=""
            local in_entry=false

            while IFS= read -r line; do
                if [[ $line =~ ^\[/[0-9]+\] ]]; then
                    if [[ -n $current_label ]]; then
                        ((count++))
                        rx_table_row "🔑" "$current_label" "$current_attrs" "$GRAY" "36"
                    fi
                    current_label=""
                    current_attrs=""
                    in_entry=true
                elif [[ $in_entry == true && $line =~ ^label[[:space:]]*=[[:space:]]*(.*) ]]; then
                    current_label="${BASH_REMATCH[1]}"
                elif [[ $in_entry == true && $line =~ ^attribute\.([^[:space:]=]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
                    local attr_key="${BASH_REMATCH[1]}"
                    local attr_val="${BASH_REMATCH[2]}"
                    if [[ -n $current_attrs ]]; then
                        current_attrs="${current_attrs}, "
                    fi
                    current_attrs="${current_attrs}${attr_key}=${attr_val}"
                fi
            done <<<"$data"
            if [[ -n $current_label ]]; then
                ((count++))
                rx_table_row "🔑" "$current_label" "$current_attrs" "$GRAY" "36"
            fi

            rx_table_separator
            rx_table_row "" "Total:" "${count} credentials" "$PINK" "36"
            rx_table_spacer
            ;;

        "store")
            if [[ -z $1 ]]; then
                rx_log "info" "Usage: retro keyring store <label> [options]"
                rx_log "info" "  -a key=val    Custom attribute (can be specified multiple times)"
                rx_log "info" ""
                rx_log "info" "If no secret is provided via stdin, you'll be prompted."
                return 1
            fi

            local label="$1"
            shift
            local attrs=()

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -a)
                        attrs+=("$1" "$2")
                        shift 2
                        ;;
                    *)
                        rx_log "error" "Unknown option: $1"
                        return 1
                        ;;
                esac
            done

            if [[ -p /dev/stdin ]]; then
                if ! bash "$core" --store "$label" "${attrs[@]}" 2>/dev/null; then
                    rx_log "error" "Failed to store credential"
                    return 1
                fi
            else
                rx_log "info" "Enter the secret to store:"
                read -rs secret
                echo
                if ! echo -n "$secret" | bash "$core" --store "$label" "${attrs[@]}" 2>/dev/null; then
                    unset secret
                    rx_log "error" "Failed to store credential"
                    return 1
                fi
                unset secret
            fi
            rx_log "success" "Credential stored: ${PINK}${label}${RESET}"
            ;;

        "retrieve")
            if [[ -z $1 || -z $2 ]]; then
                rx_log "error" "Usage: retro keyring retrieve <attribute> <value> [--show]"
                return 1
            fi

            local attr="$1"
            local value="$2"
            local show_flag="${3,,}"

            local secret
            secret=$(bash "$core" --retrieve "$attr" "$value" 2>/dev/null) || true

            if [[ -z $secret || $secret == result=error* ]]; then
                rx_log "error" "Credential not found: ${attr}=${value}"
                return 1
            fi

            if [[ $show_flag == "--show" ]]; then
                echo "$secret"
                rx_log "warn" "Credential displayed in terminal - clear your scroll buffer"
            else
                check_dep "wl-copy" "wl-clipboard" || return 1
                echo -n "$secret" | wl-copy --sensitive
                rx_log "success" "Credential copied to clipboard (will clear in 30s)"
                rx_log "info" "Use --show to print to stdout instead"

                (sleep 30 && wl-copy -c 2>/dev/null) &>/dev/null &
            fi
            unset secret
            ;;

        "delete")
            if [[ -z $1 || -z $2 ]]; then
                rx_log "error" "Usage: retro keyring delete <attribute> <value>"
                return 1
            fi

            local attr="$1"
            local value="$2"

            if ! rx_confirm "Delete credential '${attr}=${value}' from keyring?" "N"; then
                rx_log "info" "Canceled."
                return 0
            fi

            local result
            result=$(bash "$core" --delete "$attr" "$value" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Credential deleted: ${attr}=${value}"
            else
                rx_log "error" "Failed to delete credential"
                return 1
            fi
            ;;

        "password")
            if ! command -v seahorse &>/dev/null; then
                rx_log "error" "seahorse is not installed — install it with your package manager"
                return 1
            fi
            (seahorse &>/dev/null &)
            rx_log "success" "Launching seahorse — navigate to Login keyring > Change Password"
            ;;

        "help" | "")
            rx_help_usage "retro keyring <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show keyring services, PAM, and vault status" 24
            rx_help_cmd "setup" "Run keyring setup wizard (PAM + install)" 24
            rx_help_cmd "lock" "Lock the keyring" 24
            rx_help_cmd "unlock" "Unlock the keyring" 24
            rx_help_cmd "list" "List stored credentials" 24
            rx_help_cmd "store <label>" "Store a new credential (pipe stdin or prompt)" 24
            rx_help_cmd "retrieve <attr> <val>" "Copy credential to clipboard (--show for stdout)" 24
            rx_help_cmd "delete <attr> <val>" "Remove a credential" 24
            rx_help_cmd "password" "Change keyring master password" 24
            rx_help_examples
            rx_help_example "retro keyring status" "Show full keyring status" "38"
            rx_help_example "retro keyring setup" "Run interactive setup wizard" "38"
            rx_help_example "retro keyring store MyApp -a user=bob" "Store a secret with label and attribute" "38"
            rx_help_example "retro keyring list" "List all stored credentials" "38"
            rx_help_example "retro keyring retrieve user bob" "Copy bob's password to clipboard" "38"
            rx_help_example "echo pass123 | retro keyring store API" "Store from stdin" "38"
            rx_help_example "retro keyring setup -o --needed" "Non-interactive setup" "38"
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "keyring" "GNOME Keyring management, PAM config, and secret storage" "cmd_keyring"
