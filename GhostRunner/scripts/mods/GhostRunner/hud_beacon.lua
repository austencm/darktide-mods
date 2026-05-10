local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local BASE_FONT_SIZE = 28

local ui_definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		ghost_beacon_area = {
			parent             = "screen",
			vertical_alignment = "top",
			horizontal_alignment = "left",
			size               = { 200, 40 },
			position           = { 0, 0, 5 },
		},
	},
	widget_definitions = {
		beacon_text = UIWidget.create_definition({
			{
				pass_type = "text",
				style_id  = "text",
				value_id  = "text",
				value     = "GHOST",
				style     = {
					font_size                 = BASE_FONT_SIZE,
					font_type                 = "proxima_nova_bold",
					text_horizontal_alignment = "center",
					text_vertical_alignment   = "center",
					horizontal_alignment      = "center",
					vertical_alignment        = "center",
					text_color                = { 255, 180, 220, 255 },
					drop_shadow               = true,
				},
			},
		}, "ghost_beacon_area"),
	},
}

local HudElementGhostBeacon = class("HudElementGhostBeacon", "HudElementBase")

HudElementGhostBeacon.init = function(self, parent, draw_layer, start_scale)
	HudElementGhostBeacon.super.init(self, parent, draw_layer, start_scale, ui_definitions)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon_text
	if widget then
		widget.visible = false
		widget.offset = widget.offset or { 0, 0, 0 }
	end
end

HudElementGhostBeacon.set_active = function(self, active)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon_text
	if not widget then return end
	widget.visible = active
end

-- Caller passes the raw projected screen pixel (where the ghost should
-- visually appear). The widget is 200x40 anchored top-left, and the text
-- pass is center-aligned within it -- so to make the text's visual center
-- land on the projection point, we subtract the widget's half-extents
-- here. Doing the centering at widget-offset level (vs text style.offset)
-- avoids a class of subtle misalignment when font baselines or HUD
-- scaling differ.
local HALF_W, HALF_H = 100, 20
HudElementGhostBeacon.set_offset = function(self, x, y)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon_text
	if not widget or not widget.offset then return end
	widget.offset[1] = (x or 0) - HALF_W
	widget.offset[2] = (y or 0) - HALF_H
end

return HudElementGhostBeacon
