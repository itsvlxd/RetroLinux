#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/git.sh"

# TODO: refactor the update workflow

cmd_update() {
    local target="${1:-existing}"
    local type_filter=""
    local access_filter=""
    local force_reset=""

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t | --type)
                type_filter="$2"
                shift 2
                ;;
            -a | --access)
                access_filter="$2"
                shift 2
                ;;
            --hard-reset)
                force_reset="true"
                shift
                ;;
            -i | --install)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    rx_logo

    if [[ ! -d "$RETRO_DIR/.git" ]]; then
        rx_log "error" "Not a git repository: $RETRO_DIR"
        return 1
    fi

    if [[ $force_reset == "true" ]]; then
        rx_confirm "Perform git reset --hard to discard local changes?" "N" || return 0
        rx_git_reset_hard
    fi

    local old_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)

    rx_log "info" "Syncing repository with $(rx_git_branch)"

    if git -C "$RETRO_DIR" pull 2>&1; then
        local new_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)

        if [[ $old_head != $new_head ]]; then
            local commits=$(git -C "$RETRO_DIR" log "$old_head..$new_head" --pretty=format:"%s" --no-merges 2>/dev/null)

            if [[ -n $commits ]]; then
                rx_table_header "󰜘" "Changelog"

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

                [[ -n $feat ]] && rx_help_section "󰬈" "Features" && echo -e "$feat"
                [[ -n $fix ]] && rx_help_section "󰁨" "Fixes" && echo -e "$fix"
                [[ -n $refactor ]] && rx_help_section "󰑓" "Refactors" && echo -e "$refactor"
                [[ -n $style ]] && rx_help_section "󰏘" "Style" && echo -e "$style"
                [[ -n $docs ]] && rx_help_section "󰈙" "Docs" && echo -e "$docs"
                [[ -n $chore ]] && rx_help_section "󰗑" "Chore" && echo -e "$chore"
                [[ -n $other ]] && rx_help_section "󰋗" "Other" && echo -e "$other"

                rx_help_footer
            fi
        fi

        rx_log "success" "Git pull successful"

        [[ -n "$type_filter" ]] && export MODULE_TYPE_FILTER="$type_filter"
        [[ -n "$access_filter" ]] && export MODULE_ACCESS_FILTER="$access_filter"
        
        local install_flags="-y"
        [[ -n "$type_filter" ]] && install_flags+=" -t $type_filter"
        [[ -n "$access_filter" ]] && install_flags+=" -a $access_filter"
        
        if [[ $access_filter == "root" || $access_filter == "all" ]]; then
            cmd_install "existing" -a root
        fi
        if [[ $access_filter == "user" || $access_filter == "all" || -z "$access_filter" ]]; then
            cmd_install "existing" -a user
        fi
    else
        rx_log "error" "Git pull failed. Check your connection or conflicts."
        return 1
    fi
}

register_command "SYSTEM" "-u|--update" "Sync repo and refresh all modules" "cmd_update"
