local mod = get_mod("GhostRunner")

mod:info("GhostRunner v0 loaded")

-- Hard dependency check: SoloPlay must be present and enabled.
local SoloPlay = get_mod("SoloPlay")
if not SoloPlay then
	mod:error("GhostRunner requires the SoloPlay mod to be installed and enabled.")
	return
end

mod.SoloPlay = SoloPlay

mod.fs = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/fs")
mod.fs.ensure_runs_folder()
mod:info("GhostRunner runs folder: " .. tostring(mod.fs.runs_root))

mod.run_file = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/run_file")
mod.interpolation = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/interpolation")
mod.source = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/source")

mod.recorder = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/recorder")

mod.commands = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/commands")

mod.world_renderer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/world_renderer")

mod.replayer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/replayer")

mod:hook(CLASS.GameModeManager, "on_player_unit_spawn",
	function(func, self, player, player_unit, is_respawn)
		func(self, player, player_unit, is_respawn)

		if is_respawn then return end

		-- Identity: must be the local player.
		-- Compare Player instances directly. `local_player.player_unit` is a
		-- userdata field (the Unit), not a method -- calling :player_unit()
		-- crashes with "attempt to call method on userdata value".
		local local_player = Managers.player and Managers.player:local_player(1)
		if not local_player or player ~= local_player then
			return
		end

		local is_solo = mod.SoloPlay.is_soloplay()

		-- Recorder gate: solo always allowed (with record_runs setting); online
		-- only if the user opts in via record_online_missions.
		if mod:get("record_runs") then
			if is_solo or mod:get("record_online_missions") then
				mod.recorder.start(player, player_unit)
			end
		end

		-- Replayer: solo only. MP missions can't honour mission auto-set or
		-- seed pinning, and the gameplay isn't authoritative on the client.
		if is_solo then
			mod.replayer.on_local_player_spawn()
		end
	end)

mod:hook_require("scripts/managers/game_mode/game_modes/game_mode_base",
	function(GameModeBase)
		mod:hook(GameModeBase, "mission_cleanup",
			function(func, self, on_shutdown)
				-- self._state on GameModeBase is the internal state machine
				-- (`"running"`, `"done"`, etc.) -- NOT the outcome we want.
				-- The mission outcome ("won"/"lost") is stored on the manager
				-- as _end_conditions_met_outcome, set via _set_end_conditions_met
				-- when evaluate_end_conditions returns a result. It persists
				-- through mission_cleanup. Fall through to "aborted" if the
				-- mission ended without an end-condition outcome (e.g. user
				-- quit to hub mid-mission).
				local gm_mgr = Managers.state and Managers.state.game_mode
				local outcome = (gm_mgr and gm_mgr._end_conditions_met_outcome)
					or "aborted"
				mod.recorder.stop_and_save(outcome, on_shutdown)
				-- Replayer: also reset on mission end. If we were "playing" or
				-- "finished", drop back to idle. Re-arming for the next mission
				-- requires the user to /ghost load again.
				if mod.replayer.state() ~= "idle" then
					mod.replayer.disarm()
				end
				func(self, on_shutdown)
			end)
	end)

mod:register_hud_element({
	class_name = "HudElementGhostBeacon",
	filename = "GhostRunner/scripts/mods/GhostRunner/hud_beacon",
	use_hud_scale = true,
	visibility_groups = { "alive" },
	validation_function = function()
		-- Don't render in hub.
		local game_mode_manager = Managers.state and Managers.state.game_mode
		local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
		return game_mode_name ~= "hub"
	end,
})

mod:register_hud_element({
	class_name = "HudElementGhostTimer",
	filename = "GhostRunner/scripts/mods/GhostRunner/hud_timer",
	use_hud_scale = true,
	visibility_groups = { "alive" },
	validation_function = function()
		local game_mode_manager = Managers.state and Managers.state.game_mode
		local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
		return game_mode_name ~= "hub"
	end,
})

