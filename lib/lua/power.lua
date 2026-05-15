local Watcher = require("watcher")

local Power = {}

local INTEL_DB = {
    { "Ultra 9 185H", { 25, 45, 95 }, { 15, 25, 45 } },
    { "Ultra 7 155H", { 15, 28, 65 }, { 10, 18, 35 } },
    { "Ultra 5 125H", { 12, 25, 50 }, { 8, 15, 28 } },
    { "Ultra 7 258V", { 10, 17, 37 }, { 7, 12, 25 } },
    { "Ultra 5 226V", { 8, 15, 30 }, { 5, 10, 20 } },
    { "14900HX", { 45, 85, 157 }, { 25, 45, 75 } },
    { "14700HX", { 35, 65, 135 }, { 20, 35, 65 } },
    { "14650HX", { 35, 55, 115 }, { 20, 30, 55 } },
    { "13980HX", { 45, 85, 157 }, { 25, 45, 75 } },
    { "13900H", { 25, 45, 115 }, { 15, 25, 45 } },
    { "13700H", { 20, 45, 115 }, { 12, 25, 45 } },
    { "13620H", { 20, 35, 95 }, { 12, 20, 35 } },
    { "12900HK", { 30, 45, 115 }, { 18, 25, 45 } },
    { "12700H", { 20, 45, 115 }, { 12, 25, 45 } },
    { "12650H", { 20, 35, 95 }, { 12, 20, 35 } },
    { "1360P", { 15, 28, 64 }, { 10, 15, 28 } },
    { "1260P", { 15, 28, 64 }, { 10, 15, 28 } },
    { "1355U", { 10, 15, 25 }, { 7, 10, 15 } },
    { "1255U", { 10, 15, 25 }, { 7, 10, 15 } },
    { "11800H", { 25, 45, 95 }, { 15, 25, 45 } },
    { "11370H", { 15, 28, 50 }, { 10, 18, 28 } },
    { "10875H", { 25, 45, 95 }, { 15, 25, 45 } },
    { "10750H", { 20, 45, 75 }, { 12, 20, 35 } },
    { "14900K", { 65, 125, 253 }, { 35, 65, 95 } },
    { "13900K", { 65, 125, 253 }, { 35, 65, 95 } },
    { "12900K", { 65, 125, 241 }, { 35, 65, 95 } },
    { "11900K", { 65, 125, 250 }, { 35, 65, 95 } },
    { "10900K", { 65, 125, 250 }, { 35, 65, 95 } },
    { "9900K", { 65, 95, 210 }, { 35, 65, 95 } },
    { "8700K", { 65, 95, 140 }, { 35, 65, 95 } },
    { "10300H", { 15, 35, 50 }, { 10, 18, 30 } },
    { "1135G7", { 12, 20, 32 }, { 8, 12, 18 } },
}

