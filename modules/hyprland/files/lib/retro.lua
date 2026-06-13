local Variable = require("variable")

local Retro = {}

function Retro.fullscreen()
	local win = hl.get_active_window()
	if win then
		local class = win.class
		local pid = win.pid
		local fs = win.fullscreen
		if class and class:lower() == "kitty" then
			local shrink = Variable.get_var("KITTY_SHRINK_PADDING_FULLSCREEN", "true")
			local default_pd = Variable.get_var("KITTY_PADDING", "5")
			if shrink == "true" then
                local pd = (fs > 0) and default_pd or "1"
				os.execute(
					("kitty @ --to=unix:/tmp/kitty-%d set-spacing padding-top=%s padding-bottom=%s padding-left=%s padding-right=%s 2>/dev/null"):format(
						pid,
						pd,
						pd,
						pd,
						pd
					)
				)
			end
		end
	end
	hl.dispatch(hl.dsp.window.fullscreen())
end

return Retro
