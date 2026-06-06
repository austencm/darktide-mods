return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`PrettyChat` encountered an error loading the Darktide Mod Framework.")

        new_mod("PrettyChat", {
            mod_script       = "PrettyChat/scripts/mods/PrettyChat/PrettyChat",
            mod_data         = "PrettyChat/scripts/mods/PrettyChat/PrettyChat_data",
            mod_localization = "PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization",
        })
    end,
    packages = {},
}