local AMD_DB = {
    { "9945HX", { 45, 75, 120 }, { 25, 45, 65 } },
    { "8945HS", { 25, 45, 70 }, { 15, 25, 40 } },
    { "8845HS", { 20, 45, 65 }, { 12, 25, 35 } },
    { "8840U", { 10, 18, 30 }, { 7, 12, 20 } },
    { "7945HX", { 45, 75, 120 }, { 25, 45, 65 } },
    { "7940HS", { 20, 54, 80 }, { 12, 28, 45 } },
    { "7845HX", { 35, 65, 110 }, { 20, 35, 55 } },
    { "7840HS", { 15, 35, 65 }, { 10, 20, 35 } },
    { "7840U", { 10, 25, 30 }, { 7, 15, 22 } },
    { "7735HS", { 15, 35, 54 }, { 10, 20, 30 } },
    { "7640HS", { 15, 35, 50 }, { 10, 18, 30 } },
    { "7540U", { 10, 18, 28 }, { 7, 12, 20 } },
    { "6980HX", { 25, 54, 80 }, { 15, 30, 45 } },
    { "6900HX", { 20, 45, 65 }, { 12, 25, 35 } },
    { "6800H", { 15, 35, 54 }, { 10, 20, 30 } },
    { "6800U", { 10, 20, 28 }, { 7, 12, 18 } },
    { "5980HX", { 25, 54, 80 }, { 15, 30, 45 } },
    { "5900HX", { 20, 45, 65 }, { 12, 25, 35 } },
    { "5800H", { 15, 35, 54 }, { 10, 20, 30 } },
    { "5800U", { 10, 15, 25 }, { 7, 10, 15 } },
    { "4800H", { 15, 35, 54 }, { 10, 20, 30 } },
    { "9950X", { 65, 125, 200 }, { 45, 65, 95 } },
    { "9900X", { 65, 105, 160 }, { 45, 65, 85 } },
    { "7950X3D", { 65, 120, 162 }, { 45, 65, 85 } },
    { "7900X", { 65, 105, 170 }, { 45, 65, 85 } },
    { "7800X3D", { 45, 65, 85 }, { 35, 45, 65 } },
    { "5800X3D", { 45, 65, 105 }, { 35, 45, 65 } },
    { "5950X", { 65, 105, 142 }, { 45, 65, 85 } },
    { "3950X", { 65, 105, 142 }, { 45, 65, 85 } },
    { "3700X", { 45, 65, 88 }, { 35, 45, 65 } },
}

local _cpu_vendor = nil
local _rapl_loaded = false

local function get_cpu_vendor()
    if _cpu_vendor then return _cpu_vendor end
    local f = io.popen("grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}' 2>/dev/null")
    if f then
        _cpu_vendor = f:read("*l") or ""
        f:close()
    end
    return _cpu_vendor or ""
end

local function write_sys(path, value)
    local f = io.open(path, "w")
    if f then
        f:write(tostring(value))
        f:close()
        return true
    end
    return false
end

local function is_on_battery()
    local ac_path = Watcher.run_cmd("find /sys/class/power_supply/ \\( -name 'AC*' -o -name 'ADP*' \\) -type l 2>/dev/null | head -1")
    if ac_path ~= "" then
        local online = Watcher.read_sys(ac_path .. "/online")
        if online == "0" then return true end
    end
    local status = Watcher.run_cmd("grep -l 'Discharging' /sys/class/power_supply/BAT*/status 2>/dev/null | head -1")
    return status ~= ""
end

local function sync_ppd(state)
    local current = Watcher.run_cmd("powerprofilesctl get 2>/dev/null")
    if current == "" then return end
    local ppd_state = "balanced"
    if state == "performance" then ppd_state = "performance"
    elseif state == "saver" then ppd_state = "power-saver"
    end
    if current ~= ppd_state then
        Watcher.run_cmd("powerprofilesctl set " .. ppd_state)
    end
end

local function write_scaling_governor(gov)
    local f = io.popen("echo '" .. gov .. "' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1")
    if f then f:close() end
end

