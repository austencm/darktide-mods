local mod = get_mod("PrettyChat")

mod._colors = mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/colors")
mod._icons  = mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/icons")

-- ##################################################
-- Inline-token substitution
-- ##################################################
--
-- :name:       → glyph from mod._icons[name]
-- [color]…[/]  → {#color(R,G,B)}…<resume>
--
-- Closing tag's name is decorative — [/], [/red], [/anything] all close.
-- Unknown names and malformed tokens pass through as literal text.
--
-- Lua's %w is alphanumeric only and does NOT include underscore.
-- Identifier-like names (color/icon names with snake_case) need
-- [%w_]+ to match.

mod._substitute_icons = function(text)
    return (string.gsub(text, ":([%w_]+):", function(name)
        return mod._icons and mod._icons[name]
    end))
end

mod._substitute_colors = function(text, resume)
    return (string.gsub(text, "%[([%w_]+)%](.-)%[/[%w_]*%]", function(name, body)
        local rgba = mod._colors and mod._colors[name]
        if not rgba then
            return nil
        end
        return string.format("{#color(%d,%d,%d)}%s%s",
            rgba[2], rgba[3], rgba[4], body, resume or "{#reset()}")
    end))
end

-- Public API: other mods do
--   local pretty = get_mod("PrettyChat")
--   local text = pretty and pretty.substitute(raw, default_color_tag) or raw
mod.substitute = function(text, default_color_tag)
    text = mod._substitute_icons(text)
    text = mod._substitute_colors(text, default_color_tag or "{#reset()}")
    return text
end

-- wrap_color is convenient for callers building messages
-- programmatically; pulled out of the colors module so colors.lua stays
-- pure-data.
mod.wrap_color = function(text, color)
    if type(color) == "string" then
        color = mod._colors and mod._colors[color]
    end
    if not color or not text then
        return text
    end
    return string.format("{#color(%d,%d,%d)}%s{#reset()}",
        color[2], color[3], color[4], text)
end
