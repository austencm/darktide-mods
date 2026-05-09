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

mod:hook(CLASS.GameModeManager, "on_player_unit_spawn",
	function(func, self, player, player_unit, is_respawn)
		func(self, player, player_unit, is_respawn)

		if is_respawn then return end

		-- Identity: must be the local player.
		local local_player = Managers.player and Managers.player:local_player(1)
		if not local_player or local_player:player_unit() ~= player_unit then
			return
		end

		-- Only in solo sessions.
		if not mod.SoloPlay.is_soloplay() then return end

		-- TODO Task 9: also gate on mod:get("record_runs"). For now always record.
		mod.recorder.start(player, player_unit)
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
				func(self, on_shutdown)
			end)
	end)

mod.update = function(dt)
	-- Outer pcall: any one tick subsystem throwing should not silently kill
	-- the whole frame loop for the others. Future tasks add replayer.tick
	-- and renderer.tick alongside; this insulates them.
	local ok, err = pcall(mod.recorder.tick, dt)
	if not ok then mod:warning("recorder.tick error: " .. tostring(err)) end
end

-- Dev-test helper: writes to the DMF CommandWindow (via global print, which DMF
-- hooks) AND the in-game chat overlay (via mod:echo). Removed at Task 15
-- alongside the test commands themselves.
local function _say(msg)
	print(msg)
	mod:echo(msg)
end

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
	_say("recorder state: " .. mod.recorder.state())
	mod.recorder._dump()
end)

return mod
