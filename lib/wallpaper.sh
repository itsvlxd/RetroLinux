#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"

WALL_DIR="$RETRO_CONFIG/wallpapers"
FRAME_CACHE="$RETRO_CONFIG/wallpaper_frames"
REPO_WALLS="$RETRO_DIR/wallpapers"
MPV_SOCKET="/tmp/mpvsocket"

mkdir -p "$FRAME_CACHE" "$WALL_DIR"

rx_wallpaper_generate_cache() {
    local target="$1"
    [[ -z $target ]] && return 1

    local filename=$(basename "$target")
    local output="$FRAME_CACHE/${filename}.png"

    if [[ ! -f $output ]]; then
        if [[ $target =~ \.(mp4|mkv|webm)$ ]]; then
            ffmpeg -i "$target" -frames:v 1 "$output" -y -loglevel quiet
        else
            ln -sf "$target" "$output"
        fi
    fi
    echo "$output"
}

rx_wallpaper_get_theme_dir() {
    local collection
    collection=$(get_var "RETRO_WALL_COLLECTION" "retro")

    if [[ $collection == "all" ]]; then
        echo "$WALL_DIR"
        return 0
    fi

    local target="$WALL_DIR/$collection"
    if [[ -d $target ]]; then
        echo "$target"
    else
        mkdir -p "$target"
        echo "$target"
    fi
}

rx_wallpaper_list_files() {
    local collection_override="${1:-}"
    local target_dir
    local collection

    if [[ -n $collection_override ]]; then
        collection="$collection_override"
    else
        collection=$(get_var "RETRO_WALL_COLLECTION" "retro")
    fi

    if [[ $collection == "all" ]]; then
        target_dir="$WALL_DIR"
    else
        target_dir="$WALL_DIR/$collection"
        mkdir -p "$target_dir"
    fi

    if [[ $collection == "all" ]]; then
        find "$target_dir" -maxdepth 2 \( -type f -o -type l \) 2>/dev/null \
            | grep -iE "\.(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$" \
            | grep -vE "\.[0-9]+x[0-9]+\.(mp4|mkv|webm)$" \
            | sort
    else
        find "$target_dir" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null \
            | grep -iE "\.(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$" \
            | grep -vE "\.[0-9]+x[0-9]+\.(mp4|mkv|webm)$" \
            | sort
    fi
}

rx_wallpaper_resolve_path() {
    local input="$1"
    local theme_dir=$(rx_wallpaper_get_theme_dir)
    local collection
    collection=$(get_var "RETRO_WALL_COLLECTION" "retro")

    if [[ -f $input ]]; then
        echo "$input"
    elif [[ -f "$theme_dir/$input" ]]; then
        echo "$theme_dir/$input"
    elif [[ -f "$WALL_DIR/$input" ]]; then
        echo "$WALL_DIR/$input"
    elif [[ $collection == "all" ]]; then
        local found
        found=$(find "$WALL_DIR" -maxdepth 2 -name "$input" -type f 2>/dev/null | head -1)
        if [[ -n $found ]]; then
            echo "$found"
        else
            return 1
        fi
    else
        return 1
    fi
}

rx_wallpaper_find_video() {
    local path="$1"
    [[ -z $path ]] && return 1

    if [[ $path =~ \.(mp4|mkv|webm)$ ]]; then
        echo "$path"
        return 0
    fi

    local base="${path%.*}"
    for ext in mp4 mkv webm; do
        if [[ -f "${base}.${ext}" ]]; then
            echo "${base}.${ext}"
            return 0
        fi
    done

    return 1
}

rx_wallpaper_is_static() {
    local is_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
    local static_on_saver=$(get_var "WALL_STATIC_ON_SAVER" "true")
    local force_static=$(get_var "WALL_STATIC_FORCED" "false")
    local static_on_bat=$(get_var "WALL_STATIC_ON_BAT" "false")

    [[ $force_static == "true" ]] && return 0

    if [[ $is_saver == "true" ]]; then
        [[ $static_on_saver == "true" ]] && return 0
        return 1
    fi

    [[ $(is_on_battery) == "true" && $static_on_bat == "true" ]] && return 0
    return 1
}

rx_wallpaper_ensure_awww() {
    if ! pgrep -f "awww-daemon" >/dev/null 2>&1; then
        nohup awww-daemon >/dev/null 2>&1 &
        for i in $(seq 1 10); do
            sleep 0.2
            awww query >/dev/null 2>&1 && break
        done
        return 0
    fi
    return 1
}

