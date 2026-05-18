local mod = get_mod("PrettyChat")

-- Loaded once at file-eval time. Safe — PrettyChat.lua sets _colors before
-- PrettyChat_data.lua is read by DMF? No: DMF reads mod_data BEFORE
-- mod_script in some cases. To be safe, load colors here too — it's a pure
-- io_dofile and cheap to do twice.
local colors = mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/colors")

local function _color_dropdown_options()
    local options = { { text = "none", value = "none" } }
    local names = {}
    for name, _ in pairs(colors) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local rgba = colors[name]
        local display = string.format("{#color(%d,%d,%d)}%s{#reset()}",
            rgba[2], rgba[3], rgba[4], name)
        options[#options + 1] = { text = display, value = name }
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
                setting_id = "enable_check_mode",
                type = "checkbox",
                default_value = false,
                tooltip = "enable_check_mode_desc",
            },
            {
                setting_id = "default_chat_color",
                type = "dropdown",
                default_value = "none",
                tooltip = "default_chat_color_desc",
                options = _color_dropdown_options(),
            },
        },
    },
}
