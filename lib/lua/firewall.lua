local Firewall = {}

local retro_dir = os.getenv("RETRO_DIR") or os.getenv("HOME") .. "/.essentials/retro-arch"
local core = retro_dir .. "/scripts/firewall_core.sh"

local function run_bg(cmd)
    os.execute("timeout 10 " .. cmd .. " </dev/null >/dev/null 2>&1 &")
end

local function run_cmd(cmd)
    local handle = io.popen("timeout 10 " .. cmd)
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

function Firewall.block_ip(ip, reason)
    reason = reason or "manual"
    run_bg("bash '" .. core .. "' --block '" .. ip .. "' '" .. reason .. "'")
end

function Firewall.kill_ssh_sessions(ip)
    run_bg("bash '" .. core .. "' --kill-ssh '" .. ip .. "'")
end

function Firewall.get_engine()
    return "nftables"
end

return Firewall
