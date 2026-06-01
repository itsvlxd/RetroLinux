#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "timeshift"

_read_json_field() {
    local file="$1"
    local field="$2"
    grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}

_read_json_array() {
    local file="$1"
    local field="$2"
    tr -d '\n' <"$file" | grep -oP "\"${field}\"\s*:\s*\[[^\]]*\]" 2>/dev/null | sed 's/^[^:]*:[[:space:]]*//'
}

_write_json_field() {
    local file="$1"
    local field="$2"
    local value="$3"
    if grep -q "\"${field}\"" "$file" 2>/dev/null; then
        sudo sed -i "s|\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"${field}\": \"${value}\"|" "$file"
    else
        sudo sed -i "/\"schedule_daily\"/s|$|\n  \"${field}\": \"${value}\",|" "$file"
    fi
}

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

    local backup_uuid=$(_read_json_field "$config_file" "backup_device_uuid")
    local parent_uuid=$(_read_json_field "$config_file" "parent_device_uuid")
    local btrfs_mode=$(_read_json_field "$config_file" "btrfs_mode")
    local sched_daily=$(_read_json_field "$config_file" "schedule_daily")
    local sched_weekly=$(_read_json_field "$config_file" "schedule_weekly")
    local sched_monthly=$(_read_json_field "$config_file" "schedule_monthly")
    local sched_hourly=$(_read_json_field "$config_file" "schedule_hourly")
    local sched_boot=$(_read_json_field "$config_file" "schedule_boot")
    local count_daily=$(_read_json_field "$config_file" "count_daily")
    local count_weekly=$(_read_json_field "$config_file" "count_weekly")
    local count_monthly=$(_read_json_field "$config_file" "count_monthly")
    local count_hourly=$(_read_json_field "$config_file" "count_hourly")
    local count_boot=$(_read_json_field "$config_file" "count_boot")
    local snap_count=$(_read_json_field "$config_file" "snapshot_count")
    local snap_size=$(_read_json_field "$config_file" "snapshot_size")
    local include_home=$(_read_json_field "$config_file" "include_btrfs_home_for_backup")
    local exclude=$(_read_json_array "$config_file" "exclude" | tr -d '\n')
    if [[ -z $exclude || $exclude == "[]" ]]; then
        local rsync_exclude="/etc/timeshift/rsync/exclude.list"
        if [[ -f $rsync_exclude ]]; then
            local lines=$(grep -v '^#' "$rsync_exclude" | grep -v '^$' | sed 's/^/"/; s/$/"/' | tr '\n' ',' | sed 's/,$//')
            [[ -n $lines ]] && exclude="[$lines]"
        fi
    fi
    local exclude_apps=$(_read_json_array "$config_file" "exclude-apps" | tr -d '\n')

    [[ $sched_daily == "true" ]] && sched_daily="$count_daily" || sched_daily="0"
    [[ $sched_weekly == "true" ]] && sched_weekly="$count_weekly" || sched_weekly="0"
    [[ $sched_monthly == "true" ]] && sched_monthly="$count_monthly" || sched_monthly="0"
    [[ $sched_hourly == "true" ]] && sched_hourly="$count_hourly" || sched_hourly="0"
    [[ $sched_boot == "true" ]] && sched_boot="$count_boot" || sched_boot="0"

    local device="none"
    if [[ -n $backup_uuid && $backup_uuid != "none" ]]; then
        device=$(blkid -U "$backup_uuid" 2>/dev/null | cut -d: -f1)
        [[ -z $device ]] && device="$backup_uuid"
    fi

    echo "CONFIG|${device:-none}|${backup_uuid:-none}|${parent_uuid:-none}|${btrfs_mode:-false}|${sched_daily:-0}|${sched_weekly:-0}|${sched_monthly:-0}|${sched_hourly:-0}|${sched_boot:-0}|${snap_count:-0}|${snap_size:-0}|${include_home:-false}|${exclude:-[]}|${exclude_apps:-[]}"
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
        daily) field="schedule_daily" ;;
        weekly) field="schedule_weekly" ;;
        monthly) field="schedule_monthly" ;;
        hourly) field="schedule_hourly" ;;
        boot) field="schedule_boot" ;;
        *)
            echo "ERROR:invalid_timeframe"
            return 1
            ;;
    esac

    local count_field="count_${timeframe}"
    _write_json_field "$config_file" "$field" "$([ $count -gt 0 ] && echo "true" || echo "false")"
    _write_json_field "$config_file" "$count_field" "$count"

    echo "SET|${timeframe}|${count}"
}

_set_retention() {
    local retention="$1"
    local config_file="/etc/timeshift/timeshift.json"

    if [[ ! -f $config_file ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    IFS=',' read -ra pairs <<<"$retention"
    for pair in "${pairs[@]}"; do
        local key="${pair%%=*}"
        local val="${pair#*=}"
        case "$key" in
            daily)
                [[ $val -gt 0 ]] && {
                    _write_json_field "$config_file" "schedule_daily" "true"
                    _write_json_field "$config_file" "count_daily" "$val"
                } || _write_json_field "$config_file" "schedule_daily" "false"
                ;;
            weekly)
                [[ $val -gt 0 ]] && {
                    _write_json_field "$config_file" "schedule_weekly" "true"
                    _write_json_field "$config_file" "count_weekly" "$val"
                } || _write_json_field "$config_file" "schedule_weekly" "false"
                ;;
            monthly)
                [[ $val -gt 0 ]] && {
                    _write_json_field "$config_file" "schedule_monthly" "true"
                    _write_json_field "$config_file" "count_monthly" "$val"
                } || _write_json_field "$config_file" "schedule_monthly" "false"
                ;;
        esac
    done

    echo "SET|${retention}"
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

    _write_json_field "$config_file" "backup_device_uuid" "$uuid"
    echo "SET|${device}|${uuid}"
}

