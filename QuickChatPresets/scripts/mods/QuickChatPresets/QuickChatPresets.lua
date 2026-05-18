local mod = get_mod("QuickChatPresets")

local SPIKE_PRESETS = {
    {
        id = "spike_test",
        title = "Spike Test",
        message = "QuickChatPresets spike fired",
    },
}

mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc then
        print("[QuickChatPresets spike] quick_chat not present")
        return
    end

    -- After upstream loaded, _messages already populated. To get our
    -- presets to appear in upstream's panel, we'd have needed to inject
    -- BEFORE upstream's quick_chat_data.lua iterated _messages. That
    -- already happened. Confirm by checking whether our spike preset
    -- appears in upstream's dropdown options:
    local found = false
    for _, m in ipairs(qc._messages) do
        if m.id == "spike_test" then
            found = true
            break
        end
    end
    print(string.format("[QuickChatPresets spike] spike_test in quick_chat._messages BEFORE push: %s", tostring(found)))

    -- Push and re-check:
    qc._messages[#qc._messages + 1] = SPIKE_PRESETS[1]
    print(string.format("[QuickChatPresets spike] _messages count after push: %d", #qc._messages))
end

-- Attempt 1: hook by class. DMFMod is the metatable for mod instances.
-- If DMFMod is globally exposed, this might work:
local ok1, err1 = pcall(function()
    if DMFMod and DMFMod.io_dofile then
        mod:hook(DMFMod, "io_dofile", function(func, self, path)
            print(string.format("[QuickChatPresets spike] DMFMod hook fired for path=%s mod=%s", tostring(path), self and self:get_name() or "?"))
            if self and self:get_name() == "quick_chat" and path:match("chat_settings$") then
                return SPIKE_PRESETS
            end
            return func(self, path)
        end)
        print("[QuickChatPresets spike] DMFMod io_dofile hook registered")
    else
        print("[QuickChatPresets spike] DMFMod global not found or has no io_dofile")
    end
end)
if not ok1 then
    print("[QuickChatPresets spike] hook attempt 1 errored: " .. tostring(err1))
end
