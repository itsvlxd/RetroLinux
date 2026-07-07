#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/variable.sh"

get_default_sink() {
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/ && match($(i-1),/\*/)) {gsub(/\./,"",$i); print $i; exit}}'
}

get_default_source() {
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/ && match($(i-1),/\*/)) {gsub(/\./,"",$i); print $i; exit}}'
}

get_sink_volume() {
    local sink=$(get_default_sink)
    [[ -z $sink ]] && echo "0" && return
    wpctl get-volume "$sink" 2>/dev/null | awk '{print int($2 * 100)}'
}

get_sink_mute() {
    local sink=$(get_default_sink)
    [[ -z $sink ]] && echo "false" && return
    wpctl get-volume "$sink" 2>/dev/null | grep -qi "\[MUTED\]" && echo "true" || echo "false"
}

get_source_mute() {
    local source=$(get_default_source)
    [[ -z $source ]] && echo "false" && return
    wpctl get-volume "$source" 2>/dev/null | grep -qi "\[MUTED\]" && echo "true" || echo "false"
}

get_source_volume() {
    local source=$(get_default_source)
    [[ -z $source ]] && echo "0" && return
    wpctl get-volume "$source" 2>/dev/null | awk '{print int($2 * 100)}'
}

set_source_volume() {
    local volume="$1"
    local source=$(get_default_source)
    [[ -z $source ]] && return 1
    local source_name=$(get_source_name "$source")
    wpctl set-volume "$source" "${volume}%" 2>/dev/null
}

get_sinks() {
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/) {gsub(/\./,"",$i); print $i}}' | while read -r id; do
        local name=$(wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/' | grep "${id}\." | head -1 | sed 's/.*[0-9]\. //' | awk -F'[' '{print $1}' | xargs)
        if [[ $name != *"Easy Effects"* ]]; then
            echo "$id"
        fi
    done
}

get_sources() {
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/) {gsub(/\./,"",$i); print $i}}' | while read -r id; do
        local name=$(wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/' | grep "${id}\." | head -1 | sed 's/.*[0-9]\. //' | awk -F'[' '{print $1}' | xargs)
        if [[ $name != *"Easy Effects"* ]]; then
            echo "$id"
        fi
    done
}

get_sink_name() {
    local sink="$1"
    [[ -z $sink ]] && return
    local name=$(wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/' | grep "${sink}\." | head -1 | sed 's/.*[0-9]\. //' | awk -F'[' '{print $1}' | xargs)
    if [[ $name == bluez_* ]]; then
        local desc=$(wpctl inspect "$sink" 2>/dev/null | grep "node.description" | head -1 | sed 's/.*= *//' | tr -d '"')
        [[ -n $desc ]] && name="$desc"
    fi
    echo "$name"
}

get_source_name() {
    local source="$1"
    [[ -z $source ]] && return
    local name=$(wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/' | grep "${source}\." | head -1 | sed 's/.*[0-9]\. //' | awk -F'[' '{print $1}' | xargs)
    if [[ $name == bluez_* ]]; then
        local desc=$(wpctl inspect "$source" 2>/dev/null | grep "node.description" | head -1 | sed 's/.*= *//' | tr -d '"')
        [[ -n $desc ]] && name="$desc"
    fi
    echo "$name"
}

get_sink_persistent_name() {
    local sink_id="$1"
    [[ -z $sink_id ]] && return
    wpctl inspect "$sink_id" 2>/dev/null | grep "node.name" | head -1 | awk '{print $NF}' | tr -d '"'
}

get_source_persistent_name() {
    local source_id="$1"
    [[ -z $source_id ]] && return
    wpctl inspect "$source_id" 2>/dev/null | grep "node.name" | head -1 | awk '{print $NF}' | tr -d '"'
}

get_sink_id_by_persistent() {
    local name="$1"
    [[ -z $name ]] && return
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/) {gsub(/\./,"",$i); print $i}}' | while read -r dev_id; do
        local pw_name=$(wpctl inspect "$dev_id" 2>/dev/null | grep "node.name" | head -1 | awk '{print $NF}' | tr -d '"')
        if [[ $pw_name == "$name" ]]; then
            echo "$dev_id"
            break
        fi
    done
}