mod.update = function(dt)
	-- Outer pcall: any one tick subsystem throwing should not silently kill
	-- the whole frame loop for the others.
	local ok, err = pcall(mod.recorder.tick, dt)
	if not ok then mod:warning("recorder.tick error: " .. tostring(err)) end

	local ok2, err2 = pcall(mod.replayer.tick, dt)
	if not ok2 then
		mod:warning("replayer.tick error: " .. tostring(err2))
		-- Disarm to break the loop; otherwise the next tick re-enters and
		-- re-throws. A 20-30 Hz error stream into the DMF print hook is
		-- enough to trigger the 16s engine watchdog deadlock if the user
		-- accidentally selects text in the dev console.
		mod.replayer.disarm()
	end

	-- World renderer (trail + pole). No-op if not playing.
	local okwr, errwr = pcall(function()
		if mod.replayer.state() ~= "playing" then return end
		-- Trail walk-back needs the loaded frames + interpolator's current idx.
		-- Replayer exposes minimal accessors so we don't reach into source internals.
		local frames = mod.replayer.frames and mod.replayer.frames()
		local idx = mod.replayer.idx and mod.replayer.idx()
		local last = mod.replayer.last_state()
		if not frames or not idx or not last then return end
		local trail_duration = 4.0   -- TODO: read from settings in Task 9
		mod.world_renderer.tick(frames, idx, last, trail_duration)
	end)
	if not okwr then mod:warning("world_renderer.tick error: " .. tostring(errwr)) end

	local ok3, err3 = pcall(function()
		local ui_manager = Managers.ui
		local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
		if not hud then return end
		local element = hud:element("HudElementGhostBeacon")
		if not element or not element.set_active then return end

		-- Hide if not currently playing.
		if mod.replayer.state() ~= "playing" then
			element:set_active(false)
			return
		end

		-- Pull the latest interpolated remote-player state.
		local s = mod.replayer.last_state()
		if not s or not s.p then
			element:set_active(false)
			return
		end

		-- Camera lookup. The HUD's player_camera() is the same one the
		-- engine's world markers use; if it's not yet available (early
		-- frames), hide the widget.
		local camera = hud.player_camera and hud:player_camera()
		if not camera then
			element:set_active(false)
			return
		end

		-- Project to screen at HEAD position (foot + offset that varies with state).
		-- Same offset used by world_renderer for the top of the pole, so the
		-- nameplate sits exactly atop the pole.
		local head_offset = mod.world_renderer
			and mod.world_renderer.head_offset_for_state(s.st)
			or 1.8
		local world_pos = Vector3(s.p[1], s.p[2], s.p[3] + head_offset)
		if Camera.inside_frustum(camera, world_pos) <= 0 then
			element:set_active(false)
			return
		end

		local screen_pos, distance = Camera.world_to_screen(camera, world_pos)
		if not screen_pos or not distance or distance <= 0 then
			element:set_active(false)
			return
		end

		-- Convert raw screen pixels to HUD-logical coords before passing to
		-- the widget. With use_hud_scale=true the scenegraph expects logical
		-- units, so without this multiplication the widget drifts
		-- proportionally to its distance from origin (= the orbit-around-
		-- ghost-position bug). This matches what the engine's vanilla
		-- HudElementWorldMarkers does at hud_element_world_markers.lua:438.
		local inverse_scale = RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.inverse_scale or 1
		element:set_active(true)
		element:set_offset(screen_pos.x * inverse_scale, screen_pos.y * inverse_scale)
		-- Keep the nameplate in sync with the loaded ghost.
		if element.set_name and mod._selected_ghost then
			local pname = mod._selected_ghost.data.metadata.player
			if pname then element:set_name(pname) end
		end
		if element.set_state then
			element:set_state(s)
		end
	end)
	if not ok3 then mod:warning("hud_beacon update error: " .. tostring(err3)) end

	local ok4, err4 = pcall(function()
		local ui_manager = Managers.ui
		local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
		if not hud then return end
		local timer = hud:element("HudElementGhostTimer")
		if not timer or not timer.set_active then return end

		local show = mod:get("show_race_timer") and mod.replayer.state() == "playing"
		if not show then
			timer:set_active(false)
			return
		end

		timer:set_active(true)
		if timer.set_state then
			local ghost_t = mod.replayer.elapsed() or 0

			-- Live progress: query MainPathManager directly each tick.
			-- side_id is a number (1 = heroes side), not a string -- per
			-- server_metrics_manager.lua:127 which is the canonical caller.
			local live_prog = nil
			local main_path = Managers.state and Managers.state.main_path
			if main_path then
				local ok_p, val = pcall(main_path.furthest_travel_percentage, main_path, 1)
				if ok_p then live_prog = val end
			end

			-- Ghost progress: from the interpolated last_state (recorded `pg` field, schema 2).
			local last = mod.replayer.last_state()
			local ghost_prog = last and last.pg

			timer:set_state({
				ghost_t = ghost_t,
				live_prog = live_prog,
				ghost_prog = ghost_prog,
			})
		end
	end)
	if not ok4 then mod:warning("hud_timer update error: " .. tostring(err4)) end
