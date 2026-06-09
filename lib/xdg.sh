#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

XDG_USER_DIRS_FILE="$HOME/.config/user-dirs.dirs"
XDG_MIMEAPPS_FILE="$HOME/.config/mimeapps.list"
XDG_PORTAL_CONF="$RETRO_CONFIG/portal.conf"

XDG_EDITOR_MIMES=(
    "text/plain" "text/x-shellscript" "text/x-lua" "text/x-c" "text/x-c++src"
    "text/x-c++hdr" "text/x-java" "text/x-python" "text/javascript" "text/typescript"
    "text/x-ruby" "text/x-rust" "text/x-go" "text/x-scala" "text/x-kotlin"
    "text/x-swift" "text/markdown" "text/x-yaml" "text/x-toml" "text/xml"
    "application/json" "text/css" "text/x-scss" "text/x-sass" "text/x-sql"
    "text/x-diff" "text/csv" "text/x-perl" "text/x-php" "text/x-haskell"
    "text/x-erlang" "text/x-latex" "text/x-objc" "text/x-fortran" "text/x-pascal"
    "text/x-asm" "text/x-dockerfile" "text/x-properties" "text/x-ini"
    "application/x-desktop" "text/x-makefile" "text/x-cmake" "text/x-gradle"
    "text/x-zig" "text/x-nim" "application/x-shellscript"
)

XDG_FM_MIMES=(
    "inode/directory" "application/x-directory"
    "x-scheme-handler/file" "x-scheme-handler/trash"
)

XDG_BROWSER_MIMES=(
    "x-scheme-handler/http" "x-scheme-handler/https" "x-scheme-handler/about"
    "x-scheme-handler/chrome" "text/html" "application/xhtml+xml"
    "application/x-extension-htm" "application/x-extension-html"
    "application/x-extension-shtml" "application/x-extension-xhtml"
    "application/x-extension-xht"
)

XDG_IMAGE_MIMES=(
    "image/png" "image/jpeg" "image/gif" "image/webp" "image/svg+xml"
    "image/bmp" "image/tiff" "image/x-xcf" "image/x-ico" "image/x-psd"
    "image/avif" "image/heic" "image/heif"
)

XDG_VIDEO_MIMES=(
    "video/mp4" "video/x-matroska" "video/webm" "video/x-msvideo"
    "video/x-flv" "video/quicktime" "video/x-ms-wmv" "video/ogg"
    "video/mpeg" "video/3gpp" "video/x-m4v"
)

rx_xdg_ensure_dirs() {
    local dirs_config="$HOME/.config/user-dirs.dirs"

    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        xdg-user-dirs-update --force 2>/dev/null

        if [[ -f $dirs_config ]] && grep -q 'DIR="$HOME/"' "$dirs_config" 2>/dev/null; then
            sed -i 's|DIR="$HOME/"|DIR="$HOME/Desktop"|' "$dirs_config" 2>/dev/null
            xdg-user-dirs-update --force 2>/dev/null
        fi

        systemctl --user enable xdg-user-dirs-update.service 2>/dev/null || true
    fi

    local dirs=(DESKTOP DOWNLOAD DOCUMENTS MUSIC PICTURES VIDEOS TEMPLATES PUBLICSHARE)
    local created=0
    for dir in "${dirs[@]}"; do
        local path=$(rx_xdg_get_dir "$dir")
        path=$(eval echo "$path")
        if [[ -n $path && $path != "$HOME" ]]; then
            [[ ! -d $path ]] && mkdir -p "$path" 2>/dev/null && ((created++))
        fi
    done
    echo "created=$created"
}

