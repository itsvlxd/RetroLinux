#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profile"
OUTPUT_DIR="$SCRIPT_DIR/out"
WORK_DIR="$SCRIPT_DIR/work"

if [[ -z ${RETRO_DIR:-} ]]; then
    export RETRO_DIR="$(dirname "$SCRIPT_DIR")"
fi

if [[ -f "$RETRO_DIR/.env" ]]; then
    set -a
    source "$RETRO_DIR/.env"
    set +a
fi

source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/git.sh"

BUILD_IMAGE="retrolinux-build:latest"
REGISTRY="ghcr.io"
GITHUB_USER="${GITHUB_USER:-itsvlxd}"
FULL_IMAGE="${REGISTRY}/${GITHUB_USER}/retrolinux-build:latest"
CACHE_VOLUME="retrolinux-cache"
REQUIRED_DEPS=("docker" "bc" "convert")

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

_calculate_build_checksum() {
    local packages_file="$PROFILE_DIR/packages.x86_64"

    if [[ ! -f "$packages_file" ]]; then
        echo "missing"
        return
    fi

    local checksum=$(cat "$packages_file" | sha256sum | awk '{print $1}')
    echo "$checksum"
}

_should_skip_build() {
    local current_checksum
    current_checksum=$(_calculate_build_checksum)
    local checksum_file="$OUTPUT_DIR/.build-checksum"
    local last_checksum
    local iso_file
    local iso_files=()

    shopt -s nullglob
    iso_files=( "$OUTPUT_DIR"/*.iso )
    shopt -u nullglob

    if [[ -z $current_checksum ]] || [[ "$current_checksum" == "missing" ]]; then
        return 1
    fi

    if [[ ! -f "$checksum_file" ]] || [[ ${#iso_files[@]} -eq 0 ]]; then
        return 1
    fi

    iso_file="${iso_files[0]}"
    last_checksum=$(cat "$checksum_file" 2>/dev/null || echo "")

    if [[ "$current_checksum" == "$last_checksum" ]]; then
        rx_log "info" "Build inputs unchanged, skipping build..."
        rx_log "info" "Use --force to rebuild anyway"
        return 0
    fi

    return 1
}

_save_build_checksum() {
    local checksum=$(_calculate_build_checksum)
    echo "$checksum" > "$OUTPUT_DIR/.build-checksum"
}

_build_help() {
    rx_help_usage "./build.sh <command> [options]"
    rx_help_commands "Available commands"
    rx_help_cmd "build, b" "Build the full ISO (default)"
    rx_help_cmd "--plymouth, -p" "Generate Plymouth splashscreen only"
    rx_help_cmd "--clean, -c" "Clean build artifacts"
    rx_help_cmd "--docker, -d" "Build and push Docker image to registry"
    rx_help_cmd "--yes, -y" "Skip all confirmations"
    rx_help_cmd "--force, -f" "Force rebuild even if inputs unchanged"
    rx_help_cmd "--help, -h" "Show this help message"
    rx_help_examples
    rx_help_example "./build.sh" "Build ISO with prompts"
    rx_help_example "./build.sh --yes" "Build ISO, skip prompts"
    rx_help_example "./build.sh --plymouth" "Generate Plymouth splashscreen only"
    rx_help_example "./build.sh --clean" "Clean artifacts"
    rx_help_example "./build.sh --docker" "Build and push Docker image only"
    rx_help_example "./build.sh --force" "Force rebuild even if unchanged"
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

_build_docker_image() {
    rx_log "info" "Building custom Docker image..."

    local dockerfile="$SCRIPT_DIR/Dockerfile"
    local context_dir="$SCRIPT_DIR"

    if [[ ! -f "$dockerfile" ]]; then
        rx_log "error" "Dockerfile not found: $dockerfile"
        return 1
    fi

    rx_log "info" "Dockerfile: $dockerfile"

    rx_log "info" "Building image (this may take a few minutes first time)..."

    export DOCKER_BUILDKIT=1

    if docker build \
        --tag "$BUILD_IMAGE" \
        --tag "$FULL_IMAGE" \
        --force-rm \
        "$context_dir"; then
        rx_log "success" "Custom Docker image built: $BUILD_IMAGE"

        local img_size=$(docker image inspect "$BUILD_IMAGE" --format '{{.Size}}')
        local size_mb=$((img_size / 1024 / 1024))
        rx_log "info" "Image size: ${size_mb} MB"
    else
        rx_log "error" "Failed to build Docker image"
        return 1
    fi
}

_push_docker_image() {
    if [[ -z ${GH_TOKEN:-} ]]; then
        rx_log "warn" "GH_TOKEN not set, skipping image push"
        return 0
    fi

    rx_log "info" "Pushing Docker image to $FULL_IMAGE..."

    echo "$GH_TOKEN" | docker login "$REGISTRY" -u "$GITHUB_USER" --password-stdin

    rx_log "info" "Tagging image..."
    docker tag "$BUILD_IMAGE" "$FULL_IMAGE"

    rx_log "info" "Pushing image..."
    if docker push "$FULL_IMAGE"; then
        rx_log "success" "Image pushed to $FULL_IMAGE"
    else
        rx_log "error" "Failed to push image"
        docker logout "$REGISTRY" 2>/dev/null || true
        return 1
    fi

    docker logout "$REGISTRY" 2>/dev/null || true
}

_pull_docker_image() {
    if [[ -z ${GH_TOKEN:-} ]]; then
        rx_log "info" "GH_TOKEN not set, will build locally"
        return 0
    fi

    rx_log "info" "Checking for cached image at $FULL_IMAGE..."

    if docker image inspect "$FULL_IMAGE" &>/dev/null; then
        rx_log "info" "Found cached image, tagging as $BUILD_IMAGE"
        docker tag "$FULL_IMAGE" "$BUILD_IMAGE"
        return 0
    fi

    rx_log "info" "No cached image found locally"

    rx_log "info" "Attempting to pull from registry..."

    if echo "$GH_TOKEN" | docker login "$REGISTRY" -u "$GITHUB_USER" --password-stdin 2>/dev/null; then
        if docker pull "$FULL_IMAGE"; then
            docker tag "$FULL_IMAGE" "$BUILD_IMAGE"
            rx_log "success" "Image pulled and tagged as $BUILD_IMAGE"
            docker logout "$REGISTRY" 2>/dev/null || true
            return 0
        fi
        docker logout "$REGISTRY" 2>/dev/null || true
    fi

    rx_log "info" "Could not pull image, will build locally"
    return 0
}

_init_and_update_cache() {
    rx_log "info" "Cache volume approach enabled"
    rx_log "success" "Cache ready"
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
        -v "${offline_dir}:/dest:rw" \
        "$BUILD_IMAGE" bash -c "
            set -e
            mkdir -p /dest
            if [[ -d /var/cache/retrolinux/mirror/offline ]] && [[ -n \"\$(ls -A /var/cache/retrolinux/mirror/offline 2>/dev/null)\" ]]; then
                cp -r /var/cache/retrolinux/mirror/offline/* /dest/
            else
                echo 'Warning: Cache is empty inside image'
            fi
        "

    cp "$PROFILE_DIR/pacman-offline.conf" "$PROFILE_DIR/airootfs/etc/pacman.conf"

    rx_log "success" "Airootfs prepared"
}

_init_cache_volume() {
    rx_log "info" "Initializing cache volume..."

    docker volume inspect "$CACHE_VOLUME" >/dev/null 2>&1 || {
        docker volume create "$CACHE_VOLUME" >/dev/null
    }

    if docker run --rm -v "${CACHE_VOLUME}:/cache" "$BUILD_IMAGE" bash -c "test -f /cache/.initialized" 2>/dev/null; then
        rx_log "info" "Cache volume already populated"
        return 0
    fi

    rx_log "info" "Populating cache volume from image..."

    docker run --rm \
        -v "${CACHE_VOLUME}:/cache" \
        "$BUILD_IMAGE" bash -c "
            set -e
            mkdir -p /cache
            cp -r /var/cache/retrolinux/mirror/offline/* /cache/ 2>/dev/null || true
            touch /cache/.initialized
        "

    rx_log "success" "Cache volume populated"
}

_check_cache_versions() {
    rx_log "info" "Checking if package cache is up to date..."

    if ! docker image inspect "$BUILD_IMAGE" &>/dev/null; then
        rx_log "warn" "Image not found, cannot check versions"
        return 1
    fi

    local current_versions="/tmp/.current-versions.$$"
    local cached_versions="/tmp/.cached-versions.$$"

    docker run --rm -v "${CACHE_VOLUME}:/cache:ro" "$BUILD_IMAGE" bash -c "cat /var/cache/retrolinux/mirror/offline/.versions" > "$cached_versions" 2>/dev/null || true

    if [[ ! -f "$cached_versions" ]] || [[ ! -s "$cached_versions" ]]; then
        rx_log "info" "No cached versions found"
        rm -f "$current_versions" "$cached_versions"
        return 1
    fi

    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        name="${pkg%% *}"
        echo "$name"
    done < "$PROFILE_DIR/packages.x86_64" | sort > "$current_versions"

    local cached_pkgs
    cached_pkgs=$(sort -u "$cached_versions" | wc -l)
    local current_pkgs
    current_pkgs=$(sort -u "$current_versions" | wc -l)

    local diff_count
    diff_count=$(comm -13 <(sort -u "$cached_versions") <(sort -u "$current_versions") | wc -l)

    rm -f "$current_versions" "$cached_versions"

    if [[ "$diff_count" -gt 0 ]]; then
        rx_log "info" "Package list changed ($diff_count differences detected)"
        return 0
    fi

    rx_log "info" "Package cache is up to date"
    return 1
}

_remove_copy_step() {
    local airootfs_cache="$PROFILE_DIR/airootfs/var/cache/retrolinux/mirror/offline"

    if [[ -d "$airootfs_cache" ]]; then
        rm -rf "$airootfs_cache"/* 2>/dev/null || true
    fi
}

_docker_build() {
    local skip_prompt="$1"
    local force_build="${FORCE_BUILD:-false}"

    if [[ "$skip_prompt" == "force" ]]; then
        force_build="true"
    fi

    local _build_start_time=$SECONDS

    rx_log "info" "Starting docker build function..."

    export SKIP_PROMPT="$skip_prompt"

    if ! _should_skip_build || [[ "$force_build" == "true" ]]; then
        rx_log "info" "Continuing with build..."
    else
        rx_log "info" "Skipping build (no changes detected)"
        return 0
    fi

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

    if ! docker image inspect "$BUILD_IMAGE" &>/dev/null; then
        rx_log "warn" "Image $BUILD_IMAGE not found locally"
        rx_log "info" "Rebuilding image..."
        _build_docker_image || {
            rx_log "error" "Failed to build Docker image"
            return 1
        }
    fi

    rx_log "info" "Initializing cache volume..."
    _init_cache_volume

    if _check_cache_versions; then
        rx_log "info" "Package cache is outdated, rebuilding Docker image..."
        _build_docker_image || {
            rx_log "error" "Failed to rebuild Docker image"
            return 1
        }
        if [[ -n ${GH_TOKEN:-} ]]; then
            _push_docker_image || {
                rx_log "warn" "Failed to push updated image"
            }
        fi
        rx_log "info" "Reinitializing cache volume with new packages..."
        docker volume rm "$CACHE_VOLUME" 2>/dev/null || true
        _init_cache_volume
    fi

    rx_log "info" "Cleaning build directory..."
    _cleanup_build
    _remove_copy_step

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
        "$BUILD_IMAGE" bash -c "
            set -e

            rm -f /var/lib/pacman/db.lck 2>/dev/null || true

            KERNEL_PKG=\$(ls /var/cache/retrolinux/mirror/offline/linux-*.pkg.tar.zst 2>/dev/null | head -1)
            if [[ -n \$KERNEL_PKG ]]; then
                KERNEL_VER=\${KERNEL_PKG##*/linux-}
                KERNEL_VER=\${KERNEL_VER%.pkg.tar.zst}
                KERNEL_VER=\${KERNEL_VER%%-*}
            fi
            [[ -z \$KERNEL_VER ]] && KERNEL_VER=unknown

            mkarchiso -v -w /work/ -o /out /profile/

            echo \"\$KERNEL_VER\" > /out/kernel-version.txt

            chown -R $host_uid:$host_gid /out/
        "

    _save_build_checksum

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

    rx_log "info" "Removing output directory..."
    if [[ -d $OUTPUT_DIR ]]; then
        if rm -rf "$OUTPUT_DIR" 2>/dev/null; then
            rx_log "success" "Output directory removed"
        else
            rx_log "warn" "Failed to remove output directory..."
        fi
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
            -d | --docker)
                command="docker"
                shift
                ;;
            -f | --force)
                export FORCE_BUILD=true
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
        docker)
            _docker_check || exit 1
            _build_docker_image || exit 1
            _push_docker_image || exit 1
            ;;
        build)
            _docker_build "$skip_prompt"
            ;;
    esac
}

if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
    export -f _iso_main _docker_check _docker_build _build_docker_image _push_docker_image _pull_docker_image _init_and_update_cache _prepare_airootfs_offline _cleanup_build _generate_splashscreen _build_help _clean_all _check_deps _calculate_build_checksum _should_skip_build _save_build_checksum _init_cache_volume _check_cache_versions _remove_copy_step
else
    _iso_main "$@"
fi