end

-- Keybind callback for "open runs folder" in F4 settings. Must be on the
-- mod table because DMF's keybind widget config has function_name = "open_runs_folder_keybind".
mod.open_runs_folder_keybind = function()
	mod.fs.open_runs_folder()
end

-- DMF splits chat input by whitespace and passes each token as a separate
-- vararg to the callback (see dmf/scripts/mods/dmf/modules/ui/chat/chat_actions.lua
-- around line 113-115). So `/ghost load 1` calls us with `("load", "1")`,
-- not `("load 1")`. Use varargs to capture everything; rejoin remaining
-- tokens with spaces for `cmd_load` (handles filenames with spaces too).
mod:command("ghost", "GhostRunner: ghost picker -- see /ghost help", function(...)
	local args = { ... }
	local sub = (args[1] or ""):lower()
	local rest = #args > 1 and table.concat(args, " ", 2) or ""

	if sub == "list" then
		mod.commands.cmd_list()
	elseif sub == "load" then
		mod.commands.cmd_load(rest)
	elseif sub == "clear" then
		mod.commands.cmd_clear()
	elseif sub == "info" then
		mod.commands.cmd_info()
	elseif sub == "delete" then
		mod.commands.cmd_delete(rest)
	elseif sub == "help" or sub == "" then
		mod:echo("Commands: /ghost list | /ghost load <n> | /ghost clear | /ghost info | /ghost delete <n>")
	else
		mod:echo("Unknown subcommand. Try /ghost help.")
	end
end)

mod:command("ghost_status", "GhostRunner: print recorder/replayer status", function()
	-- Wrap each access in pcall so one failure (e.g. nil replayer) doesn't
	-- abort the whole output.
	local rec_state = pcall(mod.recorder.state) and mod.recorder.state() or "?"
	local rep_state = pcall(mod.replayer.state) and mod.replayer.state() or "?"
	local rep_elapsed = pcall(mod.replayer.elapsed) and mod.replayer.elapsed() or 0
	local rep_duration = pcall(mod.replayer.duration) and mod.replayer.duration() or 0
	local seed_pinned = pcall(mod.replayer.is_seed_pinned) and mod.replayer.is_seed_pinned() or false

	mod:echo(string.format("Recorder: %s | Replayer: %s (%.2f/%.2fs) | seed_pinned=%s",
		rec_state, rep_state, rep_elapsed, rep_duration, tostring(seed_pinned)))

	if mod._selected_ghost then
		local m = mod._selected_ghost.data.metadata.mission
		mod:echo(string.format("  loaded ghost: %s seed=%s file=%s",
			m and m.name or "?",
			tostring(m and m.seed or "?"),
			mod._selected_ghost.filename))
	else
		mod:echo("  loaded ghost: <none>")
	end

	local s = mod.replayer.last_state()
	if s then
		mod:echo(string.format("  last_state: t=%.2f p=(%.1f,%.1f,%.1f) hp=%.2f",
			s.t, s.p[1], s.p[2], s.p[3], s.hp))
	end

	-- Recorder dump still goes to the log file only (mod:info).
	mod.recorder._dump()
end)

