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

-- The following settings are just examples. Feel free to remove or edit them.
return {
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
        id = "alert_need_help",
        title = "Need Help",
        message = "I need help!"
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
        id = "greeting_player_joined",
        title = "Greeting",
        message = "Hi [name]"
    },
    {
        id = "response_yes",
        title = "Yes",
        message = "Yes",
    },
    {
        id = "response_no",
        title = "No",
        message = "No"
    },
    {
        id = "response_sorry",
        title = "Sorry",
        message = "Sorry"
    },
    {
        id = "deploy_med_self",
        title = "Deploy Med (self)",
        message = ":check_badge: Medi-pack deployed!"
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
}
