#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/git.sh"

cmd_update() {
    local target="${1:-existing}"
    local pull_failed="false"

    rx_logo

    if [[ ! -d "$RETRO_DIR/.git" ]]; then
        rx_log "error" "Not a git repository: $RETRO_DIR"
        return 1
    fi

    faillock --user $USER --reset

    local old_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)
    local old_version=$(rx_git_version)
    local skip_file="$RETRO_DIR/.retro_skip_upgrade"

    rx_git_fix_owner

    local current_branch=$(rx_git_branch)
    if [[ $current_branch == "develop" ]]; then
        rx_log "warn" "On ${PINK}develop${RESET} branch, creating Timeshift backup before update"
        if command -v timeshift >/dev/null 2>&1; then
            if sudo timeshift --create --comments "Pre-update safety backup (develop)" --tags O >/dev/null 2>&1; then
                rx_log "success" "Timeshift backup created"
            else
                rx_log "warn" "Timeshift backup failed, continuing anyway"
            fi
        else
            rx_log "warn" "Timeshift not installed, skipping backup"
        fi
    fi

    local has_changes=$(git -C "$RETRO_DIR" status --porcelain 2>/dev/null)
    local commits=""

    if [[ -n $has_changes ]]; then
        rx_confirm "Uncommitted changes detected. Reset --hard to discard?" "N" || return 0
        rx_git_reset_hard
    fi

    rx_log "info" "Syncing repository with $(rx_git_branch)"

    if git -C "$RETRO_DIR" pull 2>&1; then
        local new_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)

        if [[ $old_head != $new_head ]]; then
            local log_base="$old_head"
            local skip_note=""
            if [[ -f $skip_file ]]; then
                local skipped_head
                skipped_head=$(cat "$skip_file")
                if git -C "$RETRO_DIR" merge-base --is-ancestor "$skipped_head" "$new_head" 2>/dev/null; then
                    log_base="$skipped_head"
                    local skip_count
                    skip_count=$(git -C "$RETRO_DIR" rev-list --count "$old_head..$skipped_head" 2>/dev/null)
                    skip_note=" (${skip_count} previously skipped)"
                fi
            fi

            commits=$(git -C "$RETRO_DIR" log "$log_base..$new_head" --pretty=format:"%s" --no-merges 2>/dev/null)

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

                local new_version=$(rx_git_version)
                rx_confirm "Continue upgrading to RetroLinux ${PINK}${new_version}${RESET}${skip_note}?" "Y" || {
                    rx_log "warn" "Skipped. Reverting to ${PINK}${old_version}${RESET}..."
                    echo "$new_head" >"$skip_file"
                    git -C "$RETRO_DIR" reset --hard "$old_head" >/dev/null 2>&1
                    return 0
                }
                rm -f "$skip_file"
            fi
        fi

        rx_log "success" "Git pull successful"

        rx_log "info" "Adding missing variables"
        $RETRO_DIR/retro.sh variable update

        local install_type=$($RETRO_DIR/retro.sh variable get RETRO_INSTALL 2>/dev/null || echo "complete")
        local retro_ricing=$($RETRO_DIR/retro.sh variable get RETRO_RICING 2>/dev/null || echo "false")
        local type_filter="-t all"
        [[ $install_type == "minimal" ]] && type_filter="-t core"

        local install_mode="-i"
        [[ $retro_ricing == "true" ]] && install_mode="-m"

        rx_log "info" "Install type: $install_type ($type_filter)"

        $RETRO_DIR/retro.sh $install_mode $target -a root $type_filter -y
        $RETRO_DIR/retro.sh $install_mode $target -a user $type_filter -y

        rx_log "info" "Syncing wallpapers from repository..."
        $RETRO_DIR/retro.sh wallpaper sync >/dev/null 2>&1

        if [[ -n $commits ]]; then
            local -A setup_modules
            while IFS= read -r msg; do
                local mod_regex='^[a-z]+\(([^)]+)\)'
                if [[ $msg =~ $mod_regex ]]; then
                    setup_modules["${BASH_REMATCH[1]}"]=1
                fi
            done <<<"$commits"

            local -a matched
            for module in "${!setup_modules[@]}"; do
                local tool_cmd="$RETRO_DIR/cmds/tools/${module}.sh"
                if [[ -f $tool_cmd ]] && grep -q '"setup")' "$tool_cmd" 2>/dev/null; then
                    matched+=("$module")
                fi
            done

            if [[ ${#matched[@]} -gt 0 ]]; then
                for module in "${matched[@]}"; do
                    rx_log "info" "Changes in ${PINK}${module}${RESET}, reapplying setup..."
                    retro "$module" setup -f 2>/dev/null || true
                done
            fi
        fi

        rx_log "success" "Update finished"
    else
        pull_failed="true"

        if [[ -n $has_changes ]]; then
            rx_confirm "Git pull failed. Reset --hard to resolve conflicts?" "N" || return 1
            rx_git_reset_hard
        fi

        rx_log "error" "Git pull failed. Check your connection or conflicts."
        return 1
    fi
}

register_command "SYSTEM" "-u|--update" "Sync repo and refresh all modules" "cmd_update"