rx_xdg_get_dir() {
    local name="$1"
    [[ -z $name ]] && return 1

    local var_name="XDG_${name^^}_DIR"
    local cached=$(get_var "$var_name" "")
    if [[ -n $cached && $cached != "null" ]]; then
        eval echo "$cached"
        return 0
    fi

    if [[ -f $XDG_USER_DIRS_FILE ]]; then
        local val=$(grep "^XDG_${name^^}_DIR=" "$XDG_USER_DIRS_FILE" 2>/dev/null | head -1 | cut -d'"' -f2)
        if [[ -n $val ]]; then
            eval echo "$val"
            return 0
        fi
    fi

    local defaults=(
        "DESKTOP|$HOME/Desktop"
        "DOWNLOAD|$HOME/Downloads"
        "DOCUMENTS|$HOME/Documents"
        "MUSIC|$HOME/Music"
        "PICTURES|$HOME/Pictures"
        "VIDEOS|$HOME/Videos"
        "TEMPLATES|$HOME/Templates"
        "PUBLICSHARE|$HOME/Public"
    )
    for entry in "${defaults[@]}"; do
        local key="${entry%%|*}"
        local val="${entry#*|}"
        if [[ $key == "${name^^}" ]]; then
            echo "$val"
            return 0
        fi
    done
    return 1
}

rx_xdg_set_dir() {
    local name="$1"
    local path="$2"
    [[ -z $name || -z $path ]] && return 1

    local var_name="XDG_${name^^}_DIR"
    local expanded_path
    expanded_path=$(eval echo "$path")

    mkdir -p "$expanded_path"

    if [[ -f $XDG_USER_DIRS_FILE ]]; then
        if grep -q "^XDG_${name^^}_DIR=" "$XDG_USER_DIRS_FILE" 2>/dev/null; then
            sed -i "s|^XDG_${name^^}_DIR=.*|XDG_${name^^}_DIR=\"$path\"|" "$XDG_USER_DIRS_FILE"
        else
            echo "XDG_${name^^}_DIR=\"$path\"" >>"$XDG_USER_DIRS_FILE"
        fi
    else
        mkdir -p "$(dirname "$XDG_USER_DIRS_FILE")"
        echo "XDG_${name^^}_DIR=\"$path\"" >"$XDG_USER_DIRS_FILE"
    fi

    set_var "$var_name" "$expanded_path"
    echo "OK|$expanded_path"
}

rx_xdg_list_dirs() {
    local dirs=(DESKTOP DOWNLOAD DOCUMENTS MUSIC PICTURES VIDEOS TEMPLATES PUBLICSHARE)
    for dir in "${dirs[@]}"; do
        local path=$(rx_xdg_get_dir "$dir")
        local exists="no"
        [[ -d $path ]] && exists="yes"
        echo "$dir|$path|$exists"
    done
}

rx_xdg_set_default() {
    local mime="$1"
    local desktop_file="$2"
    [[ -z $mime || -z $desktop_file ]] && return 1

    if ! rx_xdg_validate_desktop "$desktop_file"; then
        echo "result=error|reason=desktop_file_not_found|file=$desktop_file"
        return 1
    fi

    mkdir -p "$(dirname "$XDG_MIMEAPPS_FILE")"

    if [[ ! -f $XDG_MIMEAPPS_FILE ]]; then
        echo "[Default Applications]" >"$XDG_MIMEAPPS_FILE"
    fi

    if grep -q "^\[$mime\]" "$XDG_MIMEAPPS_FILE" 2>/dev/null; then
        sed -i "s|^${mime}=.*|${mime}=${desktop_file}|" "$XDG_MIMEAPPS_FILE"
    elif grep -q "^\[Default Applications\]" "$XDG_MIMEAPPS_FILE" 2>/dev/null; then
        sed -i "/^\[Default Applications\]/a ${mime}=${desktop_file}" "$XDG_MIMEAPPS_FILE"
    else
        echo -e "\n[Default Applications]\n${mime}=${desktop_file}" >>"$XDG_MIMEAPPS_FILE"
    fi

    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    rx_xdg_bridge_flatpak >/dev/null 2>&1

    echo "OK|$mime=$desktop_file"
}

rx_xdg_get_default() {
    local mime="$1"
    [[ -z $mime ]] && return 1

    if [[ -f $XDG_MIMEAPPS_FILE ]]; then
        local val=$(grep "^${mime}=" "$XDG_MIMEAPPS_FILE" 2>/dev/null | head -1 | cut -d= -f2- | cut -d';' -f1)
        if [[ -n $val ]]; then
            echo "$val"
            return 0
        fi
    fi

    if command -v xdg-mime >/dev/null 2>&1; then
        local fallback=$(xdg-mime query default "$mime" 2>/dev/null)
        if [[ -n $fallback ]]; then
            echo "$fallback"
            return 0
        fi
    fi
    return 1
}

