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

mod:command("ghost_test_fs", "GhostRunner: verify filesystem helpers", function()
	mod:info("[fs] runs_root: " .. tostring(mod.fs.runs_root))
	mod:info("[fs] runs_path('foo.run'): " .. tostring(mod.fs.runs_path("foo.run")))
	mod:info("[fs] index_path: " .. tostring(mod.fs.index_path()))
	mod:info("[fs] list_run_files: count=" .. tostring(#mod.fs.list_run_files()))
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
	mod:info("[runfile] wrote " .. filename)

	local data = mod.run_file.read(filename)
	mod:info(string.format("[runfile] read: %d frames, outcome=%s",
		#data.frames, data.footer.outcome))

	-- Append to index, read back.
	mod.run_file.append_to_index(filename, data)
	local idx = mod.run_file.read_index()
	mod:info(string.format("[runfile] index has %d entries", #idx.runs))

	-- Rebuild from scan and verify equivalence.
	mod.run_file.rebuild_index()
	local rebuilt = mod.run_file.read_index()
	mod:info(string.format("[runfile] rebuild: %d entries", #rebuilt.runs))
end)

return mod
