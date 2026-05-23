return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`KeepYourHead` encountered an error loading the Darktide Mod Framework.")

		new_mod("KeepYourHead", {
			mod_script       = "KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead",
			mod_data         = "KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data",
			mod_localization = "KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization",
		})
	end,
	packages = {},
}
