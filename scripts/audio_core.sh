#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "audio"

get_default_sink() {
    wpctl status 2>/dev/null | grep -A5 "Sinks:" | grep "\*" | grep -oE "[0-9]+\." | head -1 | tr -d '.'
}

get_default_source() {
    wpctl status 2>/dev/null | sed -n '/Audio/,/Video/p' | sed -n '/Sources:/,/Filters:/p' | grep -E "│  \*" | grep -oE "[0-9]+\." | head -1 | tr -d '.'
}

get_sink_volume() {
    local sink=$(get_default_sink)
    [[ -z $sink ]] && echo "0" && return
    wpctl get-volume "$sink" 2>/dev/null | awk '{print int($2 * 100)}'
}

get_sink_mute() {
    local sink=$(get_default_sink)
    [[ -z $sink ]] && echo "false" && return
    wpctl get-mute "$sink" 2>/dev/null | grep -qi "Mute: yes" && echo "true" || echo "false"
}

get_source_mute() {
    local source=$(get_default_source)
    [[ -z $source ]] && echo "false" && return
    pactl get-source-mute "$source" 2/ | grep -qi "yes" && echo "true" || echo "false"
}

get_sinks() {
    wpctl status 2>/dev/null | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/ && !match($(i-1),/\*/)) {gsub(/\./,"",$i); print $i}}'
}

get_sources() {
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Filters:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/ && !match($(i-1),/\*/)) {gsub(/\./,"",$i); print $i}}'
}

get_sink_name() {
    local sink="$1"
    [[ -z $sink ]] && return
    wpctl status 2>/dev/null | grep -A10 "Sinks:" | grep "${sink}\." | head -1 | sed 's/.*[0-9]\. //' | awk -F'[' '{print $1}' | xargs
}

get_source_name() {
    local source="$1"
    [[ -z $source ]] && return
    wpctl status 2>/dev/null | grep -A10 "Sources:" | grep "${source}\." | head -1 | sed 's/.*[0-9]\. //' | awk -F'[' '{print $1}' | xargs
}

get_pipewire_version() {
    local ver=$(pipewire --version 2>/dev/null | awk '{print $NF}' | tr -d ')')
    [[ -z $ver ]] && echo "N/A" || echo "$ver"
}

get_wireplumber_version() {
    local ver=$(wireplumber --version 2>/dev/null | awk '{print $NF}' | tr -d ')')
    [[ -z $ver ]] && echo "N/A" || echo "$ver"
}

get_easyeffects_status() {
    pgrep -x easyeffects >/dev/null 2>&1 && echo "Running" || echo "Stopped"
}

set_volume() {
    local volume="$1"
    local sink=$(get_default_sink)
    [[ -z $sink ]] && return 1
    wpctl set-volume "$sink" "${volume}%" 2>/dev/null
}

volume_up() {
    local step="${1:-5}"
    local current=$(get_sink_volume)
    local new=$((current + step))
    [[ $new -gt 100 ]] && new=100
    set_volume "$new"
    echo "$new"
}

volume_down() {
    local step="${1:-5}"
    local current=$(get_sink_volume)
    local new=$((current - step))
    [[ $new -lt 0 ]] && new=0
    set_volume "$new"
    echo "$new"
}

toggle_mute() {
    local sink=$(get_default_sink)
    [[ -z $sink ]] && return 1
    wpctl set-mute "$sink" toggle 2>/dev/null
    get_sink_mute
}

toggle_mic_mute() {
    local source=$(get_default_source)
    [[ -z $source ]] && return 1
    pactl set-source-mute "$source" toggle 2>/dev/null
    get_source_mute
}

set_sink() {
    local sink_id="$1"
    [[ -z $sink_id ]] && return 1
    wpctl set-default "$sink_id" 2>/dev/null
}

set_source() {
    local source_id="$1"
    [[ -z $source_id ]] && return 1
    wpctl set-default "$source_id" 2>/dev/null
}

list_eq_profiles() {
    local eq_dir="$HOME/.local/share/easyeffects/output"
    [[ ! -d $eq_dir ]] && echo "No EQ profiles found" && return
    find "$eq_dir" -name "*.json" -o -name "*.presets" 2>/dev/null | while read -r f; do
        basename "$f"
    done
}

get_current_eq_profile() {
    local eq_config="$HOME/.config/easyeffects/db/equalizerrc"
    if [[ -f "$eq_config" ]]; then
        local preset=$(grep "^preset=" "$eq_config" 2>/dev/null | cut -d'=' -f2-)
        if [[ -n "$preset" ]]; then
            echo "$preset"
            return
        fi
        
        local has_eq=$(grep "band.*Gain=" "$eq_config" 2>/dev/null | grep -v "=0$\|=-0$\|=[+-]0\." | head -1)
        if [[ -n "$has_eq" ]]; then
            echo "Custom"
            return
        fi
    fi
    echo "None"
}