local function write_sysfs_batch(state)
    local settings = {
        wifi_pm = "off", bt_pm = "on", usb_pm = "on",
        pcie_policy = "performance", sata_policy = "max_performance",
        audio_sleep = "0", nmi_watchdog = "1", vm_writeback = "500"
    }

    if state == "saver" then
        settings.wifi_pm = "on"
        settings.bt_pm = "auto"
        settings.usb_pm = "on"
        settings.pcie_policy = "powersave"
        settings.sata_policy = "min_power"
        settings.audio_sleep = "1"
        settings.nmi_watchdog = "0"
        settings.vm_writeback = "6000"
    elseif state == "balanced" then
        settings.wifi_pm = "on"
        settings.sata_policy = "med_power_with_dipm"
        settings.vm_writeback = "1500"
    end

    -- nmi_watchdog + dirty_writeback + audio
    write_sys("/proc/sys/kernel/nmi_watchdog", settings.nmi_watchdog)
    write_sys("/proc/sys/vm/dirty_writeback_centisecs", settings.vm_writeback)
    write_sys("/sys/module/snd_hda_intel/parameters/power_save", settings.audio_sleep)

    -- wifi + bt + usb
    local wl_iface = Watcher.run_cmd("iw dev 2>/dev/null | awk '$1==\"Interface\"{print $2}'")
    if wl_iface ~= "" then
        Watcher.run_cmd("iw dev '" .. wl_iface .. "' set power_save " .. settings.wifi_pm)
    end

    local bt_handle = io.popen("for bt in /sys/class/bluetooth/hci*/device/power/control; do [[ -f $bt ]] && echo '" .. settings.bt_pm .. "' >\"$bt\" 2>/dev/null; done")
    if bt_handle then bt_handle:close() end

    local usb_handle = io.popen("for usb in /sys/bus/usb/devices/*/power/control; do [[ -w $usb ]] && echo '" .. settings.usb_pm .. "' >\"$usb\" 2>/dev/null; done")
    if usb_handle then usb_handle:close() end
end

local function write_intel_rapl(watts, profile)
    local microwatts = watts * 1000000
    if not Watcher.run_cmd("test -d /sys/class/powercap/intel-rapl:0 && echo yes"):find("yes") then return end

    if profile == "performance" then
        write_sys("/sys/devices/system/cpu/intel_pstate/no_turbo", "0")
        write_sys("/sys/devices/system/cpu/intel_pstate/max_perf_pct", "100")
        for epp in io.popen("ls /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null"):lines() do
            write_sys(epp:gsub("%s+$", ""), "performance")
        end
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw", tostring(microwatts))
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw", tostring(microwatts))
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us", "27983872")

    elseif profile == "balanced" then
        write_sys("/sys/devices/system/cpu/intel_pstate/no_turbo", "0")
        write_sys("/sys/devices/system/cpu/intel_pstate/max_perf_pct", "100")
        for epp in io.popen("ls /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null"):lines() do
            write_sys(epp:gsub("%s+$", ""), "balance_performance")
        end
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw", tostring(microwatts))
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw", tostring(microwatts + 5000000))
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us", "976")

    elseif profile == "saver" then
        write_sys("/sys/devices/system/cpu/intel_pstate/no_turbo", "1")
        write_sys("/sys/devices/system/cpu/intel_pstate/max_perf_pct", "30")
        for epp in io.popen("ls /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null"):lines() do
            write_sys(epp:gsub("%s+$", ""), "power")
        end
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw", tostring(microwatts))
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw", tostring(microwatts))
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us", "976")

        if Watcher.run_cmd("test -f /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw && echo yes"):find("yes") then
            write_sys("/sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw", tostring(microwatts))
        end
        if Watcher.run_cmd("test -f /sys/class/powercap/intel-rapl:0:1/constraint_0_power_limit_uw && echo yes"):find("yes") then
            write_sys("/sys/class/powercap/intel-rapl:0:1/constraint_0_power_limit_uw", "3000000")
        end
    end
end

local function write_amd_epp(profile)
    local amd_epp = "balance_power"
    local amd_boost = "1"
    if profile == "performance" then amd_epp = "performance"
    elseif profile == "saver" then amd_epp = "power"; amd_boost = "0"
    end

    for epp in io.popen("ls /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null"):lines() do
        write_sys(epp:gsub("%s+$", ""), amd_epp)
    end
    write_sys("/sys/devices/system/cpu/cpufreq/boost", amd_boost)

    if Watcher.run_cmd("test -f /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw && echo yes"):find("yes") then
        local microwatts = Power.get_pwr_var(profile) * 1000000
        write_sys("/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw", tostring(microwatts))
    end
end

