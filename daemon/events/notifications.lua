local Watcher = require("watcher")
local Notify = require("notify")
local Bluetooth = require("bluetooth")
local Firewall = require("firewall")

local log = function(msg)
	Watcher.log("notifications", msg)
end

local Events = {}

function Events.on_power_disconnect(cap)
	Notify.power_disconnect(cap)
end

function Events.on_power_connect(cap)
	Notify.power_connect(cap)
end

function Events.on_battery_saver_enabled()
	Notify.battery_saver_enabled()
end

function Events.on_battery_saver_disabled()
	Notify.battery_saver_disabled()
end

function Events.on_battery_usage_high(app, watts, cpu, pid)
	local action = Notify.battery_usage_high(app, watts, cpu, pid)
	if action == "terminate" then
		Watcher.run_cmd("kill -15 '" .. pid .. "' 2>/dev/null")
	elseif action == "ignore" then
		local current = Watcher.get_var("BAT_IGNORE_APPS")
		if current == "" or current == "null" then
			Watcher.set_var("BAT_IGNORE_APPS", app)
		else
			Watcher.set_var("BAT_IGNORE_APPS", current .. "|" .. app)
		end
	end
end

function Events.on_battery_low(cap)
	Notify.battery_low(cap)
end

function Events.on_battery_critical(cap)
	Notify.battery_critical(cap)
end

function Events.on_usb_connected(label, mount_path)
	local fm_name = Watcher.get_var("RETRO_FILEMANAGER_CMD", "nemo")
	local action = Notify.usb_connected(label, mount_path, fm_name)

	if action == "open" then
		Watcher.run_cmd(fm_name .. " '" .. mount_path .. "' &")
	elseif action == "ignore" then
		local current = Watcher.get_var("USB_IGNORE_DRIVES")
		if current == "" or current == "null" then
			Watcher.set_var("USB_IGNORE_DRIVES", label)
		else
			Watcher.set_var("USB_IGNORE_DRIVES", current .. "|" .. label)
		end
	end
end

function Events.on_usb_disconnected(dev_name, label, mount_root)
	local ignore_list = Watcher.get_var("USB_IGNORE_DRIVES", "")
	local ignored = false
	if ignore_list ~= "" and ignore_list ~= "null" then
		for item in ignore_list:gmatch("[^|]+") do
			if item == label then
				ignored = true
				break
			end
		end
	end
	if not ignored then
		Notify.usb_disconnected(dev_name, label)
	end
	local link_path = mount_root .. "/" .. label
	Watcher.run_cmd("rm -f '" .. link_path .. "'")
end

function Events.on_bluetooth_connected(name, mac)
	local icon = Bluetooth.get_device_icon_path(name)
	log(
		"Notification: bluetooth_connected | name="
			.. (name or "nil")
			.. " | mac="
			.. (mac or "nil")
			.. " | icon="
			.. (icon or "nil")
	)
	local action = Notify.bluetooth_connected(name, mac, icon)

	if action == "disconnect" then
		Bluetooth.disconnect(mac)
	elseif action == "forget" then
		Bluetooth.remove_device(mac)
		Notify.send(
			"Device Forgotten",
			name .. " has been removed from trusted devices.",
			{ icon = "edit-delete", urgency = "low" }
		)
	end
end

function Events.on_bluetooth_disconnected(name, mac)
	local icon = Bluetooth.get_device_icon_path(name)
	log("Notification: bluetooth_disconnected | name=" .. (name or "nil") .. " | mac=" .. (mac or "nil"))
	Notify.bluetooth_disconnected(name, mac, icon)
end

function Events.on_bluetooth_pairing_request(name, mac)
	local icon = Bluetooth.get_device_icon_path(name)
	log("Notification: bluetooth_pairing_request | name=" .. (name or "nil") .. " | mac=" .. (mac or "nil"))
	local action = Notify.bluetooth_pairing_request(name, mac, icon)

	if action == "pair" then
		local current_locks = Watcher.get_var("BT_PAIRING_IN_PROGRESS")
		Watcher.set_var("BT_PAIRING_IN_PROGRESS", current_locks .. "|" .. mac)

		local result = Bluetooth.pair_with_agent(mac, name)

		local new_locks = current_locks:gsub("|" .. mac, "")
		Watcher.set_var("BT_PAIRING_IN_PROGRESS", new_locks)
	elseif action == "ignore" then
		local current_ignored = Watcher.get_var("BT_MAC_IGNORE")
		if current_ignored == "" or current_ignored == "null" then
			Watcher.set_var("BT_MAC_IGNORE", mac)
		else
			if not ("|" .. current_ignored .. "|"):find("|" .. mac .. "|", 1, true) then
				Watcher.set_var("BT_MAC_IGNORE", current_ignored .. "|" .. mac)
			end
		end
	end
end

function Events.on_pkg_updates_available(count, sample)
	log("Notification: pkg_updates | count=" .. count .. " | sample=" .. sample)
	local retro_dir = os.getenv("RETRO_DIR")
	local kitty_args = "kitty -- bash " .. retro_dir .. "/scripts/lib/system_update.sh " .. count .. " " .. sample
	local lua_expr = 'hl.dsp.exec_cmd("' .. kitty_args .. '" , { float = true, size = { 1000, 700 }, center = true })'
	local update_cmd = "hyprctl dispatch '" .. lua_expr .. "'"
	local action = Notify.pkg_updates(count, sample, {})
	if action == "update" then
		os.execute(update_cmd .. " &")
	elseif action == "later" then
		log("Package update deferred by user")
	end
