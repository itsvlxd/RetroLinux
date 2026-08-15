#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

RETRO_REPO_URL="https://github.com/itsvlxd/RetroLinux.git"
RETRO_BRANCH="${RETRO_BRANCH:-develop}"

rx_post_clone_repo() {
    rx_clear_logo
    rx_step "Deploying RetroLinux Framework..."

    local source_dir="/opt/retrolinux"
    local target_dir="/mnt/opt/retrolinux"

    if [[ -d "$target_dir/.git" ]]; then
        gum style --foreground 2 "RetroLinux repo already present on target"
        return 0
    fi

    mkdir -p "$target_dir"

    local iso_valid=false
    if [[ -d $source_dir ]]; then
        local item_count=$(ls -A "$source_dir" 2>/dev/null | wc -l)

        if [[ $item_count -ge 16 ]] && [[ -d "$source_dir/.git" ]]; then
            iso_valid=true
            gum style --foreground 7 "Found complete repo on ISO ($item_count items). Copying..."

            cp -rf "$source_dir/." "$target_dir/"
            find "$target_dir" -type f -name "*.sh" -exec chmod 755 {} \;

            gum style --foreground 2 "RetroLinux successfully deployed from ISO"
            return 0
        fi
    fi

    if [[ $iso_valid == "false" ]]; then
        gum style --foreground 5 "Downloading RetroLinux from github..."

        if ! ping -c 1 1.1.1.1 &>/dev/null; then
            gum style --foreground 1 "ERROR: No internet connection. Cannot clone repository."
            return 1
        fi

        local branch_args=()
        if timeout 30 git ls-remote --exit-code --heads "$RETRO_REPO_URL" "refs/heads/$RETRO_BRANCH" >/dev/null 2>&1; then
            branch_args=(--branch "$RETRO_BRANCH")
        else
            gum style --foreground 3 "Branch ${RETRO_BRANCH} not found, cloning default branch..."
        fi

        local clone_ok=false
        if [[ "$RETRO_BRANCH" == "develop" ]]; then
            if timeout 600 git clone --single-branch --depth 1 "${branch_args[@]}" "$RETRO_REPO_URL" "$target_dir"; then
                clone_ok=true
            fi
        else
            if timeout 600 git clone --single-branch "${branch_args[@]}" "$RETRO_REPO_URL" "$target_dir"; then
                clone_ok=true
            fi
        fi

        if [[ $clone_ok == true ]]; then
            find "$target_dir" -type f -name "*.sh" -exec chmod 755 {} \;
            local actual_branch
            actual_branch=$(git -C "$target_dir" branch --show-current 2>/dev/null)
            rx_select_retro_version "$target_dir" "${actual_branch:-$RETRO_BRANCH}"
            gum style --foreground 2 "Successfully cloned from GitHub (${actual_branch:-${RETRO_BRANCH:-default}})"
            return 0
        fi

        gum style --foreground 1 "ERROR: Failed to clone repository."
        return 1
    fi
}

rx_select_retro_version() {
    local target_dir="$1"
    local branch="${2:-develop}"

    if [[ "$branch" == "develop" ]]; then
        return 0
    fi

    local versions
    versions=$(git -C "$target_dir" tag -l 2>/dev/null \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sed 's/^v//' \
        | awk -F. '
            /^[0-9]+\.[0-9]+\.[0-9]+$/ {
                key = $1 "." $2
                if (!(key in max) || $3 > max[key]) { max[key] = $3; ver[key] = "v" $0 }
            }
            END { for (k in ver) print ver[k] }
        ' \
        | sort -Vr)

    if [[ -z $versions ]]; then
        gum style --foreground 3 "No release versions found, staying on ${branch}"
        return 0
    fi

    local -a options=()
    local v
    while IFS= read -r v; do
        [[ -n $v ]] && options+=("$v")
    done <<< "$versions"

    local choice=""
    if [[ -t 0 ]]; then
        rx_clear_logo
        choice=$(gum choose --header "Select RetroLinux version (${branch})" "${options[@]}")
    fi

    if [[ -z $choice ]]; then
        gum style --foreground 3 "No version selected, staying on ${branch}"
        return 0
    fi

    if git -C "$target_dir" checkout "$choice" 2>/dev/null; then
        gum style --foreground 2 "Checked out ${choice}"
    else
        gum style --foreground 1 "Failed to checkout ${choice}, staying on ${branch}"
    fi
}

rx_install_retro_bootstrap() {
    rx_clear_logo
    rx_step "Bootstrapping first-boot setup..."

    if [[ ! -f /mnt/opt/retrolinux/retro.sh ]]; then
        gum style --foreground 3 "RetroLinux framework not present, skipping first-boot bootstrap"
        return 0
    fi

    local username=$(timeout 30 arch-chroot /mnt getent passwd 1000 2>/dev/null | cut -d: -f1)
    local home_dir=""
    [[ -n $username ]] && home_dir=$(timeout 30 arch-chroot /mnt getent passwd "$username" 2>/dev/null | cut -d: -f6)

    if [[ -n $username && -n $home_dir ]]; then
        gum style --foreground 7 "Creating first-boot autostart script..."
        timeout 60 arch-chroot /mnt bash -c "
            mkdir -p '$home_dir/.config/hypr'
            autostart_file='$home_dir/.config/hypr/autostart.sh'
            cat > \$autostart_file <<'EOF'
#!/bin/bash
# RetroLinux first-boot autostart (written during install)
[[ -f \"\$HOME/.retro_install\" ]] || exit 0
exec /opt/retrolinux/retro.sh --load
EOF
            chmod +x \$autostart_file
            lua_file='$home_dir/.config/hypr/hyprland.lua'
            cat > \$lua_file <<'EOF'
local autostart = os.getenv('HOME') .. '/.config/hypr/autostart.sh'

hl.on('hyprland.start', function()
	if io.open(autostart, 'r') then
		hl.exec_cmd(autostart)
	end
end)
EOF
            chown -R $username: '$home_dir/.config' 2>/dev/null || true
        " 2>/dev/null || true
    else
        gum style --foreground 3 "Could not determine user home, skipping autostart hook"
    fi

    gum style --foreground 2 "First-boot bootstrap complete"
    gum style --foreground 7 "All remaining modules are installed by 'retro --setup' on first boot."
    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_clone_repo "$@"
    rx_install_retro_bootstrap
fi
