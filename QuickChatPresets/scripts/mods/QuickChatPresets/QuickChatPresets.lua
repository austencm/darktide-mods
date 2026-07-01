local mod = get_mod("QuickChatPresets")

local function _load_presets()
    return mod:io_dofile("QuickChatPresets/scripts/mods/QuickChatPresets/presets")
end

-- A+ path: hook quick_chat's io_dofile call so when it loads its
-- chat_settings, it receives our preset list instead. Must be registered
-- before quick_chat's localization runs (ensured by `load_before` in
-- QuickChatPresets.mod under AML; vanilla loader honors mod_load_order.txt).
if DMFMod and DMFMod.io_dofile then
    mod:hook(DMFMod, "io_dofile", function(func, self, path)
        if self and self.get_name and self:get_name() == "quick_chat"
           and type(path) == "string" and path:match("chat_settings$") then
            return _load_presets()
        end
        return func(self, path)
    end)
end
