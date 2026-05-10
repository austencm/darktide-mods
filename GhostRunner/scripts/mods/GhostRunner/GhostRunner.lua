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

		-- Only in solo sessions.
		if not mod.SoloPlay.is_soloplay() then return end

		-- Recorder: skip if user has recording off, but the replayer still arms.
		if mod:get("record_runs") then
			mod.recorder.start(player, player_unit)
		end

		-- Replayer: try to enter playing state if armed.
		mod.replayer.on_local_player_spawn()
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

		-- Project to screen. Hide if behind the camera or out of frustum.
		local world_pos = Vector3(s.p[1], s.p[2], s.p[3])
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
end

-- Keybind callback for "open runs folder" in F4 settings. Must be on the
-- mod table because DMF's keybind widget config has function_name = "open_runs_folder_keybind".
mod.open_runs_folder_keybind = function()
	mod.fs.open_runs_folder()
end

-- Dev-test helper: writes to the DMF CommandWindow (via global print, which DMF
-- hooks) AND the in-game chat overlay (via mod:echo). Removed at Task 15
-- alongside the test commands themselves.
local function _say(msg)
	print(msg)
	mod:echo(msg)
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
	elseif sub == "help" or sub == "" then
		mod:echo("Commands: /ghost list | /ghost load <n> | /ghost clear | /ghost info")
	else
		mod:echo("Unknown subcommand. Try /ghost help.")
	end
end)