get_source_id_by_persistent() {
    local name="$1"
    [[ -z $name ]] && return
    wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.$/) {gsub(/\./,"",$i); print $i}}' | while read -r dev_id; do
        local pw_name=$(wpctl inspect "$dev_id" 2>/dev/null | grep "node.name" | head -1 | awk '{print $NF}' | tr -d '"')
        if [[ $pw_name == "$name" ]]; then
            echo "$dev_id"
            break
        fi
    done
}

get_pipewire_version() {
    local ver=$(pipewire --version 2>/dev/null | grep "Linked with" | awk '{print $NF}' | tr -d ')')
    [[ -z $ver ]] && echo "N/A" || echo "$ver"
}

get_wireplumber_version() {
    local ver=$(wireplumber --version 2>/dev/null | grep "Linked with" | awk '{print $NF}' | tr -d ')')
    [[ -z $ver ]] && echo "N/A" || echo "$ver"
}

get_easyeffects_status() {
    pgrep -x easyeffects >/dev/null 2>&1 && echo "Running" || echo "Stopped"
}

set_volume() {
    local volume="$1"
    local sink=$(get_default_sink)
    [[ -z $sink ]] && return 1
    local sink_name=$(get_sink_name "$sink")
    wpctl set-volume "$sink" "${volume}%" 2>/dev/null
}

volume_up() {
    local step="${1:-5}"
    local current=$(get_sink_volume)
    local new=$((current + step))
    [[ $new -gt 100 ]] && new=100
    local sink=$(get_default_sink)
    local sink_name=$(get_sink_name "$sink")
    set_volume "$new"
    echo "$new"
}

volume_down() {
    local step="${1:-5}"
    local current=$(get_sink_volume)
    local new=$((current - step))
    [[ $new -lt 0 ]] && new=0
    local sink=$(get_default_sink)
    local sink_name=$(get_sink_name "$sink")
    set_volume "$new"
    echo "$new"
}

toggle_mute() {
    local sink=$(get_default_sink)
    [[ -z $sink ]] && return 1
    local sink_name=$(get_sink_name "$sink")
    local old_mute=$(get_sink_mute)
    wpctl set-mute "$sink" toggle 2>/dev/null
    local new_mute=$(get_sink_mute)
    get_sink_mute
}

set_mute() {
    local action="$1"
    local sink=$(get_default_sink)
    [[ -z $sink ]] && return 1
    if [[ $action == "on" || $action == "true" ]]; then
        wpctl set-mute "$sink" 1 2>/dev/null
    else
        wpctl set-mute "$sink" 0 2>/dev/null
    fi
}

toggle_mic_mute() {
    local source=$(get_default_source)
    [[ -z $source ]] && return 1
    local source_name=$(get_source_name "$source")
    local old_mute=$(get_source_mute)
    wpctl set-mute "$source" toggle 2>/dev/null
    local new_mute=$(get_source_mute)
    get_source_mute
}

set_mic_mute() {
    local action="$1"
    local source=$(get_default_source)
    [[ -z $source ]] && return 1
    if [[ $action == "on" || $action == "true" ]]; then
        wpctl set-mute "$source" 1 2>/dev/null
    else
        wpctl set-mute "$source" 0 2>/dev/null
    fi
}

set_sink() {
    local sink_id="$1"
    [[ -z $sink_id ]] && return 1
    local sink_name=$(get_sink_name "$sink_id")
    wpctl set-default "$sink_id" 2>/dev/null
}

set_source() {
    local source_id="$1"
    [[ -z $source_id ]] && return 1
    local source_name=$(get_source_name "$source_id")
    wpctl set-default "$source_id" 2>/dev/null
}