rx_wallpaper_set_image() {
    local source="$1"
    local quick="${2:-false}"
    local is_first="$3"
    local monitor="${4:-}"
    local mon_opt=""
    [[ -n $monitor ]] && mon_opt="-o $monitor"

    if [[ $is_first == "true" || $quick == "true" ]]; then
        awww img "$source" $mon_opt --transition-type none
    else
        local rand_x=$((RANDOM % 1920))
        local rand_y=$((RANDOM % 1080))
        awww img "$source" $mon_opt \
            --transition-type random \
            --transition-duration 2.4 \
            --transition-fps 120 \
            --transition-pos "$rand_x,$rand_y"
    fi
}

rx_wallpaper_apply_colors() {
    local static_source="$1"
    local filename="$2"

    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")
    [[ $scheme != "wallpaper" ]] && return 0

    env RETRO_CONFIG="${RETRO_CONFIG:-$HOME/.config/retro}" HOME="$HOME" RETRO_DIR="$RETRO_DIR" \
        bash "$RETRO_DIR/scripts/theme_core.sh" --apply-colors >/dev/null 2>&1
}

rx_wallpaper_get_gpu_env() {
    local mode=$(get_var "WALL_GPU_OFFLOAD" "auto")

    case "$mode" in
        off)
            echo "NV_PRIME_RENDER_OFFLOAD=0"
            return 0
            ;;
        nvidia)
            echo "__GLX_VENDOR_LIBRARY_NAME=nvidia LIBVA_DRIVER_NAME=nvidia GBM_BACKEND=nvidia-drm"
            return 0
            ;;
        amd)
            echo "LIBVA_DRIVER_NAME=radeonsi VDPAU_DRIVER=radeonsi"
            return 0
            ;;
        intel)
            echo "LIBVA_DRIVER_NAME=iHD VDPAU_DRIVER=va_gl"
            return 0
            ;;
        auto | *)
            if command -v lspci >/dev/null 2>&1; then
                local gpu_line=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | head -1)
                if [[ -n $gpu_line ]]; then
                    local pci_id=$(echo "$gpu_line" | awk '{print $1}')
                    local vendor_id=$(lspci -nn -s "$pci_id" 2>/dev/null | grep -oP '\[([0-9a-f]{4}):' | tr -d '[][')
                    vendor_id="${vendor_id%%:*}"
                    case "$vendor_id" in
                        10de) echo "__GLX_VENDOR_LIBRARY_NAME=nvidia LIBVA_DRIVER_NAME=nvidia GBM_BACKEND=nvidia-drm" ;;
                        1002) echo "LIBVA_DRIVER_NAME=radeonsi VDPAU_DRIVER=radeonsi" ;;
                        8086) echo "LIBVA_DRIVER_NAME=iHD VDPAU_DRIVER=va_gl" ;;
                        *) echo "NV_PRIME_RENDER_OFFLOAD=0" ;;
                    esac
                    return 0
                fi
            fi
            echo "NV_PRIME_RENDER_OFFLOAD=0"
            return 0
            ;;
    esac
}

rx_wallpaper_launch_mpvpaper() {
    local video_path="$1"
    local theme_dir="$2"
    local filename="$3"
    local target_monitor="${4:-}"

    [[ -z $video_path ]] && return 1

    local base="${filename%.*}"
    local ext="${filename##*.}"
    local custom_res=$(get_var "WALL_RESOLUTION")
    local gpu_env=$(rx_wallpaper_get_gpu_env)
    local gpu_mode=$(get_var "WALL_GPU_OFFLOAD" "auto")
    local hwdec="auto"
    [[ $gpu_mode == "off" ]] && hwdec="no"

    hyprctl monitors -j 2>/dev/null | jq -r '.[] | "\(.name)|\(.description)"' | while IFS='|' read -r m_name m_desc; do
        [[ -z $m_name ]] && continue
        [[ -n $target_monitor && $m_name != "$target_monitor" ]] && continue

        pkill -9 -f "mpvpaper.*\"$m_name\"" 2>/dev/null

        local target_video="$video_path"

        if [[ -n $custom_res && $custom_res != "null" ]]; then
            local clean_base=$(echo "$base" | sed -E 's/\.[0-9]+x[0-9]+$//')
            local opt_file="$theme_dir/${clean_base}.${custom_res}.${ext}"
            [[ -f $opt_file ]] && target_video="$opt_file"
        fi

        local mpv_opts="--loop --panscan=1.0 --no-audio --hwdec=$hwdec --input-ipc-server=$MPV_SOCKET"
        eval "$gpu_env nohup mpvpaper -o \"$mpv_opts\" \"$m_name\" \"$target_video\" >/dev/null 2>&1 &"
    done
}

