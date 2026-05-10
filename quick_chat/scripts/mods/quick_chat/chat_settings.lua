--[[
    You can add your custom chat messages by editing this file.
    Each setting must follow the template below.

    {
        id = "<id>",
        title = "<title>",
        message = "<message>"
    },

    id      -- Unique string that does not duplicate others. Use "_" (underscore) instead of " " (space) .
    title   -- Text that appears on the option menu.
    message -- Text that you want to send. If you use a table (array), a message is randomly selected from it.

    You can use "[name]" as a place holder.
    It will be replaced by the character name of the player who triggered the event.

    Darktide in-game icon glyphs are available via the `icons` table below.
    Example: icons.psyker .. " MY HEAD"  ->  renders the Psyker class icon in chat.
    See quick_chat_icons.lua for the full list.

    Chat colors:
        color("MY HEAD", "purple")             -- name lookup
        color("danger",  {255, 220, 50, 50})   -- inline {a, r, g, b}
    See quick_chat_colors.lua for the full palette.
]]

local mod = get_mod("quick_chat")
local icons = mod:io_dofile("quick_chat/scripts/mods/quick_chat/quick_chat_icons")
mod._icons = icons
local colors = mod:io_dofile("quick_chat/scripts/mods/quick_chat/quick_chat_colors")
mod._colors = colors
local color = mod.wrap_color

-- The following settings are just examples. Feel free to remove or edit them.
return {
    {
        id = "psyker_explode_self",
        title = "Psyker explode (self)",
        message = {
            "It has been [red]0[/] days without a brain incident.",
            "MY HEAD",
        }
    },
    {
        id = "alert_daemonhost",
        title = "Daemonhost",
        message = {
            "[lime]Daemonhost![/]",
            "[lime]I sense a Daemonhost![/]",
            "[lime]I think I hear a Daemonhost?[/]",
            "[lime]Oh hel… It's a Daemonhost![/]",
            "[lime]Stay alert! A Daemonhost![/]",
            "[lime]Throne… It's a fragging Daemonhost![/]",
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
        message = ":star: Medi-pack deployed!"
    },
    {
        id = "deploy_med_others",
        title = "Deploy Med (others)",
        message = "[name] deployed a medi-pack"
    },
    {
        id = "deploy_ammo_self",
        title = "Deploy Ammo (self)",
        message = ":bolt: Ammo crate deployed!"
    },
    {
        id = "deploy_ammo_others",
        title = "Deploy Ammo (others)",
        message = "[name] deployed an ammo crate"
    },
    {
        id = "psyker_explode_count",
        title = "Psyker Explode Count",
        message = "This psyker's head has exploded " .. icons.digit_1 .. "" .. icons.digit_9 .. " times."
    },
}
