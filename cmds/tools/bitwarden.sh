#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_bw() {
    local action="${1,,}"
    local val1="$2"
    local val2="$3"

    local is_enabled=$(get_var "CLIP_BITWARDEN")
    [[ $is_enabled != "true" && $action != "setup" ]] && return 0

    case "$action" in
        "sync")
            rx_log "info" "Pulling data from Bitwarden server..."
            rbw sync && rx_log "success" "Vault database synchronized." || rx_log "error" "Sync failed."
            ;;

        "lock")
            rx_log "info" "Locking Bitwarden vault..."
            rbw lock && rx_log "success" "Vault secured."
            ;;

        "unlock")
            rx_log "info" "Unlocking Bitwarden database..."
            rbw unlock && rx_log "success" "Vault unlocked."
            ;;

        "status")
            local is_unlocked=$(rbw unlocked 2>/dev/null && echo "UNLOCKED" || echo "LOCKED")
            local status_color="$ERROR"
            local total_items="${MUTE}Locked${RESET}"

            if [[ $is_unlocked == "UNLOCKED" ]]; then
                status_color="$SUCCESS"
                total_items=$(rbw list | wc -l)
            fi

            local email=$(rbw config show | grep "email" | awk -F'"' '{print $4}')
            local vault_url=$(rbw config show | grep "base_url" | awk -F'"' '{print $4}')
            local identity_url=$(rbw config show | grep "identity_url" | awk -F'"' '{print $4}')

            local sync_rate=$(get_var "CLIP_WARDEN_SYNC")
            local lock_timer=$(get_var "CLIP_WARDEN_TIMEOUT")
            local wipe_timer=$(get_var "CLIP_WARDEN_DESTRUCT")

            local encoded_url=$(echo "$vault_url" | sed 's/:/%3A/g; s/\//%2F/g')
            local db_path="$HOME/.cache/rbw/${encoded_url}:${email}.json"

            local db_size_raw=0
            local last_sync="Never"

            if [[ -f $db_path ]]; then
                db_size_raw=$(stat -c %s "$db_path")
                last_sync=$(date -d "@$(stat -c %Y "$db_path")" "+%d %b %Y - %H:%M")
            fi

            rx_table_header "" "Bitwarden Status"
            rx_table_row "󰇮" "Active Account:" "$email" "$PINK" "18"
            rx_table_row "󰆟" "Vault Server:" "${vault_url:-None}" "$PINK" "18"
            rx_table_row "󰒋" "Identity Server:" "${identity_url:-None}" "$PINK" "18"

            rx_table_separator

            rx_table_row "󰌾" "Vault State:" "$is_unlocked" "$status_color" "18"
            rx_table_row "󰔛" "Auto-Lock:" "$(rx_format_time "$lock_timer")" "$PINK" "18"
            rx_table_row "󰃢" "Clipboard Wipe:" "$(rx_format_time "$wipe_timer")" "$PINK" "18"
            rx_table_row "󱍸" "Sync Interval:" "Every $(rx_format_time "$sync_rate")" "$PINK" "18"

            rx_table_separator

            rx_table_row_gray "󰄨" "Vault Entries:" "$total_items" "18"
            rx_table_row_gray "󰋊" "Cache Size:" "$(rx_format_size "$db_size_raw")" "18"
            rx_table_row_gray "󰄭" "Last Synchronized:" "$last_sync" "18"

            rx_table_separator
            rx_table_spacer
            ;;

        "list")
            if ! rbw unlocked 2>/dev/null; then
                rbw unlock || return 1
            fi

            rx_table_header "" "Bitwarden Vault Index"

            rbw list --fields type,name,user | sort -k2,2 | while IFS=$'\t' read -r type name user; do
                [[ -z $user || $user == "null" ]] && user=""

                local match_name="${name,,}"
                local icon=" "

                if [[ $type == "card" ]]; then
                    icon=" "
                elif [[ $type == "note" ]]; then
                    icon=" "
                elif [[ $type == "identity" ]]; then
                    icon="󰇮 "
                else
                    case "$match_name" in
                        *google* | *workspace*) icon=" " ;;
                        *discord*) icon=" " ;;
                        *github* | *gh*) icon=" " ;;
                        *proton*) icon="󰆦 " ;;
                        *binance*) icon=" " ;;
                        *cloudflare*) icon=" " ;;
                        *steam*) icon="󰓓 " ;;
                        *twitch*) icon=" " ;;
                        *spotify*) icon=" " ;;
                        *whatsapp*) icon="󰖣 " ;;
                        *x.com* | *twitter*) icon="󰕄 " ;;
                        *3cx* | *telnyx*) icon=" " ;;
                        *hpe*) icon=" " ;;
                        *ebay*) icon=" " ;;
                        *paypal*) icon=" " ;;
                        *firefox*) icon="󰈹 " ;;
                        *bitwarden*) icon=" " ;;
                        *huggingface*) icon=" " ;;
                        *localhost* | *127.0.0.1*) icon="󰒋 " ;;
                    esac
                fi

                if [[ -n $user && $user != "null" && $user != "no-user" ]]; then
                    printf " ${PINK}%b ${RESET}%-35s %s${RESET}\n" "$icon" "$name:" "$user"
                else
                    printf " ${PINK}%b ${RESET}%s\n" "$icon" "$name"
                fi
            done

            rx_table_separator
            rx_table_spacer
            ;;

        "get")
            [[ -z $val1 ]] && rx_log "error" "Please provide an entry name." && return 1
            rbw unlocked || rbw unlock || return 1

            rx_log "info" "Fetching credentials: ${PINK}$val1${RESET}..."
            local pass=$(rbw get "$val1" 2>/dev/null)

            if [[ -n $pass ]]; then
                echo "$pass" | wl-copy
                local ttl=$(get_var "CLIP_WARDEN_DESTRUCT")
                : ${ttl:=15}

                rx_log "success" "Password copied to buffer."
                rx_log "warn" "Destruct active: Clipboard wipe in ${PINK}$ttl${RESET} seconds."
                (sleep "$ttl" && wl-copy --clear) &
            else
                rx_log "error" "Entry not found."
            fi
            ;;

        "code" | "totp")
            [[ -z $val1 ]] && rx_log "error" "Please provide an entry name." && return 1
            rbw unlocked || rbw unlock || return 1

            local otp=$(rbw code "$val1" 2>/dev/null)
            if [[ -n $otp ]]; then
                echo "$otp" | wl-copy
                rx_log "success" "TOTP code copied to buffer."
            else
                rx_log "error" "No authenticator code found for this entry."
            fi
            ;;

        "add")
            [[ -z $val1 ]] && rx_log "error" "Usage: retro bitwarden add <NAME> [USER]" && return 1
            rbw unlocked || rbw unlock || return 1

            rx_log "info" "Interactive entry creation: ${PINK}$val1${RESET}..."
            rbw add "$val1" "$val2" && rx_log "success" "Entry saved." && rbw sync
            ;;

        "edit")
            [[ -z $val1 ]] && rx_log "error" "Please provide an entry name to edit." && return 1
            rbw unlocked || rbw unlock || return 1

            rbw edit "$val1" && rx_log "success" "Entry updated." && rbw sync
            ;;

        "del")
            [[ -z $val1 ]] && rx_log "error" "Please provide an entry name to remove." && return 1
            rbw unlocked || rbw unlock || return 1

            rx_log "info" "Removing: ${PINK}$val1${RESET}..."
            rbw remove "$val1" && rx_log "success" "Entry deleted." && rbw sync
            ;;

        "reset")
            rx_log "warn" "Purging local data and disabling integration."
            rx_confirm "Confirm reset?" "N" || { rx_log "info" "Aborted."; return 0; }

            rbw purge
            set_var "CLIP_BITWARDEN"
            set_var "CLIP_WARDEN_SERVER"

            rbw stop-agent
            rm -rf ~/.cache/rbw

            rx_log "success" "Bitwarden integration reset."
            ;;
        "setup")
            rx_setup_parse "$@"

            local config_exists=false
            [[ $(get_var "CLIP_BITWARDEN") == "true" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            if [[ $config_exists == true ]]; then
                local cur_vault=$(get_var "CLIP_WARDEN_SERVER")
                local cur_sync=$(get_var "CLIP_WARDEN_SYNC" "1800")
                local cur_timeout=$(get_var "CLIP_WARDEN_TIMEOUT" "900")
                local cur_destruct=$(get_var "CLIP_WARDEN_DESTRUCT" "30")

                local cur_email=$(rbw config show | grep "email" | awk -F'"' '{print $4}')
                rx_setup_current "" "Current Bitwarden Configuration" \
                    "Vault" "$cur_vault" \
                    "Email" "$cur_email" \
                    "Sync" "${cur_sync}s" \
                    "Lock" "${cur_timeout}s" \
                    "Wipe" "${cur_destruct}s" || true

                if ! rx_confirm "Reconfigure?" "N"; then
                    rx_log "info" "Setup cancelled."
                    return 0
                fi
            fi

            mkdir -p ~/.cache/rbw

            rx_help_header "" "Bitwarden Setup Instructions"
            echo -e " ${PINK}1.${RESET} Open the API Settings directly: "
            echo -e "     ${PINK}https://vault.bitwarden.com/#/settings/security/security-keys${RESET}"
            echo -e " ${PINK}2.${RESET} Scroll down to the ${PINK}API KEY${RESET} section."
            echo -e " ${PINK}3.${RESET} View and copy your ${PINK}Client ID${RESET} and ${PINK}Client Secret${RESET}."
            rx_help_separator
            rx_help_spacer

            [[ "$SKIP_PROMPT" == "true" ]] || rx_confirm "Do you have your keys and wish to continue?" "Y" || return 0

            rx_log "info" "Bitwarden server selection"
            local srv_options=("Global (.com)" "Europe (.eu)" "Custom / Self-Hosted")
            local srv_choice=$(rx_menu "" "Which Bitwarden instance?" "${srv_options[@]}")

            case "$srv_choice" in
                "Global (.com)")
                    rbw config set base_url "https://vault.bitwarden.com"
                    rbw config set identity_url "https://identity.bitwarden.com"
                    ;;
                "Europe (.eu)")
                    rbw config set base_url "https://api.bitwarden.eu"
                    rbw config set identity_url "https://identity.bitwarden.eu"
                    ;;
                "Custom / Self-Hosted")
                    local custom_vault=$(rx_input "Custom Vault URL" "https://vault.example.com")
                    local custom_identity=$(rx_input "Custom Identity URL" "https://identity.example.com")
                    rbw config set base_url "$custom_vault"
                    rbw config set identity_url "$custom_identity"
                    ;;
            esac

            local current_vault=$(rbw config show | grep "base_url" | awk -F'"' '{print $4}')
            set_var "CLIP_WARDEN_SERVER" "$current_vault"

            local bw_email=""
            if [[ "$SKIP_PROMPT" == "true" ]]; then
                bw_email=$(rbw config show | grep "email" | awk -F'"' '{print $4}')
            else
                rx_log "info" "Email configuration"
                bw_email=$(rx_input "Enter your Bitwarden account email" "")
                [[ -n $bw_email ]] && rbw config set email "$bw_email"
            fi

            rx_log "info" "Launching registration. Follow the terminal prompts:"

            if rbw register; then
                set_var "CLIP_BITWARDEN" "true"

                if [[ "$SKIP_PROMPT" == "true" ]]; then
                    local val_sync=1800 val_timeout=900 val_destruct=30
                    rx_log "info" "Using defaults: sync=${val_sync}s, lock=${val_timeout}s, wipe=${val_destruct}s"
                else
                    rx_log "info" "Timer configuration"
                    local val_sync=$(rx_input_numeric "Sync interval (seconds)" "1800")
                    local val_timeout=$(rx_input_numeric "Lock timeout (seconds)" "900")
                    local val_destruct=$(rx_input_numeric "Clipboard destruct (seconds)" "30")
                fi
                rbw config set sync_interval "$val_sync"
                set_var "CLIP_WARDEN_SYNC" "$val_sync"
                rbw config set lock_timeout "$val_timeout"
                set_var "CLIP_WARDEN_TIMEOUT" "$val_timeout"
                set_var "CLIP_WARDEN_DESTRUCT" "$val_destruct"

                rx_setup_success "" "Bitwarden Configured" \
                    "Vault" "$current_vault" \
                    "Email" "$bw_email" \
                    "Sync" "${val_sync}s" \
                    "Lock" "${val_timeout}s" \
                    "Wipe" "${val_destruct}s"
            else
                rx_log "error" "Registration failed. Check your keys or server URLs."
                return 1
            fi
            ;;

        *)
            rx_help_usage "retro bitwarden <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "sync" "Sync vault with server"
            rx_help_cmd "lock" "Lock the vault"
            rx_help_cmd "unlock" "Unlock the vault"
            rx_help_cmd "status" "Show vault status and settings"
            rx_help_cmd "list" "List all vault entries"
            rx_help_cmd "get <entry>" "Copy password for an entry"
            rx_help_cmd "code <entry>" "Copy TOTP code for an entry"
            rx_help_cmd "add [name] [user]" "Create a new vault entry"
            rx_help_cmd "edit <entry>" "Edit an existing entry"
            rx_help_cmd "del <entry>" "Remove a vault entry"
            rx_help_cmd "reset" "Purge local data and disable"
            rx_help_cmd "setup" "Interactive setup wizard"
            rx_help_spacer
            ;;
    esac
}

if [[ $(get_var "CLIP_BITWARDEN") == "true" ]]; then
    register_command "TOOLS" "bitwarden" "Secure Bitwarden vault management utility" "cmd_bw"
fi
