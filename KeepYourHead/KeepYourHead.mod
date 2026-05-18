return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`WitchLeash` encountered an error loading the Darktide Mod Framework.")

		new_mod("WitchLeash", {
			mod_script       = "WitchLeash/scripts/mods/WitchLeash/WitchLeash",
			mod_data         = "WitchLeash/scripts/mods/WitchLeash/WitchLeash_data",
			mod_localization = "WitchLeash/scripts/mods/WitchLeash/WitchLeash_localization",
		})
	end,
	packages = {},
}
