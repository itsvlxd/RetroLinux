#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/wallpaper.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "wallpaper"

add_wallpaper() {
    local source_file="$1"
    if [[ ! -f $source_file ]]; then
        rx_log_file "ERROR" "Add failed: source file not found: $source_file"
        echo "result=error|reason=file_not_found|path=$source_file"
        return 1
    fi

    local ext="${source_file##*.}"
    if [[ ! ${ext,,} =~ ^(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$ ]]; then
        rx_log_file "ERROR" "Add failed: unsupported format: $ext"
        echo "result=error|reason=unsupported_format|ext=$ext"
        return 1
    fi

    local collection
    collection=$(get_var "RETRO_WALL_COLLECTION" "retro")
    local target_dir="$WALL_DIR/$collection"
    mkdir -p "$target_dir"

    local filename=$(basename "$source_file")
    local target_file="$target_dir/$filename"

    if [[ -f $target_file ]]; then
        rx_log_file "WARN" "Wallpaper already exists, overwriting: $filename"
    fi

    cp "$source_file" "$target_file"
    rx_wallpaper_generate_cache "$target_file" >/dev/null

    rx_log_file "INFO" "Wallpaper added: $filename"
    rx_wallpaper_start "$target_file"
}

slideshow_next() {
    local target_dir=$(rx_wallpaper_get_theme_dir)
    local current=$(get_var "WALL_CURRENT")

    local next_wall
    while IFS= read -r wall; do
        [[ -z $wall ]] && continue
        [[ $wall == "$current" ]] && continue
        if check_wallpaper_resolution "$wall"; then
            next_wall="$wall"
            break
        fi
    done < <(rx_wallpaper_list_files | shuf)

    if [[ -n $next_wall ]]; then
        rx_log_file "INFO" "Slideshow advancing to: $(rx_format_string "$(basename "$next_wall")")"
        rx_wallpaper_start "$next_wall"
    else
        rx_log_file "WARN" "Slideshow skipped: no valid wallpapers found in $target_dir"
    fi
}

optimize_wallpapers() {
    local res_map=$(get_var "WALL_RES_MAP")

    if [[ -z $res_map || $res_map == "null" ]]; then
        local mon_res
        mon_res=$(get_monitor_resolutions)
        res_map="default|$mon_res"
    fi

    local target_res=$(echo "$res_map" | tr ',' '\n' | cut -d'|' -f2 | head -n 1)
    local target_w="${target_res%x*}"
    local target_h="${target_res#*x}"

    [[ -z $target_w || -z $target_h ]] && return 0

    local theme=$(get_var "RETRO_THEME" "retro")

    local source_dir="$REPO_WALLS/$theme"
    [[ ! -d $source_dir ]] && source_dir="$REPO_WALLS"

    local cache_target="$WALL_DIR/$theme"
    mkdir -p "$cache_target"

    local optimized=0
    local skipped=0

    for src_file in "$source_dir"/*; do
        [[ -f $src_file ]] || continue

        local filename=$(basename "$src_file")
        local ext="${filename##*.}"
        local is_video=false
        [[ ${ext,,} =~ ^(mp4|mkv|webm)$ ]] && is_video=true

        local opt_file="$cache_target/$filename"

        local src_res=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$src_file" 2>/dev/null)
        local src_w="${src_res%x*}"
        local src_h="${src_res#*x}"

        if [[ -z $src_w || -z $src_h ]]; then
            ln -sf "$src_file" "$opt_file"
            ((skipped++))
            continue
        fi

        if [[ $src_w -eq $target_w && $src_h -eq $target_h ]]; then
            if [[ ! -L $opt_file || $(readlink "$opt_file") != "$src_file" ]]; then
                rm -f "$opt_file"
                ln -sf "$src_file" "$opt_file"
            fi
            ((skipped++))
        else

            local cached_res=""
            if [[ -f $opt_file && ! -L $opt_file ]]; then
                cached_res=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$opt_file" 2>/dev/null)
            fi

            if [[ $cached_res != "${target_w}x${target_h}" ]]; then
                rm -f "$opt_file"

                if [[ $is_video == "true" ]]; then
                    ffmpeg -y -i "$src_file" \
                        -vf "scale=${target_w}:${target_h}:force_original_aspect_ratio=decrease,pad=${target_w}:${target_h}:(ow-iw)/2:(oh-ih)/2" \
                        -c:v libx264 -preset fast -crf 23 \
                        -an "$opt_file" -loglevel error
                    ((optimized++))
                else
                    magick "$src_file" -resize "${target_w}x${target_h}^" -gravity center -extent "${target_w}x${target_h}" "$opt_file"
                    ((optimized++))
                fi
            else
                ((skipped++))
            fi
        fi
    done

    rx_log_file "INFO" "Optimization complete: $optimized optimized, $skipped skipped"
    restore_wallpaper
}

get_monitor_resolutions() {
    local res_map=$(get_var "WALL_RES_MAP")

    if [[ -n $res_map && $res_map != "null" ]]; then
        echo "$res_map" | tr ',' '\n' | cut -d'|' -f2
        return 0
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl monitors -j | jq -r '.[] | "\(.description)|\(.x)\((.width/.scale)|0floor)x\((.height/.scale)|0floor)"' 2>/dev/null | cut -d'|' -f2
        return 0
    fi

    local primary
    primary=$(cat /sys/class/drm/card0-HDMI-A-1/modes 2>/dev/null | head -1)
    if [[ -n $primary ]]; then
        echo "$primary"
        return 0
    fi

    echo "1920x1080"
}

get_image_resolution() {
    local file="$1"
    [[ -z $file || ! -f $file ]] && return 1

    local ext="${file##*.}"

    if [[ ${ext,,} =~ ^(mp4|mkv|webm)$ ]]; then
        ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$file" 2>/dev/null
    else
        magick "$file" -format "%wx%h" info:
    fi
}

check_wallpaper_resolution() {
    local file="$1"
    [[ -z $file || ! -f $file ]] && return 1

    local file_res
    file_res=$(get_image_resolution "$file")
    [[ -z $file_res ]] && return 1

    local file_w="${file_res%x*}"
    local file_h="${file_res#*x}"

    while IFS= read -r mon_res; do
        [[ -z $mon_res ]] && continue
        local mon_w="${mon_res%x*}"
        local mon_h="${mon_res#*x}"

        if [[ $file_w -eq $mon_w && $file_h -eq $mon_h ]]; then
            return 0
        fi
    done < <(get_monitor_resolutions)

    return 1
}

list_wallpapers_with_resolution() {
    local target_dir=$(rx_wallpaper_get_theme_dir)
    local show_all="${1:-false}"

    local valid_count=0
    local invalid_count=0

    while IFS= read -r f; do
        [[ -z $f ]] && continue

        local filename=$(basename "$f")

        if [[ $filename =~ \.[0-9]+x[0-9]+\.(mp4|mkv|webm)$ ]]; then
            continue
        fi

        local file_res
        file_res=$(get_image_resolution "$f")

        local status="MATCH"
        if ! check_wallpaper_resolution "$f"; then
            status="MISMATCH"
            ((invalid_count++))
        else
            ((valid_count++))
        fi

        if [[ $show_all == "true" || $status == "MISMATCH" ]]; then
            echo "$status|$filename|${file_res:-unknown}"
        fi
    done < <(rx_wallpaper_list_files)

    echo "valid=$valid_count|invalid=$invalid_count"
}

set_wallpaper() {
    local input="$1"
    local name=$(basename "$input")
    rx_log_file "INFO" "Setting wallpaper: $(rx_format_string "${name%.*}")"

    if [[ ! -f $input ]]; then
        rx_log_file "ERROR" "Wallpaper file not found: $input"
        echo "ERR|file_not_found|$input"
        return 1
    fi

    if [[ -L $input ]]; then
        local link_target=$(readlink -f "$input")
        if [[ ! -f $link_target ]]; then
            rx_log_file "ERROR" "Symlink target missing: $input -> $link_target"
            echo "ERR|symlink_broken|$input|$link_target"
            return 1
        fi
    fi

    if ! rx_wallpaper_start "$input" "${2:-false}"; then
        rx_log_file "ERROR" "Failed to start wallpaper: $input"
        echo "ERR|wallpaper_start_failed|$input"
        return 1
    fi

    echo "OK|$input"
}

restore_wallpaper() {
    local last_wall=$(get_var "WALL_CURRENT")
    if [[ -z $last_wall || $last_wall == "null" ]]; then
        rx_log_file "ERROR" "Restore failed: WALL_CURRENT is not set"
        echo "ERR|WALL_CURRENT_not_set"
        return 1
    fi

    rx_log_file "INFO" "Restoring wallpaper: $last_wall"

    if [[ ! -f $last_wall ]]; then
        rx_log_file "ERROR" "Restore failed: wallpaper file not found: $last_wall"
        echo "ERR|file_not_found|$last_wall"
        return 1
    fi

    if [[ -L $last_wall ]]; then
        local link_target=$(readlink -f "$last_wall")
        if [[ ! -f $link_target ]]; then
            rx_log_file "ERROR" "Restore failed: symlink target missing: $last_wall -> $link_target"
            echo "ERR|symlink_broken|$last_wall|$link_target"
            return 1
        fi
        rx_log_file "INFO" "Symlink: $last_wall -> $link_target"
    fi

    local filename=$(basename "$last_wall")
    local ext="${filename##*.}"
    local is_video=false
    [[ $ext =~ ^(mp4|mkv|webm)$ ]] && is_video=true

    if [[ $is_video == "true" ]]; then
        local video_path=$(rx_wallpaper_find_video "$last_wall")
        if [[ -n $video_path ]]; then
            rx_log_file "INFO" "Video version found: $video_path"
        else
            rx_log_file "WARN" "No video version found for: $filename"
        fi
    fi

    rx_wallpaper_start "$last_wall" "${1:-false}"
    echo "OK|$last_wall"
}

static_wallpaper() {
    local current=$(get_var "WALL_STATIC_FORCED")
    local new_state="$2"
    if [[ -z $new_state || $new_state == "toggle" ]]; then
        [[ $current == "true" ]] && new_state="false" || new_state="true"
    fi
    set_var "WALL_STATIC_FORCED" "$new_state"
    if [[ $new_state == "true" ]]; then
        rx_log_file "INFO" "Static mode enabled"
    else
        rx_log_file "INFO" "Static mode disabled"
    fi
    restore_wallpaper
}

pause_wallpaper() {
    pkill mpvpaper 2>/dev/null
    set_var "WALL_PAUSED" "true"
    rx_log_file "INFO" "Wallpaper paused (mpvpaper killed)"
    echo "OK|paused"
}

resume_wallpaper() {
    local current_wall=$(get_var "WALL_CURRENT")
    local video_path=$(rx_wallpaper_find_video "$current_wall")
    if [[ -n $video_path ]]; then
        rx_log_file "INFO" "Resuming with video: $(basename "$video_path")"
    else
        rx_log_file "WARN" "Resume attempted but no video version found for: $current_wall"
        echo "ERR|no_video_version|$current_wall"
        return 1
    fi
    rx_wallpaper_resume
    echo "OK|$video_path"
}

should_pause() {
    rx_wallpaper_should_pause
}

launch_picker() {
    local theme_conf="$HOME/.config/rofi/themes/gallery.rasi"
    local list=""
    local target_dir=$(rx_wallpaper_get_theme_dir)
    local collection
    collection=$(get_var "RETRO_WALL_COLLECTION" "retro")

    declare -A wall_map

    while IFS= read -r f; do
        [[ -z $f ]] && continue

        local filename=$(basename "$f")

        if [[ $filename =~ \.[0-9]+x[0-9]+\.(mp4|mkv|webm)$ ]]; then
            continue
        fi

        local display=$(rx_format_string "$filename")
        local thumb=$(rx_wallpaper_generate_cache "$f")

        wall_map["$display"]="$f"
        list+="${display}\0icon\x1f${thumb}\n"
    done < <(rx_wallpaper_list_files)

    if [[ -z $list ]]; then
        echo "result=error|reason=no_files_found|path=$target_dir"
        return 1
    fi

    local alpha=$(get_opacity_hex "0.9")
    local alpha_alt=$(get_opacity_hex "0.6")
    local base_bg=$(grep "background:" ~/.config/retro/themes/rofi-colors.rasi 2>/dev/null | awk '{print $2}' | sed 's/[#;FF]//g')
    local base_bg_alt=$(grep "background-alt:" ~/.config/retro/themes/rofi-colors.rasi 2>/dev/null | awk '{print $2}' | sed 's/[#;FF]//g')

    : ${base_bg:="1A1B26"}
    : ${base_bg_alt:="24283B"}

    local folder_name="${target_dir##*/}"

    local choice=$(printf "%b" "$list" | rofi -dmenu -i -p "󰸉 Wallpapers (${collection^})" -theme "$theme_conf" -theme-str "
                window { background-color: #${base_bg}${alpha}; } 
                inputbar { background-color: #${base_bg}${alpha}; }  
                element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
            ")

    if [[ -n $choice ]]; then
        local actual_file="${wall_map[$choice]}"

        if [[ -n $actual_file ]]; then
            set_wallpaper "$actual_file"
        fi
    fi
}

resolve_name() {
    local display_name="$1"
    [[ -z $display_name ]] && return 1

    local search_pattern=$(echo "$display_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')

    while IFS= read -r f; do
        [[ -z $f ]] && continue
        local filename=$(basename "$f")
        [[ $filename =~ \.[0-9]+x[0-9]+\.(mp4|mkv|webm)$ ]] && continue
        local raw="${filename%.*}"
        local raw_lower=$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
        if [[ "$raw_lower" == "$search_pattern" ]]; then
            echo "$f"
            return 0
        fi
    done < <(rx_wallpaper_list_files)
    return 1
}

gpu_wallpaper() {
    local action="${1:-status}"

    case "$action" in
        status)
            local mode=$(get_var "WALL_GPU_OFFLOAD" "auto")
            local vendor="none"
            local driver="none"
            local model="none"

            if command -v lspci >/dev/null 2>&1; then
                local gpu_line=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | head -1)
                if [[ -n $gpu_line ]]; then
                    local pci_id=$(echo "$gpu_line" | awk '{print $1}')
                    local vendor_id=$(lspci -nn -s "$pci_id" 2>/dev/null | grep -oP '\[([0-9a-f]{4}):' | tr -d '[][')
                    vendor_id="${vendor_id%%:*}"
                    model=$(lspci -s "$pci_id" 2>/dev/null | sed 's/^[^:]*: //' | sed 's/.*VGA compatible controller: //;s/.*3D controller: //;s/.*Display controller: //')
                    case "$vendor_id" in
                        10de) vendor="nvidia" ;;
                        1002) vendor="amd" ;;
                        8086) vendor="intel" ;;
                    esac
                    driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
                fi
            fi

            local installed="no"
            case "$vendor" in
                nvidia) pacman -Qq "nvidia-utils" >/dev/null 2>&1 && installed="yes" ;;
                amd) pacman -Qq "mesa" >/dev/null 2>&1 && installed="yes" ;;
                intel) pacman -Qq "mesa" >/dev/null 2>&1 && installed="yes" ;;
            esac

            echo "mode=$mode|vendor=$vendor|model=$model|driver=$driver|installed=$installed"
            ;;
        auto|nvidia|amd|intel|off)
            set_var "WALL_GPU_OFFLOAD" "$action"
            rx_log_file "INFO" "GPU offload mode set to: $action"
            restore_wallpaper >/dev/null 2>&1
            ;;
        *)
            echo "result=error|reason=invalid_action|action=$action"
            return 1
            ;;
    esac
}

