#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/wallpaper.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "wallpaper"

add_wallpaper() {
    local source_file="$1"
    local collection="${2:-}"
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

    [[ -z $collection ]] && collection=$(get_var "RETRO_WALL_COLLECTION" "retro")
    if [[ $collection == "all" ]]; then
        rx_log_file "ERROR" "Add failed: cannot add to the 'all' collection"
        echo "result=error|reason=invalid_collection|collection=all"
        return 1
    fi
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
    local target_res
    target_res=$(get_var "WALL_RESOLUTION")
    [[ -z $target_res || $target_res == "null" ]] && target_res=$(get_monitor_resolutions | head -1)
    local target_w="${target_res%x*}"
    local target_h="${target_res#*x}"
    [[ -z $target_w || -z $target_h ]] && return 0

    # Pause wallpaper system so the daemon doesn't restart mpvpaper
    set_var "WALL_PAUSED" "true"
    pkill -9 mpvpaper 2>/dev/null
    sleep 1

    local optimized=0 skipped=0

    # Build file list, then process with ALL stderr suppressed
    local file_list=$(mktemp /tmp/wallpaper_list.XXXXXX)
    find "$WALL_DIR" -maxdepth 2 \( -type f -o -type l \) 2>/dev/null |
        grep -iE "\.(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$" |
        grep -vE "\.[0-9]+x[0-9]+\.(mp4|mkv|webm)$" |
        sort >"$file_list"

    while IFS= read -r f; do
        [[ -z $f ]] && continue
        [[ -L $f ]] && f=$(readlink -f "$f")
        local filename=$(basename "$f")

        local file_res=$(get_image_resolution "$f")
        local file_w="${file_res%x*}"
        local file_h="${file_res#*x}"
        [[ -z $file_w || -z $file_h ]] && {
            ((skipped++))
            continue
        }

        if [[ $file_w -le $target_w && $file_h -le $target_h ]]; then
            ((skipped++))
            rx_wallpaper_generate_cache "$f" >/dev/null
            continue
        fi

        local ext="${filename##*.}"
        if [[ ${ext,,} =~ ^(mp4|mkv|webm)$ ]]; then
            local tmp=$(mktemp --suffix=".$ext")
            ffmpeg -y -i "$f" \
                -vf "scale='min($target_w,iw)':'min($target_h,ih)':force_original_aspect_ratio=decrease" \
                -c:v libx264 -preset fast -crf 23 -an "$tmp" -loglevel error &&
                mv "$tmp" "$f" || rm -f "$tmp"
        else
            magick "$f" -resize "${target_w}x${target_h}>" "$f"
        fi
        ((optimized++))
        rx_wallpaper_generate_cache "$f" >/dev/null
    done <"$file_list" 2>/dev/null
    rm -f "$file_list"

    rx_log_file "INFO" "Optimization complete: $optimized optimized, $skipped already at target resolution"
    set_var "WALL_PAUSED" "false"
    restore_wallpaper >/dev/null 2>&1
}

get_monitor_resolutions() {
    local target_res
    target_res=$(get_var "WALL_RESOLUTION")

    if [[ -n $target_res && $target_res != "null" ]]; then
        echo "$target_res" | grep -E '^[0-9]+x[0-9]+$'
        return 0
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl monitors -j | jq -r '.[] | "\(.description)|\((.width/.scale)|floor)x\((.height/.scale)|floor)"' 2>/dev/null | cut -d'|' -f2 | grep -E '^[0-9]+x[0-9]+$'
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
    [[ $file_w =~ ^[0-9]+$ && $file_h =~ ^[0-9]+$ ]] || return 1

    while IFS= read -r mon_res; do
        [[ -z $mon_res ]] && continue
        local mon_w="${mon_res%x*}"
        local mon_h="${mon_res#*x}"
        [[ $mon_w =~ ^[0-9]+$ && $mon_h =~ ^[0-9]+$ ]] || continue

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
    local quick="${2:-false}"
    local monitor="${3:-}"
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

    if ! rx_wallpaper_start "$input" "$quick" "$monitor"; then
        rx_log_file "ERROR" "Failed to start wallpaper: $input"
        echo "ERR|wallpaper_start_failed|$input"
        return 1
    fi

    mkdir -p "$HOME/.config/retro/wallpaper"
    cp "$input" "$HOME/.config/retro/wallpaper/current.png"
    rx_wallpaper_generate_cache "$input" >/dev/null

    echo "OK|$input"

    bash "$RETRO_DIR/scripts/shell_core.sh" --run "wallpaper_ping $input" 2>/dev/null &
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
    mkdir -p "$HOME/.config/retro/wallpaper"
    cp "$last_wall" "$HOME/.config/retro/wallpaper/current.png"
    rx_wallpaper_generate_cache "$last_wall" >/dev/null

    echo "OK|$last_wall"

    bash "$RETRO_DIR/scripts/shell_core.sh" --run "wallpaper_ping $last_wall" 2>/dev/null &
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
    pkill -9 mpvpaper 2>/dev/null
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
        if [[ $raw_lower == "$search_pattern" ]]; then
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
        auto | nvidia | amd | intel | off)
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

