#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"

WALL_DIR="$RETRO_CONFIG/wallpapers"
FRAME_CACHE="$RETRO_CONFIG/wallpaper_frames"
REPO_WALLS="$RETRO_DIR/wallpapers"

mkdir -p "$FRAME_CACHE"
mkdir -p "$WALL_DIR"

generate_cache() {
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

get_theme_dir() {
    local theme=$(get_var "RETRO_THEME")
    [[ -z $theme || $theme == "null" ]] && theme="retro"

    local target="$WALL_DIR/$theme"
    if [[ -d $target ]]; then
        echo "$target"
    else
        echo "$WALL_DIR"
    fi
}

add_wallpaper() {
    local source_file="$1"
    if [[ ! -f $source_file ]]; then
        echo "result=error|reason=file_not_found|path=$source_file"
        return 1
    fi

    local ext="${source_file##*.}"
    if [[ ! ${ext,,} =~ ^(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$ ]]; then
        echo "result=error|reason=unsupported_format|ext=$ext"
        return 1
    fi

    local theme=$(get_var "RETRO_THEME" "retro")
    local target_dir="$WALL_DIR/$theme"
    mkdir -p "$target_dir"

    local filename=$(basename "$source_file")
    local target_file="$target_dir/$filename"

    cp "$source_file" "$target_file"
    generate_cache "$target_file" >/dev/null

    set_wallpaper "$target_file"
}

slideshow_next() {
    local target_dir=$(get_theme_dir)
    local current=$(get_var "WALL_CURRENT")

    local next_wall
    while IFS= read -r wall; do
        [[ -z $wall ]] && continue
        if check_wallpaper_resolution "$wall"; then
            next_wall="$wall"
            break
        fi
    done < <(find "$target_dir" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null |
        grep -iE "\.(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$" |
        grep -vE "\.[0-9]+x[0-9]+\.(mp4|mkv|webm)$" |
        grep -vF "$current" |
        shuf)

    if [[ -n $next_wall ]]; then
        set_wallpaper "$next_wall"
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
            continue
        fi

        if [[ $src_w -eq $target_w && $src_h -eq $target_h ]]; then
            if [[ ! -L $opt_file || $(readlink "$opt_file") != "$src_file" ]]; then
                rm -f "$opt_file"
                ln -sf "$src_file" "$opt_file"
            fi
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
                else
                    magick "$src_file" -resize "${target_w}x${target_h}^" -gravity center -extent "${target_w}x${target_h}" "$opt_file"
                fi
            fi
        fi
    done

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
    local target_dir=$(get_theme_dir)
    local show_all="${1:-false}"
    
    local valid_count=0
    local invalid_count=0
    
    for f in "$target_dir"/*; do
        [[ -d $f ]] && continue
        [[ -f $f || -L $f ]] || continue
        
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
    done
    
    echo "valid=$valid_count|invalid=$invalid_count"
}

set_wallpaper() {
    local input_path="$1"
    local wall_path=""
    local theme_dir=$(get_theme_dir)

    if [[ -f $input_path ]]; then
        wall_path="$input_path"
    elif [[ -f "$theme_dir/$input_path" ]]; then
        wall_path="$theme_dir/$input_path"
    elif [[ -f "$WALL_DIR/$input_path" ]]; then
        wall_path="$WALL_DIR/$input_path"
    else
        return 1
    fi

    local filename=$(basename "$wall_path")
    local base="${filename%.*}"
    local ext="${filename##*.}"
    local is_video=false
    [[ $ext =~ ^(mp4|mkv|webm)$ ]] && is_video=true

    local is_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
    local force_static=$(get_var "WALL_STATIC_FORCED" "false")
    local static_on_bat=$(get_var "WALL_STATIC_ON_BAT" "false")
    local on_bat=$(is_on_battery)

    local should_be_static=false
    if [[ $is_saver == "true" || $force_static == "true" ]]; then
        should_be_static=true
    elif [[ $on_bat == "true" && $static_on_bat == "true" ]]; then
        should_be_static=true
    fi

    local is_first_load=false
    if ! pgrep -x "awww-daemon" >/dev/null; then
        is_first_load=true
        nohup awww-daemon >/dev/null 2>&1 &
        while ! awww query >/dev/null 2>&1; do sleep 0.05; done
    fi

    local static_source="$wall_path"
    [[ $is_video == "true" ]] && static_source=$(generate_cache "$wall_path")

    if [[ $is_first_load == "true" ]]; then
        awww img "$static_source" --transition-type none
    else
        local rand_x=$((RANDOM % 1920))
        local rand_y=$((RANDOM % 1080))
        awww img "$static_source" \
            --transition-type random \
            --transition-duration 2.5 \
            --transition-fps 120 \
            --transition-pos "$rand_x,$rand_y"
    fi

    (
        pkill mpvpaper

        COLOR=$(magick "$static_source" -colorspace HSL -format "%[fx:100*s]" info:)
        if [ "$(echo "$COLOR < 1.0" | bc)" -eq 1 ]; then
            matugen image -b wal "$static_source" -t scheme-monochrome --fallback-color "#ffffff" --source-color-index 0 >/dev/null 2>&1
        else
            matugen image -b wal "$static_source" -t scheme-vibrant --source-color-index 0 >/dev/null 2>&1
        fi

        if [[ $is_video == "true" && $should_be_static == "false" ]]; then
            [[ $is_first_load == "false" ]] && sleep 2.2

            local res_map=$(get_var "WALL_RES_MAP")

            hyprctl monitors -j | jq -c '.[]' | while read -r mon; do
                local m_name=$(echo "$mon" | jq -r '.name')
                local m_desc=$(echo "$mon" | jq -r '.description')

                local custom_res=""
                if [[ -n $res_map ]]; then
                    custom_res=$(echo "$res_map" | tr ',' '\n' | grep -F "$m_desc|" | cut -d'|' -f2)
                fi

                local target_video="$wall_path"

                if [[ -n $custom_res ]]; then
                    local clean_base=$(echo "$base" | sed -E 's/\.[0-9]+x[0-9]+$//')
                    local opt_file="$theme_dir/${clean_base}.${custom_res}.${ext}"

                    if [[ -f $opt_file ]]; then
                        target_video="$opt_file"
                    fi
                fi

                local mpv_opts="--loop --panscan=1.0 --no-audio --hwdec=auto"
                NV_PRIME_RENDER_OFFLOAD=0 nohup mpvpaper -o "$mpv_opts" "$m_name" "$target_video" >/dev/null 2>&1 &
            done
        fi
    ) &

    set_var "WALL_CURRENT" "$wall_path"
}

restore_wallpaper() {
    local last_wall=$(get_var "WALL_CURRENT")
    if [[ -n $last_wall && -f $last_wall ]]; then
        set_wallpaper "$last_wall"
    else
        return 1
    fi
}

static_wallpaper() {
    local current_state=$(get_var "WALL_STATIC_FORCED")
    local new_state=""

    case "$2" in
        "on" | "true") new_state="true" ;;
        "off" | "false") new_state="false" ;;
        "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
    esac

    set_var "WALL_STATIC_FORCED" "$new_state"
    restore_wallpaper
}

launch_picker() {
    local theme_conf="$HOME/.config/rofi/themes/gallery.rasi"
    local list=""
    local target_dir=$(get_theme_dir)

    declare -A wall_map

    for f in "$target_dir"/*; do
        [[ -d $f ]] && continue
        [[ -f $f || -L $f ]] || continue

        local filename=$(basename "$f")

        if [[ $filename =~ \.[0-9]+x[0-9]+\.(mp4|mkv|webm)$ ]]; then
            continue
        fi

        local display=$(rx_format_string "$filename")
        local thumb=$(generate_cache "$f")

        wall_map["$display"]="$f"
        list+="${display}\0icon\x1f${thumb}\n"
    done

    if [[ -z $list ]]; then
        echo "result=error|reason=no_files_found|path=$target_dir"
        return 1
    fi

    local alpha=$(get_opacity_hex "0.9")
    local alpha_alt=$(get_opacity_hex "0.6")
    local base_bg=$(grep "background:" ~/.config/retrp/themes/rofi-colors.rasi 2>/dev/null | awk '{print $2}' | sed 's/[#;FF]//g')
    local base_bg_alt=$(grep "background-alt:" ~/.config/retro/themes/rofi-colors.rasi 2>/dev/null | awk '{print $2}' | sed 's/[#;FF]//g')

    : ${base_bg:="1A1B26"}
    : ${base_bg_alt:="24283B"}

    local folder_name="${target_dir##*/}"

    local choice=$(printf "%b" "$list" | rofi -dmenu -i -p "󰸉 Wallpapers (${folder_name^})" -theme "$theme_conf" -theme-str "
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

case "$1" in
    "--set") set_wallpaper "$2" ;;
    "--add") add_wallpaper "$2" ;;
    "--slideshow-next") slideshow_next ;;
    "--optimize") optimize_wallpapers ;;
    "--check-resolution")
        if [[ -n $2 ]]; then
            if check_wallpaper_resolution "$2"; then
                echo "result=match|file=$2"
            else
                local res
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
            generate_cache "$2" >/dev/null
        else
            target_dir=$(get_theme_dir)
            for f in "$target_dir"/*; do
                [[ -f $f || -L $f ]] && generate_cache "$f" >/dev/null
            done
        fi
        ;;
    "--restore") restore_wallpaper ;;
    "--static") static_wallpaper "$2" ;;
    "--list")
        target_dir=$(get_theme_dir)
        if [[ "${2:-}" == "--with-resolution" || "${2:-}" == "-r" ]]; then
            list_wallpapers_with_resolution true
        else
            ls -1 "$target_dir"
        fi
        ;;
    "--picker") launch_picker ;;
esac