apply_eq_profile() {
    local profile="$1"
    local eq_dir="$HOME/.local/share/easyeffects/output"
    local profile_path=""
    
    if [[ -f "$eq_dir/$profile" ]]; then
        profile_path="$eq_dir/$profile"
    elif [[ -f "$eq_dir/${profile}.json" ]]; then
        profile_path="$eq_dir/${profile}.json"
    else
        local matches=$(find "$eq_dir" -maxdepth 1 -name "*.json" 2>/dev/null | while read -r f; do
            local name=$(basename "$f" .json)
            if [[ "$name" == *"$profile"* || "$profile" == *"$name"* ]]; then
                echo "$f"
            fi
        done | head -1)
        
        if [[ -n "$matches" ]]; then
            profile_path="$matches"
        fi
    fi
    
    if [[ -f "$profile_path" ]]; then
        echo "$profile_path"
    else
        echo "Profile not found: $profile"
        return 1
    fi
}

get_remote_eq_repos() {
    echo "JackHack96|EasyEffects-Presets|Popular gaming EQ presets"
    echo "wwmm/easyeffects|Official GitHub repo"
    echo "Bundy01|EasyEffects-presets|Various audio profiles"
    echo "Digitalone1/EasyEffects-presets|DTS/Atmos alternatives"
    echo "ShadowOne333|EasyEffects-Configs|Gaming presets"
}

eq_list_remote_profiles() {
    local dest_dir="$HOME/.local/share/easyeffects/output"
    
    if [[ -d "$dest_dir" ]]; then
        find "$dest_dir" -name "*.json" -o -name "*.presets" 2>/dev/null | while read -r f; do
            local name=$(basename "$f")
            local size=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
            echo "$name|$size"
        done
    fi
}

download_eq_preset() {
    local repo="$1"
    local cache_dir="$RETRO_CONFIG/audio/eq"
    local dest_dir="$HOME/.local/share/easyeffects/output"
    mkdir -p "$cache_dir"
    mkdir -p "$dest_dir"
    
    case "$repo" in
        "JackHack96")
            local url="https://github.com/JackHack96/EasyEffects-Presets/archive/refs/heads/master.zip"
            local tmp="/tmp/easyeffects-presets.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-Presets-master"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "wwmm"|"wwmm/easyeffects")
            local url="https://github.com/wwmm/easyeffects/archive/refs/heads/main.zip"
            local tmp="/tmp/easyeffects.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/easyeffects-main"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "Bundy01")
            local url="https://github.com/Bundy01/EasyEffects-presets/archive/refs/heads/main.zip"
            local tmp="/tmp/bundy-presets.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-presets-main"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "Digitalone1")
            local url="https://github.com/Digitalone1/EasyEffects-presets/archive/refs/heads/main.zip"
            local tmp="/tmp/digitalone-presets.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-presets-main"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        *)
            return 1
            ;;
    esac
}

start_easyeffects() {
    pgrep -x easyeffects >/dev/null 2>&1 && echo "Already running" && return 0
    nohup easyeffects --gapplication-service >/dev/null 2>&1 &
    sleep 1
    pgrep -x easyeffects >/dev/null 2>&1 && echo "Started" || echo "Failed to start"
}

stop_easyeffects() {
    pgrep -x easyeffects >/dev/null 2>&1 || { echo "Not running"; return 0; }
    pkill -x easyeffects
    sleep 1
    pgrep -x easyeffects >/dev/null 2>&1 && echo "Failed to stop" || echo "Stopped"
}