mod:command("ghost_test_fs", "GhostRunner: verify filesystem helpers", function()
	local ok, err = pcall(function()
		_say("[fs] runs_root: " .. tostring(mod.fs.runs_root))
		_say("[fs] runs_path('foo.run'): " .. tostring(mod.fs.runs_path("foo.run")))
		_say("[fs] index_path: " .. tostring(mod.fs.index_path()))
		_say("[fs] list_run_files: count=" .. tostring(#mod.fs.list_run_files()))
	end)
	if not ok then
		mod:error("[fs] callback errored: " .. tostring(err))
	end
end)

-- Diagnostic: reports whether DMF's print hook is actually installed.
-- If `print == __print` the hook never installed; CommandWindow output
-- will not work regardless of what the DMF settings say.
mod:command("ghost_diag_print", "GhostRunner: diagnose DMF print hook state", function()
	local hooked = print ~= __print
	mod:echo(string.format("[diag] print == __print: %s (hook %s)",
		tostring(print == __print),
		hooked and "INSTALLED" or "MISSING"))
	mod:echo(string.format("[diag] tostring(print): %s", tostring(print)))
	mod:echo(string.format("[diag] tostring(__print): %s", tostring(__print)))

	-- Also try a direct CommandWindow.print bypassing print global, to see
	-- whether the engine API itself is responsive.
	if CommandWindow and CommandWindow.print then
		local cw_ok = pcall(CommandWindow.print, "[diag] direct CommandWindow.print test")
		mod:echo(string.format("[diag] CommandWindow.print direct call: %s",
			cw_ok and "OK" or "ERRORED"))
	else
		mod:echo("[diag] CommandWindow.print not available")
	end
end)

mod:command("ghost_test_runfile", "GhostRunner: write+read a synthetic .run + index", function()
	local filename = "test-synthetic.run"
	local meta = {
		player = "TestPlayer",
		class = "psyker",
		mission = {
			name = "throneside_damnation",
			difficulty = 5,
			circumstance = "default",
			side = nil,
			giver = "morrow",
			havoc = nil,
			seed = 1234567890,
		},
		recorded_at = "2026-05-07T14:32:11.000Z",
	}
	local writer, err = mod.run_file.create_writer(filename, meta)
	if not writer then
		mod:error("[runfile] writer creation failed: " .. tostring(err))
		return
	end
	for i = 1, 5 do
		writer:append_frame({
			t = i * 0.05, p = { 10.0 + i, 20.0, 1.8 }, y = 1.57,
			hp = 1.0, peril = 0.0, w = 3, d = false,
		})
	end
	writer:finalize("completed", 0.25, true, false)
	_say("[runfile] wrote " .. filename)

	local data, read_err = mod.run_file.read(filename)
	if not data then
		mod:error("[runfile] read failed: " .. tostring(read_err))
		return
	end
	_say(string.format("[runfile] read: %d frames, outcome=%s",
		#data.frames, data.footer.outcome))

	-- Append to index, read back.
	mod.run_file.append_to_index(filename, data)
	local idx = mod.run_file.read_index()
	_say(string.format("[runfile] index has %d entries", #idx.runs))

	-- Rebuild from scan and verify equivalence.
	mod.run_file.rebuild_index()
	local rebuilt = mod.run_file.read_index()
	_say(string.format("[runfile] rebuild: %d entries", #rebuilt.runs))
end)

mod:command("ghost_test_source", "GhostRunner: exercise ReplaySource and MockSource", function()
	-- ReplaySource against the synthetic file from Task 3-4.
	local data = mod.run_file.read("test-synthetic.run")
	if not data then
		mod:error("[source] need test-synthetic.run; run /ghost_test_runfile first")
		return
	end
	local rs = mod.source.create_replay_source(data)
	_say(string.format("[source] replay duration=%.2fs frames=%d",
		rs:duration(), #data.frames))

	-- Walk through 6 advances of 0.04s and print position. Should interpolate.
	for i = 1, 6 do
		local s, finished = rs:advance(0.04)
		_say(string.format("[source]   t=%.3f p=(%.2f,%.2f,%.2f) y=%.2f hp=%.2f finished=%s",
			s.t, s.p[1], s.p[2], s.p[3], s.y, s.hp, tostring(finished)))
	end

	-- MockSource sanity.
	local ms = mod.source.create_mock_source()
	for _ = 1, 3 do
		local s = ms:advance(0.5)
		_say(string.format("[source][mock] t=%.2f p=(%.2f,%.2f,%.2f)",
			s.t, s.p[1], s.p[2], s.p[3]))
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

	_say(string.format("Recorder: %s | Replayer: %s (%.2f/%.2fs) | seed_pinned=%s",
		rec_state, rep_state, rep_elapsed, rep_duration, tostring(seed_pinned)))

	-- Selected ghost details (set by /ghost load).
	if mod._selected_ghost then
		local m = mod._selected_ghost.data.metadata.mission
		_say(string.format("  loaded ghost: %s seed=%s file=%s",
			m and m.name or "?",
			tostring(m and m.seed or "?"),
			mod._selected_ghost.filename))
	else
		_say("  loaded ghost: <none>")
	end

	-- Replayer interpolation snapshot (only when playing).
	local s = mod.replayer.last_state()
	if s then
		_say(string.format("  last_state: t=%.2f p=(%.1f,%.1f,%.1f) hp=%.2f",
			s.t, s.p[1], s.p[2], s.p[3], s.hp))
	end

	-- Recorder dump still goes to the log file only (mod:info).
	mod.recorder._dump()
end)

-- Dev-only: fake the engine's end-conditions outcome so a subsequent
-- "Leave Mission" (which triggers mission_cleanup) records the chosen
-- outcome instead of "aborted". Tests the full hook + outcome-mapping
-- path without needing a real 10-20 minute Damnation run.
-- Usage:
--   /ghost_fake_outcome won   -> recorder will save as outcome="completed"
--   /ghost_fake_outcome lost  -> recorder will save as outcome="failed"
--   /ghost_fake_outcome <anything else>  -> "aborted" (default behaviour)
mod:command("ghost_fake_outcome", "GhostRunner: fake mission outcome for fast testing", function(arg)
	arg = arg and arg:match("^%s*(.-)%s*$") or ""  -- trim
	if arg == "" then
		_say("[fake_outcome] usage: /ghost_fake_outcome won|lost|aborted")
		return
	end
	local gm_mgr = Managers.state and Managers.state.game_mode
	if not gm_mgr then
		_say("[fake_outcome] no game_mode manager (are you in a mission?)")
		return
	end
	gm_mgr._end_conditions_met_outcome = arg
	_say("[fake_outcome] set _end_conditions_met_outcome = " .. arg .. "; now Leave Mission to trigger save")
end)

-- Dev-only: force the recorder to finalize right now without going through
-- the engine's mission_cleanup. Bypasses the hook entirely; tests the
-- recorder.stop_and_save mapping in isolation.
-- Usage: /ghost_force_save won|lost|aborted
mod:command("ghost_force_save", "GhostRunner: force recorder.stop_and_save (bypasses hook)", function(arg)
	arg = arg and arg:match("^%s*(.-)%s*$") or ""
	if arg == "" then arg = "aborted" end
	mod.recorder.stop_and_save(arg, false)
	_say("[force_save] called stop_and_save with outcome=" .. arg)
end)

return mod
