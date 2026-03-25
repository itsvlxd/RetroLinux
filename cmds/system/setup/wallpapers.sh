#!/bin/bash

source "$RETRO_DIR/cmds/tools/wallpaper.sh"

VAR_SCRIPT="$RETRO_DIR/scripts/variable_core.sh"
WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"
CACHE_WALLS="$HOME/.cache/retro/wallpapers"
SOURCE_WALLS="$RETRO_DIR/wallpapers"

rx_setup_wallpapers() {
    if [[ ! -d $SOURCE_WALLS ]]; then
        rx_log "error" "Source wallpapers not found in $SOURCE_WALLS"
        return 1
    fi

    local needs_update="false"
    if [[ ! -d $CACHE_WALLS ]]; then
        needs_update="true"
    else
        for src_theme in "$SOURCE_WALLS"/*/; do
            [[ -d $src_theme ]] || continue
            local theme_name=$(basename "$src_theme")

            for src_file in "$src_theme"/*; do
                [[ -e $src_file ]] || continue
                local filename=$(basename "$src_file")
                if [[ ! -e "$CACHE_WALLS/$theme_name/$filename" ]]; then
                    needs_update="true"
                    break 2
                fi
            done
        done
    fi

    if [[ $needs_update == "true" ]]; then
        rx_log "info" "Syncing new wallpaper assets..."
        mkdir -p "$CACHE_WALLS"
        cp -rn "$SOURCE_WALLS"/* "$CACHE_WALLS/"
    fi

    local current_theme=$(bash "$VAR_SCRIPT" --get "RETRO_THEME")
    if [[ -z $current_theme || $current_theme == "null" ]]; then
        rx_log "info" "Choose a default aesthetic for your desktop:"

        declare -a theme_dirs
        declare -a display_names
        local i=1

        for dir in "$SOURCE_WALLS"/*/; do
            [[ -d $dir ]] || continue

            local raw_name=$(basename "$dir")
            theme_dirs[$i]="$raw_name"

            local pretty_name=$(echo "$raw_name" | tr '_' ' ' | awk '{for(j=1;j<=NF;j++) $j=toupper(substr($j,1,1)) tolower(substr($j,2)); print}')
            display_names[$i]="$pretty_name"

            echo -e " ${PINK}$i)${RESET} $pretty_name"
            ((i++))
        done

        if ((i > 1)); then
            printf " ${PINK}󰄾${RESET} Select a theme [1-$((i - 1))]: "
            read theme_choice

            local selected_theme="${theme_dirs[$theme_choice]}"
            if [[ -z $selected_theme ]]; then
                selected_theme="retro"
                rx_log "error" "Invalid choice. Falling back to Retro."
            fi

            bash "$VAR_SCRIPT" --set "RETRO_THEME" "$selected_theme"
            rx_log "success" "Theme mapped to: ${PINK}${display_names[$theme_choice]}${RESET}"

            declare -A default_walls=(
                ["retro"]="car-in-neon-gas-station.mp4"
                ["black_and_white"]="monochrome-spider-man.mp4"
            )

            local def_wall="${default_walls[$selected_theme]}"

            if [[ -z $def_wall || ! -f "$CACHE_WALLS/$selected_theme/$def_wall" ]]; then
                def_wall=$(ls -1 "$CACHE_WALLS/$selected_theme" | grep -vE '\.[0-9]+x[0-9]+\.(mp4|mkv|webm)$' | head -n 1)
            fi

            if [[ -n $def_wall ]]; then
                bash "$WALL_CORE" --set "$def_wall" >/dev/null 2>&1 &
            fi
        fi
    fi

    if [[ -f $WALL_CORE ]]; then
        rx_log "info" "Generating missing wallpaper caches..."
        bash "$WALL_CORE" --cache

        local res_map=$(bash "$VAR_SCRIPT" --get "WALL_RES_MAP")
        if [[ -z $res_map || $res_map == "null" ]]; then
            echo -e ""
            rx_log "info" "Let's optimize your video wallpapers to save CPU overhead."
            cmd_wallpaper "res"
        else
            bash "$WALL_CORE" --restore >/dev/null 2>&1 &
        fi
    else
        rx_log "error" "Wallpaper core script missing."
        return 1
    fi

    rx_log "success" "Wallpaper system is fully configured."
}
