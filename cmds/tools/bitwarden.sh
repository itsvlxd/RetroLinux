#!/bin/bash

cmd_bw() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"
    local action="$1"
    local val1="$2"
    local val2="$3"

    local is_enabled=$(bash "$var_script" --get "CLIP_BITWARDEN")
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

            local sync_rate=$(bash "$var_script" --get "CLIP_WARDEN_SYNC")
            local lock_timer=$(bash "$var_script" --get "CLIP_WARDEN_TIMEOUT")
            local wipe_timer=$(bash "$var_script" --get "CLIP_WARDEN_DESTRUCT")

            local encoded_url=$(echo "$vault_url" | sed 's/:/%3A/g; s/\//%2F/g')
            local db_path="$HOME/.cache/rbw/${encoded_url}:${email}.json"

            local db_size_raw=0
            local last_sync="Never"

            if [[ -f $db_path ]]; then
                db_size_raw=$(stat -c %s "$db_path")
                last_sync=$(date -d "@$(stat -c %Y "$db_path")" "+%d %b %Y - %H:%M")
            fi

            echo -e "\n ${PINK} Bitwarden Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            printf " ${PINK}󰇮${RESET} %-18s %s\n" "Active Account:" "$email"
            printf " ${PINK}󰆟${RESET} %-18s %s\n" "Vault Server:" "${vault_url:-None}"
            printf " ${PINK}󰒋${RESET} %-18s %s\n" "Identity Server:" "${identity_url:-None}"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            printf " ${PINK}󰌾${RESET} %-18s ${status_color}%s${RESET}\n" "Vault State:" "$is_unlocked"
            printf " ${PINK}󰔛${RESET} %-18s %s\n" "Auto-Lock:" "$(rx_format_time "$lock_timer")"
            printf " ${PINK}󰃢${RESET} %-18s %s\n" "Clipboard Wipe:" "$(rx_format_time "$wipe_timer")"
            printf " ${PINK}󱍸${RESET} %-18s Every %s\n" "Sync Interval:" "$(rx_format_time "$sync_rate")"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            printf " ${PINK}󰄨${RESET} %-18s %b\n" "Vault Entries:" "$total_items"
            printf " ${PINK}󰋊${RESET} %-18s %s\n" "Cache Size:" "$(rx_format_size "$db_size_raw")"
            printf " ${PINK}󰄭${RESET} %-18s %s\n" "Last Synchronized:" "$last_sync"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "list")
            if ! rbw unlocked 2>/dev/null; then
                rbw unlock || return 1
            fi

            echo -e "\n ${PINK} Bitwarden Vault Index${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────────────────────────────────"

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

            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────────────────────────────────${RESET}\n"
            ;;

        "get")
            [[ -z $val1 ]] && rx_log "error" "Please provide an entry name." && return 1
            rbw unlocked || rbw unlock || return 1

            rx_log "info" "Fetching credentials: ${PINK}$val1${RESET}..."
            local pass=$(rbw get "$val1" 2>/dev/null)

            if [[ -n $pass ]]; then
                echo "$pass" | wl-copy
                local ttl=$(bash "$var_script" --get "CLIP_WARDEN_DESTRUCT")
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
            echo -ne " ${PINK}󰄾 ${RESET}Confirm reset? ${PINK}[y/N]${RESET}: "
            read -r confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                rbw purge
                bash "$var_script" --del "CLIP_BITWARDEN"
                bash "$var_script" --del "CLIP_WARDEN_SERVER"

                rbw stop-agent
                rm -rf ~/.cache/rbw

                rx_log "success" "Bitwarden integration reset."
            fi
            ;;
        "setup")
            mkdir -p ~/.cache/rbw

            echo -e "\n ${PINK} Bitwarden Setup Instructions${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────${RESET}"
            echo -e " ${PINK}1.${RESET} Open the API Settings directly: "
            echo -e "     ${PINK}https://vault.bitwarden.com/#/settings/security/security-keys${RESET}"
            echo -e " ${PINK}2.${RESET} Scroll down to the ${PINK}API KEY${RESET} section."
            echo -e " ${PINK}3.${RESET} View and copy your ${PINK}Client ID${RESET} and ${PINK}Client Secret${RESET}."
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────"

            rx_log "info" "Do you have your keys and wish to continue? ${PINK}[y/N]${RESET}: "
            read -r ready
            [[ ! $ready =~ ^[Yy]$ ]] && return 0

            rx_log "info" "Which Bitwarden instance are you using?"
            echo -e "    ${PINK}1)${RESET} Global (.com)"
            echo -e "    ${PINK}2)${RESET} Europe (.eu)"
            echo -e "    ${PINK}8)${RESET} Custom / Self-Hosted"
            echo -ne "\n ${PINK}󰄾 ${RESET}Choice [1-3]: "
            read -r srv_choice

            case "$srv_choice" in
                1)
                    rbw config set base_url "https://vault.bitwarden.com"
                    rbw config set identity_url "https://identity.bitwarden.com"
                    ;;
                2)
                    rbw config set base_url "https://api.bitwarden.eu"
                    rbw config set identity_url "https://identity.bitwarden.eu"
                    ;;
                3)
                    rx_log "info" "Enter your Custom Vault URL (e.g., https://vault.domain.com): "
                    read -r custom_vault
                    rx_log "info" "Enter your Custom Identity URL (e.g., https://identity.domain.com): "
                    read -r custom_identity
                    rbw config set base_url "$custom_vault"
                    rbw config set identity_url "$custom_identity"
                    ;;
                *)
                    rbw config set base_url "https://vault.bitwarden.com"
                    rbw config set identity_url "https://identity.bitwarden.com"
                    ;;
            esac

            local current_vault=$(rbw config show | grep "base_url" | awk -F'"' '{print $4}')
            bash "$var_script" --set "CLIP_WARDEN_SERVER" "$current_vault"

            rx_log "info" "Launching registration. Please follow the terminal prompts:"

            if rbw register; then
                bash "$var_script" --set "CLIP_BITWARDEN" "true"

                rx_log "info" "How often should I pull fresh data from the server? (seconds) ${PINK}[Default: 1800]${RESET}: "
                read -r input_sync
                local val_sync=${input_sync:-1800}
                rbw config set sync_interval "$val_sync"
                bash "$var_script" --set "CLIP_WARDEN_SYNC" "$val_sync"

                rx_log "info" "How long should the vault stay unlocked before requiring a PIN? (seconds) ${PINK}[Default: 900]${RESET}: "
                read -r input_timeout
                local val_timeout=${input_timeout:-900}
                rbw config set lock_timeout "$val_timeout"
                bash "$var_script" --set "CLIP_WARDEN_TIMEOUT" "$val_timeout"

                rx_log "info" "How many seconds before a copied password is wiped from the clipboard? ${PINK}[Default: 30]${RESET}: "
                read -r input_destruct
                local val_destruct=${input_destruct:-30}
                bash "$var_script" --set "CLIP_WARDEN_DESTRUCT" "$val_destruct"

                rx_log "success" "Bitwarden integration and security policies enabled!"
            else
                rx_log "error" "Registration failed. Check your keys or server URLs."
                return 1
            fi
            ;;

        *)
            rx_log "info" "Usage: retro bitwarden <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "sync" "Sync vault with server"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "lock" "Lock the vault"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "unlock" "Unlock the vault"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show vault status and settings"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List all vault entries"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "get <entry>" "Copy password for an entry"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "code <entry>" "Copy TOTP code for an entry"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "add [name] [user]" "Create a new vault entry"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "edit <entry>" "Edit an existing entry"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "del <entry>" "Remove a vault entry"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "reset" "Purge local data and disable"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "setup" "Interactive setup wizard"
            echo ""
            ;;
    esac
}

if [[ $(bash "$RETRO_DIR/scripts/variable_core.sh" --get "CLIP_BITWARDEN") == "true" ]]; then
    register_command "TOOLS" "bitwarden" "Secure Bitwarden vault management utility" "cmd_bw"
fi
