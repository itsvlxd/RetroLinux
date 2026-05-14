#!/bin/bash

get_hw() {
    case "$1" in
        "cpu")
            local name=$(grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//' | sed 's/ \+/ /g')
            local ucode=$(grep -m 1 'microcode' /proc/cpuinfo | awk '{print $3}' || echo "N/A")
            local arch=$(uname -m)
            local threads=$(nproc)
            echo "${name}|${ucode}|${arch}|${threads}"
            ;;
        "gpu")
            local raw=$(lspci -mm | grep -iE "vga|3d|display" | head -n 1)
            local pci_id=$(echo "$raw" | awk '{print $1}')
            local vendor=$(echo "$raw" | awk -F'"' '{print $4}')
            local name=$(echo "$raw" | awk -F'"' '{print $6}')
            local driver=$(lspci -ks "$pci_id" | grep "Kernel driver" | awk '{print $5}')

            [[ -z $driver ]] && driver="Built-in"
            [[ -z $name ]] && name="Unknown GPU"
            echo "${vendor} ${name}|${driver}"
            ;;
        "ram")
            local kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            local gb=$(awk "BEGIN {printf \"%.0f\", $kb/1024/1024}")
            local standard_ram=2
            for r in 4 8 12 16 24 32 48 64 96 128; do
                if ((gb <= r + 2 && gb >= r - 2)); then
                    standard_ram=$r
                    break
                fi
            done
            echo "${standard_ram}GB"
            ;;
        "disk")
            local root_src=$(findmnt -nlo SOURCE / | head -n 1 | sed 's/\[.*\]//')

            local base_dev=$(lsblk -s -nlo NAME "$root_src" 2>/dev/null | awk 'NF' | tail -n 1)
            local dev_types=$(lsblk -s -nlo TYPE "$root_src" 2>/dev/null)

            local model=$(lsblk -d -nlo MODEL "/dev/$base_dev" 2>/dev/null | xargs)
            local tran=$(lsblk -d -nlo TRAN "/dev/$base_dev" 2>/dev/null | xargs)
            local is_rot=$(cat /sys/block/$base_dev/queue/rotational 2>/dev/null || echo "0")

            [[ -z $model ]] && model="Generic Storage"

            local type="HDD"
            if [[ $is_rot == "0" ]]; then
                [[ ${tran,,} == "nvme" || $base_dev == nvme* ]] && type="NVMe SSD" || type="SATA SSD"
            fi

            local tags=""
            [[ $dev_types == *"crypt"* ]] && tags+="LUKS "
            [[ $dev_types == *"lvm"* ]] && tags+="LVM "

            if [[ -n $tags ]]; then
                type="$type ${tags% }"
            fi

            echo "${model}|${type}"
            ;;
        "net")
            local wifi=$(iwgetid -r 2>/dev/null)
            if [[ -n $wifi ]]; then
                echo "Wi-Fi ($wifi)"
            else
                local eth=$(ip -br l | awk '$1 !~ "lo|vir|wl" && $2=="UP" {print $1}' | head -n 1)
                [[ -n $eth ]] && echo "Ethernet ($eth)" || echo "Offline"
            fi
            ;;
    esac
}

run_cpu() {
    local out=$(sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) --time=10 run)
    local score=$(echo "$out" | awk '/events per second:/ {print $4}')
    local min=$(echo "$out" | awk '/min:/ {print $2}')
    local avg=$(echo "$out" | awk '/avg:/ {print $2}')
    local max=$(echo "$out" | awk '/max:/ {print $2}')
    echo "${score}|${min}|${avg}|${max}"
}

run_ram() {
    local out=$(sysbench memory --memory-block-size=1M --memory-total-size=10G --threads=$(nproc) run)
    local score=$(echo "$out" | awk '/transferred/ {print $4}' | tr -d '()')
    local min=$(echo "$out" | awk '/min:/ {print $2}')
    local avg=$(echo "$out" | awk '/avg:/ {print $2}')
    local max=$(echo "$out" | awk '/max:/ {print $2}')
    echo "${score}|${min}|${avg}|${max}"
}

run_disk() {
    local test_file="$RETRO_CONFIG/bench_test.img"
    mkdir -p "$HOME/.config/retro"

    dd if=/dev/zero of="$test_file" bs=100M count=10 oflag=direct status=progress 2>&1 | tail -n 1 | awk '{print $(NF-1), $NF}' >/tmp/retro_write
    sudo sysctl -w vm.drop_caches=3 >/dev/null 2>&1
    dd if="$test_file" of=/dev/null bs=100M count=10 iflag=direct status=progress 2>&1 | tail -n 1 | awk '{print $(NF-1), $NF}' >/tmp/retro_read

    rm -f "$test_file"
    echo "$(cat /tmp/retro_write)|$(cat /tmp/retro_read)"
}

run_gpu() {
    if command -v vkmark >/dev/null; then
        vkmark | awk '/vkmark Score/ {print $3}'
    else
        echo "Missing_VKMark"
    fi
}

run_internet() {
    if command -v speedtest-cli >/dev/null; then
        local st=$(speedtest-cli --simple)
        local ping=$(echo "$st" | grep "Ping" | awk '{print $2, $3}')
        local down=$(echo "$st" | grep "Download" | awk '{print $2, $3}')
        local up=$(echo "$st" | grep "Upload" | awk '{print $2, $3}')
        echo "${ping}|${down}|${up}"
    else
        echo "Missing_Speedtest"
    fi
}

hud_set_preset() {
    local preset="$1"
    [[ -z $preset ]] && return 1

    local config_dir="$HOME/.config/MangoHud"
    local valid_presets=("minimal" "full" "advanced" "gaming" "performance")

    local valid=false
    for p in "${valid_presets[@]}"; do
        [[ $preset == "$p" ]] && valid=true && break
    done

    if [[ $valid == "false" ]]; then
        return 1
    fi

    if [[ -f "$config_dir/${preset}.conf" ]]; then
        local vars_file="$RETRO_CONFIG/variables.sh"
        mkdir -p "$RETRO_CONFIG"
        if grep -q "^export MANGOHUD_PROFILE=" "$vars_file" 2>/dev/null; then
            sed -i "s@^export MANGOHUD_PROFILE=.*@export MANGOHUD_PROFILE=\"$preset\"@" "$vars_file"
        else
            echo "export MANGOHUD_PROFILE=\"$preset\"" >>"$vars_file"
        fi

        if [[ "$config_dir/${preset}.conf" -ef "$config_dir/MangoHud.conf" ]]; then
            sed -i '/^toggle_hud=/d' "$config_dir/MangoHud.conf"
            echo "toggle_hud=F11" >>"$config_dir/MangoHud.conf"
        else
            cp "$config_dir/${preset}.conf" "$config_dir/MangoHud.conf"
            sed -i '/^toggle_hud=/d' "$config_dir/MangoHud.conf"
            echo "toggle_hud=F11" >>"$config_dir/MangoHud.conf"
        fi

        return 0
    else
        return 1
    fi
}

case "$1" in
    "--hw-cpu") get_hw "cpu" ;;
    "--hw-gpu") get_hw "gpu" ;;
    "--hw-ram") get_hw "ram" ;;
    "--hw-disk") get_hw "disk" ;;
    "--hw-net") get_hw "net" ;;
    "--cpu") run_cpu ;;
    "--ram") run_ram ;;
    "--disk") run_disk ;;
    "--gpu") run_gpu ;;
    "--internet") run_internet ;;
    "--hud-set") hud_set_preset "$2" ;;
esac