rx_xdg_list_defaults() {
    [[ ! -f $XDG_MIMEAPPS_FILE ]] && return 0

    local in_section=false
    while IFS= read -r line; do
        [[ $line =~ ^\[ ]] && {
            in_section=false
            [[ $line == "[Default Applications]" ]] && in_section=true
            continue
        }
        if $in_section && [[ $line == *=* && ! $line =~ ^# ]]; then
            local mime="${line%%=*}"
            local desktop="${line#*=}"
            desktop="${desktop%%;*}"
            local app_name=$(rx_xdg_desktop_name "$desktop")
            echo "$mime|$desktop|$app_name"
        fi
    done <"$XDG_MIMEAPPS_FILE"
}

rx_xdg_reset_defaults() {
    local editor=$(get_var "RETRO_EDITOR_CMD" "nvim")
    local fm=$(get_var "RETRO_FILEMANAGER_CMD" "thunar")
    local terminal=$(get_var "RETRO_TERMINAL_CMD" "kitty")

    local editor_desktop=$(rx_xdg_resolve_desktop "$editor")
    local fm_desktop=$(rx_xdg_resolve_desktop "$fm")

    local browser_desktop="firefox.desktop"
    for b in zen firefox chromium floorp thorium nyxt google-chrome; do
        if rx_xdg_validate_desktop "${b}.desktop"; then
            browser_desktop="${b}.desktop"
            break
        fi
    done

    local image_desktop=$(rx_xdg_resolve_desktop "loupe")
    local video_desktop=$(rx_xdg_resolve_desktop "mpv")
    local terminal_desktop="${terminal}.desktop"

    mkdir -p "$(dirname "$XDG_MIMEAPPS_FILE")"
    cat >"$XDG_MIMEAPPS_FILE" <<EOF
[Default Applications]
EOF

    for mime in "${XDG_EDITOR_MIMES[@]}"; do
        echo "${mime}=${editor_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_FM_MIMES[@]}"; do
        echo "${mime}=${fm_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_BROWSER_MIMES[@]}"; do
        echo "${mime}=${browser_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_IMAGE_MIMES[@]}"; do
        echo "${mime}=${image_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_VIDEO_MIMES[@]}"; do
        echo "${mime}=${video_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    echo "x-scheme-handler/terminal=${terminal_desktop}" >>"$XDG_MIMEAPPS_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    fi

    rx_xdg_bridge_flatpak >/dev/null 2>&1

    echo "OK|reset_complete"
}

rx_xdg_resolve_desktop() {
    local input="$1"
    [[ -z $input ]] && return 1

    if [[ $input == *.desktop ]]; then
        if rx_xdg_validate_desktop "$input"; then
            echo "$input"
            return 0
        fi
        input="${input%.desktop}"
    fi

    local direct="${input}.desktop"
    if rx_xdg_validate_desktop "$direct"; then
        echo "$direct"
        return 0
    fi

    local search_paths=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
    )
    for sp in "${search_paths[@]}"; do
        [[ ! -d $sp ]] && continue
        local found=$(find "$sp" -maxdepth 1 -name "${input}*.desktop" -type f 2>/dev/null | head -1)
        if [[ -n $found ]]; then
            local basename=$(basename "$found")
            if rx_xdg_validate_desktop "$basename"; then
                echo "$basename"
                return 0
            fi
        fi
    done

    for sp in "${search_paths[@]}"; do
        [[ ! -d $sp ]] && continue
        while IFS= read -r df; do
            [[ -z $df ]] && continue
            if grep -q "^Exec=.*${input}" "$df" 2>/dev/null || grep -q "^Exec=${input}" "$df" 2>/dev/null; then
                local basename=$(basename "$df")
                if rx_xdg_validate_desktop "$basename"; then
                    echo "$basename"
                    return 0
                fi
            fi
        done < <(find "$sp" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null)
    done

    echo "${input}.desktop"
}

rx_xdg_setup() {
    local editor_input="$1"
    local browser_input="$2"
    local fm_input="$3"
    local image_input="$4"
    local video_input="$5"

    [[ -z $editor_input ]] && editor_input=$(get_var "RETRO_EDITOR_CMD" "nvim")
    [[ -z $browser_input ]] && browser_input=$(get_var "BROWSER_CHOICE" "zen")
    [[ -z $fm_input ]] && fm_input=$(get_var "RETRO_FILEMANAGER_CMD" "thunar")
    [[ -z $image_input ]] && image_input="loupe"
    [[ -z $video_input ]] && video_input="mpv"

    local editor_desktop=$(rx_xdg_resolve_desktop "$editor_input")
    local browser_desktop=$(rx_xdg_resolve_desktop "$browser_input")
    local fm_desktop=$(rx_xdg_resolve_desktop "$fm_input")
    local image_desktop=$(rx_xdg_resolve_desktop "$image_input")
    local video_desktop=$(rx_xdg_resolve_desktop "$video_input")
    local terminal_desktop="kitty.desktop"

    [[ $fm_desktop == "thunar.desktop" ]] && ! rx_xdg_validate_desktop "thunar.desktop" && fm_desktop=$(rx_xdg_resolve_desktop "nemo")
    [[ $image_desktop == "loupe.desktop" ]] && ! rx_xdg_validate_desktop "loupe.desktop" && image_desktop=$(rx_xdg_resolve_desktop "viewnior")

    mkdir -p "$(dirname "$XDG_MIMEAPPS_FILE")"
    cat >"$XDG_MIMEAPPS_FILE" <<EOF
[Default Applications]
EOF

    for mime in "${XDG_EDITOR_MIMES[@]}"; do
        echo "${mime}=${editor_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_FM_MIMES[@]}"; do
        echo "${mime}=${fm_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_BROWSER_MIMES[@]}"; do
        echo "${mime}=${browser_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_IMAGE_MIMES[@]}"; do
        echo "${mime}=${image_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    for mime in "${XDG_VIDEO_MIMES[@]}"; do
        echo "${mime}=${video_desktop}" >>"$XDG_MIMEAPPS_FILE"
    done
    echo "x-scheme-handler/terminal=${terminal_desktop}" >>"$XDG_MIMEAPPS_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    fi

    rx_xdg_bridge_flatpak >/dev/null 2>&1

    set_var "RETRO_EDITOR_CMD" "$editor_input"
    set_var "RETRO_FILEMANAGER_CMD" "$fm_input"
    set_var "RETRO_TERMINAL_CMD" "kitty"
    set_var "RETRO_BROWSER_CMD" "$browser_input"

    echo "OK|editor=$editor_desktop|browser=$browser_desktop|fm=$fm_desktop|image=$image_desktop|video=$video_desktop|terminal=$terminal_desktop"
}

rx_xdg_find_handlers() {
    local mime="$1"
    [[ -z $mime ]] && return 1

    local search_paths=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
    )

    for sp in "${search_paths[@]}"; do
        [[ ! -d $sp ]] && continue
        while IFS= read -r desktop_file; do
            [[ -z $desktop_file ]] && continue
            if grep -q "MimeType=.*${mime}" "$desktop_file" 2>/dev/null; then
                local basename=$(basename "$desktop_file")
                local name=$(rx_xdg_desktop_name "$basename")
                local hidden=$(grep -c "^Hidden=true" "$desktop_file" 2>/dev/null)
                [[ $hidden -gt 0 ]] && continue
                echo "$basename|$name|$desktop_file"
            fi
        done < <(find "$sp" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null)
    done
}

rx_xdg_validate_desktop() {
    local desktop_file="$1"
    [[ -z $desktop_file ]] && return 1

    local search_paths=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
    )

    if [[ -f $desktop_file ]]; then
        local has_exec=$(grep -c "^Exec=" "$desktop_file" 2>/dev/null)
        local hidden=$(grep -c "^Hidden=true" "$desktop_file" 2>/dev/null)
        [[ $has_exec -gt 0 && $hidden -eq 0 ]] && return 0
        return 1
    fi

    for sp in "${search_paths[@]}"; do
        local full_path="$sp/$desktop_file"
        if [[ -f $full_path ]]; then
            local has_exec=$(grep -c "^Exec=" "$full_path" 2>/dev/null)
            local hidden=$(grep -c "^Hidden=true" "$full_path" 2>/dev/null)
            [[ $has_exec -gt 0 && $hidden -eq 0 ]] && return 0
        fi
    done
    return 1
}

