#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

MODULE_TYPE_FILTER=""
MODULE_ACCESS_FILTER=""

get_installed_modules() {
    local access="$1"
    
    for dir in "$RETRO_DIR"/modules/*/; do
        [[ -d $dir ]] || continue
        local mod_name=$(basename "$dir")
        
        rx_module_status "$mod_name"
        local status_code=$?
        
        [[ $status_code -eq 2 ]] && continue
        
        local mod_access=$(get_module_access "$mod_name")
        
        if [[ -n $access ]]; then
            [[ "$mod_access" == "$access" ]] && echo "$mod_name"
        else
            echo "$mod_name"
        fi
    done
}

get_module_paths() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    local src_rel=$(rx_get_json "$json_file" "config" "files")
    local dest_path=$(rx_get_json "$json_file" "install" "$HOME/.config/$name")

    local src_path="$mod_path/$src_rel"
    echo "$src_path|$dest_path"
}

get_module_type() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "type" "extra" 2>/dev/null
}

get_module_access() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "access" "user" 2>/dev/null
}

get_module_defaults() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "defaults" "false" 2>/dev/null
}

get_module_mode() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "mode" "all" 2>/dev/null
}

get_module_overwrite() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "overwrite" "false" 2>/dev/null
}

get_module_check() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "check" "" 2>/dev/null
}

get_module_files() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    local raw
    raw=$(rx_get_json "$json_file" "files" "" 2>/dev/null)
    [[ -z $raw ]] && return 0
    echo "$raw" | jq -r '.[]? // empty' 2>/dev/null
}

get_module_dependencies() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    local raw
    raw=$(rx_get_json "$json_file" "dependencies" "" 2>/dev/null)
    [[ -z $raw ]] && return 0
    echo "$raw" | jq -r '.[]? // empty' 2>/dev/null
}

get_module_uninstall_pkgs() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "uninstall_pkgs" "false" 2>/dev/null
}

get_module_gui() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/properties.json"

    rx_get_json "$json_file" "gui" "false" 2>/dev/null
}

is_core_module() {
    local name="$1"
    local mod_type=$(get_module_type "$name")

    [[ $mod_type == "core" ]]
}

filter_module() {
    local name="$1"

    if [[ -n $MODULE_TYPE_FILTER && $MODULE_TYPE_FILTER != "all" ]]; then
        local mod_type=$(get_module_type "$name")
        [[ $mod_type != "$MODULE_TYPE_FILTER" ]] && return 1
    fi

    if [[ -n $MODULE_ACCESS_FILTER && $MODULE_ACCESS_FILTER != "all" ]]; then
        local mod_access=$(get_module_access "$name")
        [[ $mod_access != "$MODULE_ACCESS_FILTER" ]] && return 1
    fi

    if [[ ${RETRO_SETUP:-false} == "true" || ${RETRO_CHROOT:-false} == "true" ]]; then
        local mod_gui=$(get_module_gui "$name")
        if [[ $mod_gui == "true" ]]; then
            rx_log "warn" "Skipping $name — requires a working GUI session. Install later with 'retro -i $name'"
            return 1
        fi
    fi

    return 0
}

run_task() {
    local type="$1"
    local module="$2"

    if [[ $module == "all" || -z $module ]]; then
        for dir in "$RETRO_DIR"/modules/*/; do
            [[ -d $dir ]] || continue

            local mod_name=$(basename "$dir")

            filter_module "$mod_name" && execute_logic "$type" "$mod_name"
        done
    elif [[ $module == "existing" ]]; then
        local access_filter=""
        [[ -n $MODULE_ACCESS_FILTER && $MODULE_ACCESS_FILTER != "all" ]] && access_filter="$MODULE_ACCESS_FILTER"
        
        while IFS= read -r installed_mod; do
            [[ -z $installed_mod ]] && continue
            filter_module "$installed_mod" && execute_logic "$type" "$installed_mod"
        done < <(get_installed_modules "$access_filter")
    else
        if [[ -d "$RETRO_DIR/modules/$module" ]]; then
            filter_module "$module" && execute_logic "$type" "$module"
        else
            execute_logic "$type" "$module"
        fi
    fi
}

