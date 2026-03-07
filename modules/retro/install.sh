#!/bin/bash

RETRO_CACHE="$HOME/.cache/retro"
source_bin="$RETRO_DIR/retro.sh"
bin_dir="/usr/local/bin"
cmd_name="retro"
target="$bin_dir/$cmd_name"
tmp_file="/etc/tmpfiles.d/retro-power.conf"

setup_power_permissions() {
    read -r -d '' expected_content <<EOF
# Retro Power Management Permissions
f /sys/devices/system/cpu/intel_pstate/no_turbo                          0666 root root -   -
f /sys/devices/system/cpu/intel_pstate/max_perf_pct                      0666 root root -   -
z /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference 0666 root root -   -
z /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 0666 root root -   -
f /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw        0666 root root -   -
f /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw        0666 root root -   -
f /sys/class/powercap/intel-rapl:0/constraint_0_time_window_us        0666 root root -   -
f /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw        0666 root root -   -
EOF

    if [[ -f $tmp_file ]]; then
        echo "$expected_content" >/tmp/retro_pwr_check
        if diff -q /tmp/retro_pwr_check "$tmp_file" >/dev/null 2>&1; then
            rm /tmp/retro_pwr_check
            return 0
        fi
        rm /tmp/retro_pwr_check
    fi

    rx_log "info" "Syncing CPU power permissions..."
    sudo bash -c "echo \"$expected_content\" > $tmp_file"
    sudo systemd-tmpfiles --create "$tmp_file" 2>/dev/null
    rx_log "success" "Power permissions synchronized."
}

setup_power_permissions

if [[ ! -L $target ]] || [[ "$(readlink -f "$target")" != "$source_bin" ]]; then
    rx_log "info" "Installing ${PINK}${cmd_name}${RESET} to ${bin_dir}..."
    [[ ! -d $bin_dir ]] && sudo mkdir -p "$bin_dir"
    sudo ln -sf "$source_bin" "$target"
    sudo chmod +x "$target"
    rx_log "success" "The ${PINK}${cmd_name}${RESET} command is now global."
fi

patch_env() {
    local file="$1"
    local var_name="$2"
    local var_val="$3"

    if [[ -f $file ]]; then
        if ! grep -q "export $var_name=" "$file"; then
            echo "export $var_name=\"$var_val\"" >>"$file"
            rx_log "success" "Added $var_name to $(basename "$file")"
        fi
    fi
}

patch_env "$HOME/.profile" "RETRO_DIR" "$RETRO_DIR"
patch_env "$HOME/.profile" "RETRO_CACHE" "$RETRO_CACHE"

shell_conf=""
[[ -f "$HOME/.zshrc" ]] && shell_conf="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" ]] && [[ -z $shell_conf ]] && shell_conf="$HOME/.bashrc"

if [[ -n $shell_conf ]]; then
    if ! grep -q "$bin_dir" "$shell_conf"; then
        echo -e "\n# Retro PATH\nexport PATH=\"$bin_dir:\$PATH\"" >>"$shell_conf"
    fi

    patch_env "$shell_conf" "RETRO_DIR" "$RETRO_DIR"
    patch_env "$shell_conf" "RETRO_CACHE" "$RETRO_CACHE"
fi

[[ ! -d $RETRO_CACHE ]] && mkdir -p "$RETRO_CACHE"
