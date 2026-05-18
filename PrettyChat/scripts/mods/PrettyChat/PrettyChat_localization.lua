return {
    mod_name = { en = "PrettyChat" },
    mod_description = { en = "Color and icon shortcodes for typed chat, with a live preview row." },
    enable_check_mode = { en = "Check mode (echo locally, don't send)" },
    enable_check_mode_desc = { en = "When on, typed messages are echoed back to you without being sent"
        .. " — useful for previewing markup without spamming the channel." },
    default_chat_color = { en = "Default chat color" },
    default_chat_color_desc = { en = "If set, all of your typed messages get wrapped in this color"
        .. " unless overridden by an inline [color]…[/] tag." },
    cycle_chat_color_hotkey = { en = "Cycle default chat color (forward)" },
    cycle_chat_color_hotkey_desc = { en = "Cycles through none → all palette colors alphabetically." },
    cycle_chat_color_backward_hotkey = { en = "Cycle default chat color (backward)" },
    cycle_chat_color_backward_hotkey_desc = { en = "Cycles backwards through the same order." },
}