WALLPAPER_REPO_URL="${WALLPAPER_REPO_URL:-https://github.com/itsvlxd/retrowallpapers.git}"
WALLPAPER_RAW_BASE="${WALLPAPER_RAW_BASE:-https://raw.githubusercontent.com/itsvlxd/retrowallpapers/main}"
WALLPAPER_STATE="$RETRO_CONFIG/.retro_wallpaper_state"

_wallpaper_state_sha() {
    local collection="$1"
    [[ -f $WALLPAPER_STATE ]] || return 1
    grep "^${collection}=" "$WALLPAPER_STATE" 2>/dev/null | cut -d= -f2 | head -1
}

_wallpaper_set_state_sha() {
    local collection="$1"
    local sha="$2"
    mkdir -p "$RETRO_CONFIG"
    if [[ -f $WALLPAPER_STATE ]] && grep -q "^${collection}=" "$WALLPAPER_STATE"; then
        sed -i "s@^${collection}=.*@${collection}=${sha}@" "$WALLPAPER_STATE"
    else
        echo "${collection}=${sha}" >>"$WALLPAPER_STATE"
    fi
}

list_remote_collections() {
    local cache
    cache=$(mktemp /tmp/retro_wall_meta.XXXXXX)
    if ! curl -sL --max-time 15 "$WALLPAPER_RAW_BASE/metadata.json" -o "$cache"; then
        rm -f "$cache" 2>/dev/null
        echo "result=error|reason=network"
        return 1
    fi
    if ! jq -e '.collections' "$cache" >/dev/null 2>&1; then
        rm -f "$cache" 2>/dev/null
        echo "result=error|reason=bad_metadata"
        return 1
    fi

    jq -r '.collections[] | [.name,.branch,.count,.size_human,.sha,.description] | @tsv' "$cache"
    rm -f "$cache" 2>/dev/null
    return 0
}

