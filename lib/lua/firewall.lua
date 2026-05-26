local Firewall = {}

local retro_dir = os.getenv("RETRO_DIR") or os.getenv("HOME") .. "/.essentials/retro-arch"

local function run_cmd(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

function Firewall.block_ip(ip)
    run_cmd("bash '" .. retro_dir .. "/scripts/lib/firewall_lib.sh' --block '" .. ip .. "'")
end

function Firewall.kill_ssh_sessions(ip)
    run_cmd("bash '" .. retro_dir .. "/scripts/lib/firewall_lib.sh' --kill-ssh '" .. ip .. "'")
end

function Firewall.get_engine()
    return run_cmd("bash '" .. retro_dir .. "/scripts/lib/firewall_lib.sh' --engine")
end

return Firewall