_get_disk_usage() {
    local config=$(_get_config)
    if [[ $config == "ERROR"* ]]; then
        echo "$config"
        return 1
    fi

    IFS='|' read -r key device uuid parent btrfs daily weekly monthly hourly boot hidden level <<<"$config"

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

_list_devices() {
    local found=false
    while IFS= read -r line; do
        local dev=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local fstype=$(echo "$line" | awk '{print $3}')
        local mount=$(echo "$line" | awk '{print $4}')
        [[ -z $dev || $dev == "NAME" ]] && continue
        echo "DEVICE|${dev}|${size}|${fstype}|${mount}"
        found=true
    done < <(lsblk -dpo NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -v "loop")
    [[ $found == false ]] && echo "ERROR:no_devices"
}

_apply_setup() {
    local config_file="/etc/timeshift/timeshift.json"
    local initial_setup=false

    if [[ ! -f $config_file ]]; then
        initial_setup=true
        echo '{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "true",
  "include_btrfs_home_for_restore" : "true",
  "stop_cron_emails" : "false",
  "schedule_monthly" : "false",
  "schedule_weekly" : "false",
  "schedule_daily" : "false",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "2",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : ["+ /home/*/.config/**", "/home/*", "/root"],
  "exclude-apps" : []
}' | sudo tee "$config_file" >/dev/null
    fi

    for pair in "$@"; do
        local key="${pair%%=*}"
        local val="${pair#*=}"
        case "$key" in
            device)
                local uuid=$(blkid -s UUID -o value "$val" 2>/dev/null)
                [[ -n $uuid ]] && _write_json_field "$config_file" "backup_device_uuid" "$uuid"
                ;;
            btrfs) _write_json_field "$config_file" "btrfs_mode" "$val" ;;
            daily)
                [[ $val -gt 0 ]] && {
                    _write_json_field "$config_file" "schedule_daily" "true"
                    _write_json_field "$config_file" "count_daily" "$val"
                } || _write_json_field "$config_file" "schedule_daily" "false"
                ;;
            weekly)
                [[ $val -gt 0 ]] && {
                    _write_json_field "$config_file" "schedule_weekly" "true"
                    _write_json_field "$config_file" "count_weekly" "$val"
                } || _write_json_field "$config_file" "schedule_weekly" "false"
                ;;
            monthly)
                [[ $val -gt 0 ]] && {
                    _write_json_field "$config_file" "schedule_monthly" "true"
                    _write_json_field "$config_file" "count_monthly" "$val"
                } || _write_json_field "$config_file" "schedule_monthly" "false"
                ;;
            boot)
                [[ $val == "true" || $val == "on" ]] && {
                    _write_json_field "$config_file" "schedule_boot" "true"
                    _write_json_field "$config_file" "count_boot" "${boot_count:-2}"
                } || _write_json_field "$config_file" "schedule_boot" "false"
                ;;
            boot_count) _write_json_field "$config_file" "count_boot" "$val" ;;
            exclude_home)
                _write_json_field "$config_file" "include_btrfs_home_for_backup" "$([ "$val" == "true" ] && echo "false" || echo "true")"
                _write_json_field "$config_file" "include_btrfs_home_for_restore" "$([ "$val" == "true" ] && echo "false" || echo "true")"
                local exclude_arr='["/home/*", "/root"]'
                [[ $val == "false" ]] && exclude_arr='["+ /home/*/.config/**", "/home/*", "/root"]'
                sudo python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
cfg['exclude'] = $exclude_arr
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                ;;
            filters)
                local arr="["
                for p in $val; do
                    [[ -z $p || $p == "+" ]] && continue
                    [[ $p == +* ]] && p="+ ${p#+}"
                    arr+="\"$p\", "
                done
                arr="${arr%, }]"
                sudo python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
cfg['exclude'] = $arr
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                ;;
        esac
    done

    echo "OK|setup_applied"
}

_set_boot() {
    local value="$1"
    local config_file="/etc/timeshift/timeshift.json"

    if [[ ! -f $config_file ]]; then
        echo "ERROR:not_configured"
        return 1
    fi

    if [[ $value == "true" || $value == "on" || $value == "enable" ]]; then
        _write_json_field "$config_file" "schedule_boot" "true"
        local current_count=$(_read_json_field "$config_file" "count_boot")
        [[ -z $current_count || $current_count == "0" ]] && _write_json_field "$config_file" "count_boot" "2"
        echo "SET|boot|true"
    elif [[ $value == "false" || $value == "off" || $value == "disable" ]]; then
        _write_json_field "$config_file" "schedule_boot" "false"
        echo "SET|boot|false"
    else
        [[ $value =~ ^[0-9]+$ ]] && _write_json_field "$config_file" "count_boot" "$value" && echo "SET|boot_count|${value}" || echo "ERROR:invalid_value"
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

_open_gui() {
    local check=$(_check_timeshift)
    [[ $check == "ERROR"* ]] && echo "$check" && return 1

    if command -v timeshift-gtk >/dev/null 2>&1; then
        pkexec env WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR timeshift-gtk &>/dev/null &
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
    "--schedule") _set_schedule "$2" "$3" ;;
    "--retention") _set_retention "$2" ;;
    "--location") _set_location "$2" ;;
    "--list-devices") _list_devices ;;
    "--apply-setup") shift; _apply_setup "$@" ;;
    "--set-boot") _set_boot "$2" ;;
    "--disk-usage") _get_disk_usage ;;
    "--stats") _get_stats ;;
    "--gui") _open_gui ;;
esac
