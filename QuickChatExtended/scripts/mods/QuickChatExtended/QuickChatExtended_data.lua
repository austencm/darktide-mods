local mod = get_mod("QuickChatExtended")

-- Event ids QuickChatExtended dispatches. Each generates an
-- "auto_<event>" dropdown widget bound to a quick_chat preset.
-- Add a new entry here to get a new dropdown widget; the dispatcher in
-- QuickChatExtended.lua must call _send("auto_<event>", ...) to match.
local events = {
    -- Combat events
    "tagged_daemonhost",
    "psyker_exploded_self",
    "psyker_exploded_teammate",
    -- Player-disabled events (3s rescue grace window, shared cooldown)
    "player_knocked_down",
    "player_ledge_hanging",
    "player_netted",
    "player_pounced",
    "player_consumed",
    "player_warp_grabbed",
    "player_vortex_grabbed",
    "player_disabled",      -- generic fallback when specific is "none"
    "player_catapulted",    -- explosion-flight, supports [airtime] / [distance]
}

-- Build preset dropdown options from quick_chat's _messages table at our
-- mod-load time. quick_chat loads first (hard dep), so _messages is
-- populated. QuickChatPresets may have already pushed into it.
local function _preset_dropdown_options()
    -- localize = false on the options table tells DMF the `text` fields are
    -- already display-ready strings, not locale keys. Without it, DMF runs
    -- mod:localize on each text and wraps unknown keys in "<...>" markers.
    local options = {
        localize = false,
        { text = "none", value = "none" },
    }
    local qc = get_mod("quick_chat")
    if not qc or not qc._messages then
        return options
    end
    for _, setting in ipairs(qc._messages) do
        options[#options + 1] = { text = setting.title or setting.id, value = setting.id }
    end
    return options
end

local function _event_widgets()
    local widgets = {}
    for _, event in ipairs(events) do
        local id = "auto_" .. event
        widgets[#widgets + 1] = {
            setting_id = id,
            type = "dropdown",
            default_value = "none",
            tooltip = id .. "_desc",
            options = _preset_dropdown_options(),
        }
    end
    return widgets
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "events",
                type = "group",
                sub_widgets = _event_widgets(),
            },
            {
                setting_id = "debug",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_debug_mode",
                        type = "checkbox",
                        default_value = false,
                        tooltip = "enable_debug_mode_desc",
                    },
                },
            },
        },
    },
}
