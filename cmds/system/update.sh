#!/bin/bash

cmd_update() {
    local target="$1"

    if [[ ! -d "$RETRO_DIR/.git" ]]; then
        rx_log "error" "Not a git repository: $RETRO_DIR"
        return 1
    fi

    local old_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)

    rx_log "info" "Syncing repository with $(rx_git_branch)"

    if git -C "$RETRO_DIR" pull 2>&1; then
        local new_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)

        if [[ $old_head != $new_head ]]; then
            local commits=$(git -C "$RETRO_DIR" log "$old_head..$new_head" --pretty=format:"%s" --no-merges 2>/dev/null)

            if [[ -n $commits ]]; then
                echo -e "\n ${PINK}󰜘 Changelog${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

                local feat="" fix="" refactor="" style="" docs="" chore="" other=""

                while IFS= read -r msg; do
                    local clean_msg="${msg#*: }"
                    local prefix="${msg%%:*}"
                    local module=""
                    local mod_regex='^[a-z]+\(([^)]+)\)'

                    if [[ $prefix =~ $mod_regex ]]; then
                        module="${BASH_REMATCH[1]}"
                        module="$(echo "${module:0:1}" | tr '[:lower:]' '[:upper:]')${module:1}"
                    fi

                    case "$prefix" in
                        feat*)
                            if [[ -n $module ]]; then
                                feat+="  ${PINK}󰬈${RESET} ${PINK}${module}${GRAY}: ${RESET}${clean_msg}\n"
                            else
                                feat+="  ${PINK}󰬈${RESET} ${clean_msg}\n"
                            fi
                            ;;
                        fix*)
                            if [[ -n $module ]]; then
                                fix+="  ${PINK}󰁨${RESET} ${PINK}${module}${GRAY}: ${RESET}${clean_msg}\n"
                            else
                                fix+="  ${PINK}󰁨${RESET} ${clean_msg}\n"
                            fi
                            ;;
                        refactor*)
                            if [[ -n $module ]]; then
                                refactor+="  ${PINK}󰑓${RESET} ${PINK}${module}${GRAY}: ${RESET}${clean_msg}\n"
                            else
                                refactor+="  ${PINK}󰑓${RESET} ${clean_msg}\n"
                            fi
                            ;;
                        style*)
                            if [[ -n $module ]]; then
                                style+="  ${PINK}󰏘${RESET} ${PINK}${module}${GRAY}: ${RESET}${clean_msg}\n"
                            else
                                style+="  ${PINK}󰏘${RESET} ${clean_msg}\n"
                            fi
                            ;;
                        docs*)
                            if [[ -n $module ]]; then
                                docs+="  ${PINK}󰈙${RESET} ${PINK}${module}${GRAY}: ${RESET}${clean_msg}\n"
                            else
                                docs+="  ${PINK}󰈙${RESET} ${clean_msg}\n"
                            fi
                            ;;
                        chore*)
                            if [[ -n $module ]]; then
                                chore+="  ${PINK}󰗑${RESET} ${PINK}${module}${GRAY}: ${RESET}${clean_msg}\n"
                            else
                                chore+="  ${PINK}󰗑${RESET} ${clean_msg}\n"
                            fi
                            ;;
                        *) other+="  ${PINK}󰋗${RESET} ${msg}\n" ;;
                    esac
                done <<<"$commits"

                [[ -n $feat ]] && echo -e " ${PINK}󰬈${RESET} Features${GRAY}:${RESET}" && echo -e "$feat"
                [[ -n $fix ]] && echo -e " ${PINK}󰁨${RESET} Fixes${GRAY}:${RESET}" && echo -e "$fix"
                [[ -n $refactor ]] && echo -e " ${PINK}󰑓${RESET} Refactors${GRAY}:${RESET}" && echo -e "$refactor"
                [[ -n $style ]] && echo -e " ${PINK}󰏘${RESET} Style${GRAY}:${RESET}" && echo -e "$style"
                [[ -n $docs ]] && echo -e " ${PINK}󰈙${RESET} Docs${GRAY}:${RESET}" && echo -e "$docs"
                [[ -n $chore ]] && echo -e " ${PINK}󰗑${RESET} Chore${GRAY}:${RESET}" && echo -e "$chore"
                [[ -n $other ]] && echo -e " ${PINK}󰋗${RESET} Other${GRAY}:${RESET}" && echo -e "$other"

                echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            fi
        fi

        rx_log "success" "Git pull successful"

        if [[ $SKIP_PROMPT != true ]]; then
            rx_log "info" "Would you like to update all modules? ${PINK}[y/N]${RESET}"
            read -r confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                SKIP_PROMPT=true
                cmd_install "$target"
            else
                rx_log "info" "Skipping module updates."
            fi
        else
            cmd_install "$target"
        fi
    else
        rx_log "error" "Git pull failed. Check your connection or conflicts."
        return 1
    fi
}

register_command "SYSTEM" "-u|--update" "Sync repo and refresh all modules" "cmd_update"
