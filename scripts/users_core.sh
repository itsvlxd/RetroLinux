#!/bin/bash

RETRO_DIR="${RETRO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "users_core"

USERNAME_RE='^[a-z_][a-z0-9_-]*$'
DESKTOP_GROUPS=(video render audio input disk lp)

_real_home() {
    local user="$1"
    getent passwd "$user" 2>/dev/null | cut -d: -f6
}

_user_exists() {
    getent passwd "$1" >/dev/null 2>&1
}

_source_user() {
    if [[ -n ${SUDO_USER:-} ]]; then
        echo "$SUDO_USER"
    elif [[ -n ${PKEXEC_UID:-} ]]; then
        getent passwd "$PKEXEC_UID" 2>/dev/null | cut -d: -f1
    else
        echo "$LOGNAME"
    fi
}

_source_vars_file() {
    local src_user="$1"
    local home
    home="$(_real_home "$src_user")"
    echo "$home/.config/retro/variables.sh"
}

_seed_variables() {
    local target_user="$1"
    local target_home
    target_home="$(_real_home "$target_user")"

    local src_user
    src_user="$(_source_user)"
    local src_file
    src_file="$(_source_vars_file "$src_user")"

    local retro_dir="$target_home/.config/retro"
    mkdir -p "$retro_dir" || return 1

    if [[ ! -f $src_file ]]; then
        rx_log_file "warn" "No variables.sh found for $src_user — leaving retro config empty"
        return 0
    fi

    local old_home
    old_home="$(_real_home "$src_user")"

    sed -e "s|$old_home|$target_home|g" "$src_file" >"$retro_dir/variables.sh"
    rx_log_file "success" "Copied variables.sh → $retro_dir/variables.sh (paths rewritten to $target_home)"
}

_fix_ownership() {
    local target_user="$1"
    local target_home
    target_home="$(_real_home "$target_user")"

    chown -R "$target_user:$(id -gn "$target_user")" "$target_home" 2>/dev/null

    chmod 644 "$target_home/.face" "$target_home/.face.icon" 2>/dev/null
    chmod o+x "$target_home" 2>/dev/null
    chmod 755 "$target_home/.config/retro" 2>/dev/null
    chmod 644 "$target_home/.config/retro/variables.sh" 2>/dev/null
}