rx_xdg_desktop_name() {
    local desktop_file="$1"
    [[ -z $desktop_file ]] && echo "Unknown" && return 1

    local search_paths=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
    )

    if [[ -f $desktop_file ]]; then
        local name=$(grep "^Name=" "$desktop_file" 2>/dev/null | head -1 | cut -d= -f2-)
        echo "${name:-$desktop_file}"
        return 0
    fi

    for sp in "${search_paths[@]}"; do
        local full_path="$sp/$desktop_file"
        if [[ -f $full_path ]]; then
            local name=$(grep "^Name=" "$full_path" 2>/dev/null | head -1 | cut -d= -f2-)
            echo "${name:-$desktop_file}"
            return 0
        fi
    done

    echo "${desktop_file%.desktop}"
}

rx_xdg_bridge_flatpak() {
    command -v flatpak >/dev/null 2>&1 || return 0
    flatpak override --user --filesystem=xdg-config/mimeapps.list:ro 2>/dev/null
    echo "OK|flatpak_bridge_applied"
}

rx_xdg_get_portal_backend() {
    local active=""

    if [[ -f $XDG_PORTAL_CONF ]]; then
        active=$(grep "^portal=" "$XDG_PORTAL_CONF" 2>/dev/null | head -1 | cut -d= -f2-)
        if [[ -n $active ]]; then
            echo "$active"
            return 0
        fi
    fi

    local conf="/etc/xdg/xdg-desktop-portal/hyprland-portals.conf"
    if [[ -f $conf ]]; then
        active=$(grep "^default=" "$conf" 2>/dev/null | head -1 | cut -d= -f2-)
        if [[ -n $active ]]; then
            echo "$active"
            return 0
        fi
    fi

    local env_conf="$RETRO_CONFIG/env.lua"
    if [[ -f $env_conf ]]; then
        local portal_line=$(grep "xdg-desktop-portal" "$env_conf" 2>/dev/null | head -1)
        if [[ -n $portal_line ]]; then
            local backend=$(echo "$portal_line" | grep -oP '(hyprland|gtk)' | head -1)
            if [[ -n $backend ]]; then
                echo "$backend"
                return 0
            fi
        fi
    fi

    if pacman -Qq xdg-desktop-portal-hyprland >/dev/null 2>&1; then
        echo "hyprland"
    elif pacman -Qq xdg-desktop-portal-gtk >/dev/null 2>&1; then
        echo "gtk"
    else
        echo "none"
    fi
}

