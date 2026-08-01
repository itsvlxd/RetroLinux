return {
	name = "audio",
	interval = 2,
	enabled = function()
		return true
	end,
	start = function(engine)
		local Watcher = require("watcher")
		local Audio = require("audio")

		Watcher.log("audio", "Audio watcher starting", "info")

		local last_sink_id = ""
		local last_source_id = ""
		local primary_sink_was_unavail = false
		local primary_source_was_unavail = false
		local last_ee_running = false
		local ee_crashed_at = nil

		while true do
			local priority_enabled = Watcher.get_var("AUDIO_PRIORITY_ENABLED", "true")
			local primary_sink = Watcher.get_var("AUDIO_PRIMARY_SINK", "")
			local fallback_sink = Watcher.get_var("AUDIO_FALLBACK_SINK", "")
			local primary_source = Watcher.get_var("AUDIO_PRIMARY_SOURCE", "")
			local fallback_source = Watcher.get_var("AUDIO_FALLBACK_SOURCE", "")

			if priority_enabled == "true" then
				Audio.invalidate_cache()
				local cur_sink = Audio.get_default_sink()

				if cur_sink ~= last_sink_id then
					if last_sink_id ~= "" and cur_sink == "" then
						Watcher.log("audio", "Default sink disappeared, was: " .. last_sink_id, "info")
						if fallback_sink ~= "" then
							local result, name = Audio.apply_fallback("sink")
							if result == "fallback_applied" then
								Watcher.log("audio", "Fallback applied: " .. name, "info")
								engine:emit("on_audio_sink_fallback", name)
							elseif result == "current_still_valid" then
								Watcher.log("audio", "Fallback already active: " .. name, "info")
							elseif result == "no_fallback_configured" then
								Watcher.log("audio", "No fallback configured", "info")
							elseif result == "fallback_not_available" then
								Watcher.log("audio", "Fallback not available", "info")
							end
						end
					elseif cur_sink ~= "" and last_sink_id ~= "" then
						Watcher.log("audio", "Default sink changed: " .. last_sink_id .. " -> " .. cur_sink, "info")
					elseif cur_sink ~= "" and last_sink_id == "" then
						Watcher.log("audio", "Default sink appeared: " .. cur_sink, "info")
					end

					if primary_sink ~= "" then
						local primary_id = Audio.get_sink_id_by_persistent(primary_sink)
						if primary_id ~= "" then
							if cur_sink ~= primary_id then
								Watcher.log(
									"audio",
									"Enforcing primary sink: "
										.. primary_sink
										.. " (ID "
										.. primary_id
										.. "), current was "
										.. cur_sink,
									"info"
								)
								Audio.set_default("sink", primary_id)
								cur_sink = primary_id
							end
						else
							Watcher.log("audio", "Primary sink not available: " .. primary_sink, "warn")
						end
					end

					last_sink_id = cur_sink
				end

				if primary_sink ~= "" then
					local primary_id = Audio.get_sink_id_by_persistent(primary_sink)
					local available = primary_id ~= ""
					if not available and not primary_sink_was_unavail then
						primary_sink_was_unavail = true
						Watcher.log("audio", "Primary sink unavailable: " .. primary_sink, "info")
						if fallback_sink ~= "" then
							local result, name = Audio.apply_fallback("sink")
							if result == "fallback_applied" then
								Watcher.log("audio", "Fallback applied (primary unavailable): " .. name, "info")
								engine:emit("on_audio_sink_fallback", name)
							elseif result == "current_still_valid" then
								Watcher.log("audio", "Fallback already active: " .. name, "info")
							elseif result == "no_fallback_configured" then
								Watcher.log("audio", "No fallback configured", "info")
							elseif result == "fallback_not_available" then
								Watcher.log("audio", "Fallback not available", "info")
							end
						end
					elseif available then
						primary_sink_was_unavail = false
					end
				end
			end

			if priority_enabled == "true" then
				Audio.invalidate_cache()
				local cur_source = Audio.get_default_source()

				if cur_source ~= last_source_id then
					if last_source_id ~= "" and cur_source == "" then
						Watcher.log("audio", "Default source disappeared, was: " .. last_source_id, "info")
						if fallback_source ~= "" then
							local result, name = Audio.apply_fallback("source")
							if result == "fallback_applied" then
								Watcher.log("audio", "Fallback applied: " .. name, "info")
								engine:emit("on_audio_source_fallback", name)
							elseif result == "current_still_valid" then
								Watcher.log("audio", "Fallback already active: " .. name, "info")
							elseif result == "no_fallback_configured" then
								Watcher.log("audio", "No fallback configured", "info")
							elseif result == "fallback_not_available" then
								Watcher.log("audio", "Fallback not available", "info")
							end
						end
					elseif cur_source ~= "" and last_source_id ~= "" then
						Watcher.log("audio", "Default source changed: " .. last_source_id .. " -> " .. cur_source, "info")
					elseif cur_source ~= "" and last_source_id == "" then
						Watcher.log("audio", "Default source appeared: " .. cur_source, "info")
					end

					if primary_source ~= "" then
						local primary_id = Audio.get_source_id_by_persistent(primary_source)
						if primary_id ~= "" then
							if cur_source ~= primary_id then
								Watcher.log(
									"audio",
									"Enforcing primary source: "
										.. primary_source
										.. " (ID "
										.. primary_id
										.. "), current was "
										.. cur_source,
									"info"
								)
								Audio.set_default("source", primary_id)
								cur_source = primary_id
							end
						else
							Watcher.log("audio", "Primary source not available: " .. primary_source, "warn")
						end
					end

					last_source_id = cur_source
				end

				if primary_source ~= "" then
					local primary_id = Audio.get_source_id_by_persistent(primary_source)
					local available = primary_id ~= ""
					if not available and not primary_source_was_unavail then
						primary_source_was_unavail = true
						Watcher.log("audio", "Primary source unavailable: " .. primary_source, "info")
						if fallback_source ~= "" then
							local result, name = Audio.apply_fallback("source")
							if result == "fallback_applied" then
								Watcher.log("audio", "Fallback applied (primary unavailable): " .. name, "info")
								engine:emit("on_audio_source_fallback", name)
							elseif result == "current_still_valid" then
								Watcher.log("audio", "Fallback already active: " .. name, "info")
							elseif result == "no_fallback_configured" then
								Watcher.log("audio", "No fallback configured", "info")
							elseif result == "fallback_not_available" then
								Watcher.log("audio", "Fallback not available", "info")
							end
						end
					elseif available then
						primary_source_was_unavail = false
					end
				end
			end

			local ee_running = (io.popen("pgrep -x easyeffects 2>/dev/null"):read("*l") or "") ~= ""

			local crash_restart = Watcher.get_var("AUDIO_RESTART_ON_CRASH", "true")
			local crash_threshold = tonumber(Watcher.get_var("AUDIO_RESTART_ON_CRASH_THRESHOLD", "20")) or 20
			local crash_notify = Watcher.get_var("AUDIO_RESTART_ON_CRASH_NOTIFY", "true")

			if crash_restart == "true" then
				if last_ee_running and not ee_running then
					ee_crashed_at = os.time()
					Watcher.log("audio", "EasyEffects stopped — waiting " .. crash_threshold .. "s before restart", "warn")
				elseif ee_crashed_at and ee_running then
					ee_crashed_at = nil
					Watcher.log("audio", "EasyEffects recovered on its own", "info")
				elseif ee_crashed_at and not ee_running then
					if os.time() - ee_crashed_at >= crash_threshold then
						Watcher.log("audio", "EasyEffects still down after " .. crash_threshold .. "s — restarting", "warn")
						io.popen("nohup retro audio ee restart &")
						if crash_notify == "true" then
							engine:emit("on_audio_ee_restarted")
						end
						ee_crashed_at = nil
					end
				end
			else
				if last_ee_running and not ee_running then
					Watcher.log("audio", "EasyEffects stopped (auto-restart disabled)", "info")
				elseif not last_ee_running and ee_running then
					Watcher.log("audio", "EasyEffects started", "info")
				end
			end

			last_ee_running = ee_running

			coroutine.yield()
		end
	end,
}
