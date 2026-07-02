local Notify = {}

function Notify.send(summary, body, opts)
	opts = opts or {}
	local urgency = opts.urgency or "normal"
	local icon = opts.icon or ""
	local timeout = opts.timeout or "5000"
	local app_name = opts.app_name or "retro"

	local function build_base_cmd(with_wait)
		local base = string.format("notify-send -a '%s' -u %s", app_name, urgency)
		if with_wait then
			base = base .. " -t " .. timeout .. " -w"
		else
			base = base .. " -t " .. timeout
		end
		if icon ~= "" then
			base = base .. " -i '" .. icon .. "'"
		end
		base = base .. " '" .. summary .. "' '" .. (body or "") .. "'"
		if opts.actions then
			for _, a in ipairs(opts.actions) do
				base = base .. " -A '" .. a.key .. "=" .. a.label .. "'"
			end
		end
		return base
	end

	if opts.background then
		local cmd = build_base_cmd(true)
		local bg = "action=$(" .. cmd .. " 2>/dev/null); "
		if opts.action_handlers then
			for _, h in ipairs(opts.action_handlers) do
				bg = bg .. string.format('if [[ "$action" == "%s" ]]; then %s & fi; ', h.key, h.cmd)
			end
		end
		os.execute(bg .. " &")
		return nil
	end

	local cmd = build_base_cmd(opts.wait)

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
	Notify.send("Battery Low", cap .. "% remaining — find a plug soon", {
		icon = "battery-low",
		app_name = "retro",
	})
end

function Notify.battery_critical(cap)
	Notify.send("Battery Critical", "Only " .. cap .. "% left. Connect power now.", {
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

function Notify.pkg_updates(count, sample, extra_opts)
	extra_opts = extra_opts or {}
	local opts = {
		icon = "software-update-available-symbolic",
		urgency = "normal",
		timeout = "20000",
		wait = true,
		actions = {
			{ key = "update", label = "Update Now" },
			{ key = "later", label = "Remind Later" },
		},
	}
	for k, v in pairs(extra_opts) do
		opts[k] = v
	end
	return Notify.send(
		"System Updates Available",
		"<b>" .. count .. "</b> packages have pending updates.\nIncluding: <i>" .. sample .. "</i>",
		opts
	)
end

function Notify.retro_update(commits, extra_opts)
	extra_opts = extra_opts or {}
	local opts = {
		icon = "software-update-available-symbolic",
		urgency = "normal",
		timeout = "20000",
		wait = true,
		actions = {
			{ key = "update", label = "Update" },
			{ key = "later", label = "Remind me later" },
		},
	}
	for k, v in pairs(extra_opts) do
		opts[k] = v
	end
	return Notify.send(
		"Retro Update Available",
		"RetroLinux has some new updates. \n<b>" .. commits .. "</b> new commits have been added.",
		opts
	)
end

return Notify
