#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profile"
OUTPUT_DIR="$SCRIPT_DIR/out"
WORK_DIR="$SCRIPT_DIR/work"

if [[ -z ${RETRO_DIR:-} ]]; then
    export RETRO_DIR="$(dirname "$SCRIPT_DIR")"
fi

source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/git.sh"

CACHE_VOLUME="retrolinux-pkg-cache"
REQUIRED_DEPS=("bc" "convert")

_check_deps() {
    rx_log "info" "Checking dependencies..."

    local missing=()
    for cmd in "${REQUIRED_DEPS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            rx_log "warn" "Missing: $cmd"
            missing+=("$cmd")
        else
            rx_log "info" "Found: $cmd at $(which "$cmd")"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        rx_log "warn" "Missing host dependencies: ${PINK}${missing[*]}${RESET}"
        rx_log "info" "Docker container will install its own packages"
    else
        rx_log "success" "All host dependencies satisfied"
    fi
}

_build_help() {
    rx_help_usage "./build.sh <command> [options]"
    rx_help_commands "Available commands"
    rx_help_cmd "build, b" "Build the full ISO (default)"
    rx_help_cmd "--plymouth, -p" "Generate Plymouth splashscreen only"
    rx_help_cmd "--clean, -c" "Clean cache and work dir, then build"
    rx_help_cmd "--yes, -y" "Skip all confirmations"
    rx_help_cmd "--help, -h" "Show this help message"
    rx_help_examples
    rx_help_example "./build.sh" "Build ISO with prompts"
    rx_help_example "./build.sh --yes" "Build ISO, skip prompts"
    rx_help_example "./build.sh --plymouth" "Generate splashscreen only"
    rx_help_example "./build.sh --clean" "Clean everything and rebuild"
    rx_help_example "./build.sh -c -y" "Clean and build, skip prompts"
}

_generate_splashscreen() {
    local theme_dir="$PROFILE_DIR/airootfs/usr/share/plymouth/themes/retrolinux"
    local splash_png="${theme_dir}/logo.png"
    local source_logo="$RETRO_DIR/assets/logo-palm-wide-transparent-bg.png"

    mkdir -p "$theme_dir"

    if [[ ! -f $source_logo ]]; then
        rx_log "error" "Source logo not found: ${source_logo}"
        return 1
    fi

    rx_log "info" "Generating Plymouth splashscreen..."
    magick "$source_logo" -resize 60% "$splash_png"

    local size_bytes=$(stat -c%s "$splash_png")
    local size_kb=$(awk "BEGIN {printf \"%.2f\", $size_bytes / 1024}")

    rx_log "success" "Splashscreen generated: ${splash_png}"
    rx_log "info" "Size: ${size_kb} KB"
}

_docker_check() {
    rx_log "info" "Checking Docker..."

    if ! command -v docker &>/dev/null; then
        rx_log "error" "Docker is not installed"
        rx_log "info" "Install with: sudo pacman -S docker"
        return 1
    fi

    if ! docker info &>/dev/null; then
        rx_log "error" "Docker daemon is not running"
        rx_log "info" "Start with: sudo systemctl start docker"
        rx_log "info" "Enable at boot: sudo systemctl enable docker"
        return 1
    fi

    rx_log "success" "Docker is ready"
}