sync_wallpapers() {
    local source_dir="$REPO_WALLS"
    [[ ! -d $source_dir ]] && echo "result=error|reason=repo_not_found" && return 1

    local synced=0
    local skipped=0

    for theme_dir in "$source_dir"/*/; do
        [[ -d $theme_dir ]] || continue
        local theme_name=$(basename "$theme_dir")
        local config_theme="$WALL_DIR/$theme_name"
        mkdir -p "$config_theme"

        for src_file in "$theme_dir"/*; do
            [[ -f $src_file ]] || continue

            local filename=$(basename "$src_file")
            local target_file="$config_theme/$filename"

            if [[ -f $target_file || -L $target_file ]]; then
                ((skipped++))
            else
                cp "$src_file" "$target_file"
                ((synced++))
            fi
        done
    done

    rx_log_file "info" "Wallpaper sync: ${synced} new, ${skipped} skipped"
}

case "$1" in
    "--set") set_wallpaper "$2" "${3:-false}" ;;
    "--add") add_wallpaper "$2" ;;
    "--slideshow-next") slideshow_next ;;
    "--optimize") optimize_wallpapers ;;
    "--check-resolution")
        if [[ -n $2 ]]; then
            if check_wallpaper_resolution "$2"; then
                echo "result=match|file=$2"
            else
                res=$(get_image_resolution "$2")
                echo "result=mismatch|file=$2|resolution=${res:-unknown}"
            fi
        else
            list_wallpapers_with_resolution "${2:-true}"
        fi
        ;;
    "--cache")
        rm -rf "$FRAME_CACHE"
        mkdir -p "$FRAME_CACHE"

        if [[ -n $2 ]]; then
            rx_wallpaper_generate_cache "$2" >/dev/null
        else
            while IFS= read -r f; do
                [[ -z $f ]] && continue
                rx_wallpaper_generate_cache "$f" >/dev/null
            done < <(rx_wallpaper_list_files)
        fi
        ;;
    "--precache-all")
        mkdir -p "$FRAME_CACHE"
        while IFS= read -r f; do
            [[ -z $f ]] && continue
            ext="${f##*.}"
            if [[ ${ext,,} =~ ^(mp4|mkv|webm)$ ]]; then
                rx_wallpaper_generate_cache "$f" >/dev/null
            fi
        done < <(rx_wallpaper_list_files)
        ;;
    "--restore") restore_wallpaper "${2:-false}" ;;
    "--static") static_wallpaper "$2" ;;
    "--pause") pause_wallpaper ;;
    "--resume") resume_wallpaper ;;
    "--should-pause") should_pause && echo "should_pause=true" || echo "should_pause=false" ;;
    "--list")
        target_dir=$(rx_wallpaper_get_theme_dir)
        if [[ ${2:-} == "--with-resolution" || ${2:-} == "-r" ]]; then
            list_wallpapers_with_resolution true
        else
            while IFS= read -r f; do
                [[ -z $f ]] && continue
                echo "$(basename "$f")"
            done < <(rx_wallpaper_list_files)
        fi
        ;;
    "--list-with-res")
        while IFS= read -r f; do
            [[ -z $f ]] && continue
            filename=$(basename "$f")
            [[ $filename =~ \.[0-9]+x[0-9]+\.(mp4|mkv|webm)$ ]] && continue
            res=$(get_image_resolution "$f")
            [[ -z $res ]] && res="unknown"
            echo "$filename|$res"
        done < <(rx_wallpaper_list_files)
        ;;
    "--resolve-name")
        resolve_name "$2"
        ;;
    "--get-resolution")
        if [[ -n $2 && -f $2 ]]; then
            get_image_resolution "$2"
        else
            echo "unknown"
        fi
        ;;
    "--sync")
        sync_wallpapers
        ;;
    "--gpu")
        gpu_wallpaper "$2"
        ;;
    "--collection")
        new_collection="$2"
        current_collection=$(get_var "RETRO_WALL_COLLECTION" "retro")

        if [[ -z $new_collection ]]; then
            echo "current=$current_collection"
            exit 0
        fi

        if [[ $new_collection == "list" ]]; then
            found=false
            for d in "$WALL_DIR"/*/; do
                [[ -d $d ]] || continue
                echo "$(basename "$d")"
                found=true
            done
            [[ $found == false ]] && echo "(no collections yet)"
            exit 0
        fi

        set_var "RETRO_WALL_COLLECTION" "$new_collection"

        if [[ $new_collection != "all" ]]; then
            target="$WALL_DIR/$new_collection"
            mkdir -p "$target"
        fi

        restore_wallpaper >/dev/null 2>&1
        echo "collection=$new_collection"
        ;;
    "--picker") launch_picker ;;
    "--setup-get")
        theme=$(get_var "RETRO_THEME" "retro")
        current=$(get_var "WALL_CURRENT" "")
        collection=$(get_var "RETRO_WALL_COLLECTION" "retro")
        echo "theme=${theme}"
        echo "collection=${collection}"
        echo "wallpaper=$(basename "$current")"
        ;;
    "--setup-apply")
        theme="${2:-retro}"
        sync_wallpapers
        set_var "RETRO_THEME" "$theme"
        set_var "RETRO_WALL_COLLECTION" "$theme"

        declare -A default_walls=(
            ["retro"]="car-in-neon-gas-station.mp4"
            ["black_and_white"]="monochrome-spider-man.mp4"
        )
        def_wall="${default_walls[$theme]}"
        if [[ -z $def_wall || ! -f "$WALL_DIR/$theme/$def_wall" ]]; then
            def_wall=$(ls -1 "$WALL_DIR/$theme" 2>/dev/null | grep -vE '\.[0-9]+x[0-9]+\.(mp4|mkv|webm)$' | head -n 1)
        fi

        if [[ -n $def_wall ]]; then
            rx_wallpaper_start "$WALL_DIR/$theme/$def_wall" "true" &>/dev/null &
        fi

        # TODO: Auto-detect per-monitor resolution and pre-configure WALL_RES_MAP
        # TODO: Generate theme-specific matugen color template on setup
        # TODO: Add size-optimized video re-encoding to target resolution
        # TODO: Build a proper theme management tool (themes folder, icon packs, qtile/gtk integration)
        # TODO: Add animated preview thumbnail generation for all wallpapers in the theme pool
        rm -rf "$FRAME_CACHE"
        mkdir -p "$FRAME_CACHE"
        target_dir="$WALL_DIR/$theme"
        while IFS= read -r f; do
            [[ -z $f ]] && continue
            rx_wallpaper_generate_cache "$f" >/dev/null
        done < <(rx_wallpaper_list_files)

        echo "OK|configured|theme=${theme}|wallpaper=${def_wall:-none}"
        rx_log_file "success" "Wallpaper configured (theme=${theme})"
        ;;
esac
