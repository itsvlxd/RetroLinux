#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

_var_get() {
    bash "$RETRO_DIR/scripts/variable_core.sh" --get "$1" 2>/dev/null
}

_var_set() {
    bash "$RETRO_DIR/scripts/variable_core.sh" --set "$1" "$2" >/dev/null 2>&1
}

_stable_tag() {
    local tag
    tag=$(rx_git_run describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null)
    [[ -n $tag ]] && { echo "$tag"; return 0; }
    tag=$(_var_get "RETRO_LAST_STABLE")
    [[ -z $tag || $tag == "null" ]] && tag=""
    [[ -n $tag ]] && { echo "$tag"; return 0; }
    tag=$(rx_git_run describe --tags --abbrev=0 --match 'v[0-9]*' origin/main 2>/dev/null)
    [[ -n $tag ]] && { echo "$tag"; return 0; }
    tag=$(git -C "$RETRO_DIR" tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
    echo "$tag"
}

cmd_branch() {
    local action="${1,,}"
    shift 2>/dev/null || true

    case "$action" in
        status)
            local branch=$(rx_git_run rev-parse --abbrev-ref HEAD)
            local tag=$(rx_git_run describe --tags --abbrev=0 --match 'v[0-9]*' HEAD)
            echo "branch=${branch:-unknown}"
            echo "version=${tag:-none}"
            ;;

        list)
            git -C "$RETRO_DIR" branch -a 2>/dev/null \
                | sed 's/^[* ] //' \
                | grep -v '^remotes/' \
                | sort -u
            ;;

        switch)
            local target="$1"
            [[ -z $target ]] && { echo "result=error|reason=no_target"; return 1; }

            if [[ -n $(git -C "$RETRO_DIR" status --porcelain 2>/dev/null) ]]; then
                git -C "$RETRO_DIR" reset --hard >/dev/null 2>&1
            fi

            git -C "$RETRO_DIR" fetch origin --tags >/dev/null 2>&1 \
                || { echo "result=error|reason=fetch_failed"; return 1; }

            git -C "$RETRO_DIR" rev-parse --verify "origin/$target" >/dev/null 2>&1 \
                || { echo "result=error|reason=branch_not_found|branch=$target"; return 1; }

            local stable
            stable=$(_stable_tag)

            rx_log "info" "Switching to ${PINK}${target}${RESET} at ${PINK}${stable:-latest}${RESET}"

            if [[ -n $stable ]]; then
                _var_set "RETRO_LAST_STABLE" "$stable"
                if git -C "$RETRO_DIR" checkout -B "$target" "$stable" >/dev/null 2>&1; then
                    _var_set "RETRO_BRANCH" "$target"
                    rx_log "success" "On ${PINK}${target}${RESET} (${PINK}${stable}${RESET})"
                    echo "OK|$target"
                    return 0
                fi
                echo "result=error|reason=checkout_failed|branch=$target"
                return 1
            fi

            if git -C "$RETRO_DIR" checkout -B "$target" "origin/$target" >/dev/null 2>&1; then
                _var_set "RETRO_BRANCH" "$target"
                rx_log "success" "On ${PINK}${target}${RESET}"
                echo "OK|$target"
                return 0
            fi
            echo "result=error|reason=checkout_failed|branch=$target"
            return 1
            ;;

        updates)
            local branch=$(rx_git_run rev-parse --abbrev-ref HEAD)
            [[ -z $branch || $branch == "N/A" ]] && { echo "count=-1"; return 0; }

            git -C "$RETRO_DIR" fetch origin --tags >/dev/null 2>&1 || true

            if [[ $branch == "main" ]]; then
                local cur=$(_stable_tag)
                local count=0
                local tag
                while IFS= read -r tag; do
                    [[ -z $tag ]] && continue
                    if [[ -n $cur && $tag == "$cur" ]]; then
                        continue
                    fi
                    if [[ -z $cur || "$(printf '%s\n%s' "$cur" "$tag" | sort -V | tail -1)" == "$tag" ]]; then
                        ((count++))
                    fi
                done < <(git -C "$RETRO_DIR" tag --list 'v*' --sort=v:refname --merged origin/main 2>/dev/null)
                echo "count=$count"
            else
                local out
                out=$(git -C "$RETRO_DIR" rev-list --count "HEAD..origin/$branch" 2>/dev/null)
                echo "count=${out:-0}"
            fi
            ;;

        *)
            rx_help_usage "retro -b <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show current branch and release version"
            rx_help_cmd "list" "List local branches"
            rx_help_cmd "switch <develop|main>" "Switch branch to the last stable release"
            rx_help_cmd "updates" "Count available updates"
            rx_help_examples
            rx_help_example "retro -b switch main" "Restore the last stable release on main"
            rx_help_example "retro -b updates" "Show how many updates are available"
            rx_help_spacer
            ;;
    esac
}

register_command "SYSTEM" "-b|--branch" "Switch branches and check updates from the terminal" "cmd_branch"
