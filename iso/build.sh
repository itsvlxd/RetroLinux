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
source "$RETRO_DIR/lib/git.sh"

CACHE_VOLUME="retrolinux-pkg-cache"

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

            mapfile -t packages < <(grep -v '^#' /profile/packages.x86_64 | grep -v '^$')
            total=\${#packages[@]}

            mkdir -p /packages-cache
            mkdir -p /tmp/offlinedb

            pacman -Syw \"\${packages[@]}\" --noconfirm \
                --cachedir /packages-cache \
                --dbpath /tmp/offlinedb

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

            mapfile -t packages < <(grep -v '^#' /profile/packages.x86_64 | grep -v '^$')

            mkdir -p /tmp/offlinedb
            pacman -Syw \"\${packages[@]}\" --noconfirm \
                --cachedir /packages-cache \
                --dbpath /tmp/offlinedb

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

    _docker_check || return 1

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
            pacman --noconfirm -Sy archiso git sudo base-devel jq grub

            mkarchiso -v -w /work/ -o /out /profile/

            chown -R $host_uid:$host_gid /out/
        "

    rx_log "success" "ISO built successfully"

    local iso_file
    iso_file=$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.iso' 2>/dev/null | head -n1)

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
        rx_log "info" "SHA256: ${sha256}"
        rx_log "info" "Build time: ${build_time_formatted}"
    fi
}

_iso_main() {
    local skip_prompt="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y | --yes)
                skip_prompt="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    _docker_build "$skip_prompt"
}

if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
    export -f _iso_main _docker_check _docker_build _init_offline_cache _update_offline_cache _prepare_airootfs_offline _cleanup_build
else
    _iso_main "$@"
fi
