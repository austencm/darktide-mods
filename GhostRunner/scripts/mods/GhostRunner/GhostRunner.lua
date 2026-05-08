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

mod:command("ghost_test_fs", "GhostRunner: verify filesystem helpers", function()
	mod:info("[fs] runs_root: " .. tostring(mod.fs.runs_root))
	mod:info("[fs] runs_path('foo.run'): " .. tostring(mod.fs.runs_path("foo.run")))
	mod:info("[fs] index_path: " .. tostring(mod.fs.index_path()))
	mod:info("[fs] list_run_files: count=" .. tostring(#mod.fs.list_run_files()))
end)

return mod
