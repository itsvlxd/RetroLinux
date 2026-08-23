#!/usr/bin/env bash

category="$1"
num="$2"

case "$category" in
    win_active)
        case "$num" in
            1) echo "󰼏" ;;
            2) echo "󰼐" ;;
            3) echo "󰼑" ;;
            4) echo "󰼒" ;;
            5) echo "󰼓" ;;
            6) echo "󰼔" ;;
            7) echo "󰼕" ;;
            8) echo "󰼖" ;;
            9) echo "󰼗" ;;
            10) echo "󰿪" ;;
            *) echo "$num" ;;
        esac
        ;;
    win_inactive)
        case "$num" in
            1) echo "󰎥" ;;
            2) echo "󰎨" ;;
            3) echo "󰎫" ;;
            4) echo "󰎲" ;;
            5) echo "󰎯" ;;
            6) echo "󰎴" ;;
            7) echo "󰎷" ;;
            8) echo "󰎺" ;;
            9) echo "󰎽" ;;
            10) echo "󰿫" ;;
            *) echo "$num" ;;
        esac
        ;;
    pane_active)
        case "$num" in
            1) echo "󰎤" ;;
            2) echo "󰎧" ;;
            3) echo "󰎪" ;;
            4) echo "󰎭" ;;
            5) echo "󰎱" ;;
            6) echo "󰎳" ;;
            7) echo "󰎶" ;;
            8) echo "󰎹" ;;
            9) echo "󰎼" ;;
            10) echo "󰽽" ;;
            *) echo "$num" ;;
        esac
        ;;
    pane_inactive)
        case "$num" in
            1) echo "󰎦" ;;
            2) echo "󰎩" ;;
            3) echo "󰎬" ;;
            4) echo "󰎮" ;;
            5) echo "󰎰" ;;
            6) echo "󰎵" ;;
            7) echo "󰎸" ;;
            8) echo "󰎻" ;;
            9) echo "󰎾" ;;
            10) echo "󰽾" ;;
            *) echo "$num" ;;
        esac
        ;;
    *)
        echo "$num"
        ;;
esac
