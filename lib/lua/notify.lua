local Notify = {}

function Notify.send(summary, body, opts)
	opts = opts or {}
	local urgency = opts.urgency or "normal"
	local icon = opts.icon or ""
	local timeout = opts.timeout or "5000"
	local app_name = opts.app_name or "retro"

	local cmd =
		string.format("notify-send -a '%s' -u %s -t %s '%s' '%s'", app_name, urgency, timeout, summary, body or "")

	if icon ~= "" then
		cmd = cmd .. " -i '" .. icon .. "'"
	end

	if opts.wait then
		cmd = "notify-send -a '" .. app_name .. "' -u " .. urgency .. " -t " .. timeout .. " -w"
		if icon ~= "" then
			cmd = cmd .. " -i '" .. icon .. "'"
		end
		cmd = cmd .. " '" .. summary .. "' '" .. (body or "") .. "'"
		if opts.actions then
			for _, a in ipairs(opts.actions) do
				cmd = cmd .. " -A '" .. a.key .. "=" .. a.label .. "'"
			end
		end
	end

	if opts.actions and not opts.wait then
		for _, a in ipairs(opts.actions) do
			cmd = cmd .. " -A '" .. a.key .. "=" .. a.label .. "'"
		end
	end

	if opts.async then
		os.execute(cmd .. " &")
		return nil
	end

	local handle = io.popen(cmd .. " 2>/dev/null")
	if not handle then
		return nil
	end
	local result = handle:read("*l")
	handle:close()
	return result
end

function Notify.info(summary, body, opts)
	opts = opts or {}
	opts.urgency = opts.urgency or "normal"
	return Notify.send(summary, body, opts)
end

function Notify.warn(summary, body, opts)
	opts = opts or {}
	opts.urgency = opts.urgency or "normal"
	return Notify.send(summary, body, opts)
end

function Notify.error(summary, body, opts)
	opts = opts or {}
	opts.urgency = opts.urgency or "critical"
	return Notify.send(summary, body, opts)
end

function Notify.power_disconnect(cap)
	Notify.send("Power Disconnected", "Now on battery power (" .. cap .. "%)", {
		icon = "battery-caution",
		app_name = "retro",
	})
end

function Notify.power_connect(cap)
	local icon = cap == "100" and "battery-full-charging" or "battery-charging"
	local msg = cap == "100" and "Running on AC (Battery bypassed)" or "Charging up (" .. cap .. "%)"
	Notify.send("Power Connected", msg, { icon = icon, app_name = "retro" })
end

function Notify.battery_saver_enabled()
	Notify.send("Battery Saver", "Power draw capped to extend runtime", {
		icon = "power-profile-saver",
		app_name = "retro",
	})
end

function Notify.battery_saver_disabled()
	Notify.send("Battery Saver", "Standard power limits restored", {
		icon = "power-profile-balanced",
		app_name = "retro",
	})
end

function Notify.battery_low(cap)
	Notify.send("Battery Low", cap .. "%% remaining — find a plug soon", {
		icon = "battery-low",
		app_name = "retro",
	})
end

function Notify.battery_critical(cap)
	Notify.send("Battery Critical", "Only " .. cap .. "%% left. Connect power now.", {
		icon = "battery-empty",
		urgency = "critical",
		app_name = "retro",
	})
end

function Notify.battery_usage_high(app, watts, cpu, pid)
	local action = Notify.send(
		"Battery Usage",
		"High battery usage detected.\n<b>"
			.. app
			.. " ("
			.. pid
			.. ")</b> is pulling "
			.. watts
			.. "W and "
			.. cpu
			.. "%% CPU",
		{
			icon = "dialog-warning-symbolic",
			urgency = "normal",
			timeout = "15000",
			app_name = "retro_battery_usage_" .. app,
			wait = true,
			actions = {
				{ key = "terminate", label = "Terminate Process" },
				{ key = "ignore", label = "Ignore " .. app },
			},
		}
	)
	return action
end

function Notify.usb_connected(label, mount_path, fm_name)
	local fm_display = fm_name:sub(1, 1):upper() .. fm_name:sub(2)
	local action =
		Notify.send("USB Drive Detected", "<b>" .. label .. "</b> has been mounted.\nLocation: " .. mount_path, {
			icon = "drive-removable-media-symbolic",
			urgency = "normal",
			timeout = "10000",
			app_name = "retro_usb_con_" .. label,
			wait = true,
			actions = {
				{ key = "open", label = "Open in " .. fm_display },
				{ key = "ignore", label = "Ignore " .. label },
			},
		})
	return action
end

function Notify.usb_disconnected(dev_name, label)
	Notify.send(
		"USB Drive Removed",
		"Drive <b>" .. label .. "</b> (" .. dev_name .. ") has been disconnected.",
		{ icon = "drive-removable-media-symbolic", app_name = "retro_usb_dis_" .. dev_name }
	)
end

function Notify.bluetooth_connected(name, mac, icon)
	local action = Notify.send(
		"Connection Established",
		"<b>" .. name .. "</b> (" .. mac .. ") has been connected successfully.",
		{
			icon = icon or "bluetooth-active",
			urgency = "normal",
			timeout = "10000",
			app_name = "retro_bluetooth_con_" .. mac,
			wait = true,
			actions = {
				{ key = "disconnect", label = "Disconnect" },
				{ key = "forget", label = "Forget Device" },
			},
		}
	)
	return action
end

function Notify.bluetooth_disconnected(name, mac, icon)
	Notify.send(
		"Connection Closed",
		"<b>" .. name .. "</b> (" .. mac .. ") is no longer active.",
		{ icon = icon or "bluetooth-active", timeout = "5000", app_name = "retro_bluetooth_con_" .. mac }
	)
end

function Notify.bluetooth_pairing_request(name, mac, icon)
	local action = Notify.send(
		"Bluetooth Pairing Request",
		"Device <b>" .. name .. "</b> sent a bluetooth pairing request.\nAddress: " .. mac,
		{
			icon = icon or "bluetooth-active",
			urgency = "critical",
			app_name = "retro_bluetooth_con_" .. mac,
			wait = true,
			actions = {
				{ key = "pair", label = "Pair" },
				{ key = "ignore", label = "Ignore" },
			},
		}
	)
	return action
end

function Notify.pkg_updates(count, sample)
	local action = Notify.send(
		"System Updates Available",
		"<b>" .. count .. "</b> packages have pending updates.\nIncluding: <i>" .. sample .. "</i>",
		{
			icon = "software-update-available-symbolic",
			urgency = "normal",
			timeout = "20000",
			app_name = "retro",
			wait = true,
			actions = {
				{ key = "update", label = "Update Now" },
				{ key = "later", label = "Remind Later" },
			},
		}
	)
	return action
end

function Notify.retro_update(commits)
	local action = Notify.send(
		"Retro Update Available",
		"RetroLinux has some new updates. \n<b>" .. commits .. "</b> new commits have been added.",
		{
			icon = "software-update-available-symbolic",
			urgency = "normal",
			timeout = "20000",
			app_name = "retro",
			wait = true,
			actions = {
				{ key = "update", label = "Update" },
				{ key = "later", label = "Remind me later" },
			},
		}
	)
	return action
end

return Notify
