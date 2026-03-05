#!/bin/bash

run_task() {
    local type="$1"
    local module="$2"

    if [[ $module == "all" || -z $module ]]; then
        for dir in "$RETRO_DIR"/modules/*/; do
            [[ -d $dir ]] || continue

            local m_name=$(basename "$dir")

            execute_logic "$type" "$m_name"
        done
    else
        execute_logic "$type" "$module"
    fi
}

execute_logic() {
    local type="$1"
    local name="$2"

    local mod_path="$RETRO_DIR/modules/$name"
    local script="$mod_path/${type}.sh"
    local pre_script="$mod_path/pre.sh"
    local post_script="$mod_path/post.sh"

    if [[ ! -d $mod_path ]]; then
        rx_log "error" "Module '$name' not found in $RETRO_DIR/modules/"
        return 1
    fi

    local action_icon="${PINK}󰄾${RESET}"
    local action_msg=""

    case "$type" in
        "install")
            action_icon="${PINK}󰇚${RESET}"
            action_msg="Install the ${PINK}$name${RESET} module?"
            ;;
        "uninstall")
            action_icon="${PINK}󰈚${RESET}"
            action_msg="Uninstall the ${PINK}$name${RESET} module?"
            ;;
        "pull")
            action_icon="${PINK}󱇪${RESET}"
            action_msg="Pull latest changes for ${PINK}$name${RESET}?"
            ;;
        "mirror")
            action_icon="${PINK}󱂷${RESET}"
            action_msg="Mirror ${PINK}$name${RESET} to your config?"
            ;;
        *) action_msg="Execute ${PINK}$type${RESET} on ${PINK}$name${RESET}?" ;;
    esac

    if [[ $SKIP_PROMPT == "false" ]]; then
        echo -ne " $action_icon $action_msg [Y/n]: "
        read -r opt
        [[ $opt =~ ^[Nn]$ ]] && {
            rx_log "info" "Skipping $name..."
            return 0
        }
    fi

    if [[ -f $pre_script ]]; then
        rx_log "info" "Running pre-hook for $name..."
        (cd "$mod_path" && bash "./pre.sh" "$type")
    fi

    if [[ $type == "install" || $type == "mirror" ]]; then
        if [[ -f "$mod_path/pkg.list" ]]; then
            local sync_pkgs=true

            if [[ $SKIP_PROMPT == "false" ]]; then
                echo -ne " ${PINK}󱖫${RESET} Install dependencies for ${PINK}$name${RESET} from ${PINK}pkg.list${RESET}? [Y/n]: "
                read -r pkg_opt
                [[ $pkg_opt =~ ^[Nn]$ ]] && sync_pkgs=false
            fi

            if [[ $sync_pkgs == "true" ]]; then
                rx_log "info" "Syncing dependencies for $name..."
                rx_pkg_install "$mod_path/pkg.list"
            else
                rx_log "warn" "Skipping dependencies for $name"
            fi
        fi
    fi

    if [[ $type == "uninstall" && -f "$mod_path/pkg.list" ]]; then
        local pkgs=$(grep -v '^#' "$mod_path/pkg.list" | xargs)

        if [[ -n $pkgs ]]; then
            local purge_pkgs=false

            if [[ $SKIP_PROMPT == "false" ]]; then
                echo -ne " ${PINK}󱖫${RESET} Purge all dependencies found in ${PINK}pkg.list${RESET} for ${PINK}$name${RESET}? [y/N]: "
                read -r purge_opt
                [[ $purge_opt =~ ^[Yy]$ ]] && purge_pkgs=true
            fi

            if [[ $purge_pkgs == "true" ]]; then
                rx_log "info" "Purging dependencies for $name..."
                sudo pacman -Rs $pkgs --noconfirm 2>/dev/null
            fi
        fi
    fi

    if [[ -f $script ]]; then
        rx_log "info" "Using custom $type script for $name"
        (cd "$mod_path" && source "./${type}.sh")
    else
        case "$type" in
            "install") rx_default_install "$name" ;;
            "pull") rx_default_pull "$name" ;;
            "mirror") rx_default_mirror "$name" ;;
            "uninstall") rx_default_uninstall "$name" ;;
        esac
    fi

    if [[ -f $post_script ]]; then
        rx_log "info" "Running post-hook for $name..."
        (cd "$mod_path" && bash "./post.sh" "$type")
    fi
}

get_target_path() {
    local mod_name="$1"
    local target_file="$RETRO_DIR/modules/$mod_name/.target"
    local raw_path

    if [[ -f $target_file ]]; then
        raw_path=$(head -n 1 "$target_file" | xargs)
        echo "${raw_path/#\~/$HOME}"
    else
        echo "$HOME/.config/$mod_name"
    fi
}

rx_default_install() {
    local mod_name="$1"
    local mod_path="$RETRO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Installing $mod_name"

    if [[ -e $target_path && ! -L $target_path ]]; then
        if [[ ! -e "${target_path}.bak" ]]; then
            rx_log "warn" "Existing config found. Creating backup: ${target_path}.bak"
            mv "$target_path" "${target_path}.bak"
        else
            rx_log "warn" "Target exists but a backup is already present. Skipping backup to avoid overwriting original data."
            mv "$target_path" "${target_path}.dirty.$(date +%s)"
        fi
    fi

    if [[ -d "$mod_path/files" ]]; then
        rx_link "$mod_path/files" "$target_path"
    fi
}

rx_default_pull() {
    local mod_name="$1"
    local mod_path="$RETRO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Backing up $mod_name"

    if [[ -d $target_path ]]; then
        if [[ -L $target_path ]]; then
            rx_log "success" "$mod_name is linked, nothing to pull"
        else
            rx_mirror_pull "$target_path" "$mod_path/files"
            rx_log "success" "$mod_name backed up to repository"
        fi
    else
        rx_log "error" "Target path not found: $target_path"
    fi
}

rx_default_mirror() {
    local mod_name="$1"
    local mod_path="$RETRO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Mirroring $mod_name to $target_path"

    if [[ -d "$mod_path/files" ]]; then
        rx_mirror_install "$mod_path/files" "$target_path"
    else
        rx_log "error" "No config folder found for $mod_name"
    fi
}

rx_default_uninstall() {
    local mod_name="$1"
    local mod_path="$RETRO_DIR/modules/$mod_name"
    local target_path=$(get_target_path "$mod_name")

    rx_log "info" "Uninstalling module: $mod_name"

    if [[ -L $target_path ]]; then
        local link_destination=$(readlink -f "$target_path")
        if [[ $link_destination != "$mod_path"* ]]; then
            rx_log "error" "Target $target_path is a link but doesn't point to this module. Aborting to save your files!"
            return 1
        fi
    elif [[ -e $target_path ]]; then
        rx_log "warn" "$target_path is a real file/directory. Skipping deletion to prevent data loss."
        [[ -e "${target_path}.bak" ]] && rx_log "info" "Backup exists, but I won't overwrite current config with it."
        return 0
    fi

    rx_restore "$target_path"
}