end

function Events.on_ssh_login(username, ip, method)
	log("Login: " .. username .. "@" .. ip .. " (" .. (method or "unknown") .. ")")

	local action = Notify.send(
		"SSH Login",
		"<b>" .. username .. "</b> logged in from " .. ip .. " (" .. (method or "unknown") .. ")",
		{
			icon = "network-server-symbolic",
			urgency = "normal",
			timeout = "10000",
			app_name = "RetroLinux",
			wait = true,
			actions = {
				{ key = "disconnect", label = "Disconnect" },
				{ key = "block", label = "Block IP" },
			},
		}
	)

	if action == "disconnect" then
		log("Disconnecting: " .. ip)
		Firewall.kill_ssh_sessions(ip)
		log("Disconnected: " .. ip)
		Notify.send(
			"SSH Disconnected",
			"SSH sessions from " .. ip .. " have been terminated.",
			{ icon = "network-offline-symbolic", timeout = "3000", app_name = "RetroLinux" }
		)
	elseif action == "block" then
		log("Blocking: " .. ip)
		Firewall.block_ip(ip, "brute-force")
		Firewall.kill_ssh_sessions(ip)
		log("Blocked: " .. ip)
		Notify.send(
			"IP Blocked",
			ip .. " has been blocked and its SSH sessions terminated.",
			{ icon = "security-low-symbolic", timeout = "3000", app_name = "RetroLinux" }
		)
	end
end

function Events.on_ssh_failed(username, ip)
	log("Failed attempt: " .. username .. "@" .. ip)
	local failed_count_key = "SSH_FAILED_" .. ip:gsub("%.", "_")
	local current_count = tonumber(Watcher.get_var(failed_count_key, "0")) or 0
	current_count = current_count + 1
	Watcher.set_var(failed_count_key, tostring(current_count))

	if current_count >= 5 then
		local action = Notify.send(
			"SSH Brute Force",
			"<b>" .. current_count .. "</b> failed attempts from " .. ip .. " (user: " .. username .. ")",
			{
				icon = "dialog-warning-symbolic",
				urgency = "normal",
				timeout = "15000",
				app_name = "RetroLinux",
				wait = true,
				actions = {
					{ key = "block", label = "Block IP" },
				},
			}
		)
		Watcher.set_var(failed_count_key, "0")
		if action == "block" then
			log("Brute force blocking: " .. ip)
			Firewall.block_ip(ip, "brute-force")
			Firewall.kill_ssh_sessions(ip)
			log("Brute force blocked: " .. ip)
			Notify.send(
				"IP Blocked",
				ip .. " has been blocked for brute force and its sessions terminated.",
				{ icon = "security-low-symbolic", timeout = "3000", app_name = "RetroLinux" }
			)
		end
	end
end

function Events.on_ssh_close(username, ip, reason)
	local desc = ip
	if username ~= "" then
		desc = username .. "@" .. ip
	end
	log("Close: " .. desc .. " (" .. (reason or "unknown") .. ")")

	if reason == "auth_fail" then
		local action = Notify.send(
			"SSH Authentication Failed",
			"User <b>" .. username .. "</b> tried to login using SSH on this device with wrong credentials.",
			{
				icon = "dialog-warning-symbolic",
				urgency = "critical",
				timeout = "10000",
				app_name = "RetroLinux",
				wait = true,
				actions = {
					{ key = "block", label = "Block IP" },
				},
			}
		)
		if action == "block" then
			log("Blocking: " .. ip)
			Firewall.block_ip(ip, "brute-force")
			Firewall.kill_ssh_sessions(ip)
			log("Blocked: " .. ip)
			Notify.send(
				"IP Blocked",
				ip .. " has been blocked and its SSH sessions terminated.",
				{ icon = "security-low-symbolic", timeout = "3000", app_name = "RetroLinux" }
			)
		end
	else
		Notify.send("SSH Session Closed", "<b>" .. desc .. "</b> (" .. (reason or "unknown") .. ")", {
			icon = "network-offline-symbolic",
			urgency = "low",
			timeout = "5000",
			app_name = "RetroLinux",
		})
	end
end

function Events.on_audio_ee_restarted()
	Notify.send(
		"Audio Crashed",
		"The Audio Daemon has crashed. Attempting to safely restart the engine...",
		{ icon = "audio-card-symbolic", urgency = "normal", timeout = "10000" }
	)
end

function Events.on_retro_update_available(commits)
	log("Notification: retro_update | commits=" .. commits)
	local retro_dir = os.getenv("RETRO_DIR")
	local kitty_args = 'kitty -- bash -c "cd '
		.. retro_dir
		.. ' && bash retro.sh --update; echo; echo Press Enter to close.; read"'
	local kitty_esc = kitty_args:gsub('"', '\\"')
	local lua_expr = 'hl.dsp.exec_cmd("' .. kitty_esc .. '" , { float = true, size = { 1000, 700 }, center = true })'
	local update_cmd = "hyprctl dispatch '" .. lua_expr .. "'"
	local action = Notify.retro_update(commits, {})
	if action == "update" then
		os.execute(update_cmd .. " &")
	elseif action == "later" then
		log("Retro update deferred by user")
	end
end

return Events
