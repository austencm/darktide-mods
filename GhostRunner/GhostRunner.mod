return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`GhostRunner` encountered an error loading the Darktide Mod Framework.")

		new_mod("GhostRunner", {
			mod_script       = "GhostRunner/scripts/mods/GhostRunner/GhostRunner",
			mod_data         = "GhostRunner/scripts/mods/GhostRunner/GhostRunner_data",
			mod_localization = "GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization",
		})
	end,
	packages = {},
	load_after = { "SoloPlay" },
}