run_default_task() {
    local type="$1"
    local name="$2"
    local mode=$(get_module_mode "$name")

    case "$type" in
        "install")
            if [[ $mode == "mirror" ]]; then
                rx_log "warn" "$name is set to 'mirror' mode. Overriding to mirror (copying files)..."
                rx_default_mirror "$name"
            else
                rx_default_install "$name"
            fi
            ;;
        "mirror")
            if [[ $mode == "install" ]]; then
                rx_log "warn" "$name is set to 'install' mode. Overriding to install (symlinking files)..."
                rx_default_install "$name"
            else
                rx_default_mirror "$name"
            fi
            ;;
        "pull") rx_default_pull "$name" ;;
        "uninstall") rx_default_uninstall "$name" ;;
    esac
}

execute_logic() {
    local type="$1"
    local name="$2"
    shift 2
    local extra_args=("$@")

    local mod_path="$RETRO_DIR/modules/$name"
    local script="$mod_path/${type}.sh"
    local pre_hook="$mod_path/pre.sh"
    local post_hook="$mod_path/post.sh"

    [[ ! -d $mod_path ]] && rx_log "error" "Module '$name' not found." && return 1

    local dep
    while IFS= read -r dep; do
        [[ -z $dep ]] && continue
        if [[ $type == "install" ]]; then
            local dep_path="$RETRO_DIR/modules/$dep"
            if [[ -d $dep_path ]]; then
                if ! rx_module_status "$dep" >/dev/null 2>&1; then
                    rx_log "info" "Installing dependency: ${PINK}$dep${RESET}..."
                    execute_logic "install" "$dep"
                fi
            fi
        fi
    done <<< "$(get_module_dependencies "$name")"

    local mod_access=$(get_module_access "$name")
    if [[ $mod_access == "root" && $EUID -ne 0 ]]; then
        rx_log "warn" "Module '${name}' requires root permissions, running with sudo..."
        local y_flag=""
        [[ $SKIP_PROMPT == "true" ]] && y_flag="-y"
        sudo RETRO_CONFIG="$RETRO_CONFIG" "$RETRO_DIR/retro.sh" -i "$name" $y_flag "${extra_args[@]}"
        return $?
    fi

    if [[ $type == "uninstall" ]] && is_core_module "$name"; then
        rx_log "error" "Cannot uninstall core module '$name'. Core modules are required by the system."
        return 1
    fi

    local action_icon="${PINK}󰄾${RESET}"
    local action_msg=""
    case "$type" in
        "install")
            action_icon="${PINK}󰇚${RESET}"
            action_msg="Would you like to install ${PINK}$name${RESET}?"
            ;;
        "uninstall")
            action_icon="${PINK}󰈚${RESET}"
            action_msg="Would you like to uninstall ${PINK}$name${RESET}?"
            ;;
        "pull")
            action_icon="${PINK}󱇪${RESET}"
            action_msg="Would you like to pull changes for ${PINK}$name${RESET}?"
            ;;
        "mirror")
            action_icon="${PINK}󱂷${RESET}"
            action_msg="Mirror ${PINK}$name${RESET} to system?"
            ;;
        *) action_msg="Execute ${PINK}$type${RESET} on ${PINK}$name${RESET}?" ;;
    esac

    if [[ $SKIP_PROMPT != "true" ]]; then
        echo -ne " $action_icon $action_msg ${PINK}[Y/n]${RESET}: "
        read -r opt
        [[ $opt =~ ^[Nn]$ ]] && return 0
    fi

    [[ -f $pre_hook ]] && (cd "$mod_path" && bash "./pre.sh" "$type")

    if [[ $type == "install" || $type == "mirror" ]]; then
        if [[ -f "$mod_path/packages.sh" ]]; then
            local sync_pkgs=true

            if [[ $SKIP_PROMPT != "true" ]]; then
                echo -ne " ${PINK}󱖫${RESET} Install dependencies for ${PINK}$name${RESET}? ${PINK}[Y/n]${RESET}: "

                read -r pkg_opt

                [[ $pkg_opt =~ ^[Nn]$ ]] && sync_pkgs=false
            fi

            [[ $sync_pkgs == "true" ]] && rx_pkg_install "$mod_path/packages.sh"
        fi
    fi

    local use_defaults=$(get_module_defaults "$name")

    if [[ -f $script ]]; then
        rx_log "info" "Running custom ${type} script for $name..."
        (cd "$mod_path" && source "./${type}.sh")

        if [[ $use_defaults == "true" ]]; then
            rx_log "info" "Applying default ${type} logic for $name..."
            run_default_task "$type" "$name"
        fi
    else
        run_default_task "$type" "$name"
    fi

    if [[ $type == "uninstall" && $(get_module_uninstall_pkgs "$name") == "true" && -f "$mod_path/packages.sh" ]]; then
        rx_pkg_uninstall "$mod_path/packages.sh"
    fi

    [[ -f $post_hook ]] && (cd "$mod_path" && bash "./post.sh" "$type")

    case "$type" in
        "install") rx_log "success" "Module ${PINK}$name${RESET} installed successfully" ;;
        "uninstall") rx_log "success" "Module ${PINK}$name${RESET} uninstalled successfully" ;;
        "pull") rx_log "success" "Module ${PINK}$name${RESET} updated successfully" ;;
        "mirror") rx_log "success" "Module ${PINK}$name${RESET} mirrored successfully" ;;
    esac
}