rx_wallpaper_start() {
    local input_path="$1"
    local quick="${2:-false}"
    local monitor="${3:-}"

    local wall_path=$(rx_wallpaper_resolve_path "$input_path")
    [[ -z $wall_path ]] && return 1

    local filename=$(basename "$wall_path")
    local base="${filename%.*}"
    local ext="${filename##*.}"
    local is_video=false
    [[ $ext =~ ^(mp4|mkv|webm)$ ]] && is_video=true

    local theme_dir=$(rx_wallpaper_get_theme_dir)

    local is_first_load=false
    rx_wallpaper_ensure_awww && is_first_load=true

    local static_source="$wall_path"
    [[ $is_video == "true" ]] && static_source=$(rx_wallpaper_generate_cache "$wall_path")

    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")
    local needs_colors=false
    [[ $scheme == "wallpaper" ]] && needs_colors=true

    date +%s >/tmp/retro_wallpaper_switch_ts

    if [[ -z $monitor ]]; then
        set_var "WALL_CURRENT" "$wall_path"
    else
        set_var "WALL_MONITOR_$monitor" "$wall_path"
    fi

    pkill -9 mpvpaper 2>/dev/null

    rx_wallpaper_set_image "$static_source" "$quick" "$is_first_load" "$monitor"

    if [[ $is_video == "true" ]]; then
        local v_static=$(get_var "WALL_STATIC_FORCED" "false")
        local v_paused=$(get_var "WALL_PAUSED" "false")
        if [[ $v_static != "true" && $v_paused != "true" ]]; then
            local trans_delay=0.4
            if [[ $is_first_load != "true" && $quick != "true" ]]; then
                trans_delay=2.6
            fi
            (
                sleep $trans_delay
                local current_check=$(get_var "WALL_CURRENT")
                [[ $current_check != "$wall_path" ]] && exit 0
                pkill -9 mpvpaper 2>/dev/null
                rx_wallpaper_launch_mpvpaper "$wall_path" "$theme_dir" "$filename" "$monitor"
            ) >>/tmp/retro_wallpaper_launch.log 2>&1 &
        fi
    fi

    if [[ $needs_colors == "true" ]]; then
        (
            if [[ -z $monitor ]]; then
                local current_check=$(get_var "WALL_CURRENT")
                [[ $current_check != "$wall_path" ]] && exit 0
            fi
            rx_wallpaper_apply_colors "$static_source" "$filename"
        ) &>/dev/null &
    fi
}

rx_wallpaper_restore() {
    local quick="${1:-false}"

    while IFS='=' read -r var value; do
        if [[ $var =~ ^export\ WALL_MONITOR_ ]]; then
            local mon="${var#export WALL_MONITOR_}"
            mon="${mon%%=*}"
            local path="${value#\"}"
            path="${path%\"}"
            if [[ -f $path ]]; then
                rx_wallpaper_start "$path" "$quick" "$mon"
            fi
        fi
    done < <(grep "^export WALL_MONITOR_" "$RETRO_CONFIG/variables.sh" 2>/dev/null)

    local last_wall=$(get_var "WALL_CURRENT")
    if [[ -z $last_wall || $last_wall == "null" ]]; then
        rx_log_file "ERROR" "Restore failed: WALL_CURRENT is not set"
        return 1
    fi
    if [[ ! -f $last_wall ]]; then
        rx_log_file "ERROR" "Restore failed: wallpaper file not found: $last_wall"
        return 1
    fi

    for mon in $(hyprctl monitors -j 2>/dev/null | jq -r '.[].name'); do
        local existing=$(get_var "WALL_MONITOR_$mon")
        if [[ -z $existing || $existing == "null" ]]; then
            rx_wallpaper_start "$last_wall" "$quick" "$mon"
        fi
    done
}

rx_wallpaper_pause() {
    pkill -9 mpvpaper 2>/dev/null
    set_var "WALL_PAUSED" "true"
}

rx_wallpaper_resume() {
    set_var "WALL_PAUSED" "false"
    local current_wall=$(get_var "WALL_CURRENT")
    local video_path=$(rx_wallpaper_find_video "$current_wall")
    if [[ -n $video_path ]]; then
        rx_wallpaper_start "$video_path" "true"
        return 0
    fi
    return 1
}

rx_wallpaper_should_pause() {
    local on_fullscreen=$(get_var "WALL_STATIC_ON_FULLSCREEN" "true")
    local pause_procs=$(get_var "WALL_PAUSE_PROCS" "")

    if [[ $on_fullscreen == "true" ]]; then
        local fs_count=$(hyprctl clients -j 2>/dev/null | jq '[.[] | select(.fullscreen > 0 and .initialClass != "mpvpaper" and .class != "mpvpaper")] | length')
        [[ ${fs_count:-0} -gt 0 ]] && return 0
    fi

    if [[ -n $pause_procs && $pause_procs != "null" ]]; then
        local IFS='|'
        for proc in $pause_procs; do
            [[ -z $proc ]] && continue
            pgrep -x "$proc" >/dev/null 2>&1 && return 0
        done
    fi

    return 1
}
