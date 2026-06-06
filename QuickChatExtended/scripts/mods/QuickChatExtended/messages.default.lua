--[[
    messages.default.lua — Default chat presets shipped with QuickChatExtended.

    Loaded by QuickChatExtended_data.lua at mod-data eval time and appended
    to quick_chat._messages so the new event dropdowns have meaningful
    bindings out of the box.

    To customize without losing your edits on QCE updates, copy this file
    to messages.local.lua (gitignored) and edit there. With messages.local
    present, entries overwrite quick_chat's matching ids (user-wins);
    without it, this file appends politely (skips existing ids).

    Defaults intentionally avoid markup so they render correctly without
    PrettyChat installed. Add your own [color]…[/] / :icon: flair in
    messages.local.lua.

    Catapulted preset supports [airtime] (e.g. "2.4") and [distance]
    (e.g. "18") placeholders, substituted from the catapult dispatch.
]]

return {
    -- ##################################################
    -- Combat events
    -- ##################################################

    {
        id = "qce_daemonhost",
        title = "Daemonhost!",
        message = {
            "Daemonhost!",
            "I sense a Daemonhost!",
            "Daemonhost ahead!",
            "Stay alert…a Daemonhost!",
            "Throne…a Daemonhost!",
            "Oh hel…it's a Daemonhost!",
        },
    },
    {
        id = "qce_psyker_exploded_self",
        title = "Psyker exploded (self)",
        message = {
            "MY HEAD",
            "Oof.",
            "Brain incident.",
        },
    },
    {
        id = "qce_psyker_exploded_teammate",
        title = "Psyker exploded (teammate)",
        message = "[name]'s head popped!",
    },

    -- ##################################################
    -- Player disabled (5s rescue grace before fire)
    -- ##################################################

    {
        id = "qce_knocked_down",
        title = "Knocked down",
        message = {
            "I'm down!",
            "Help me up!",
            "Need a pickup.",
        },
    },
    {
        id = "qce_ledge_hanging",
        title = "Hanging from ledge",
        message = {
            "Hanging from a ledge!",
            "Help! I'm slipping!",
            "Don't let me fall!",
        },
    },
    {
        id = "qce_netted",
        title = "Netted",
        message = {
            "Trapper got me!",
            "Netted! Cut me out!",
        },
    },
    {
        id = "qce_pounced",
        title = "Pounced",
        message = {
            "Hound on me!",
            "Pounced! Help!",
            "Get this dog off!",
        },
    },
    {
        id = "qce_consumed",
        title = "Inside Beast of Nurgle",
        message = {
            "*sad digesting noises*",
            "I'm being eaten!",
        },
    },
    {
        id = "qce_warp_grabbed",
        title = "Grabbed by Daemonhost",
        message = {
            "I'm…slipping away…",
        },
    },
    {
        id = "qce_disabled",
        title = "Need help (generic)",
        message = "I need help!",
    },

    -- ##################################################
    -- Catapulted by explosion
    -- ##################################################

    {
        id = "qce_catapulted",
        title = "Catapulted!",
        message = {
            "Distance: [distance]. Airtime: [airtime]s.",
        },
    },
}