_init_offline_cache() {

    docker volume inspect "$CACHE_VOLUME" >/dev/null 2>&1 || {
        docker volume create "$CACHE_VOLUME" >/dev/null 2>&1
    }

    if docker run --rm -v "${CACHE_VOLUME}:/cache" archlinux/archlinux:latest bash -c "test -f /cache/.cache-initialized" 2>/dev/null; then
        rx_log "info" "Using existing cache"
        return 0
    fi

    rx_log "info" "Initializing offline package cache..."
    rx_log "info" "Downloading packages to cache..."

    local host_uid=$(id -u)
    local host_gid=$(id -g)

    docker run --rm \
        -e "HOST_UID=$host_uid" \
        -e "HOST_GID=$host_gid" \
        -v "$PROFILE_DIR:/profile:ro" \
        -v "${CACHE_VOLUME}:/packages-cache" \
        archlinux/archlinux:latest bash -c "
            set -e

            pacman -Sy --noconfirm

            mkdir -p /packages-cache
            mkdir -p /tmp/offlinedb

            yes | xargs pacman -Syw --noconfirm \
                --cachedir /packages-cache \
                --dbpath /tmp/offlinedb < /profile/packages.x86_64

            repo-add /packages-cache/offline.db.tar.gz /packages-cache/*.pkg.tar.zst

            chown -R $host_uid:$host_gid /packages-cache

            touch /packages-cache/.cache-initialized
        "

    rx_log "success" "Cache initialized"
}

_update_offline_cache() {
    rx_log "info" "Updating offline package cache..."

    local host_uid=$(id -u)
    local host_gid=$(id -g)

    docker run --rm \
        -e "HOST_UID=$host_uid" \
        -e "HOST_GID=$host_gid" \
        -v "$PROFILE_DIR:/profile:ro" \
        -v "${CACHE_VOLUME}:/packages-cache" \
        archlinux/archlinux:latest bash -c "
            set -e

            pacman -Sy --noconfirm

            mkdir -p /tmp/offlinedb
            yes | xargs pacman -Syw --noconfirm \
                --cachedir /packages-cache \
                --dbpath /tmp/offlinedb < /profile/packages.x86_64

            cd /packages-cache

            for pkg in *.pkg.tar.zst; do
                [[ -f \$pkg ]] || continue
                base=\${pkg%.pkg.tar.zst}
                name=\${base%-*-*}
                version=\${base#*-\$name-}
                version=\${version%-[0-9]*}

                duplicates=(\$(ls -1 \$name-*.pkg.tar.zst 2>/dev/null | sort -t'-' -k2 -V))
                if [[ \${#duplicates[@]} -gt 1 ]]; then
                    for dup in \"\${duplicates[@]:0:\$(( \${#duplicates[@]} - 1 ))}\"; do
                        rm -f \"\$dup\"
                    done
                fi
            done

            rm -f linux-firmware-nvidia-*.pkg.tar.zst
            rm -f linux-firmware-marvell-*.pkg.tar.zst
            rm -f linux-firmware-atheros-*.pkg.tar.zst
            rm -f linux-firmware-mediatek-*.pkg.tar.zst
            rm -f linux-firmware-broadcom-*.pkg.tar.zst
            rm -f linux-firmware-other-*.pkg.tar.zst
            rm -f linux-firmware-cirrus-*.pkg.tar.zst
            rm -f linux-firmware-radeon-*.pkg.tar.zst
            rm -f linux-firmware-20260309-1-any.pkg.tar.zst

            rm -f /packages-cache/offline.db.tar.gz
            repo-add /packages-cache/offline.db.tar.gz /packages-cache/*.pkg.tar.zst

            chown -R $host_uid:$host_gid /packages-cache
        "

    rx_log "success" "Cache updated"
}

_cleanup_build() {
    if [[ -d $WORK_DIR ]]; then
        rx_log "warn" "Existing build directory found"

        if ! rx_confirm "Delete existing build and continue?" "N" "${skip_prompt:-false}"; then
            rx_log "info" "Build cancelled"
            exit 0
        fi

        rx_log "info" "Cleaning up existing build directory..."
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi

    local iso_file
    shopt -s nullglob
    for iso_file in "$OUTPUT_DIR"/*.iso; do
        if [[ -f $iso_file ]]; then
            local filename="${iso_file##*/}"

            if [[ ${skip_prompt:-false} == "true" ]]; then
                rx_log "info" "Deleting old ISO: ${filename}"
                rm -f "$iso_file" 2>/dev/null || true
            else
                if rx_confirm "Delete ${filename} and continue?" "N" "false"; then
                    rx_log "info" "Deleting old ISO: ${filename}"
                    rm -f "$iso_file" 2>/dev/null || true
                fi
            fi
        fi
    done
    shopt -u nullglob

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$WORK_DIR"
}

