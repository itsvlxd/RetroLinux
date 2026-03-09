#!/bin/bash

get_module_paths() {
    local name="$1"
    local mod_path="$RETRO_DIR/modules/$name"
    local json_file="$mod_path/targets.json"

    local src_rel=$(rx_get_json "$json_file" "config" "files")
    local dest_path=$(rx_get_json "$json_file" "install" "$HOME/.config/$name")

    local src_path="$mod_path/$src_rel"
    echo "$src_path|$dest_path"
}

run_task() {
    local type="$1"
    local module="$2"

    if [[ $module == "all" || -z $module ]]; then
        for dir in "$RETRO_DIR"/modules/*/; do
            [[ -d $dir ]] || continue
            execute_logic "$type" "$(basename "$dir")"
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
    local pre_hook="$mod_path/pre.sh"
    local post_hook="$mod_path/post.sh"

    [[ ! -d $mod_path ]] && rx_log "error" "Module '$name' not found." && return 1

    local action_icon="${PINK}󰄾${RESET}"
    local action_msg=""
    case "$type" in
        "install")
            action_icon="${PINK}󰇚${RESET}"
            action_msg="Install ${PINK}$name${RESET}?"
            ;;
        "uninstall")
            action_icon="${PINK}󰈚${RESET}"
            action_msg="Uninstall ${PINK}$name${RESET}?"
            ;;
        "pull")
            action_icon="${PINK}󱇪${RESET}"
            action_msg="Pull changes for ${PINK}$name${RESET}?"
            ;;
        "mirror")
            action_icon="${PINK}󱂷${RESET}"
            action_msg="Mirror ${PINK}$name${RESET} to system?"
            ;;
        *) action_msg="Execute ${PINK}$type${RESET} on ${PINK}$name${RESET}?" ;;
    esac

    if [[ $SKIP_PROMPT == "false" ]]; then
        echo -ne " $action_icon $action_msg [Y/n]: "
        read -r opt
        [[ $opt =~ ^[Nn]$ ]] && return 0
    fi

    [[ -f $pre_hook ]] && (cd "$mod_path" && bash "./pre.sh" "$type")

    if [[ $type == "install" || $type == "mirror" ]]; then
        if [[ -f "$mod_path/packages.sh" ]]; then
            local sync_pkgs=true
            if [[ $SKIP_PROMPT == "false" ]]; then
                echo -ne " ${PINK}󱖫${RESET} Install dependencies for ${PINK}$name${RESET}? [Y/n]: "
                read -r pkg_opt
                [[ $pkg_opt =~ ^[Nn]$ ]] && sync_pkgs=false
            fi
            [[ $sync_pkgs == "true" ]] && rx_pkg_install "$mod_path/packages.sh"
        fi
    fi

    if [[ -f $script ]]; then
        (cd "$mod_path" && source "./${type}.sh")
    else
        case "$type" in
            "install") rx_default_install "$name" ;;
            "pull") rx_default_pull "$name" ;;
            "mirror") rx_default_mirror "$name" ;;
            "uninstall") rx_default_uninstall "$name" ;;
        esac
    fi

    [[ -f $post_hook ]] && (cd "$mod_path" && bash "./post.sh" "$type")
}

rx_default_install() {
    local name="$1"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    [[ -d $src ]] && rx_link "$src" "$dest"
}

rx_default_pull() {
    local name="$1"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    if [[ -d $dest ]]; then
        if [[ -L $dest ]]; then
            rx_log "success" "$name is already linked."
        else
            rx_mirror_pull "$dest" "$src"
        fi
    fi
}

rx_default_mirror() {
    local name="$1"
    IFS='|' read -r src dest <<<"$(get_module_paths "$name")"

    [[ -d $src ]] && rx_mirror_install "$src" "$dest"
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