get_pcore_threads() {
    local cpu_vendor=$(grep -m1 "vendor" /proc/cpuinfo | awk '{print $3}')
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | awk '{$1=""; $2=""; print $0}' | xargs)
    
    if [[ "$cpu_vendor" == *"Intel"* ]]; then
        local is_big_little=false
        
        if [[ "$cpu_model" == *"Ultra"* ]]; then
            is_big_little=true
        elif [[ "$cpu_model" =~ [0-9]{2}[0-9]H ]]; then
            local gen=$(echo "$cpu_model" | grep -oE "^[0-9]{2}" | head -1)
            if [[ $gen -ge 12 ]]; then
                is_big_little=true
            fi
        elif [[ "$cpu_model" =~ [0-9]+[0-9]00 ]]; then
            local gen_num=$(echo "$cpu_model" | grep -oE '[0-9]+[0-9]00' | head -1 | grep -oE '^[0-9]+')
            if [[ $gen_num -ge 12 ]]; then
                is_big_little=true
            fi
        fi
        
        if [[ "$is_big_little" == "true" ]]; then
            local p_cores=()
            for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
                local id=$(basename "$cpu" | sed 's/cpu//')
                
                if [[ -f "$cpu/online" ]] && [[ $(cat "$cpu/online") == "1" ]]; then
                    local freq=$(cat "$cpu/cpufreq/scaling_max_freq" 2>/dev/null)
                    if [[ -n "$freq" && $freq -gt 4000000 ]]; then
                        p_cores+=("$id")
                    fi
                fi
            done
            
            if [[ ${#p_cores[@]} -gt 0 ]]; then
                echo "$(IFS=,; echo "${p_cores[*]}")"
                return 0
            fi
        fi
        
        local cores=$(nproc 2>/dev/null || echo 4)
        local threads_per_core=$(lscpu 2>/dev/null | grep "Thread(s) per core" | awk '{print $4}')
        local pcore_cores=$((cores / threads_per_core))
        
        local pcore_threads=""
        for ((i=0; i<pcore_cores * threads_per_core; i++)); do
            [[ -n "$pcore_threads" ]] && pcore_threads+="," || pcore_threads+=""
            pcore_threads+="$i"
        done
        echo "$pcore_threads"
    elif [[ "$cpu_vendor" == *"AMD"* ]]; then
        local cores=$(nproc 2>/dev/null || echo 4)
        local threads_per_core=$(lscpu 2>/dev/null | grep "Thread(s) per core" | awk '{print $4}')
        local total_threads=$((cores / threads_per_core))
        
        local threads=""
        for ((i=0; i<total_threads; i++)); do
            [[ -n "$threads" ]] && threads+=","
            threads+="$i"
        done
        echo "$threads"
    else
        local cores=$(nproc 2>/dev/null || echo 4)
        local threads=""
        for ((i=0; i<cores; i++)); do
            [[ -n "$threads" ]] && threads+=","
            threads+="$i"
        done
        echo "$threads"
    fi
}

fix_stutter() {
    local services=("pipewire" "wireplumber" "easyeffects")
    local cpu_vendor=$(grep -m1 "vendor" /proc/cpuinfo | awk '{print $3}')
    
    local affinity=$(get_pcore_threads)
    
    if [[ -z "$affinity" ]]; then
        local cores=$(nproc 2>/dev/null || echo 4)
        affinity="0-$((cores - 1))"
    fi
    
    local method="P-cores"
    [[ "$cpu_vendor" == *"AMD"* ]] && method="all cores"
    [[ "$cpu_vendor" != *"Intel"* && "$cpu_vendor" != *"AMD"* ]] && method="all cores"
    
    for svc in "${services[@]}"; do
        local unit="${svc}.service"
        local override_dir="$HOME/.config/systemd/user/${unit}.d"
        mkdir -p "$override_dir"
        cat > "$override_dir/override.conf" <<EOF
[Service]
CPUAffinity=$affinity
EOF
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user restart "$unit" 2>/dev/null
    done
    echo "$affinity"
}

case "$1" in
    "--status")
        echo "pipewire:$(get_pipewire_version)"
        echo "wireplumber:$(get_wireplumber_version)"
        echo "sink:$(get_default_sink)"
        echo "sink_volume:$(get_sink_volume)"
        echo "sink_mute:$(get_sink_mute)"
        echo "source:$(get_default_source)"
        echo "source_mute:$(get_source_mute)"
        echo "easyeffects:$(get_easyeffects_status)"
        ;;
    "--set-volume") set_volume "$2" ;;
    "--volume-up") volume_up "$2" ;;
    "--volume-down") volume_down "$2" ;;
    "--toggle-mute") toggle_mute ;;
    "--toggle-mic-mute") toggle_mic_mute ;;
    "--get-sinks") get_sinks ;;
    "--get-sources") get_sources ;;
    "--get-sink-name") get_sink_name "$2" ;;
    "--get-source-name") get_source_name "$2" ;;
    "--set-sink") set_sink "$2" ;;
    "--set-source") set_source "$2" ;;
    "--eq-list") list_eq_profiles ;;
    "--eq-current") get_current_eq_profile ;;
    "--eq-apply") apply_eq_profile "$2" ;;
    "--eq-download") download_eq_preset "$2" ;;
    "--eq-list-remote") get_remote_eq_repos ;;
    "--eq-list-remote-profiles") eq_list_remote_profiles ;;
    "--ee-start") start_easyeffects ;;
    "--ee-stop") stop_easyeffects ;;
    "--fix-stutter") fix_stutter ;;
esac