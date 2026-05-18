local mod = get_mod("QuickChatExtended")

-- Build preset dropdown options from quick_chat's _messages table at our
-- mod-load time. quick_chat loads first (hard dep), so _messages is
-- populated. QuickChatPresets may have already pushed into it.
local function _preset_dropdown_options()
    local options = { { text = "none", value = "none" } }
    local qc = get_mod("quick_chat")
    if not qc or not qc._messages then
        return options
    end
    for _, setting in ipairs(qc._messages) do
        options[#options + 1] = { text = setting.id, value = setting.id }
    end
    return options
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "auto_tagged_daemonhost",
                type = "dropdown",
                default_value = "none",
                tooltip = "auto_tagged_daemonhost_desc",
                options = _preset_dropdown_options(),
            },
            {
                setting_id = "auto_psyker_exploded_self",
                type = "dropdown",
                default_value = "none",
                tooltip = "auto_psyker_exploded_self_desc",
                options = _preset_dropdown_options(),
            },
            {
                setting_id = "auto_psyker_exploded_teammate",
                type = "dropdown",
                default_value = "none",
                tooltip = "auto_psyker_exploded_teammate_desc",
                options = _preset_dropdown_options(),
            },
            {
                setting_id = "enable_slot_color",
                type = "checkbox",
                default_value = false,
                tooltip = "enable_slot_color_desc",
            },
        },
    },
}
