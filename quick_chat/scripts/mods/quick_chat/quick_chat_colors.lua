--[[
    Curated chat colors for Darktide's chat panel.

    The chat panel renders against a dark background, so colors in this
    palette are tuned for legibility on dark — bright, saturated, with no
    very-dark entries. Names are short and generic (red, blue, purple, …)
    so messages read naturally: wrap_color("Daemonhost!", "purple").

    Format: {a, r, g, b} — matches Darktide's UISettings.player_slot_colors
    convention (indices 2,3,4 are RGB) so these tables are drop-in
    compatible with the existing slot-color path in
    quick_chat.lua/_replace_place_holder. The chat color tag only uses RGB;
    the alpha component is ignored by chat but kept for slot-color reuse.

    Usage:
        local mod = get_mod("quick_chat")

        -- Get a color value:
        local c = mod._colors.red

        -- Wrap a string with chat color tags:
        local s = mod.wrap_color("MY HEAD", "purple")
        local s = mod.wrap_color("danger", {255, 220, 50, 50})  -- inline color

        -- Use directly in chat_settings.lua message strings:
        message = mod.wrap_color("Daemonhost!", "red"),
]]

local mod = get_mod("quick_chat")

local colors = {
    white   = {255, 255, 255, 255},
    gold    = {255, 255, 200,  80},
    cyan    = {255, 130, 220, 240},
    red     = {255, 220,  50,  50},
    crimson = {255, 180,  30,  30},
    amber   = {255, 255, 170,  60},
    purple  = {255, 180, 100, 220},
    lime    = {255, 130, 200,  70},
    blue    = {255,  90, 140, 220},
    brass   = {255, 200, 130,  50},
    pink    = {255, 230, 110, 210},
    green   = {255, 110, 220, 110},
}

mod.wrap_color = function(text, color)
    if type(color) == "string" then
        color = colors[color]
    end
    if not color or not text then
        return text
    end
    return string.format("{#color(%d,%d,%d)}%s{#reset()}",
        color[2], color[3], color[4], text)
end

return colors
