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

    faillock --user "$USER" --reset 2>/dev/null || true

    local old_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)
    local old_version=$(rx_git_version)
    local skip_file="/tmp/retro_skip_upgrade"

    rx_git_fix_owner

    local current_branch=$(rx_git_branch)
    local desired_branch=$($RETRO_DIR/retro.sh variable get RETRO_BRANCH 2>/dev/null || echo "")
    [[ $desired_branch == "null" ]] && desired_branch=""

    if command -v timeshift >/dev/null 2>&1; then
        rx_log "warn" "Creating Timeshift backup before update"
        if sudo timeshift --create --comments "Pre-update safety backup" --tags O >/dev/null 2>&1; then
            rx_log "success" "Timeshift backup created"
        else
            rx_log "warn" "Timeshift backup failed, continuing anyway"
        fi
    else
        rx_log "warn" "Timeshift not installed, skipping backup"
    fi

    local has_changes=$(git -C "$RETRO_DIR" status --porcelain 2>/dev/null)
    local commits=""

    if [[ -n $has_changes ]]; then
        rx_confirm "Uncommitted changes detected. Reset --hard to discard?" "N" || return 0
        rx_git_reset_hard
    fi

    if [[ -n $desired_branch && $desired_branch != $current_branch ]]; then
        rx_log "info" "Switching to configured branch ${PINK}${desired_branch}${RESET}..."
        if git -C "$RETRO_DIR" fetch origin >/dev/null 2>&1 \
            && git -C "$RETRO_DIR" rev-parse --verify "origin/$desired_branch" >/dev/null 2>&1; then
            if git -C "$RETRO_DIR" checkout -B "$desired_branch" "origin/$desired_branch" 2>&1; then
                rx_log "success" "Now on ${PINK}${desired_branch}${RESET}"
            else
                rx_log "warn" "Could not switch to ${PINK}${desired_branch}${RESET}, staying on ${PINK}${current_branch}${RESET}"
            fi
        else
            rx_log "warn" "Branch ${PINK}${desired_branch}${RESET} not found on the remote, staying on ${PINK}${current_branch}${RESET}"
        fi
    fi

    rx_log "info" "Syncing repository with $(rx_git_branch)"

    local old_release_tag=""
    local new_release_tag=""
    if [[ $(rx_git_branch) == "main" ]]; then
        old_release_tag=$(git -C "$RETRO_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' "$old_head" 2>/dev/null || true)
        git -C "$RETRO_DIR" fetch origin >/dev/null 2>&1 || true
        new_release_tag=$(git -C "$RETRO_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' origin/main 2>/dev/null || true)
        if [[ -z $new_release_tag || $new_release_tag == "$old_release_tag" ]]; then
            rx_log "warn" "No new release published on main yet (current: ${old_release_tag:-none})."
            rx_log "warn" "Stable updates only ship with a new release tag. Skipping update."
            return 0
        fi
    fi

    if git -C "$RETRO_DIR" pull 2>&1; then
        local new_head=$(git -C "$RETRO_DIR" rev-parse HEAD 2>/dev/null)

        if [[ $old_head != $new_head ]]; then
            if [[ $(rx_git_branch) == "main" && -n $old_release_tag && -n $new_release_tag ]]; then
                commits=$(git -C "$RETRO_DIR" log "$old_release_tag..$new_release_tag" --pretty=format:"%s" --no-merges 2>/dev/null)
            else
                commits=$(git -C "$RETRO_DIR" log "$old_head..$new_head" --pretty=format:"%s" --no-merges 2>/dev/null)
            fi

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

            local new_version=$(rx_git_version)
            rx_confirm "Continue upgrading to RetroLinux ${PINK}${new_version}${RESET}?" "Y" || {
                rx_log "warn" "Skipped. Reverting to ${PINK}${old_version}${RESET}..."
                echo "$new_head" >"$skip_file"
                git -C "$RETRO_DIR" reset --hard "$old_head" >/dev/null 2>&1
                return 0
            }
            rm -f "$skip_file"
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

        rx_log "info" "Refreshing installed wallpaper collections..."
        $RETRO_DIR/retro.sh wallpaper sync >/dev/null 2>&1 &
        wait $! 2>/dev/null || true

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

        if [[ $(rx_git_branch) == "main" && -n $new_release_tag ]]; then
            $RETRO_DIR/retro.sh variable set RETRO_LAST_STABLE "$new_release_tag" >/dev/null 2>&1 || true
            rx_log "success" "Last stable version updated to ${PINK}${new_release_tag}${RESET}"
        fi

        rx_log "info" "Restarting Retro daemon..."
        $RETRO_DIR/retro.sh daemon restart

        if [[ -n $commits ]] && grep -qi "retroshell" <<<"$commits"; then
            rx_log "info" "RetroShell changed in this update, restarting it..."
            $RETRO_DIR/retro.sh shell restart
        fi
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
