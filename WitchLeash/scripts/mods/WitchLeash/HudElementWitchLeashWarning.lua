local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local BASE_FONT_SIZE = 32

local ui_definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		witch_leash_warning_area = {
			parent             = "screen",
			vertical_alignment = "center",
			horizontal_alignment = "center",
			size               = { 400, 60 },
			-- Below the crosshair by default. The user can fine-tune via the
			-- `hud_offset_x` / `hud_offset_y` settings, applied as widget.offset.
			position           = { 0, 100, 5 },
		},
	},
	widget_definitions = {
		warning_text = UIWidget.create_definition({
			{
				pass_type = "text",
				style_id  = "text",
				value_id  = "text",
				value     = "DANGER",
				style     = {
					font_size                 = BASE_FONT_SIZE,
					font_type                 = "machine_medium",
					text_horizontal_alignment = "center",
					text_vertical_alignment   = "center",
					horizontal_alignment      = "center",
					vertical_alignment        = "center",
					text_color                = { 255, 255, 90, 90 },
					drop_shadow               = true,
				},
			},
		}, "witch_leash_warning_area"),
	},
}

local HudElementWitchLeashWarning = class("HudElementWitchLeashWarning", "HudElementBase")

HudElementWitchLeashWarning.init = function(self, parent, draw_layer, start_scale)
	HudElementWitchLeashWarning.super.init(self, parent, draw_layer, start_scale, ui_definitions)
	-- Start hidden; main script's poller will flip this on when peril
	-- crosses the threshold. Ensure the offset table exists so set_offset
	-- can mutate it.
	local widget = self._widgets_by_name and self._widgets_by_name.warning_text
	if widget then
		widget.visible = false
		widget.offset = widget.offset or { 0, 0, 0 }
	end
end

HudElementWitchLeashWarning.set_active = function(self, active)
	local widget = self._widgets_by_name and self._widgets_by_name.warning_text
	if not widget then return end
	widget.visible = active
end

HudElementWitchLeashWarning.set_offset = function(self, x, y)
	local widget = self._widgets_by_name and self._widgets_by_name.warning_text
	if not widget or not widget.offset then return end
	widget.offset[1] = x or 0
	widget.offset[2] = y or 0
end

HudElementWitchLeashWarning.set_scale = function(self, scale)
	local widget = self._widgets_by_name and self._widgets_by_name.warning_text
	if not widget or not widget.style or not widget.style.text then return end
	widget.style.text.font_size = BASE_FONT_SIZE * (scale or 1)
	-- Hint the renderer to re-measure / re-rasterize. Some text passes cache
	-- glyph metrics from the initial font_size and need an explicit dirty
	-- signal to pick up live mutations.
	widget.dirty = true
end

return HudElementWitchLeashWarning
