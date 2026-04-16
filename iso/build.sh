#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profile"
OUTPUT_DIR="$SCRIPT_DIR/out"
WORK_DIR="$SCRIPT_DIR/work"
CACHE_DIR="$PROFILE_DIR/packages-cache"

if [[ -z ${RETRO_DIR:-} ]]; then
    export RETRO_DIR="$(dirname "$SCRIPT_DIR")"
fi

source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/git.sh"

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

    rx_log "info" "Docker is ready"
}

_init_offline_cache() {
    local cache_init_marker="$CACHE_DIR/.cache-initialized"

    if [[ -f $cache_init_marker ]]; then
        rx_log "info" "Offline package cache exists"
        return 0
    fi

    rx_log "info" "Initializing offline package cache..."
    rx_log "info" "This may take a while on first run..."

    local host_uid=$(id -u)
    local host_gid=$(id -g)

    docker run --rm \
        -e "HOST_UID=$host_uid" \
        -e "HOST_GID=$host_gid" \
        -v "$PROFILE_DIR:/profile:ro" \
        -v "$CACHE_DIR:/packages-cache" \
        archlinux/archlinux:latest bash -c "
            set -e

            rx_log() {
                local level=\"\$1\"
                shift
                echo \"[\$level] \$*\"
            }

            rx_log 'info' 'Updating package list...'
            pacman -Sy --noconfirm

            rx_log 'info' 'Reading package list...'
            mapfile -t packages < <(grep -v '^#' /profile/packages.x86_64 | grep -v '^$')
            total=\${#packages[@]}
            rx_log 'info' \"Found \$total packages to cache\"

            rx_log 'info' 'Downloading packages to cache...'
            mkdir -p /packages-cache
            mkdir -p /tmp/offlinedb

            pacman -Syw \"\${packages[@]}\" --noconfirm \
                --cachedir /packages-cache \
                --dbpath /tmp/offlinedb

            rx_log 'info' 'Creating local repo database...'
            repo-add /packages-cache/offline.db.tar.gz /packages-cache/*.pkg.tar.zst

            rx_log 'info' 'Fixing cache ownership...'
            chown -R $host_uid:$host_gid /packages-cache

            touch /packages-cache/.cache-initialized
            rx_log 'info' 'Cache initialization complete'
        "

    rx_log "success" "Offline package cache initialized"
}

_update_offline_cache() {
    rx_log "info" "Updating offline package cache..."

    local host_uid=$(id -u)
    local host_gid=$(id -g)

    docker run --rm \
        -e "HOST_UID=$host_uid" \
        -e "HOST_GID=$host_gid" \
        -v "$PROFILE_DIR:/profile:ro" \
        -v "$CACHE_DIR:/packages-cache" \
        archlinux/archlinux:latest bash -c "
            set -e

            rx_log() {
                local level=\"\$1\"
                shift
                echo \"[\$level] \$*\"
            }

            rx_log 'info' 'Updating package list...'
            pacman -Sy --noconfirm

            rx_log 'info' 'Reading package list...'
            mapfile -t packages < <(grep -v '^#' /profile/packages.x86_64 | grep -v '^$')

            rx_log 'info' 'Checking for package updates...'
            mkdir -p /tmp/offlinedb
            pacman -Syw \"\${packages[@]}\" --noconfirm \
                --cachedir /packages-cache \
                --dbpath /tmp/offlinedb

            rx_log 'info' 'Rebuilding local repo database...'
            rm -f /packages-cache/offline.db.tar.gz
            repo-add /packages-cache/offline.db.tar.gz /packages-cache/*.pkg.tar.zst

            rx_log 'info' 'Fixing cache ownership...'
            chown -R $host_uid:$host_gid /packages-cache

            rx_log 'info' 'Cache update complete'
        "

    rx_log "success" "Offline package cache updated"
}

_prepare_airootfs_offline() {
    rx_log "info" "Preparing offline packages inside airootfs..."

    local offline_dir="$PROFILE_DIR/airootfs/var/cache/retrolinux/mirror/offline"
    mkdir -p "$offline_dir"

    rx_log "info" "Copying packages to airootfs..."
    cp -r "$CACHE_DIR"/* "$offline_dir/"

    rx_log "info" "Copying offline pacman.conf to airootfs..."
    cp "$PROFILE_DIR/pacman-offline.conf" "$PROFILE_DIR/airootfs/etc/pacman.conf"

    rx_log "info" "Airootfs offline preparation complete"
}

_docker_build() {
    local skip_prompt="$1"

    _docker_check || return 1

    _init_offline_cache
    _update_offline_cache

    if [[ -d $WORK_DIR ]] || [[ -n "$(ls -A "$OUTPUT_DIR" 2>/dev/null)" ]]; then
        rx_log "warn" "Existing build found"
        rx_log "info" "Work directory: $WORK_DIR"
        rx_log "info" "Output directory: $OUTPUT_DIR"

        rx_confirm "Delete existing build and continue?" "N" "$skip_prompt" || {
            rx_log "info" "Build cancelled"
            return 0
        }

        rx_log "info" "Cleaning up existing build..."
        rm -rf "$WORK_DIR" 2>/dev/null || true
        rm -f "$OUTPUT_DIR"/*.iso 2>/dev/null || true
    fi

    local version=$(rx_git_version)
    local branch=$(rx_git_branch)
    local iso_date=$(date '+%Y.%m.%d')

    sed -i "s|@ISO_VERSION@|${iso_date}|g" "$PROFILE_DIR/profiledef.sh"

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$WORK_DIR"

    _prepare_airootfs_offline

    rx_log "info" "Building RetroLinux ISO ${version} (${branch})"
    rx_log "info" "Profile: $PROFILE_DIR"
    rx_log "info" "Output: $OUTPUT_DIR"
    rx_log "info" "Starting Docker build..."

    local host_uid=$(id -u)
    local host_gid=$(id -g)

    docker run --rm \
        --privileged \
        -e "HOST_UID=$host_uid" \
        -e "HOST_GID=$host_gid" \
        -v "$PROFILE_DIR:/profile:ro" \
        -v "$WORK_DIR:/work" \
        -v "$OUTPUT_DIR:/out" \
        -v "$CACHE_DIR:/var/cache/retrolinux/mirror/offline:ro" \
        archlinux/archlinux:latest bash -c "
            set -e

            rx_log() {
                local level=\"\$1\"
                shift
                echo \"[\$level] \$*\"
            }

            rx_log 'info' 'Cleaning up any stale locks...'
            rm -f /var/lib/pacman/db.lck 2>/dev/null || true

            rx_log 'info' 'Installing build dependencies...'
            pacman -Sy --noconfirm
            pacman --noconfirm -Sy archiso git sudo base-devel jq grub

            rx_log 'info' 'Running mkarchiso...'
            mkarchiso -v -w /work/ -o /out /profile/

            rx_log 'info' 'Fixing output ownership...'
            chown -R $host_uid:$host_gid /out/
        "

    rx_log "success" "ISO built successfully"
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
    export -f _iso_main _docker_check _docker_build _init_offline_cache _update_offline_cache _prepare_airootfs_offline
else
    _iso_main "$@"
fi

