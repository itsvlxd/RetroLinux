#!/bin/bash

_check_timeshift() {
    if ! command -v timeshift >/dev/null 2>&1; then
        echo "ERROR:not_installed"
        return 1
    fi
    echo "OK"
}

_get_config() {
    local config_file="/etc/timeshift/timeshift.json"
    if [[ ! -f $config_file ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    local backup_device=$(grep -o '"backup_device_uuid"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local snapshot_dir=$(grep -o '"snapshot_dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local btrfs_mode=$(grep -o '"btrfs_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local sched_daily=$(grep -o '"schedule_daily"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local sched_weekly=$(grep -o '"schedule_weekly"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local sched_monthly=$(grep -o '"schedule_monthly"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local sched_hourly=$(grep -o '"schedule_hourly"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local sched_boot=$(grep -o '"schedule_boot"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local count_daily=$(grep -o '"count_daily"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local count_weekly=$(grep -o '"count_weekly"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local count_monthly=$(grep -o '"count_monthly"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local count_hourly=$(grep -o '"count_hourly"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local count_boot=$(grep -o '"count_boot"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local snap_count=$(grep -o '"snapshot_count"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')
    local snap_size=$(grep -o '"snapshot_size"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | grep -o '"[^"]*"$' | tr -d '"')

    [[ $sched_daily == "true" ]] && sched_daily="$count_daily" || sched_daily="0"
    [[ $sched_weekly == "true" ]] && sched_weekly="$count_weekly" || sched_weekly="0"
    [[ $sched_monthly == "true" ]] && sched_monthly="$count_monthly" || sched_monthly="0"
    [[ $sched_hourly == "true" ]] && sched_hourly="$count_hourly" || sched_hourly="0"
    [[ $sched_boot == "true" ]] && sched_boot="$count_boot" || sched_boot="0"

    echo "CONFIG|${backup_device:-none}|${snapshot_dir:-none}|${btrfs_mode:-false}|${sched_daily:-0}|${sched_weekly:-0}|${sched_monthly:-0}|${sched_hourly:-0}|${sched_boot:-0}|${snap_count:-0}|${snap_size:-0}"
}

_list_snapshots() {
    local check=$(_check_timeshift)
    [[ $check == "ERROR"* ]] && echo "$check" && return 1

    local config=$(_get_config)
    if [[ $config == "ERROR"* ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    local output
    output=$(sudo timeshift --list 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]] || echo "$output" | grep -qi "no snapshots found\|authentication\|password\|sudo"; then
        local btrfs_mode=$(echo "$config" | cut -d'|' -f4)
        if [[ $btrfs_mode == "true" ]]; then
            local snap_list=$(sudo btrfs subvolume list / 2>/dev/null | grep "timeshift-btrfs" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
            if [[ -n $snap_list ]]; then
                echo "$snap_list" | while IFS= read -r date; do
                    echo "SNAPSHOT|${date}|O|"
                done
                local count=$(echo "$snap_list" | wc -l)
                echo "COUNT|${count}"
                return 0
            fi
        fi
        local snap_count=$(echo "$config" | cut -d'|' -f10)
        if [[ -n $snap_count && $snap_count != "0" && $snap_count != "none" ]]; then
            echo "COUNT|${snap_count}"
            echo "AUTH_REQUIRED"
            return 0
        fi
        echo "NONE"
        return 0
    fi

    echo "$output" | grep -P "\d{4}-\d{2}-\d{2}" | while IFS= read -r line; do
        local date=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
        [[ -z $date ]] && continue
        local tag=$(echo "$line" | grep -oP '\s[OBMWD]\s' | tr -d ' ')
        [[ -z $tag ]] && tag=$(echo "$line" | grep -oP '  [OBMWD]  ' | tr -d ' ')
        local comment=$(echo "$line" | grep -oP '\{[^}]+\}(?:\s*\{[^}]+\})*' | xargs)

        echo "SNAPSHOT|${date}|${tag}|${comment}"
    done

    local count=$(echo "$output" | grep -cP "\d{4}-\d{2}-\d{2}")
    echo "COUNT|${count}"
}

_create_snapshot() {
    local check=$(_check_timeshift)
    [[ $check == "ERROR"* ]] && echo "$check" && return 1

    local comment="$1"
    local tag="${2:-O}"

    if [[ -n $comment ]]; then
        sudo timeshift --create --comments "$comment" --tags "$tag" 2>&1
    else
        sudo timeshift --create --tags "$tag" 2>&1
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo "CREATED|${comment:-manual}|${tag}"
    else
        echo "CREATE_FAILED"
    fi
    return $status
}

_restore_snapshot() {
    local check=$(_check_timeshift)
    [[ $check == "ERROR"* ]] && echo "$check" && return 1

    local snapshot="$1"
    [[ -z $snapshot ]] && echo "ERROR:no_snapshot" && return 1

    echo "RESTORE|${snapshot}"
}

_delete_snapshot() {
    local check=$(_check_timeshift)
    [[ $check == "ERROR"* ]] && echo "$check" && return 1

    local snapshot="$1"
    [[ -z $snapshot ]] && echo "ERROR:no_snapshot" && return 1

    sudo timeshift --delete --snapshot "$snapshot" 2>&1
    local status=$?

    if [[ $status -eq 0 ]]; then
        echo "DELETED|${snapshot}"
    else
        echo "DELETE_FAILED|${snapshot}"
    fi
    return $status
}

_delete_oldest() {
    local snapshots=$(_list_snapshots)
    if [[ $snapshots == "NONE" || $snapshots == "ERROR"* ]]; then
        echo "$snapshots"
        return 1
    fi

    local oldest=$(echo "$snapshots" | grep "^SNAPSHOT|" | head -1)
    if [[ -z $oldest ]]; then
        echo "ERROR:no_snapshots"
        return 1
    fi

    IFS='|' read -r key date tag comment size name <<<"$oldest"
    _delete_snapshot "$name"
}

_set_schedule() {
    local timeframe="$1"
    local value="$2"
    local config_file="/etc/timeshift/timeshift.json"

    if [[ ! -f $config_file ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    [[ -z $value ]] && value="disable"

    local count=0
    if [[ $value == "disable" || $value == "0" ]]; then
        count=0
    elif [[ $value =~ ^[0-9]+$ ]]; then
        count=$value
    else
        echo "ERROR:invalid_value"
        return 1
    fi

    local field=""
    case "$timeframe" in
        daily)   field="schedule_daily" ;;
        weekly)  field="schedule_weekly" ;;
        monthly) field="schedule_monthly" ;;
        hourly)  field="schedule_hourly" ;;
        boot)    field="schedule_boot" ;;
        *)
            echo "ERROR:invalid_timeframe"
            return 1
            ;;
    esac

    local count_field="count_${timeframe}"
    sudo sed -i "s/\"${field}\":[[:space:]]*\"[^\"]*\"/\"${field}\": \"$([ $count -gt 0 ] && echo "true" || echo "false")\"/" "$config_file"
    sudo sed -i "s/\"${count_field}\":[[:space:]]*\"[^\"]*\"/\"${count_field}\": \"$count\"/" "$config_file"

    echo "SET|${timeframe}|${count}"
}

_set_retention() {
    local retention="$1"
    local config_file="/etc/timeshift/timeshift.json"

    if [[ ! -f $config_file ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    local daily=$(echo "$retention" | grep -oP 'daily=\K[0-9]+')
    local weekly=$(echo "$retention" | grep -oP 'weekly=\K[0-9]+')
    local monthly=$(echo "$retention" | grep -oP 'monthly=\K[0-9]+')

    [[ -z $daily ]] && daily=0
    [[ -z $weekly ]] && weekly=0
    [[ -z $monthly ]] && monthly=0

    sudo sed -i "s/\"schedule_daily\":[[:space:]]*[0-9]*/\"schedule_daily\": $daily/" "$config_file"
    sudo sed -i "s/\"schedule_weekly\":[[:space:]]*[0-9]*/\"schedule_weekly\": $weekly/" "$config_file"
    sudo sed -i "s/\"schedule_monthly\":[[:space:]]*[0-9]*/\"schedule_monthly\": $monthly/" "$config_file"

    echo "SET|daily=${daily},weekly=${weekly},monthly=${monthly}"
}

_set_location() {
    local device="$1"
    local config_file="/etc/timeshift/timeshift.json"

    if [[ ! -f $config_file ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    local uuid=$(blkid -s UUID -o value "$device" 2>/dev/null)
    if [[ -z $uuid ]]; then
        echo "ERROR:invalid_device"
        return 1
    fi

    sudo sed -i "s/\"snapshot_device\":[[:space:]]*\"[^\"]*\"/\"snapshot_device\": \"$device\"/" "$config_file"
    sudo sed -i "s/\"snapshot_device_uuid\":[[:space:]]*\"[^\"]*\"/\"snapshot_device_uuid\": \"$uuid\"/" "$config_file"

    echo "SET|${device}|${uuid}"
}

_get_disk_usage() {
    local config=$(_get_config)
    if [[ $config == "ERROR"* ]]; then
        echo "$config"
        return 1
    fi

    IFS='|' read -r key device uuid dir daily weekly monthly hourly boot hidden level <<<"$config"

    if [[ $device != "none" ]]; then
        local total=$(df -h "$device" 2>/dev/null | tail -1 | awk '{print $2}')
        local used=$(df -h "$device" 2>/dev/null | tail -1 | awk '{print $3}')
        local avail=$(df -h "$device" 2>/dev/null | tail -1 | awk '{print $4}')
        local pct=$(df -h "$device" 2>/dev/null | tail -1 | awk '{print $5}')
        echo "DISK|${device}|${total}|${used}|${avail}|${pct}"
    else
        echo "DISK|none|none|none|none|none"
    fi
}

_get_stats() {
    local snapshots=$(_list_snapshots)
    if [[ $snapshots == "NONE" || $snapshots == "ERROR"* ]]; then
        echo "STATS|0|0|none"
        return 0
    fi

    local count=$(echo "$snapshots" | grep -c "^SNAPSHOT|")
    local total_size=$(echo "$snapshots" | grep "^SNAPSHOT|" | awk -F'|' '{sum+=$5} END {print sum}')
    local oldest=$(echo "$snapshots" | grep "^SNAPSHOT|" | head -1 | cut -d'|' -f2)
    local newest=$(echo "$snapshots" | grep "^SNAPSHOT|" | tail -1 | cut -d'|' -f2)

    echo "STATS|${count}|${total_size}|${oldest}|${newest}"
}

_setup_wizard() {
    local check=$(_check_timeshift)
    if [[ $check == "ERROR"* ]]; then
        echo "ERROR:not_installed"
        return 1
    fi

    local config=$(_get_config)
    if [[ $config != "ERROR"* ]]; then
        echo "ALREADY_CONFIGURED"
        return 0
    fi

    echo "WIZARD|start"

    local devices=$(lsblk -dnpo NAME,SIZE,TYPE | grep -E "disk|part" | grep -v "loop")
    echo "DEVICES|${devices}"

    echo "WIZARD|complete"
}

_open_gui() {
    local check=$(_check_timeshift)
    [[ $check == "ERROR"* ]] && echo "$check" && return 1

    if command -v timeshift-gtk >/dev/null 2>&1; then
        local user="${SUDO_USER:-$USER}"

        timeshift-gtk &>/dev/null &

        sleep 2

        if command -v hyprctl >/dev/null 2>&1; then
            local win_addr=$(hyprctl clients -j 2>/dev/null | grep -oP '"address":"0x[^"]*"[^}]*"class":"timeshift-gtk"' | grep -oP '"address":"\K0x[^"]*')
            if [[ -n $win_addr ]]; then
                hyprctl dispatch togglefloating address:"$win_addr" 2>/dev/null
                hyprctl dispatch focuswindow address:"$win_addr" 2>/dev/null
            fi
        fi

        echo "OPENED|timeshift-gtk"
    elif command -v timeshift >/dev/null 2>&1; then
        echo "ERROR:no_gui"
        return 1
    else
        echo "ERROR:not_installed"
        return 1
    fi
}

case "$1" in
    "--check") _check_timeshift ;;
    "--config") _get_config ;;
    "--list") _list_snapshots ;;
    "--create") _create_snapshot "$2" "$3" ;;
    "--restore") _restore_snapshot "$2" ;;
    "--delete") _delete_snapshot "$2" ;;
    "--delete-oldest") _delete_oldest ;;
    "--schedule") _set_schedule "$2" ;;
    "--retention") _set_retention "$2" ;;
    "--location") _set_location "$2" ;;
    "--disk-usage") _get_disk_usage ;;
    "--stats") _get_stats ;;
    "--setup-wizard") _setup_wizard ;;
    "--gui") _open_gui ;;
esac
