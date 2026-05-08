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

return mod