set_audio_priority() {
    local type="$1"
    local primary_input="$2"
    local fallback_input="$3"

    [[ -z $type || -z $primary_input ]] && echo "ERR_MISSING_ARGS" && return 1

    local primary_name=""
    local fallback_name=""

    if [[ $type == "sink" ]]; then
        if [[ $primary_input =~ ^[0-9]+$ ]]; then
            primary_name=$(get_sink_persistent_name "$primary_input")
        else
            if get_sink_id_by_persistent "$primary_input" | grep -q .; then
                primary_name="$primary_input"
            fi
        fi
        if [[ -n $fallback_input ]]; then
            if [[ $fallback_input =~ ^[0-9]+$ ]]; then
                fallback_name=$(get_sink_persistent_name "$fallback_input")
            else
                if get_sink_id_by_persistent "$fallback_input" | grep -q .; then
                    fallback_name="$fallback_input"
                fi
            fi
        fi
        if [[ -z $primary_name ]]; then
            echo "ERR_PRIMARY_NOT_FOUND"
            return 1
        fi
        local old_primary=$(get_var "AUDIO_PRIMARY_SINK" "")
        local old_fallback=$(get_var "AUDIO_FALLBACK_SINK" "")
        set_var "AUDIO_PRIMARY_SINK" "$primary_name"
        set_var "AUDIO_FALLBACK_SINK" "${fallback_name:-}"
        local primary_id=$(get_sink_id_by_persistent "$primary_name")
        if [[ -n $primary_id ]]; then
            wpctl set-default "$primary_id" 2>/dev/null
        fi
        echo "OK|primary=$primary_name|fallback=${fallback_name:-none}"
    elif [[ $type == "source" ]]; then
        if [[ $primary_input =~ ^[0-9]+$ ]]; then
            primary_name=$(get_source_persistent_name "$primary_input")
        else
            if get_source_id_by_persistent "$primary_input" | grep -q .; then
                primary_name="$primary_input"
            fi
        fi
        if [[ -n $fallback_input ]]; then
            if [[ $fallback_input =~ ^[0-9]+$ ]]; then
                fallback_name=$(get_source_persistent_name "$fallback_input")
            else
                if get_source_id_by_persistent "$fallback_input" | grep -q .; then
                    fallback_name="$fallback_input"
                fi
            fi
        fi
        if [[ -z $primary_name ]]; then
            echo "ERR_PRIMARY_NOT_FOUND"
            return 1
        fi
        local old_primary=$(get_var "AUDIO_PRIMARY_SOURCE" "")
        local old_fallback=$(get_var "AUDIO_FALLBACK_SOURCE" "")
        set_var "AUDIO_PRIMARY_SOURCE" "$primary_name"
        set_var "AUDIO_FALLBACK_SOURCE" "${fallback_name:-}"
        local primary_id=$(get_source_id_by_persistent "$primary_name")
        if [[ -n $primary_id ]]; then
            wpctl set-default "$primary_id" 2>/dev/null
        fi
        echo "OK|primary=$primary_name|fallback=${fallback_name:-none}"
    else
        echo "ERR_INVALID_TYPE"
        return 1
    fi
}

get_audio_priority() {
    local type="$1"
    [[ -z $type ]] && echo "ERR_MISSING_ARGS" && return 1

    if [[ $type == "sink" ]]; then
        local primary=$(get_var "AUDIO_PRIMARY_SINK" "")
        local fallback=$(get_var "AUDIO_FALLBACK_SINK" "")
        echo "primary=$primary|fallback=${fallback:-none}"
    elif [[ $type == "source" ]]; then
        local primary=$(get_var "AUDIO_PRIMARY_SOURCE" "")
        local fallback=$(get_var "AUDIO_FALLBACK_SOURCE" "")
        echo "primary=$primary|fallback=${fallback:-none}"
    else
        echo "ERR_INVALID_TYPE"
        return 1
    fi
}

clear_audio_priority() {
    local type="$1"
    [[ -z $type ]] && echo "ERR_MISSING_ARGS" && return 1

    if [[ $type == "sink" ]]; then
        local old_primary=$(get_var "AUDIO_PRIMARY_SINK" "")
        local old_fallback=$(get_var "AUDIO_FALLBACK_SINK" "")
        set_var "AUDIO_PRIMARY_SINK" ""
        set_var "AUDIO_FALLBACK_SINK" ""
    elif [[ $type == "source" ]]; then
        local old_primary=$(get_var "AUDIO_PRIMARY_SOURCE" "")
        local old_fallback=$(get_var "AUDIO_FALLBACK_SOURCE" "")
        set_var "AUDIO_PRIMARY_SOURCE" ""
        set_var "AUDIO_FALLBACK_SOURCE" ""
    else
        echo "ERR_INVALID_TYPE"
        return 1
    fi
    echo "OK"
}

device_exists_by_persistent() {
    local type="$1"
    local name="$2"
    [[ -z $type || -z $name ]] && return 1

    local current_id=""
    if [[ $type == "sink" ]]; then
        current_id=$(get_sink_id_by_persistent "$name")
    else
        current_id=$(get_source_id_by_persistent "$name")
    fi

    [[ -n $current_id ]]
}

