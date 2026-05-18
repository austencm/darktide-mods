return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`QuickChatPresets` encountered an error loading the Darktide Mod Framework.")

        new_mod("QuickChatPresets", {
            mod_script       = "QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets",
            mod_data         = "QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_data",
            mod_localization = "QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_localization",
        })
    end,
    packages = {},
}
