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

-- ##################################################
-- Typed-chat wrapper
-- ##################################################
--
-- The chat element strips {#…} tags from typed text before sending
-- (constant_element_chat.lua, gsub of "{#.-}"), so we can't pre-inject
-- markup into the input field. Instead we wrap
-- Managers.chat.send_channel_message for the duration of the input
-- handler and substitute at the manager boundary.

local function _build_default_color_tag()
    local color_name = mod:get("default_chat_color")
    if not color_name or color_name == "none" or not mod._colors then
        return ""
    end
    local rgba = mod._colors[color_name]
    if not rgba then
        return ""
    end
    return string.format("{#color(%d,%d,%d)}", rgba[2], rgba[3], rgba[4])
end

local function _wrap_typed_chat(func, self, ...)
    local default_color_tag = _build_default_color_tag()
    local check_mode = mod:get("enable_check_mode")

    -- Psykhanium / Meat Grinder: no Vivox session, so
    -- ConstantElementChat._handle_active_chat_input gates Enter on
    --   can_send_message = self._selected_channel_handle and #input_text > 0
    -- When check mode is on we don't actually need a real channel — inject
    -- a sentinel for the duration of the handler so the engine attempts the
    -- send; our manager-level wrap intercepts with mod:echo.
    local restored_handle = false
    if check_mode and not self._selected_channel_handle then
        self._selected_channel_handle = "PrettyChat_check_mode"
        restored_handle = true
    end

    local chat_mgr = Managers.chat
    local orig = chat_mgr.send_channel_message
    chat_mgr.send_channel_message = function(mgr, handle, text, ...)
        text = mod._substitute_icons(text)
        text = mod._substitute_colors(text,
            default_color_tag ~= "" and default_color_tag or "{#reset()}")
        if default_color_tag ~= "" then
            text = default_color_tag .. text .. "{#reset()}"
        end
        if check_mode then
            mod:echo(text)
            return
        end
        return orig(mgr, handle, text, ...)
    end
    local ok, err = pcall(func, self, ...)
    chat_mgr.send_channel_message = orig
    if restored_handle then
        self._selected_channel_handle = nil
    end
    if not ok then
        error(err)
    end
end

mod:hook("ConstantElementChat", "_handle_active_chat_input", _wrap_typed_chat)
mod:hook("ConstantElementChat", "_handle_console_input", _wrap_typed_chat)
