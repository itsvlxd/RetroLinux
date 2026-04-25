if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

plymouth quit 2>/dev/null || true
clear
~/.automated_script.sh
