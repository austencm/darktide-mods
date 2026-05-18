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

-- ##################################################
-- Live preview HUD
-- ##################################################
--
-- Renders a single text row above the chat input showing the
-- fully-substituted preview of what's typed. Style and positioning live in
-- HudElementChatPreview.lua; this section computes the preview text and
-- pushes it via the registered HUD element.

local function _build_preview_text(raw_text)
    local default_color_tag = _build_default_color_tag()
    if not raw_text or #raw_text == 0 then
        if default_color_tag ~= "" then
            return default_color_tag .. "(preview){#reset()}"
        end
        return "(preview)"
    end
    local text = mod._substitute_icons(raw_text)
    text = mod._substitute_colors(text,
        default_color_tag ~= "" and default_color_tag or "{#reset()}")
    if default_color_tag ~= "" then
        text = default_color_tag .. text .. "{#reset()}"
    end
    return text
end

-- DMF auto-cleanup only fires on UIHud:destroy, so on a Ctrl+Shift+R hot
-- reload the previous injection is still in _player_hud._elements.
-- Re-registering hits "element_already_exists" once per frame — which
-- floods the console buffer and triggers the engine's 16s deadlock
-- watchdog. Clear manually first.
local dmf = get_mod("DMF")
if dmf and dmf.remove_injected_hud_elements then
    pcall(dmf.remove_injected_hud_elements, mod)
end

mod:register_hud_element({
    class_name = "HudElementChatPreview",
    filename = "PrettyChat/scripts/mods/PrettyChat/HudElementChatPreview",
    use_hud_scale = false,
    visibility_groups = { "alive", "dead" },
})

-- Capture the chat element ref on each per-frame _handle_input call (not
-- on init — chat is constructed during game boot before this mod's hooks
-- register, so an init hook would never fire).
mod._chat_element_ref = nil
mod:hook_safe("ConstantElementChat", "_handle_input", function(self)
    mod._chat_element_ref = self
end)

mod.update = function(dt)
    local chat_element = mod._chat_element_ref
    if not chat_element then return end

    local ui_manager = Managers.ui
    local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
    if not hud then return end
    local hud_element = hud:element("HudElementChatPreview")
    if not hud_element or not hud_element.set_active then return end

    local input_widget = chat_element._input_field_widget
    local is_writing = input_widget
        and input_widget.content
        and input_widget.content.is_writing
    if not is_writing then
        hud_element:set_active(false)
        return
    end

    local raw_text = input_widget.content.input_text
    if not raw_text or #raw_text == 0 then
        hud_element:set_active(false)
        return
    end

    hud_element:set_text(_build_preview_text(raw_text))
    hud_element:set_active(true)
end

-- ##################################################
-- Color cycle hotkey
-- ##################################################
--
-- Cycles default_chat_color through "none" + every key in mod._colors
-- (alphabetical). The preview line reflects the new value next frame.

mod._color_cycle = nil

local function _build_color_cycle()
    local order = { "none" }
    if mod._colors then
        local names = {}
        for name, _ in pairs(mod._colors) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            order[#order + 1] = name
        end
    end
    return order
end

local function _cycle_color(direction)
    if not mod._color_cycle then
        mod._color_cycle = _build_color_cycle()
    end
    local cycle = mod._color_cycle
    local current = mod:get("default_chat_color") or "none"
    local idx = 1
    for i, name in ipairs(cycle) do
        if name == current then
            idx = i
            break
        end
    end
    -- ((idx - 1 + direction) mod N) + 1 wraps cleanly in both directions.
    local next_idx = ((idx - 1 + direction) % #cycle) + 1
    mod:set("default_chat_color", cycle[next_idx])
end

mod.trigger_cycle_chat_color = function() _cycle_color(1) end
mod.trigger_cycle_chat_color_backward = function() _cycle_color(-1) end
