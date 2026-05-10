local mod = get_mod("quick_chat")

local _get_message_dropdown = function()
    local messages = mod._messages
    local options = {}

    for _, setting in pairs(messages) do
        local id = setting.id

        options[#options + 1] = { text = id, value = id }
    end

    table.insert(options, 1, { text = "none", value = "none" })

    return options
end

local _get_color_dropdown = function()
    local colors = mod._colors
    local options = { { text = "none", value = "none" } }

    if not colors then
        return options
    end

    local names = {}
    for name, _ in pairs(colors) do
        names[#names + 1] = name
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local rgba = colors[name]
        local display = name
        if rgba then
            display = string.format("{#color(%d,%d,%d)}%s{#reset()}",
                rgba[2], rgba[3], rgba[4], name)
        end
        options[#options + 1] = { text = display, value = name }
    end

    return options
end

local _get_message_widgets = function()
    local messages = mod._messages
    local widgets = {}

    for _, setting in ipairs(messages) do
        local id = setting.id

        widgets[#widgets + 1] = {
            setting_id = id,
            type = "keybind",
            default_value = {},
            keybind_trigger = "pressed",
            keybind_type = "function_call",
            function_name = "trigger_" .. id,
            tooltip = "tooltip_" .. id
        }
    end

    return widgets
end

local _get_event_widgets = function()
    local events = {}
    for _, event in ipairs(mod._events) do
        local id = "auto_" .. event
        events[#events + 1] = {
            setting_id = id,
            type = "dropdown",
            default_value = "none",
            tooltip = id .. "_desc",
            options = _get_message_dropdown()
        }
    end

    return events
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "enable_check_mode",
                type = "checkbox",
                default_value = false,
                tooltip = "check_mode_desc",
            },
            {
                setting_id = "enable_in_hub",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "enable_slot_color",
                type = "checkbox",
                default_value = false,
                tooltip = "enable_slot_color_desc",
            },
            {
                setting_id = "default_chat_color",
                type = "dropdown",
                default_value = "none",
                tooltip = "default_chat_color_desc",
                options = _get_color_dropdown(),
            },
            {
                setting_id = "cycle_chat_color_hotkey",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "trigger_cycle_chat_color",
                tooltip = "cycle_chat_color_hotkey_desc",
            },
            {
                setting_id = "cycle_chat_color_backward_hotkey",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "trigger_cycle_chat_color_backward",
                tooltip = "cycle_chat_color_backward_hotkey_desc",
            },
            {
                setting_id = "events",
                type = "group",
                sub_widgets = _get_event_widgets()
            },
            {
                setting_id = "hotkeys",
                type = "group",
                sub_widgets = _get_message_widgets()
            },
            {
                setting_id = "debug_mode",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_debug_mode",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "probe_icons_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "trigger_probe_icons",
                        tooltip = "probe_icons_hotkey_desc",
                    },
                    {
                        setting_id = "list_icons_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "trigger_list_icons",
                        tooltip = "list_icons_hotkey_desc",
                    },
                    {
                        setting_id = "list_colors_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "trigger_list_colors",
                        tooltip = "list_colors_hotkey_desc",
                    },
                },
            },
        }
    }
}