_gen_face() {
    local target_user="$1"
    local target_home
    target_home="$(_real_home "$target_user")"

    if ! command -v python3 >/dev/null 2>&1; then
        rx_log_file "warn" "python3 not available — skipping generated avatar"
        return 0
    fi

    local out="/tmp/retro-face-${target_user}.png"
    local rc=1
    if python3 -c "import PIL" >/dev/null 2>&1; then
        python3 - "$target_user" "$out" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont

name = sys.argv[1]
out = sys.argv[2]
size = 512
c1 = (206, 61, 201)
c2 = (220, 135, 213)

img = Image.new("RGB", (size, size))
draw = ImageDraw.Draw(img)
for y in range(size):
    t = y / (size - 1)
    r = int(c1[0] + (c2[0] - c1[0]) * t)
    g = int(c1[1] + (c2[1] - c1[1]) * t)
    b = int(c1[2] + (c2[2] - c1[2]) * t)
    draw.line([(0, y), (size, y)], fill=(r, g, b))

initials = "".join(p[0].upper() for p in name.replace("_", " ").split() if p)[:2] or "?"
try:
    font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", 200)
except Exception:
    font = ImageFont.load_default()

bbox = draw.textbbox((0, 0), initials, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
x = (size - tw) / 2 - bbox[0]
y = (size - th) / 2 - bbox[1]
draw.text((x, y), initials, font=font, fill=(255, 255, 255))

img.save(out, "PNG")
print("OK")
PY
        rc=$?
    else
        rx_log_file "warn" "PIL not available — skipping generated avatar"
        return 0
    fi

    if [[ $rc -eq 0 && -f $out ]]; then
        cp "$out" "$target_home/.face" 2>/dev/null
        cp "$out" "$target_home/.face.icon" 2>/dev/null
        chown "$target_user:$(id -gn "$target_user")" "$target_home/.face" "$target_home/.face.icon" 2>/dev/null
        chmod 644 "$target_home/.face" "$target_home/.face.icon" 2>/dev/null
        chmod o+x "$target_home" 2>/dev/null
        rm -f "$out"
        rx_log_file "success" "Generated gradient avatar for $target_user"
        return 0
    fi

    rm -f "$out"
    rx_log_file "warn" "Avatar generation failed — user will have initials-only avatar"
    return 0
}

_sync_sddm_face() {
    local user="$1"
    local home
    home="$(_real_home "$user")"

    [[ -f $home/.face.icon ]] || return 0

    local faces_dir="/usr/share/sddm/faces"
    local target="$faces_dir/${user}.face.icon"

    if [[ ! -w $faces_dir ]]; then
        if sudo -n mkdir -p "$faces_dir" 2>/dev/null && sudo -n cp -f "$home/.face.icon" "$target" 2>/dev/null; then
            sudo -n chmod 644 "$target" 2>/dev/null || true
        elif command -v pkexec >/dev/null 2>&1 && timeout 5 pkexec cp -f "$home/.face.icon" "$target" 2>/dev/null; then
            chmod 644 "$target" 2>/dev/null || true
        else
            rx_log_file "warn" "Could not write SDDM face for $user (needs root)"
            return 0
        fi
    else
        mkdir -p "$faces_dir" 2>/dev/null || return 0
        cp -f "$home/.face.icon" "$target" 2>/dev/null || return 0
        chmod 644 "$target" 2>/dev/null || true
    fi

    rx_log_file "success" "Synced SDDM face for $user → $target"
}

users_gen_face() {
    local user="$1"

    if ! _user_exists "$user"; then
        echo "ERROR: User '$user' does not exist"
        return 1
    fi

    _gen_face "$user"
    _fix_ownership "$user"
    _sync_sddm_face "$user"
    return 0
}

_run_install() {
    local target_user="$1"
    local target_home
    target_home="$(_real_home "$target_user")"

    rx_log_file "info" "Installing user modules for $target_user (retro -i all -a user -y)"
    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        USER="$target_user" \
        LOGNAME="$target_user" \
        "$RETRO_DIR/retro.sh" -i all -a user -y
    local rc=$?

    _fix_ownership "$target_user"

    if [[ $rc -eq 0 ]]; then
        rx_log_file "success" "Modules installed for $target_user"
    else
        rx_log_file "error" "Module install finished with status $rc for $target_user"
    fi
    return $rc
}

_run_post_setup() {
    local target_user="$1"
    local target_home
    target_home="$(_real_home "$target_user")"

    rx_log_file "info" "Running wallpaper/theme setup for $target_user"

    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        "$RETRO_DIR/retro.sh" wallpaper static true

    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        "$RETRO_DIR/retro.sh" wallpaper set "Retrowave Gtr Wallpaper"

    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        "$RETRO_DIR/retro.sh" wallpaper setup --needed -y -o "theme=retro"

    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        "$RETRO_DIR/retro.sh" theme setup --needed -y

    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        "$RETRO_DIR/retro.sh" theme mode dark

    env HOME="$target_home" \
        RETRO_CONFIG="$target_home/.config/retro" \
        RETRO_DIR="$RETRO_DIR" \
        RETRO_SETUP=true \
        RETRO_SECONDARY_INSTALL=true \
        "$RETRO_DIR/retro.sh" shell start

    _fix_ownership "$target_user"
    rx_log_file "success" "Wallpaper/theme setup complete for $target_user"
}

_validate_user() {
    local user="$1"
    [[ -z $user ]] && return 1
    [[ $user =~ $USERNAME_RE ]]
}

users_list() {
    local src_user
    src_user="$(_source_user)"

    while IFS=: read -r name _pw uid _gid _gecos home shell; do
        [[ -z $name ]] && continue
        ((uid < 1000)) && continue
        [[ $shell == */nologin || $shell == */false ]] && continue

        local retro_state="no"
        [[ -f "$home/.config/retro/variables.sh" ]] && retro_state="yes"

        local marker=""
        [[ $name == "$src_user" ]] && marker="(you)"

        echo "$name|$uid|$home|$shell|$retro_state|$marker"
    done < <(getent passwd)
}

users_create() {
    local user="$1"
    local full_name="${2:-}"
    local admin="${3:-false}"
    local password="${4:-}"

    if ! _validate_user "$user"; then
        echo "ERROR: Invalid username '$user' (use lowercase letters, digits, _ and -)"
        return 1
    fi
    if _user_exists "$user"; then
        echo "ERROR: User '$user' already exists"
        return 1
    fi

    local groups=()
    for g in "${DESKTOP_GROUPS[@]}"; do
        groups+=("$g")
    done
    [[ $admin == "true" ]] && groups+=(wheel)

    local seen=" "
    local group_args=""
    for g in "${groups[@]}"; do
        if [[ $seen != *" $g "* ]]; then
            seen+=" $g "
            group_args+="$g,"
        fi
    done
    group_args="${group_args%,}"

    local default_shell="bash"
    local shell_bin
    shell_bin=$(grep -m1 "^export RETRO_BIN_SHELL=" "$(_source_vars_file "$(_source_user)")" 2>/dev/null | sed 's/^export RETRO_BIN_SHELL="\?\([^"]*\)"\?/\1/')
    [[ -n $shell_bin ]] && default_shell="$shell_bin"
    local shell_path="/bin/$default_shell"
    [[ -x $shell_path ]] || shell_path="/usr/bin/$default_shell"
    [[ -x $shell_path ]] || shell_path="/bin/bash"

    rx_log_file "info" "Creating user $user (groups: $group_args, shell: $shell_path)"
    if ! useradd -m -s "$shell_path" -G "$group_args" "$user"; then
        echo "ERROR: Failed to create user '$user'"
        return 1
    fi
    [[ -n $full_name ]] && chfn -f "$full_name" "$user" >/dev/null 2>&1

    if [[ -n $password ]]; then
        echo "$user:$password" | chpasswd
        rx_log_file "success" "Password set for $user"
    else
        echo "Set a password for $user (required to log in)"
        passwd "$user" || {
            echo "WARNING: Password not set — the account is locked until a password is assigned"
        }
    fi

    if [[ $admin == "true" ]]; then
        rx_log_file "success" "$user added to wheel (sudo access)"
    fi

    _seed_variables "$user" || {
        echo "WARNING: Continuing without seeded variables"
    }

    _gen_face "$user"

    _run_install "$user"
    _run_post_setup "$user"
    return 0
}

users_resync() {
    local user="$1"

    if ! _user_exists "$user"; then
        echo "ERROR: User '$user' does not exist"
        return 1
    fi

    _seed_variables "$user" || {
        echo "WARNING: Continuing without re-seeded variables"
    }

    _run_install "$user"
    _run_post_setup "$user"
    return 0
}

users_delete() {
    local user="$1"
    local src_user
    src_user="$(_source_user)"

    if [[ $user == "root" ]]; then
        echo "ERROR: Refusing to delete root"
        return 1
    fi
    if [[ $user == "$src_user" ]]; then
        echo "ERROR: Refusing to delete the current user ($src_user)"
        return 1
    fi
    if ! _user_exists "$user"; then
        echo "ERROR: User '$user' does not exist"
        return 1
    fi

    rx_log_file "info" "Deleting user $user and their home directory"
    userdel -r "$user"
    rx_log_file "success" "Deleted user $user"
}

users_set_face() {
    local user="$1"
    local image="$2"

    if ! _user_exists "$user"; then
        echo "ERROR: User '$user' does not exist"
        return 1
    fi
    if [[ -z $image || ! -f $image ]]; then
        echo "ERROR: Image not found: $image"
        return 1
    fi

    local home
    home="$(_real_home "$user")"

    cp "$image" "$home/.face" 2>/dev/null || {
        echo "ERROR: Failed to write $home/.face"
        return 1
    }
    cp "$image" "$home/.face.icon" 2>/dev/null
    chown "$user:$(id -gn "$user")" "$home/.face" "$home/.face.icon" 2>/dev/null
    chmod 644 "$home/.face" "$home/.face.icon" 2>/dev/null
    chmod o+x "$home" 2>/dev/null

    _sync_sddm_face "$user"

    rx_log_file "success" "Profile picture set for $user"
}

_set_shell_var() {
    local user="$1"
    local shell="$2"
    local home
    home="$(_real_home "$user")"
    local vars_file="$home/.config/retro/variables.sh"

    [[ -f $vars_file ]] || return 0

    if grep -q "^export RETRO_BIN_SHELL=" "$vars_file"; then
        sed -i "s|^export RETRO_BIN_SHELL=.*|export RETRO_BIN_SHELL=\"$shell\"|" "$vars_file"
    else
        echo "export RETRO_BIN_SHELL=\"$shell\"" >>"$vars_file"
    fi
    chown "$user:$(id -gn "$user")" "$vars_file" 2>/dev/null
    chmod 644 "$vars_file" 2>/dev/null
}

users_modify() {
    local user="$1"
    local new_home=""
    local new_shell=""
    local delete_old="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --home)
                new_home="${2:-}"
                shift
                ;;
            --shell)
                new_shell="${2:-}"
                shift
                ;;
            --delete-old)
                delete_old="${2:-false}"
                shift
                ;;
            *) ;;
        esac
        shift
    done

    if ! _user_exists "$user"; then
        echo "ERROR: User '$user' does not exist"
        return 1
    fi

    local old_home
    old_home="$(_real_home "$user")"

    if [[ -n $new_home && $new_home != "$old_home" ]]; then
        if [[ -e $new_home ]]; then
            echo "ERROR: Target home '$new_home' already exists"
            return 1
        fi
        if ! usermod -m -d "$new_home" "$user"; then
            echo "ERROR: Failed to move home to $new_home"
            return 1
        fi
        rx_log_file "info" "Moved home for $user: $old_home → $new_home"

        _fix_ownership "$user"

        if [[ $delete_old == "true" && -d $old_home ]]; then
            rm -rf "$old_home"
            rx_log_file "info" "Removed old home $old_home"
        fi

        _gen_face "$user"
        _run_install "$user"
    fi

    if [[ -n $new_shell ]]; then
        if ! grep -qx "$new_shell" /etc/shells 2>/dev/null; then
            echo "ERROR: '$new_shell' is not a valid login shell (see /etc/shells)"
            return 1
        fi
        if ! usermod -s "$new_shell" "$user"; then
            echo "ERROR: Failed to set shell for $user"
            return 1
        fi
        _set_shell_var "$user" "$new_shell"
        rx_log_file "info" "Set shell for $user: $new_shell"
    fi

    if [[ -z $new_home && -z $new_shell ]]; then
        echo "ERROR: Nothing to modify — pass --home and/or --shell"
        return 1
    fi

    return 0
}

ACTION="${1:-}"
USER=""
FULL_NAME=""
ADMIN=false
PASSWORD=""

case "$ACTION" in
    --create)
        USER="${2:-}"
        shift 2
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --admin) ADMIN=true ;;
                --full-name)
                    FULL_NAME="${2:-}"
                    shift
                    ;;
                --password)
                    PASSWORD="${2:-}"
                    shift
                    ;;
                *) ;;
            esac
            shift
        done
        users_create "$USER" "$FULL_NAME" "$ADMIN" "$PASSWORD"
        ;;
    --resync)
        users_resync "${2:-}"
        ;;
    --delete)
        users_delete "${2:-}"
        ;;
    --list)
        users_list
        ;;
    --set-face)
        users_set_face "${2:-}" "${3:-}"
        ;;
    --gen-face)
        users_gen_face "${2:-}"
        ;;
    --modify)
        USER="${2:-}"
        shift 2
        users_modify "$USER" "$@"
        ;;
    *)
        echo "ERROR: Usage: users_core.sh <--list|--create|--resync|--delete|--set-face|--modify> [user] [--admin] [--full-name NAME] [--home PATH] [--shell PATH] [--delete-old true|false] [image]"
        exit 1
        ;;
esac