rx_xdg_list_portals() {
    local portals=(hyprland gtk gnome kde)
    for p in "${portals[@]}"; do
        local pkg="xdg-desktop-portal-${p}"
        local installed="no"
        pacman -Qq "$pkg" >/dev/null 2>&1 && installed="yes"
        local running="no"
        pgrep -f "xdg-desktop-portal-${p}" >/dev/null 2>&1 && running="yes"
        local conflict="no"
        [[ $p == "gnome" || $p == "kde" ]] && conflict="yes"
        echo "$p|$installed|$running|$conflict"
    done
}

rx_xdg_detect_conflicting_portals() {
    local found=0
    local conflicts=(gnome kde)
    for p in "${conflicts[@]}"; do
        local pkg="xdg-desktop-portal-${p}"
        local installed="no"
        pacman -Qq "$pkg" >/dev/null 2>&1 && installed="yes"
        local running="no"
        pgrep -f "xdg-desktop-portal-${p}" >/dev/null 2>&1 && running="yes"
        if [[ $installed == "yes" || $running == "yes" ]]; then
            echo "$p|$installed|$running"
            ((found++))
        fi
    done
    [[ $found -eq 0 ]] && echo "none"
}

rx_xdg_set_portal_backend() {
    local backend="$1"
    [[ -z $backend ]] && return 1

    [[ $backend != "hyprland" && $backend != "gtk" ]] && echo "result=error|reason=invalid_backend|backend=$backend" && return 1

    local pkg="xdg-desktop-portal-${backend}"

    if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
        echo "result=error|reason=package_not_installed|package=$pkg"
        return 1
    fi

    mkdir -p "$(dirname "$XDG_PORTAL_CONF")"
    cat >"$XDG_PORTAL_CONF" <<EOF
[portal]
portal=$backend
EOF

    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland 2>/dev/null
    export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null
    systemctl --user restart --wait xdg-desktop-portal "xdg-desktop-portal-${backend}" 2>/dev/null

    echo "OK|$backend"
}