_prepare_airootfs_offline() {
    rx_log "info" "Preparing airootfs offline packages..."

    local offline_dir="$PROFILE_DIR/airootfs/var/cache/retrolinux/mirror/offline"
    mkdir -p "$offline_dir"

    docker run --rm \
        -v "${CACHE_VOLUME}:/cache:ro" \
        -v "${offline_dir}:/dest:rw" \
        archlinux/archlinux:latest bash -c "
            set -e
            mkdir -p /dest
            if [[ -d /cache ]] && [[ -n \"\$(ls -A /cache 2>/dev/null)\" ]]; then
                cp -r /cache/* /dest/
            else
                echo 'Warning: Cache is empty'
            fi
        "

    cp "$PROFILE_DIR/pacman-offline.conf" "$PROFILE_DIR/airootfs/etc/pacman.conf"

    rx_log "success" "Airootfs prepared"
}

_docker_build() {
    local skip_prompt="$1"
    local _build_start_time=$SECONDS

    rx_log "info" "Starting docker build function..."

    export SKIP_PROMPT="$skip_prompt"

    rx_log "info" "Checking for existing ISO size..."

    local old_iso_size=0
    local old_iso_file
    old_iso_file=$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.iso' 2>/dev/null | head -n1 || true)
    if [[ -n $old_iso_file && -f $old_iso_file ]]; then
        old_iso_size=$(stat -c%s "$old_iso_file" 2>/dev/null || echo "0")
        rx_log "info" "Found old ISO: $old_iso_file ($old_iso_size bytes)"
    else
        rx_log "info" "No existing ISO found"
    fi

    rx_log "info" "Running docker check..."
    _docker_check || {
        rx_log "error" "Docker check failed"
        return 1
    }

    rx_log "info" "Running deps check (optional on host)..."
    if ! _check_deps 2>/dev/null; then
        rx_log "warn" "Some host dependencies missing, but Docker build will use its own packages"
    fi

    rx_log "info" "All checks passed, starting build..."

    _init_offline_cache
    _update_offline_cache
    _cleanup_build
    _prepare_airootfs_offline

    local version=$(rx_git_version)
    local branch=$(rx_git_branch)
    local iso_date=$(date '+%Y.%m.%d')

    sed -i "s|@ISO_VERSION@|${iso_date}|g" "$PROFILE_DIR/profiledef.sh"

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$WORK_DIR"

    rx_log "info" "Building RetroLinux ISO ${version} (${branch})..."
    rx_log "info" "Starting Docker build (this may take a while)..."

    local host_uid=$(id -u)
    local host_gid=$(id -g)

    docker run --rm \
        --privileged \
        -e "HOST_UID=$host_uid" \
        -e "HOST_GID=$host_gid" \
        -v "$PROFILE_DIR:/profile:ro" \
        -v "$WORK_DIR:/work" \
        -v "$OUTPUT_DIR:/out" \
        -v "${CACHE_VOLUME}:/var/cache/retrolinux/mirror/offline:ro" \
        archlinux/archlinux:latest bash -c "
            set -e

            rm -f /var/lib/pacman/db.lck 2>/dev/null || true

            pacman -Sy --noconfirm
            pacman --noconfirm -Sy archiso git sudo base-devel jq grub bc imagemagick

            KERNEL_PKG=\$(ls /var/cache/retrolinux/mirror/offline/linux-*.pkg.tar.zst 2>/dev/null | head -1)
            if [[ -n \$KERNEL_PKG ]]; then
                KERNEL_VER=\${KERNEL_PKG##*/linux-}
                KERNEL_VER=\${KERNEL_VER%.pkg.tar.zst}
            fi
            [[ -z \$KERNEL_VER ]] && KERNEL_VER=unknown

            mkarchiso -v -w /work/ -o /out /profile/

            echo \"\$KERNEL_VER\" > /out/kernel-version.txt

            chown -R $host_uid:$host_gid /out/
        "

    rx_log "success" "ISO built successfully"

    rx_log "info" "Build output directory: $OUTPUT_DIR"
    rx_log "info" "Listing output dir contents:"
    ls -la "$OUTPUT_DIR/" 2>&1 || rx_log "warn" "Could not list output directory"

    local iso_file
    iso_file=$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.iso' 2>/dev/null | head -n1)
    if [[ -n $iso_file ]]; then
        rx_log "info" "Found ISO: $iso_file"

        if [[ -f $iso_file ]]; then
            local filename="${iso_file##*/}"
            local size_bytes=$(stat -c%s "$iso_file")
            local size_gb=$(awk "BEGIN {printf \"%.2f\", $size_bytes / 1024 / 1024 / 1024}")
            local sha256=$(sha256sum "$iso_file" | awk '{print $1}')
            local build_time=$((SECONDS - _build_start_time))
            local build_time_formatted=""

            if [[ $build_time -ge 60 ]]; then
                build_time_formatted=$(printf '%dm %ds' $((build_time / 60)) $((build_time % 60)))
            else
                build_time_formatted="${build_time}s"
            fi

            rx_log "info" "Build completed"
            rx_log "info" "Filename: ${filename}"
            rx_log "info" "Size: ${size_gb} GB (${size_bytes} bytes)"
            if [[ $old_iso_size -gt 0 ]]; then
                local old_size_gb=$(awk "BEGIN {printf \"%.2f\", $old_iso_size / 1024 / 1024 / 1024}")
                local size_diff=$((size_bytes - old_iso_size))
                local size_diff_abs=${size_diff#-}
                local diff_mb=$(awk "BEGIN {printf \"%.2f\", $size_diff_abs / 1024 / 1024}")
                local diff_gb=$(awk "BEGIN {printf \"%.2f\", $size_diff_abs / 1024 / 1024 / 1024}")
                if [[ $size_diff -lt 0 ]]; then
                    rx_log "info" "Previous ISO: ${old_size_gb} GB (-${diff_mb} MB, smaller)"
                elif [[ $size_diff -gt 0 ]]; then
                    rx_log "info" "Previous ISO: ${old_size_gb} GB (+${diff_mb} MB, larger)"
                else
                    rx_log "info" "Previous ISO: ${old_size_gb} GB (same size)"
                fi
            fi
            rx_log "info" "SHA256: ${sha256}"
            rx_log "info" "Build time: ${build_time_formatted}"

            local kernel_version_file="$OUTPUT_DIR/kernel-version.txt"
            if [[ -f $kernel_version_file ]]; then
                local kernel_version_in_iso=$(cat "$kernel_version_file")
                if [[ -n $kernel_version_in_iso ]]; then
                    rx_log "info" "Kernel: ${kernel_version_in_iso}"
                fi
            fi
        fi
    fi
}

_clean_all() {
    rx_log "info" "Cleaning all build artifacts..."

    rx_log "info" "Removing work directory..."
    if [[ -d $WORK_DIR ]]; then
        if rm -rf "$WORK_DIR" 2>/dev/null; then
            rx_log "success" "Work directory removed"
        else
            rx_log "warn" "Failed to remove work directory, trying with sudo..."
            if sudo rm -rf "$WORK_DIR" 2>/dev/null; then
                rx_log "success" "Work directory removed"
            else
                rx_log "error" "Failed to remove work directory. Please remove manually: sudo rm -rf $WORK_DIR"
            fi
        fi
    else
        rx_log "info" "Work directory does not exist"
    fi

    rx_log "info" "Removing Docker package cache..."
    if docker volume rm "$CACHE_VOLUME" 2>/dev/null; then
        rx_log "success" "Docker cache volume removed"
    else
        rx_log "info" "Docker cache volume does not exist or already removed"
    fi

    rx_log "success" "Clean complete"
}

_iso_main() {
    rx_logo "$(
        cat <<'EOF'
██████╗ ███████╗████████╗██████╗  ██████╗     ██╗███████╗ ██████╗
██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗    ██║██╔════╝██╔═══██╗
██████╔╝█████╗     ██║   ██████╔╝██║   ██║    ██║███████╗██║   ██║
██╔══██╗██╔══╝     ██║   ██╔══██╗██║   ██║    ██║╚════██║██║   ██║
██║  ██║███████╗   ██║   ██║  ██║╚██████╔╝    ██║███████║╚██████╔╝
╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝     ╚═╝╚══════╝ ╚═════╝
EOF
    )"

    local skip_prompt="false"
    local command="build"
    local do_clean="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                _build_help
                exit 0
                ;;
            -y | --yes)
                skip_prompt="true"
                shift
                ;;
            -p | --plymouth)
                command="plymouth"
                shift
                ;;
            -c | --clean)
                do_clean="true"
                shift
                ;;
            build | b)
                command="build"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ $do_clean == "true" ]]; then
        _clean_all
    fi

    case "$command" in
        plymouth)
            _generate_splashscreen
            ;;
        build)
            _docker_build "$skip_prompt"
            ;;
    esac
}

if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
    export -f _iso_main _docker_check _docker_build _init_offline_cache _update_offline_cache _prepare_airootfs_offline _cleanup_build _generate_splashscreen _build_help _clean_all _check_deps
else
    _iso_main "$@"
fi
