local mount_root
local device_labels = {}
local last_usb = {}

local function run(cmd)
	local h = io.popen("timeout 10 " .. cmd .. " 2>/dev/null")
	if not h then
		return ""
	end
	local r = h:read("*a")
	h:close()
	return r:gsub("%s+$", "")
end

local function get_usb_parts()
	local raw = run("lsblk -nlo NAME,RM,TYPE,TRAN")
	if raw == "" then
		return nil
	end
	local usb_disks = {}
	local parts = {}
	for line in raw:gmatch("[^\n]+") do
		local name, rm, typ, tran = line:match("^(%S+)%s+(%S+)%s+(%S+)%s*(%S*)$")
		if name and rm == "1" and typ == "disk" and tran == "usb" then
			usb_disks[name] = true
		end
	end
	for line in raw:gmatch("[^\n]+") do
		local name, rm, typ = line:match("^(%S+)%s+(%S+)%s+(%S+)")
		if name and rm == "1" and typ == "part" then
			for disk, _ in pairs(usb_disks) do
				if name:sub(1, #disk) == disk then
					parts[name] = true
					break
				end
			end
		end
	end
	return parts
end

return {
	name = "usb",
	interval = 0,
	enabled = function()
		return true
	end,
	start = function(engine)
		local Watcher = require("watcher")
		local home = os.getenv("HOME") or "/tmp"
		mount_root = home .. "/Mounts"
		os.execute("mkdir -p '" .. mount_root .. "'")
		last_usb = {}
		device_labels = {}
		tick_count = 0
		Watcher.log("usb", "USB watcher started", "info")
	end,
	tick = function(engine)
		local Watcher = require("watcher")

		local current = get_usb_parts()
		if not current then
			return
		end

		for dev, _ in pairs(current) do
			if not last_usb[dev] then
				local dev_path = "/dev/" .. dev
				local label = run("lsblk -nlo LABEL '" .. dev_path .. "'")
				if label == "" then
					label = "USB_" .. dev
				end
				device_labels[dev] = label
				Watcher.log("usb", "new: " .. dev .. " (" .. label .. ")", "info")

				local mount = run("findmnt -nlo TARGET '" .. dev_path .. "'")
				if mount == "" then
					run("udisksctl mount -b '" .. dev_path .. "' --no-user-interaction 2>&1")
					Watcher.sleep(1)
					mount = run("findmnt -nlo TARGET '" .. dev_path .. "'")
				end

				if mount ~= "" then
					local symlink = mount_root .. "/" .. label
					run("ln -sfn '" .. mount .. "' '" .. symlink .. "'")

					local ignore = Watcher.get_var("USB_IGNORE_DRIVES", "")
					local ignored = false
					if ignore ~= "" and ignore ~= "null" then
						for item in ignore:gmatch("[^|]+") do
							if item == label then
								ignored = true
								break
							end
						end
					end
					if not ignored then
						Watcher.log("usb", "emit: on_usb_connected " .. label, "info")
						engine:emit("on_usb_connected", label, symlink)
					end
				end
			end
		end

		for dev, _ in pairs(last_usb) do
			if not current[dev] then
				local label = device_labels[dev] or dev
				Watcher.log("usb", "removed: " .. dev .. " (" .. label .. ")", "info")
				engine:emit("on_usb_disconnected", dev, label, mount_root)
				device_labels[dev] = nil
			end
		end

		last_usb = current
	end,
}
