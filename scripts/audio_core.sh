#!/bin/bash

get_default_sink() {
    wpctl status 2>/dev/null | grep -A5 "Sinks:" | grep "\*" | grep -oE "[0-9]+\." | head -1 | tr -d '.'
}

get_default_source() {
    wpctl status 2>/dev/null | grep -A5 "Sources:" | grep "\*" | grep -oE "[0-9]+\." | head -1 | tr -d '.'
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
    wpctl get-mute "$source" 2>/dev/null | grep -qi "Mute: yes" && echo "true" || echo "false"
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
    pipewire --version 2>/dev/null | awk '{print $NF}' | tr -d ')'
}

get_wireplumber_version() {
    wireplumber --version 2>/dev/null | awk '{print $NF}' | tr -d ')'
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
    wpctl set-mute "$source" toggle 2>/dev/null
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

apply_eq_profile() {
    local profile="$1"
    local eq_dir="$HOME/.local/share/easyeffects/output"
    local profile_path="$eq_dir/$profile"
    [[ ! -f "$profile_path" ]] && profile_path="$eq_dir/${profile}.json"
    [[ ! -f "$profile_path" ]] && echo "Profile not found: $profile" && return 1
    echo "$profile_path"
}

get_remote_eq_repos() {
    echo "JackHack96|EasyEffects-Presets|Popular gaming EQ presets"
    echo "wwmm/easyeffects|Official GitHub repo"
    echo "Bundy01|EasyEffects-presets|Various audio profiles"
    echo "Digitalone1/EasyEffects-presets|DTS/Atmos alternatives"
    echo "ShadowOne333|EasyEffects-Configs|Gaming presets"
}

download_eq_preset() {
    local repo="$1"
    local cache_dir="$RETRO_CACHE/audio/eq"
    local dest_dir="$HOME/.local/share/easyeffects/output"
    mkdir -p "$cache_dir"
    mkdir -p "$dest_dir"
    
    case "$repo" in
        "JackHack96")
            local url="https://github.com/JackHack96/EasyEffects-Presets/archive/refs/heads/master.zip"
            local tmp="/tmp/easyeffects-presets.zip"
            echo "Downloading JackHack96 presets..."
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-Presets-master"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "wwmm"|"wwmm/easyeffects")
            local url="https://github.com/wwmm/easyeffects/archive/refs/heads/main.zip"
            local tmp="/tmp/easyeffects.zip"
            echo "Downloading official EasyEffects presets..."
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/easyeffects-main"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "Bundy01")
            local url="https://github.com/Bundy01/EasyEffects-presets/archive/refs/heads/main.zip"
            local tmp="/tmp/bundy-presets.zip"
            echo "Downloading Bundy01 presets..."
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-presets-main"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "Digitalone1")
            local url="https://github.com/Digitalone1/EasyEffects-presets/archive/refs/heads/main.zip"
            local tmp="/tmp/digitalone-presets.zip"
            echo "Downloading Digitalone1 presets..."
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-presets-main"
            [[ -d "$preset_dir" ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        *)
            echo "Unknown repo: $repo"
            return 1
            ;;
    esac
    echo "Presets installed to $dest_dir"
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

fix_stutter() {
    local services=("pipewire" "wireplumber" "easyeffects")
    local pcore_count=$(nproc 2>/dev/null || echo 4)
    local affinity=""
    [[ $pcore_count -gt 8 ]] && affinity="0-7" || [[ $pcore_count -gt 4 ]] && affinity="0-3" || affinity="0-$((pcore_count - 1))"
    
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
    "--eq-apply") apply_eq_profile "$2" ;;
    "--eq-download") download_eq_preset "$2" ;;
    "--eq-list-remote") get_remote_eq_repos ;;
    "--ee-start") start_easyeffects ;;
    "--ee-stop") stop_easyeffects ;;
    "--fix-stutter") fix_stutter ;;
esac