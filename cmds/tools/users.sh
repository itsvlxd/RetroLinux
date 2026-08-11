#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_users() {
    local users_core="$RETRO_DIR/scripts/users_core.sh"
    local action="${1,,}"
    shift 2>/dev/null || true

    case "$action" in
        "list" | "ls")
            local output
            output=$(bash "$users_core" --list)

            rx_table_header "󰏰" "System Users"

            while IFS='|' read -r name uid home shell retro marker; do
                [[ -z $name ]] && continue

                local status_color="$GRAY"
                local status_icon="󰿅"
                if [[ $retro == "yes" ]]; then
                    status_color="$SUCCESS"
                    status_icon="󰠮"
                fi

                local you_suffix=""
                if [[ -n $marker ]]; then
                    you_suffix=" ${PINK}(${RESET}${PINK}you${RESET}${PINK})${RESET}"
                fi

                printf " ${PINK}󰉋${RESET} %-16s%s %sUID %s${RESET} %s %s\n" \
                    "$name" "$you_suffix" "$GRAY" "$uid" "${home:0:34}" "$status_color$status_icon"
            done <<<"$output"

            rx_table_separator
            rx_table_spacer
            ;;

        "info" | "status")
            local user="$1"
            if [[ -z $user ]]; then
                user="$LOGNAME"
            fi

            if ! getent passwd "$user" >/dev/null 2>&1; then
                rx_log "error" "User '$user' does not exist"
                return 1
            fi

            local info
            info=$(getent passwd "$user")
            IFS=: read -r name _pw uid gid gecos home shell <<<"$info"

            rx_table_header "󰉋" "User: $name"

            rx_table_row "󰿅" "UID:" "$uid" "$PINK" "20"
            rx_table_row "󰤴" "GID:" "$gid" "$PINK" "20"
            rx_table_row "󰋜" "Full Name:" "${gecos:-—}" "$GRAY" "20"
            rx_table_row "󰪥" "Home:" "$home" "$GRAY" "20"
            rx_table_row "󰀻" "Shell:" "$shell" "$GRAY" "20"

            local retro_state="Not configured"
            local retro_color="$GRAY"
            if [[ -f "$home/.config/retro/variables.sh" ]]; then
                retro_state="Configured"
                retro_color="$SUCCESS"
            fi
            rx_table_row "󰠮" "Retro Config:" "$retro_state" "$retro_color" "20"

            local admin="No"
            if id -nG "$user" | grep -qw wheel; then
                admin="Yes"
            fi
            rx_table_row "󰊄" "Sudo (wheel):" "$admin" "$PINK" "20"

            local groups
            groups=$(id -nG "$user")
            rx_table_row "󰑀" "Groups:" "$groups" "$GRAY" "20"

            rx_table_separator
            rx_table_spacer
            ;;

        "create" | "add")
            local user=""
            local full_name=""
            local admin=false
            local password=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --admin) admin=true ;;
                    --full-name | --name)
                        full_name="${2:-}"
                        shift
                        ;;
                    --password | -p)
                        password="${2:-}"
                        shift
                        ;;
                    --help)
                        rx_help_usage "retro users create <username> [--admin] [--full-name NAME] [--password PW]"
                        rx_help_commands "Create options"
                        rx_help_cmd "--admin" "Grant sudo access (add to wheel group)"
                        rx_help_cmd "--full-name <name>" "Set the user's display name"
                        rx_help_cmd "--password <pw>" "Set the user's password (skips the prompt)"
                        rx_help_examples
                        rx_help_example "retro users create alex --admin" "Create alex with sudo"
                        rx_help_example "retro users create alex --full-name 'Alex Smith'" "Create with display name"
                        rx_help_example "retro users create alex --password secret123" "Create with a set password"
                        rx_help_spacer
                        return 0
                        ;;
                    *) user="$1" ;;
                esac
                shift
            done

            if [[ -z $user ]]; then
                rx_log "error" "Usage: retro users create <username> [--admin] [--full-name NAME] [--password PW]"
                return 1
            fi

            if ! [[ $user =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                rx_log "error" "Invalid username '$user' (use lowercase letters, digits, _ and -)"
                return 1

            fi

            local args=""
            [[ $admin == "true" ]] && args+=" --admin"
            [[ -n $full_name ]] && args+=" --full-name '${full_name//\'/\'\\\'\'}'"
            if [[ -n $password ]]; then
                args+=" --password '${password//\'/\'\\\'\'}'"
                rx_log "warn" "Password passed on the command line — visible in process list"
            fi

            rx_log "info" "Creating user ${PINK}$user${RESET} (copies current retro config + installs modules)..."
            sudo bash "$users_core" --create "$user" $args
            ;;

        "resync" | "sync")
            local user="$1"
            if [[ -z $user ]]; then
                rx_log "error" "Usage: retro users resync <username>"
                return 1
            fi

            rx_log "info" "Re-syncing retro config for ${PINK}$user${RESET}..."
            sudo bash "$users_core" --resync "$user"
            ;;

        "delete" | "remove" | "rm")
            local user="$1"
            if [[ -z $user ]]; then
                rx_log "error" "Usage: retro users delete <username>"
                return 1
            fi

            rx_log "warn" "Deleting user ${PINK}$user${RESET} — this removes their home directory"
            if rx_confirm "Delete user $user?" "N"; then
                sudo bash "$users_core" --delete "$user"
            else
                rx_log "info" "Cancelled"
            fi
            ;;

        "set-face" | "picture" | "photo")
            local user=""
            local image=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --help)
                        rx_help_usage "retro users set-face <username> <image>"
                        rx_help_commands "Picture options"
                        rx_help_cmd "username" "The user whose picture to set"
                        rx_help_cmd "image" "Path to the image file (png/jpg)"
                        rx_help_examples
                        rx_help_example "retro users set-face alex /path/to/pic.png" "Set alex's profile picture"
                        rx_help_spacer
                        return 0
                        ;;
                    *) if [[ -z $user ]]; then user="$1"; else image="$1"; fi ;;
                esac
                shift
            done

            if [[ -z $user || -z $image ]]; then
                rx_log "error" "Usage: retro users set-face <username> <image>"
                return 1
            fi
            if [[ ! -f $image ]]; then
                rx_log "error" "Image not found: $image"
                return 1
            fi

            rx_log "info" "Setting profile picture for ${PINK}$user${RESET}..."
            sudo bash "$users_core" --set-face "$user" "$image"
            ;;

        "modify" | "edit")
            local user=""
            local new_home=""
            local new_shell=""
            local delete_old="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --home)
                        new_home="${2:-}"
                        shift
                        ;;
                    --shell)
                        new_shell="${2:-}"
                        shift
                        ;;
                    --delete-old)
                        delete_old="true"
                        ;;
                    --help)
                        rx_help_usage "retro users modify <username> [--home PATH] [--shell PATH] [--delete-old]"
                        rx_help_commands "Modify options"
                        rx_help_cmd "--home <path>" "Move the user's home directory"
                        rx_help_cmd "--shell <path>" "Set the user's login shell (updates RETRO_BIN_SHELL)"
                        rx_help_cmd "--delete-old" "Remove the old home directory after moving"
                        rx_help_examples
                        rx_help_example "retro users modify alex --home /data/alex" "Move alex's home to /data/alex"
                        rx_help_example "retro users modify alex --shell /usr/bin/zsh" "Set alex's shell to zsh"
                        rx_help_example "retro users modify alex --home /data/alex --delete-old" "Move home and delete the old one"
                        rx_help_spacer
                        return 0
                        ;;
                    *) user="$1" ;;
                esac
                shift
            done

            if [[ -z $user ]]; then
                rx_log "error" "Usage: retro users modify <username> [--home PATH] [--shell PATH] [--delete-old]"
                return 1
            fi
            if [[ -z $new_home && -z $new_shell ]]; then
                rx_log "error" "Nothing to modify — pass --home and/or --shell"
                return 1
            fi

            local args=()
            [[ -n $new_home ]] && args+=(--home "$new_home")
            [[ -n $new_shell ]] && args+=(--shell "$new_shell")
            if [[ $delete_old == "true" ]]; then
                rx_log "warn" "The old home directory will be DELETED"
                if rx_confirm "Delete old home directory for $user?" "N"; then
                    args+=(--delete-old true)
                else
                    rx_log "info" "Keeping the old home directory"
                fi
            fi

            rx_log "info" "Modifying user ${PINK}$user${RESET}..."
            sudo bash "$users_core" --modify "$user" "${args[@]}"
            ;;

        *)
            rx_help_usage "retro users <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "list" "List system users and retro config status"
            rx_help_cmd "info <user>" "Show details for a user"
            rx_help_cmd "create <user> [--admin]" "Create a user, copy config, install modules"
            rx_help_cmd "modify <user> [--home] [--shell]" "Move home / change login shell"
            rx_help_cmd "set-face <user> <image>" "Set a user's profile picture"
            rx_help_cmd "resync <user>" "Re-copy config and reinstall modules for a user"
            rx_help_cmd "delete <user>" "Delete a user and their home directory"
            rx_help_examples
            rx_help_example "retro users list" "List all users"
            rx_help_example "retro users info alex" "Show alex's details"
            rx_help_example "retro users create alex --admin" "Create alex with sudo + full retro setup"
            rx_help_example "retro users modify alex --shell /usr/bin/zsh" "Set alex's shell to zsh"
            rx_help_example "retro users modify alex --home /data/alex --delete-old" "Move alex's home"
            rx_help_example "retro users set-face alex ~/pic.png" "Set alex's profile picture"
            rx_help_example "retro users resync alex" "Re-sync alex's config"
            rx_help_example "retro users delete alex" "Remove alex"
            rx_help_spacer
            ;;
    esac
}

register_command "SYSTEM" "users" "Manage system users with Retro config" "cmd_users"