rx_xdg_configure_xdg_open() {
    local wrapper="/usr/local/bin/xdg-open"
    local system_xdg="/usr/bin/xdg-open"

    if [[ ! -f $system_xdg ]]; then
        echo "result=error|reason=system_xdg_open_not_found"
        return 1
    fi

    mkdir -p "$(dirname "$wrapper")"
    cat >"$wrapper" <<'WRAPPER'
#!/bin/bash
if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]]; then
    mime=$(xdg-mime query filetype "$1" 2>/dev/null)
    if [[ -n $mime ]]; then
        default=$(xdg-mime query default "$mime" 2>/dev/null)
        if [[ -n $default ]]; then
            exec xdg-open --desktop "$default" "$1" 2>/dev/null || exec /usr/bin/xdg-open "$1"
        fi
    fi
fi
exec /usr/bin/xdg-open "$1"
WRAPPER
    chmod +x "$wrapper"
    echo "OK|wrapper_created"
}

rx_xdg_query() {
    local input="$1"
    [[ -z $input ]] && return 1

    local mime=""
    local display_name="$input"

    if [[ -f $input ]]; then
        mime=$(xdg-mime query filetype "$input" 2>/dev/null)
        display_name=$(basename "$input")
    elif [[ $input == .* ]]; then
        mime=$(xdg-mime query filetype "dummy${input}" 2>/dev/null)
        display_name="$input"
    else
        mime=$(xdg-mime query filetype "dummy.${input}" 2>/dev/null)
        display_name="$input"
    fi

    [[ -z $mime ]] && echo "result=error|reason=unknown_mime|input=$input" && return 1

    local default_app=""
    local app_name="No default set"
    default_app=$(rx_xdg_get_default "$mime")
    if [[ -n $default_app ]]; then
        app_name=$(rx_xdg_desktop_name "$default_app")
    fi

    local handlers_count=0
    while IFS='|' read -r _ _ _; do
        ((handlers_count++))
    done < <(rx_xdg_find_handlers "$mime")

    echo "file=$display_name|mime=$mime|default=$default_app|app_name=$app_name|handlers=$handlers_count"
}

rx_xdg_autostart_list() {
    local search_paths=(
        "$HOME/.config/autostart"
        "/etc/xdg/autostart"
    )

    for sp in "${search_paths[@]}"; do
        [[ ! -d $sp ]] && continue
        local scope="system"
        [[ $sp == "$HOME"* ]] && scope="user"

        while IFS= read -r desktop_file; do
            [[ -z $desktop_file ]] && continue
            [[ ! -f $desktop_file ]] && continue

            local name=$(grep "^Name=" "$desktop_file" 2>/dev/null | head -1 | cut -d= -f2-)
            local exec_cmd=$(grep "^Exec=" "$desktop_file" 2>/dev/null | head -1 | cut -d= -f2-)
            local hidden=$(grep -c "^Hidden=true" "$desktop_file" 2>/dev/null)
            local enabled="true"
            [[ $hidden -gt 0 ]] && enabled="false"

            local binary=$(echo "$exec_cmd" | awk '{print $1}')
            local binary_exists="no"
            [[ -n $binary ]] && command -v "$binary" >/dev/null 2>&1 && binary_exists="yes"

            echo "$name|$desktop_file|$enabled|$binary_exists|$scope"
        done < <(find "$sp" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | sort)
    done
}

