#!/usr/bin/env bash

read_cpu() {
    awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat
}

read -r total1 idle1 < <(read_cpu)
sleep 0.5
read -r total2 idle2 < <(read_cpu)

diff_idle=$((idle2 - idle1))
diff_total=$((total2 - total1))

[[ $diff_total -eq 0 ]] && exit 0

usage=$(((diff_total - diff_idle) * 100 / diff_total))
echo "#[bg=brightblack,fg=yellow] ${usage}% #[bg=default] "