rx_default_install() {
    local name="$1"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    local tracked_files
    tracked_files=$(get_module_files "$name")

    if [[ -n $tracked_files ]]; then
        rx_log "info" "Linking specific tracked files for ${PINK}$name${RESET}..."
        while IFS= read -r file; do
            [[ -z $file ]] && continue
            local repo_file="$src/$file"
            local system_file="$dest/$file"
            [[ -e $repo_file ]] && rx_link "$repo_file" "$system_file"
        done <<< "$tracked_files"
    else
        [[ -d $src ]] && rx_link "$src" "$dest"
    fi
}

rx_default_pull() {
    local name="$1"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    local tracked_files
    tracked_files=$(get_module_files "$name")

    if [[ -n $tracked_files ]]; then
        rx_log "info" "Pulling specific tracked files for ${PINK}$name${RESET}..."
        while IFS= read -r file; do
            [[ -z $file ]] && continue
            local system_file="$dest/$file"
            local repo_file="$src/$file"
            if [[ -e $system_file ]]; then
                mkdir -p "$(dirname "$repo_file")"
                cp "$system_file" "$repo_file"
            fi
        done <<< "$tracked_files"
    else
        if [[ -d $dest ]]; then
            if [[ -L $dest ]]; then
                rx_log "success" "Module ${PINK}$name${RESET} is already linked, skipping"
            else
                rx_mirror_pull "$dest" "$src"
            fi
        fi
    fi
}

rx_default_mirror() {
    local name="$1"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    [[ -d $src ]] || return 0

    local ricing=$(get_var "RETRO_RICING" "false")
    local overwrite=$(get_module_overwrite "$name")

    if [[ $ricing == "true" || $overwrite == "true" ]]; then
        rx_mirror_install "$src" "$dest"
    else
        rx_mirror_add_missing "$src" "$dest"
    fi
}

rx_default_uninstall() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    if [[ -L $dest ]]; then
        local link_target=$(readlink -f "$dest")
        [[ $link_target == "$mod_path"* ]] && rm "$dest"
    fi

    rx_restore "$dest"
}
