 --[[
    presets.lua — Personal quick_chat preset list.

    This table is returned by QuickChatPresets and injected into quick_chat
    via an io_dofile hook (A+ path). Presets appear natively in quick_chat's
    options panel — event dropdowns, keybind list — exactly as if this file
    were quick_chat's own chat_settings.

    Markup support (processed by PrettyChat soft-dep integration):
      :icon_name:           → Darktide PUA glyph (see PrettyChat/icons.lua)
      [color]text[/]        → named color from PrettyChat/colors.lua
      [r,g,b]text[/]        → inline ARGB color
      [name]                → replaced with triggering player's character name
]]

return {
    {
        id = "psyker_explode_self",
        title = "Psyker explode (self)",
        message = {
            "It has been [red]0[/] days without a brain incident.",
            "[pink]The voices…[/]",
        }
    },
    {
        id = "alert_daemonhost",
        title = "Daemonhost",
        message = {
            "[lime]Daemonhost![/]",
            "[lime]I sense a Daemonhost![/]",
            "[lime]I think I hear a Daemonhost?[/]",
            "[lime]Oh hel…it's a Daemonhost![/]",
            "[lime]Stay alert! A Daemonhost![/]",
            "[lime]Throne…it's a fragging Daemonhost![/]",
        }
    },
    {
        id = "alert_stay_together",
        title = "Stay Together",
        message = "Close up! Stay together!"
    },
    {
        id = "greeting_good_game",
        title = "Good Game",
        message = "gg"
    },
    {
        id = "greeting_good_game_psyker",
        title = "Good Game (psyker)",
        message = "gg :psyker_simple:"
    },
    {
        id = "greeting_player_joined",
        title = "Greeting",
        message = "Hi [name]"
    },
    {
        id = "response_sorry",
        title = "Sorry",
        message = "Sorry"
    },
    {
        id = "deploy_med_self",
        title = "Deploy Med (self)",
        message = ":xbox_dpad: Medi-pack deployed!"
    },
    {
        id = "deploy_med_others",
        title = "Deploy Med (others)",
        message = "[name] deployed a medi-pack"
    },
    {
        id = "deploy_ammo_self",
        title = "Deploy Ammo (self)",
        message = ":melkbucks: Ammo crate deployed!"
    },
    {
        id = "deploy_ammo_others",
        title = "Deploy Ammo (others)",
        message = "[name] deployed an ammo crate"
    },
    {
        id = "psyker_explode_count",
        title = "Psyker Explode Count",
        message = "This psyker's head has exploded :digit_1::digit_9: times."
    },
}