get_current_id_by_persistent() {
    local type="$1"
    local name="$2"
    [[ -z $type || -z $name ]] && return

    if [[ $type == "sink" ]]; then
        get_sink_id_by_persistent "$name"
    else
        get_source_id_by_persistent "$name"
    fi
}

get_device_name_by_persistent() {
    local type="$1"
    local name="$2"
    [[ -z $type || -z $name ]] && return

    local current_id
    current_id=$(get_current_id_by_persistent "$type" "$name")
    if [[ -n $current_id ]]; then
        if [[ $type == "sink" ]]; then
            get_sink_name "$current_id"
        else
            get_source_name "$current_id"
        fi
    fi
}

apply_audio_fallback() {
    local type="$1"
    [[ -z $type ]] && echo "ERR_MISSING_ARGS" && return 1

    local current_id
    if [[ $type == "sink" ]]; then
        current_id=$(get_default_sink)
    else
        current_id=$(get_default_source)
    fi

    local current_name=""
    if [[ -n $current_id ]]; then
        if [[ $type == "sink" ]]; then
            current_name=$(get_sink_name "$current_id")
        else
            current_name=$(get_source_name "$current_id")
        fi
    fi

    if [[ -n $current_name && $current_name != "EasyEffects" ]]; then
        echo "OK|current_still_valid|$current_name"
        return 0
    fi

    local fallback_name
    if [[ $type == "sink" ]]; then
        fallback_name=$(get_var "AUDIO_FALLBACK_SINK" "")
    else
        fallback_name=$(get_var "AUDIO_FALLBACK_SOURCE" "")
    fi

    if [[ -z $fallback_name ]]; then
        echo "ERR_NO_FALLBACK_CONFIGURED"
        return 1
    fi

    local fallback_id
    fallback_id=$(get_current_id_by_persistent "$type" "$fallback_name")

    if [[ -z $fallback_id ]]; then
        echo "ERR_FALLBACK_NOT_AVAILABLE"
        return 1
    fi

    wpctl set-default "$fallback_id" 2>/dev/null

    local fallback_display_name
    if [[ $type == "sink" ]]; then
        fallback_display_name=$(get_sink_name "$fallback_id")
    else
        fallback_display_name=$(get_source_name "$fallback_id")
    fi


    local eq_preset=$(get_var "AUDIO_EQ_PRESET" "")
    if [[ -n $eq_preset && $eq_preset != "None" ]]; then
        if command -v easyeffects >/dev/null 2>&1 && pgrep -x easyeffects >/dev/null 2>&1; then
            easyeffects -l "$eq_preset" 2>/dev/null
        fi
    fi

    echo "OK|$fallback_display_name"
}

