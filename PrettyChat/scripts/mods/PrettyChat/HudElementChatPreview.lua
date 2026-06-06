local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIRenderer = require("scripts/managers/ui/ui_renderer")

-- Anchored just BELOW the chat window. The chat constant element draws
-- on top of HUD-element rendering, so positioning the preview inside
-- chat_window's rect would put it behind the chat background. Below the
-- input field is the natural spot — visually attached to where you're
-- typing, and outside chat's draw rect so it stays visible.
--
-- Coordinates derived from ConstantElementChatSettings:
--   chat_window_offset = {50, -490, 0}, vertical_alignment = "bottom"
--   chat_window_size   = {500, 250}
--   input_field_height = 40, input_field offset_y = 45
-- Empirically (input_field world_position[2]=595, height=40) →
-- chat_window bottom at y=640, top at y=390 in design-res 1080.
-- Preview sits at y=645 — 5px below chat_window's bottom edge.
local PREVIEW_SIZE = { 484, 22 }
local PREVIEW_POSITION = { 56, 640, 5 }

local ui_definitions = {
    scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,
        chat_preview_area = {
            parent               = "screen",
            horizontal_alignment = "left",
            vertical_alignment   = "top",
            size                 = PREVIEW_SIZE,
            position             = PREVIEW_POSITION,
        },
    },
    widget_definitions = {
        preview_text = UIWidget.create_definition({
            {
                -- 50% black background for readability over the game world.
                -- Drawn first so the text pass below renders on top.
                -- size_addition is recomputed per frame from the rendered
                -- text width in HudElementChatPreview.update — the values
                -- here are the static initial state (full width + a touch
                -- of horizontal padding).
                pass_type = "rect",
                style_id  = "background",
                style     = {
                    color         = { 128, 0, 0, 0 },  -- {a, r, g, b}
                    size_addition = { 16, 0 },
                    offset        = { -6, 0, 0 },
                },
            },
            {
                pass_type = "text",
                style_id  = "text",
                value_id  = "text",
                value     = "",
                style     = {
                    font_size                 = 15,
                    -- machine_medium works in HUD context;
                    -- proxima_nova_bold_masked is not loaded for HUD packages.
                    font_type                 = "machine_medium",
                    text_horizontal_alignment = "left",
                    text_vertical_alignment   = "center",
                    horizontal_alignment      = "left",
                    vertical_alignment        = "center",
                    -- Light off-white at ~70% alpha for the empty-input
                    -- placeholder case. When the live preview includes
                    -- `{#color(R,G,B)}` markup (always, when default_chat_color
                    -- or inline color spans are in use), the markup overrides
                    -- this RGB at render time; alpha carries through to give
                    -- the "preview" feel.
                    text_color                = { 178, 220, 220, 220 },
                    drop_shadow               = true,
                },
            },
        }, "chat_preview_area"),
    },
}

local HudElementChatPreview = class("HudElementChatPreview", "HudElementBase")

HudElementChatPreview.init = function(self, parent, draw_layer, start_scale)
    HudElementChatPreview.super.init(self, parent, draw_layer, start_scale, ui_definitions)
    local widget = self._widgets_by_name and self._widgets_by_name.preview_text
    if widget then
        widget.visible = false
    end
end

HudElementChatPreview.set_active = function(self, active)
    local widget = self._widgets_by_name and self._widgets_by_name.preview_text
    if not widget then return end
    widget.visible = active and true or false
end

HudElementChatPreview.set_text = function(self, text)
    local widget = self._widgets_by_name and self._widgets_by_name.preview_text
    if not widget then return end
    widget.content.text = text or ""
end

-- Per-frame: shrink-wrap the background rect to the rendered text width.
-- The text pass's width measurement parses {#color(...)} markup, so the
-- returned width is the visual width of the rendered glyphs (markup chars
-- excluded). size_addition is relative to the widget's base size — we
-- subtract that out and add the desired horizontal padding.
local HORIZONTAL_PADDING = 8

HudElementChatPreview.update = function(self, dt, t, ui_renderer, render_settings, input_service)
    local widget = self._widgets_by_name and self._widgets_by_name.preview_text
    if not widget or not widget.visible then return end

    local text = widget.content.text
    if not text or text == "" then return end

    local text_style = widget.style.text
    local rect_style = widget.style.background
    if not text_style or not rect_style then return end

    local text_width = UIRenderer.text_size(ui_renderer, text,
        text_style.font_type, text_style.font_size)
    local target_total = text_width + HORIZONTAL_PADDING * 2
    local size_delta = target_total - PREVIEW_SIZE[1]

    rect_style.size_addition[1] = size_delta
    rect_style.offset[1] = -HORIZONTAL_PADDING
end

return HudElementChatPreview