function Power.get_pwr_var(profile)
    profile = profile:upper()
    local source = is_on_battery() and "BAT" or "AC"
    local var_name = "PWR_" .. source .. "_" .. profile
    local val = Watcher.get_var(var_name)

    if val == "" or val == "null" then
        local defaults = {
            BAT_SAVER = 7, AC_SAVER = 15,
            BAT_BALANCED = 14, AC_BALANCED = 28,
            BAT_PERFORMANCE = 35, AC_PERFORMANCE = 65,
        }
        val = defaults[var_name] or 28
    end
    return tonumber(val) or 28
end

function Power.set_profile(profile)
    profile = profile:lower()
    local prev = Watcher.get_var("PWR_CURRENT")
    if prev ~= profile then
        Watcher.set_var("PWR_PREVIOUS", prev)
    end
    Watcher.set_var("PWR_CURRENT", profile)

    local watts = Power.get_pwr_var(profile)
    sync_ppd(profile)
    write_scaling_governor(profile == "saver" and "powersave" or (profile == "balanced" and "powersave" or "performance"))
    write_sysfs_batch(profile)

    -- modprobe RAPL
    if not _rapl_loaded and not Watcher.run_cmd("test -d /sys/class/powercap/intel-rapl:0 && echo yes"):find("yes") then
        Watcher.run_cmd("sudo modprobe intel_rapl_msr 2>/dev/null")
        Watcher.run_cmd("sudo modprobe intel_rapl_common 2>/dev/null")
        if Watcher.run_cmd("test -d /sys/class/powercap/intel-rapl:0 && echo yes"):find("yes") then
            _rapl_loaded = true
        end
    end

    local vendor = get_cpu_vendor()
    if vendor == "GenuineIntel" then
        if not _rapl_loaded and not Watcher.run_cmd("test -d /sys/class/powercap/intel-rapl:0 && echo yes"):find("yes") then
            Watcher.run_cmd("sudo modprobe intel_rapl_msr 2>/dev/null")
            if Watcher.run_cmd("test -d /sys/class/powercap/intel-rapl:0 && echo yes"):find("yes") then
                _rapl_loaded = true
            end
        end
        write_intel_rapl(watts, profile)
    elseif vendor == "AuthenticAMD" then
        write_amd_epp(profile)
    end

    if profile == "saver" then
        Watcher.set_var("BAT_SAVER_FORCED", "true")
        Watcher.set_var("BAT_SAVER_ACTIVE", "true")
    end

    return true
end

function Power.restore_profile()
    local curr = Watcher.get_var("PWR_CURRENT")
    if curr == "" or curr == "null" then curr = "balanced" end
    Power.set_profile(curr)
end

function Power.restore_previous()
    local prev = Watcher.get_var("PWR_PREVIOUS")
    if prev and prev ~= "" and prev ~= "null" then
        Power.set_profile(prev)
    else
        Power.restore_profile()
    end
end

function Power.toggle_profile()
    local curr = Watcher.get_var("PWR_CURRENT")
    local prev = Watcher.get_var("PWR_PREVIOUS")

    if not prev or prev == "" or prev == "null" or prev == curr then
        if curr == "saver" then prev = "balanced"
        elseif curr == "balanced" then prev = "performance"
        else prev = "saver"
        end
    end
    Power.set_profile(prev)
    return prev
end

function Power.optimize_cpu()
    local model = Watcher.run_cmd("grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\\s*:\\s*//'")
    local vendor = get_cpu_vendor()
    local target_db = vendor == "AuthenticAMD" and AMD_DB or INTEL_DB

    for _, entry in ipairs(target_db) do
        if model:find(entry[1], 1, true) then
            return entry[1], entry[2], entry[3]
        end
    end

    if Watcher.has_battery() then
        return "Generic Laptop", { 15, 25, 45 }, { 10, 15, 25 }
    else
        return "Generic PC", { 65, 95, 125 }, { 45, 65, 95 }
    end
end

return Power