pull_wallpapers() {
    local collection="$1"
    local force="${2:-false}"
    [[ -z $collection ]] && echo "result=error|reason=collection_required" && return 1
    [[ $collection == "all" ]] && echo "result=error|reason=invalid_collection" && return 1

    local cache
    cache=$(mktemp /tmp/retro_wall_meta.XXXXXX)
    if ! curl -sL --max-time 15 "$WALLPAPER_RAW_BASE/metadata.json" -o "$cache"; then
        rm -f "$cache" 2>/dev/null
        echo "result=error|reason=network"
        return 1
    fi

    local branch sha size_human
    branch=$(jq -r --arg c "$collection" '.collections[] | select(.name==$c) | .branch' "$cache" 2>/dev/null | head -1)
    sha=$(jq -r --arg c "$collection" '.collections[] | select(.name==$c) | .sha' "$cache" 2>/dev/null | head -1)
    size_human=$(jq -r --arg c "$collection" '.collections[] | select(.name==$c) | .size_human' "$cache" 2>/dev/null | head -1)
    rm -f "$cache" 2>/dev/null

    if [[ -z $branch ]]; then
        echo "result=error|reason=not_found|collection=$collection"
        return 1
    fi

    local installed_sha
    installed_sha=$(_wallpaper_state_sha "$collection")
    if [[ $sha == "$installed_sha" && $force != "true" ]]; then
        echo "result=ok|status=up_to_date|collection=$collection|sha=$sha"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/retro_wall_pull.XXXXXX)
    if ! git clone --depth 1 --branch "$branch" --single-branch "$WALLPAPER_REPO_URL" "$tmpdir" >/dev/null 2>&1; then
        rm -rf "$tmpdir" 2>/dev/null
        echo "result=error|reason=clone_failed|collection=$collection"
        return 1
    fi

    local dest="$WALL_DIR/$collection"
    mkdir -p "$dest"

    local synced=0
    local updated=0
    while IFS= read -r -d '' src_file; do
        [[ -f $src_file ]] || continue
        local fn
        fn=$(basename "$src_file")
        if [[ ! -f "$dest/$fn" ]]; then
            cp "$src_file" "$dest/$fn"
            ((synced++))
        else
            if [[ $force == "true" ]]; then
                cp "$src_file" "$dest/$fn"
                ((updated++))
            fi
        fi
    done < <(find "$tmpdir" -maxdepth 1 -type f -print0)

    rm -rf "$tmpdir" 2>/dev/null
    _wallpaper_set_state_sha "$collection" "$sha"
    rx_log_file "info" "Wallpaper pull $collection: ${synced} new, ${updated} updated (${size_human:-unknown})"
    echo "result=ok|collection=$collection|synced=$synced|updated=$updated|size=${size_human:-unknown}"
    return 0
}

sync_wallpapers() {
    # Refresh every installed collection to the latest remote version.
    local updated_total=0
    local found=false
    for d in "$WALL_DIR"/*/; do
        [[ -d $d ]] || continue
        local name
        name=$(basename "$d")
        [[ $name == "all" ]] && continue
        found=true
        local res
        res=$(pull_wallpapers "$name")
        if echo "$res" | grep -q "result=ok"; then
            local n
            n=$(echo "$res" | grep -oP 'synced=\K[0-9]+' || echo 0)
            updated_total=$((updated_total + n))
        fi
    done

    if [[ $found == false ]]; then
        echo "result=ok|status=no_collections"
        return 0
    fi
    rx_log_file "info" "Wallpaper sync: ${updated_total} new/updated across installed collections"
    echo "result=ok|synced=$updated_total"
    return 0
}

case "$1" in
    "--current") get_var "WALL_CURRENT" ;;
    "--set") set_wallpaper "$2" "${3:-false}" "$4" ;;
    "--add") add_wallpaper "$2" "$3" ;;
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
        done < <(rx_wallpaper_list_files "$2")
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
    "--pull")
        pull_wallpapers "$2" "$3"
        ;;
    "--pull-list")
        list_remote_collections
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
                name=$(basename "$d")
                [[ $name == "all" ]] && continue
                echo "$name"
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
    "--collection-create")
        name="$2"
        if [[ -z $name || $name == "all" ]]; then
            echo "result=error|reason=invalid_collection"
            exit 1
        fi
        target="$WALL_DIR/$name"
        if [[ -d $target ]]; then
            set_var "RETRO_WALL_COLLECTION" "$name"
            echo "result=ok|exists=1|collection=$name"
            exit 0
        fi
        mkdir -p "$target"
        set_var "RETRO_WALL_COLLECTION" "$name"
        echo "result=ok|collection=$name"
        ;;
    "--collection-delete")
        name="$2"
        if [[ -z $name || $name == "all" ]]; then
            echo "result=error|reason=invalid_collection"
            exit 1
        fi
        if [[ ! -d "$WALL_DIR/$name" ]]; then
            echo "result=error|reason=not_found|collection=$name"
            exit 1
        fi
        rm -rf "$WALL_DIR/$name"
        if [[ $(get_var "RETRO_WALL_COLLECTION" "retro") == "$name" ]]; then
            set_var "RETRO_WALL_COLLECTION" "retro"
        fi
        echo "result=ok|collection=$name"
        ;;
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
        pull_wallpapers "$theme" >/dev/null 2>&1
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
