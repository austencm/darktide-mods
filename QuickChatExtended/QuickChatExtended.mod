return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`QuickChatExtended` encountered an error loading the Darktide Mod Framework.")

        new_mod("QuickChatExtended", {
            mod_script       = "QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended",
            mod_data         = "QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data",
            mod_localization = "QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization",
        })
    end,
    packages = {},
}