rx_xdg_autostart_toggle() {
    local name="$1"
    local action="$2"
    [[ -z $name ]] && echo "result=error|reason=no_name" && return 1

    local user_autostart="$HOME/.config/autostart"
    local system_autostart="/etc/xdg/autostart"
    local target_file=""

    if [[ -f "$user_autostart/$name" ]]; then
        target_file="$user_autostart/$name"
    elif [[ -f "$system_autostart/$name" ]]; then
        mkdir -p "$user_autostart"
        cp "$system_autostart/$name" "$user_autostart/$name"
        target_file="$user_autostart/$name"
    else
        echo "result=error|reason=not_found|name=$name"
        return 1
    fi

    case "$action" in
        enable)
            sed -i '/^Hidden=true/d' "$target_file"
            echo "OK|enabled"
            ;;
        disable)
            if grep -q "^Hidden=true" "$target_file" 2>/dev/null; then
                echo "OK|already_disabled"
            else
                echo "Hidden=true" >>"$target_file"
                echo "OK|disabled"
            fi
            ;;
        toggle)
            if grep -q "^Hidden=true" "$target_file" 2>/dev/null; then
                sed -i '/^Hidden=true/d' "$target_file"
                echo "OK|enabled"
            else
                echo "Hidden=true" >>"$target_file"
                echo "OK|disabled"
            fi
            ;;
        *)
            echo "result=error|reason=invalid_action|action=$action"
            return 1
            ;;
    esac
}

rx_xdg_autostart_clean() {
    local user_autostart="$HOME/.config/autostart"
    [[ ! -d $user_autostart ]] && echo "cleaned=0" && return 0

    local cleaned=0
    while IFS= read -r desktop_file; do
        [[ -z $desktop_file ]] && continue
        local exec_cmd=$(grep "^Exec=" "$desktop_file" 2>/dev/null | head -1 | cut -d= -f2-)
        local binary=$(echo "$exec_cmd" | awk '{print $1}')
        if [[ -n $binary ]] && ! command -v "$binary" >/dev/null 2>&1; then
            rm -f "$desktop_file"
            ((cleaned++))
        fi
    done < <(find "$user_autostart" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null)

    echo "cleaned=$cleaned"
}

rx_xdg_health() {
    local mimeapps="$HOME/.config/mimeapps.list"
    [[ ! -f $mimeapps ]] && echo "status=ok|issues=0" && return 0

    local total=0
    local valid=0
    local ghost_desktop=0
    local ghost_binary=0
    local issues=""

    local in_section=false
    while IFS= read -r line; do
        [[ $line =~ ^\[ ]] && {
            in_section=false
            [[ $line == "[Default Applications]" ]] && in_section=true
            continue
        }
        if $in_section && [[ $line == *=* && ! $line =~ ^# ]]; then
            local mime="${line%%=*}"
            local desktop="${line#*=}"
            ((total++))

            local desktop_path=""
            local found=false
            for sp in "/usr/share/applications" "$HOME/.local/share/applications" "/var/lib/flatpak/exports/share/applications"; do
                if [[ -f "$sp/$desktop" ]]; then
                    desktop_path="$sp/$desktop"
                    found=true
                    break
                fi
            done

            if [[ $found == false ]]; then
                ((ghost_desktop++))
                issues+="desktop_missing|$mime|$desktop|"
                continue
            fi

            local exec_cmd=$(grep "^Exec=" "$desktop_path" 2>/dev/null | head -1 | cut -d= -f2-)
            local binary=$(echo "$exec_cmd" | awk '{print $1}')
            if [[ -n $binary ]] && ! command -v "$binary" >/dev/null 2>&1; then
                ((ghost_binary++))
                issues+="binary_missing|$mime|$desktop|$binary|"
                continue
            fi

            ((valid++))
        fi
    done <"$mimeapps"

    echo "total=$total|valid=$valid|ghost_desktop=$ghost_desktop|ghost_binary=$ghost_binary|issues=$issues"
}
