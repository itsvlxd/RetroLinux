#!/bin/bash

SHELL_DIR="${RETRO_DIR:-$PWD}/modules/retroshell/files"
PIPE="/tmp/retroshell_ipc.pipe"
PID_FILE="/tmp/retroshell.pid"

run_cmd() {
    local cmd="$1"
    [[ -z $cmd ]] && echo "ERR|no_command" && return 1

    if [[ -p $PIPE ]]; then
        echo "$cmd" >"$PIPE" &
        echo "OK|$cmd"
    else
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
            qs ipc --pid "$pid" call retroshell run "$cmd" 2>/dev/null && echo "OK|$cmd" || echo "ERR|ipc_failed"
        else
            echo "ERR|not_running"
            return 1
        fi
    fi
}

case "$1" in
    "--run")
        run_cmd "$2"
        ;;
    "--start")
        if [[ -f $PID_FILE ]]; then
            old_pid=$(cat "$PID_FILE")
            if kill -0 "$old_pid" 2>/dev/null; then
                echo "ERR|already_running|$old_pid"
                exit 0
            fi
            rm -f "$PID_FILE"
        fi
        export QS_ICON_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
        export QT_QPA_PLATFORMTHEME=qt6ct
        nohup qs -p "$SHELL_DIR/shell.qml" >/dev/null 2>&1 &
        unset HL_INITIAL_WORKSPACE_TOKEN
        echo "$!" >"$PID_FILE"

        # Wait for IPC pipe to be ready before returning
        for i in $(seq 1 50); do
            [[ -p $PIPE ]] && break
            sleep 0.1
        done
        echo "OK|$!"
        ;;
    "--stop")
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
            run_cmd "quit" >/dev/null 2>&1
            kill "$pid" 2>/dev/null
            # Wait for process to actually die
            for i in $(seq 1 30); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            rm -f "$PIPE" "$PID_FILE"
            echo "OK|stopped"
        else
            echo "ERR|not_running"
        fi
        ;;
    "--status")
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
            echo "running|$pid"
        else
            echo "stopped|"
        fi
        ;;
    "--lock")
        sid="${XDG_SESSION_ID:-}"
        if [[ -z $sid ]]; then
            sid=$(loginctl 2>/dev/null | awk 'NR>1 {print $1}' | head -1)
        fi
        locked=$(loginctl show-session "$sid" -p LockedHint 2>/dev/null | sed 's/^LockedHint=//')
        if [[ "$locked" == "yes" ]]; then
            echo "OK|already_locked"
        else
            run_cmd "lockscreen"
        fi
        ;;
    "--pid")
        cat "$PID_FILE" 2>/dev/null || echo ""
        ;;
    "--restart")
        bash "$0" --stop
        sleep 0.5
        bash "$0" --start
        ;;
    *)
        echo "Usage: $0 --run <cmd>|--start|--stop|--restart|--status|--lock|--pid"
        exit 1
        ;;
esac