apply_audio_primary() {
    local type="$1"
    [[ -z $type ]] && echo "ERR_MISSING_ARGS" && return 1

    local primary_name
    if [[ $type == "sink" ]]; then
        primary_name=$(get_var "AUDIO_PRIMARY_SINK" "")
    else
        primary_name=$(get_var "AUDIO_PRIMARY_SOURCE" "")
    fi

    if [[ -z $primary_name ]]; then
        echo "OK|no_primary_configured"
        return 0
    fi

    local primary_id
    primary_id=$(get_current_id_by_persistent "$type" "$primary_name")

    if [[ -z $primary_id ]]; then
        echo "OK|primary_not_available"
        return 0
    fi

    local current_id
    if [[ $type == "sink" ]]; then
        current_id=$(get_default_sink)
    else
        current_id=$(get_default_source)
    fi

    local current_name=""
    if [[ -n $current_id ]]; then
        if [[ $type == "sink" ]]; then
            current_name=$(get_sink_name "$current_id")
        else
            current_name=$(get_source_name "$current_id")
        fi
    fi

    if [[ $current_id == "$primary_id" ]]; then
        echo "OK|already_primary|$current_name"
        return 0
    fi

    wpctl set-default "$primary_id" 2>/dev/null

    local primary_display_name
    if [[ $type == "sink" ]]; then
        primary_display_name=$(get_sink_name "$primary_id")
    else
        primary_display_name=$(get_source_name "$primary_id")
    fi


    local eq_preset=$(get_var "AUDIO_EQ_PRESET" "")
    if [[ -n $eq_preset && $eq_preset != "None" ]]; then
        if command -v easyeffects >/dev/null 2>&1 && pgrep -x easyeffects >/dev/null 2>&1; then
            easyeffects -l "$eq_preset" 2>/dev/null
        fi
    fi

    echo "OK|$primary_display_name"
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
    if [[ -f $eq_config ]]; then
        local preset=$(grep "^preset=" "$eq_config" 2>/dev/null | cut -d'=' -f2-)
        if [[ -n $preset ]]; then
            echo "$preset"
            return
        fi

        local has_eq=$(grep "band.*Gain=" "$eq_config" 2>/dev/null | grep -v "=0$\|=-0$\|=[+-]0\." | head -1)
        if [[ -n $has_eq ]]; then
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
            if [[ $name == *"$profile"* || $profile == *"$name"* ]]; then
                echo "$f"
            fi
        done | head -1)

        if [[ -n $matches ]]; then
            profile_path="$matches"
        fi
    fi

    if [[ -f $profile_path ]]; then
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

    if [[ -d $dest_dir ]]; then
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
            [[ -d $preset_dir ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "wwmm" | "wwmm/easyeffects")
            local url="https://github.com/wwmm/easyeffects/archive/refs/heads/main.zip"
            local tmp="/tmp/easyeffects.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/easyeffects-main"
            [[ -d $preset_dir ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "Bundy01")
            local url="https://github.com/Bundy01/EasyEffects-presets/archive/refs/heads/main.zip"
            local tmp="/tmp/bundy-presets.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-presets-main"
            [[ -d $preset_dir ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
            rm -f "$tmp"
            ;;
        "Digitalone1")
            local url="https://github.com/Digitalone1/EasyEffects-presets/archive/refs/heads/main.zip"
            local tmp="/tmp/digitalone-presets.zip"
            curl -Ls "$url" -o "$tmp"
            unzip -o "$tmp" -d "$cache_dir" 2>/dev/null
            local preset_dir="$cache_dir/EasyEffects-presets-main"
            [[ -d $preset_dir ]] && cp -r "$preset_dir"/* "$dest_dir/" 2>/dev/null
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
    pgrep -x easyeffects >/dev/null 2>&1 || {
        echo "Not running"
        return 0
    }
    pkill -x easyeffects
    sleep 1
    pgrep -x easyeffects >/dev/null 2>&1 && echo "Failed to stop" || echo "Stopped"
}

get_pcore_threads() {
    local cpu_vendor=$(grep -m1 "vendor" /proc/cpuinfo | awk '{print $3}')
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | awk '{$1=""; $2=""; print $0}' | xargs)

    if [[ $cpu_vendor == *"Intel"* ]]; then
        local is_big_little=false

        if [[ $cpu_model == *"Ultra"* ]]; then
            is_big_little=true
        elif [[ $cpu_model =~ [0-9]{2}[0-9]H ]]; then
            local gen=$(echo "$cpu_model" | grep -oE "^[0-9]{2}" | head -1)
            if [[ $gen -ge 12 ]]; then
                is_big_little=true
            fi
        elif [[ $cpu_model =~ [0-9]+[0-9]00 ]]; then
            local gen_num=$(echo "$cpu_model" | grep -oE '[0-9]+[0-9]00' | head -1 | grep -oE '^[0-9]+')
            if [[ $gen_num -ge 12 ]]; then
                is_big_little=true
            fi
        fi

        if [[ $is_big_little == "true" ]]; then
            local p_cores=()
            for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
                local id=$(basename "$cpu" | sed 's/cpu//')

                if [[ -f "$cpu/online" ]] && [[ $(cat "$cpu/online") == "1" ]]; then
                    local freq=$(cat "$cpu/cpufreq/scaling_max_freq" 2>/dev/null)
                    if [[ -n $freq && $freq -gt 4000000 ]]; then
                        p_cores+=("$id")
                    fi
                fi
            done

            if [[ ${#p_cores[@]} -gt 0 ]]; then
                echo "$(
                    IFS=,
                    echo "${p_cores[*]}"
                )"
                return 0
            fi
        fi

        local cores=$(nproc 2>/dev/null || echo 4)
        local threads_per_core=$(lscpu 2>/dev/null | grep "Thread(s) per core" | awk '{print $4}')
        local pcore_cores=$((cores / threads_per_core))

        local pcore_threads=""
        for ((i = 0; i < pcore_cores * threads_per_core; i++)); do
            [[ -n $pcore_threads ]] && pcore_threads+="," || pcore_threads+=""
            pcore_threads+="$i"
        done
        echo "$pcore_threads"
    elif [[ $cpu_vendor == *"AMD"* ]]; then
        local cores=$(nproc 2>/dev/null || echo 4)
        local threads_per_core=$(lscpu 2>/dev/null | grep "Thread(s) per core" | awk '{print $4}')
        local total_threads=$((cores / threads_per_core))

        local threads=""
        for ((i = 0; i < total_threads; i++)); do
            [[ -n $threads ]] && threads+=","
            threads+="$i"
        done
        echo "$threads"
    else
        local cores=$(nproc 2>/dev/null || echo 4)
        local threads=""
        for ((i = 0; i < cores; i++)); do
            [[ -n $threads ]] && threads+=","
            threads+="$i"
        done
        echo "$threads"
    fi
}

fix_stutter() {
    local services=("pipewire" "wireplumber")
    local cpu_vendor=$(grep -m1 "vendor" /proc/cpuinfo | awk '{print $3}')

    local affinity=$(get_pcore_threads)

    if [[ -z $affinity ]]; then
        local cores=$(nproc 2>/dev/null || echo 4)
        affinity="0-$((cores - 1))"
    fi

    local method="P-cores"
    [[ $cpu_vendor != *"Intel"* ]] && method="all cores"

    local pw_config_dir="$HOME/.config/pipewire/pipewire.conf.d"
    mkdir -p "$pw_config_dir"
    cat >"$pw_config_dir/99-force-static.conf" <<EOF
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 48000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 512
    default.clock.max-quantum   = 2048
}
EOF

    for svc in "${services[@]}"; do
        local unit="${svc}.service"
        local override_dir="$HOME/.config/systemd/user/${unit}.d"
        mkdir -p "$override_dir"

        cat >"$override_dir/override.conf" <<EOF
[Service]
CPUAffinity=$affinity
Nice=-15
LimitRTPRIO=95
LimitMEMLOCK=infinity
EOF
    done

    systemctl --user daemon-reload 2>/dev/null

    for svc in "${services[@]}"; do
        local unit="${svc}.service"
        systemctl --user restart "$unit" 2>/dev/null
    done

    retro audio ee restart

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
        echo "source_volume:$(get_source_volume)"
        echo "easyeffects:$(get_easyeffects_status)"
        ;;
    "--set-volume") set_volume "$2" ;;
    "--volume-up") volume_up "$2" ;;
    "--volume-down") volume_down "$2" ;;
    "--toggle-mute") toggle_mute ;;
    "--set-mute") set_mute "$2" ;;
    "--toggle-mic-mute") toggle_mic_mute ;;
    "--set-mic-mute") set_mic_mute "$2" ;;
    "--get-sinks") get_sinks ;;
    "--get-sources") get_sources ;;
    "--get-sink-name") get_sink_name "$2" ;;
    "--get-source-name") get_source_name "$2" ;;
    "--get-sink-persistent-name") get_sink_persistent_name "$2" ;;
    "--get-source-persistent-name") get_source_persistent_name "$2" ;;
    "--get-sink-id-by-name") get_sink_id_by_persistent "$2" ;;
    "--get-source-id-by-name") get_source_id_by_persistent "$2" ;;
    "--set-sink") set_sink "$2" ;;
    "--set-source") set_source "$2" ;;
    "--get-source-volume") get_source_volume ;;
    "--set-source-volume") set_source_volume "$2" ;;
    "--eq-list") list_eq_profiles ;;
    "--eq-current") get_current_eq_profile ;;
    "--eq-apply") apply_eq_profile "$2" ;;
    "--eq-download") download_eq_preset "$2" ;;
    "--eq-list-remote") get_remote_eq_repos ;;
    "--eq-list-remote-profiles") eq_list_remote_profiles ;;
    "--ee-start") start_easyeffects ;;
    "--ee-stop") stop_easyeffects ;;
    "--fix-stutter") fix_stutter ;;
    "--audio-priority-set") set_audio_priority "$2" "$3" "$4" ;;
    "--audio-priority-get") get_audio_priority "$2" ;;
    "--audio-priority-clear") clear_audio_priority "$2" ;;
    "--audio-fallback") apply_audio_fallback "$2" ;;
    "--audio-primary") apply_audio_primary "$2" ;;
    "--audio-find-device") find_device_by_pattern "$2" "$3" ;;
esac
