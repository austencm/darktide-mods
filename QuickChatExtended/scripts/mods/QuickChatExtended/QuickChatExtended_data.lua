local mod = get_mod("QuickChatExtended")

-- ##################################################
-- Default messages append
-- ##################################################
--
-- QCE ships default presets for the events it dispatches (messages.default.lua,
-- tracked). Users can customize without losing edits on QCE updates by
-- creating messages.local.lua next to it.
--
-- Conflict policy:
--   - messages.local.lua exists -> user-wins on id conflict with
--     quick_chat._messages (and overlays QCP if present)
--   - only messages.default.lua -> polite append (skip ids already in
--     quick_chat._messages)
--
-- Runs as a side effect at mod_data eval time so the dropdown widget
-- options below see the newly-merged messages. Putting it in
-- on_all_mods_loaded would be too late — DMF would have already built
-- the widget data by then.

local function _user_messages_exist()
    local _io = Mods and Mods.lua and Mods.lua.io
    if not (_io and _io.open) then return false end
    local f = _io.open(
        "./../mods/QuickChatExtended/scripts/mods/QuickChatExtended/messages.local.lua", "r")
    if f then f:close(); return true end
    return false
end

local function _merge_messages()
    local qc = get_mod("quick_chat")
    if not qc or not qc._messages then return end

    local is_user_customized = _user_messages_exist()
    local module_path = is_user_customized
        and "QuickChatExtended/scripts/mods/QuickChatExtended/messages.local"
        or "QuickChatExtended/scripts/mods/QuickChatExtended/messages.default"
    local messages = mod:io_dofile(module_path)
    if not messages then return end

    for _, preset in ipairs(messages) do
        local existing_idx
        for i, existing in ipairs(qc._messages) do
            if existing.id == preset.id then
                existing_idx = i
                break
            end
        end
        if existing_idx then
            if is_user_customized then
                qc._messages[existing_idx] = preset  -- user-wins
            end
            -- else: leave existing entry alone
        else
            qc._messages[#qc._messages + 1] = preset
        end
    end
end

_merge_messages()

-- Event ids QuickChatExtended dispatches. Each generates an
-- "auto_<event>" dropdown widget bound to a quick_chat preset.
-- Add a new entry here to get a new dropdown widget; the dispatcher in
-- QuickChatExtended.lua must call _send("auto_<event>", ...) to match.
local events = {
    -- Combat events
    "tagged_daemonhost",
    "psyker_exploded_self",
    "psyker_exploded_teammate",
    -- Player-disabled events (5s rescue grace window, shared cooldown)
    "player_knocked_down",
    "player_ledge_hanging",
    "player_netted",
    "player_pounced",
    "player_consumed",
    "player_warp_grabbed",
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
