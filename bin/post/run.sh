#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

POST_DIR="/opt/retrolinux/bin/post"
EXCLUDE_SCRIPTS=("run.sh")

rx_discover_scripts() {
    local scripts=()
    for script in "$POST_DIR"/*.sh; do
        [[ -f $script && -x $script ]] || continue
        local basename="${script##*/}"
        [[ " ${EXCLUDE_SCRIPTS[*]} " =~ " ${basename} " ]] && continue
        scripts+=("$script")
    done

    local priority_scripts=(
        "packages.sh"
        "network.sh"
        "aur.sh"
        "clone.sh"
        "state.sh"
        "modules.sh")
    local sorted_scripts=()
    local remaining_scripts=()

    for priority in "${priority_scripts[@]}"; do
        for script in "${scripts[@]}"; do
            [[ $script == *"$priority" ]] && sorted_scripts+=("$script") && break
        done
    done

    for script in "${scripts[@]}"; do
        local found=false
        for p in "${sorted_scripts[@]}"; do
            [[ $script == "$p" ]] && found=true && break
        done
        [[ $found == false ]] && remaining_scripts+=("$script")
    done

    printf '%s\n' "${sorted_scripts[@]}" "${remaining_scripts[@]}"
}

rx_run_post_install() {
    rx_clear_logo
    gum style --foreground 5 "Post-Installation Configuration" --padding "1 0 1 $PADDING_LEFT"
    gum style --foreground 7 "Applying final system configuration..." --padding "1 0 1 $PADDING_LEFT"

    local scripts
    mapfile -t scripts < <(rx_discover_scripts)
    local total=${#scripts[@]}
    local current=0

    for script in "${scripts[@]}"; do
        ((current++))
        local name="${script##*/}"
        local name_without_ext="${name%.sh}"
        local display_name="${name_without_ext//_/ }"

        gum style --foreground 7 "Step ${current}/${total}: Configuring ${display_name}..." --padding "1 0 1 $PADDING_LEFT"
        if bash "$script"; then
            gum style --foreground 2 "  ${display_name^} configured" --padding "1 0 1 $PADDING_LEFT"
        else
            gum style --foreground 1 "  ${display_name^} failed" --padding "1 0 1 $PADDING_LEFT"
        fi
        if [[ $RX_DEBUG == 1 ]]; then
            gum style --foreground 7 "Press Enter to continue..." --padding "1 0 1 $PADDING_LEFT"
            read -r
        fi
    done

    gum style --foreground 2 "Post-installation complete!" --padding "1 0 1 $PADDING_LEFT"
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_run_post_install "$@"
fi