-- TEMP (removed in Task 10 cleanup): verify schema-1 frame translation.
mod:command("ghost_test_translate", "GhostRunner dev: schema-1 frame translation test", function()
	-- Synthesize a schema-1-looking frame in memory.
	local frame1_old = {
		type = "f", t = 1.5, p = {1, 2, 3}, y = 0.5,
		hp = 0.8, peril = 0.3, w = 3, d = true, prog = 0.1,
	}
	-- Round-trip through cjson to match what comes off disk.
	local round = cjson.decode(cjson.encode(frame1_old))
	-- Apply the read-side path by calling run_file.read on a synthesized file...
	-- Actually simpler: directly invoke the (now internal) translator if exported.
	-- Since _translate_schema1_frame is file-local, just verify by reading a
	-- real schema-1 ghost file from the user's runs/ directory.
	local index = mod.run_file.read_index()
	local schema1_filename = nil
	for _, entry in ipairs(index.runs or {}) do
		local r = mod.run_file.read(entry.file)
		if r and r.metadata.schema == 1 then
			schema1_filename = entry.file
			break
		end
	end
	if not schema1_filename then
		mod:echo("No schema-1 ghost in runs/. Test inconclusive — manually verify with a fresh recording (will be schema 2).")
		return
	end
	local data = mod.run_file.read(schema1_filename)
	if not data then
		mod:echo("Schema-1 file failed to parse: " .. tostring(schema1_filename))
		return
	end
	local f1 = data.frames[1]
	mod:echo(string.format("Schema-1 loaded: %s | first frame: t=%.2f hp=%.2f st=%s pg=%s d=%s peril=%s",
		schema1_filename, f1.t or 0, f1.hp or 0,
		tostring(f1.st), tostring(f1.pg),
		tostring(f1.d), tostring(f1.peril)))
	mod:echo("Expected: st=walking or knocked_down (translated from d); d=nil; peril=nil")
end)

-- TEMP (removed in Task 10 cleanup): verify interpolator handles schema-2 fields.
mod:command("ghost_test_interp", "GhostRunner dev: interpolation test", function()
	local frames = {
		{ t = 0.0, p = {0,0,0}, y = 0,   hp = 1.0, to = 1.0, ab = 1.0, w = 3, st = "walking",     pg = 0.0 },
		{ t = 1.0, p = {1,0,0}, y = 0.5, hp = 0.8, to = 0.5, ab = 0.5, w = 3, st = "sprinting",   pg = 0.1 },
		{ t = 2.0, p = {2,0,0}, y = 1.0, hp = 0.4, to = 0.0, ab = 0.0, w = 2, st = "knocked_down",pg = 0.2 },
	}
	-- Sample at t=0.5 (between frame 1 and 2):
	local s, idx, fin = mod.interpolation.frame_at(frames, 1, 0.5)
	mod:echo(string.format("@t=0.5: p=(%.2f,%.2f,%.2f) hp=%.2f to=%.2f ab=%.2f st=%s pg=%.2f",
		s.p[1], s.p[2], s.p[3], s.hp, s.to, s.ab, tostring(s.st), s.pg))
	mod:echo("Expected: p=(0.5,0,0) hp=0.9 to=0.75 ab=0.75 st=walking pg=0.05")
	-- Sample at t=1.5 (between frame 2 and 3):
	local s2 = mod.interpolation.frame_at(frames, 2, 1.5)
	mod:echo(string.format("@t=1.5: hp=%.2f to=%.2f ab=%.2f st=%s",
		s2.hp, s2.to, s2.ab, tostring(s2.st)))
	mod:echo("Expected: hp=0.6 to=0.25 ab=0.25 st=sprinting")
end)

return mod
