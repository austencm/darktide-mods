local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local NAME_FONT_SIZE = 18
local BAR_WIDTH = 140
local BAR_HEIGHT = 6
local BG_COLOR = { 200, 30, 30, 30 }     -- semi-transparent dark backing
local HP_COLOR = { 255, 220, 60, 60 }    -- red
local PERIL_COLOR = { 255, 160, 80, 220 } -- purple
local NAME_COLOR = { 255, 255, 255, 255 }

-- Widget bounds: 200 wide x 60 tall.
-- Layout (relative to widget center):
--   name text:    -8 above center
--   hp bar:       +5 below center, BAR_WIDTH wide
--   peril bar:   +14 below center, BAR_WIDTH wide
-- The screen-space `widget.offset` is updated each frame with the projected
-- pixel for the ghost's center; widget passes use `style.offset` for layout
-- within the widget bounds.

local ui_definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		ghost_beacon_area = {
			parent             = "screen",
			vertical_alignment = "top",
			horizontal_alignment = "left",
			size               = { 200, 60 },
			position           = { 0, 0, 5 },
		},
	},
	widget_definitions = {
		beacon = UIWidget.create_definition({
			-- Name (top of widget)
			{
				pass_type = "text",
				style_id  = "name",
				value_id  = "name",
				value     = "Ghost",
				style     = {
					font_size                 = NAME_FONT_SIZE,
					font_type                 = "proxima_nova_bold",
					text_horizontal_alignment = "center",
					text_vertical_alignment   = "center",
					horizontal_alignment      = "center",
					vertical_alignment        = "top",
					text_color                = NAME_COLOR,
					drop_shadow               = true,
					offset                    = { 0, 0, 1 },
				},
			},
			-- HP bar background
			{
				pass_type = "rect",
				style_id  = "hp_bg",
				style     = {
					horizontal_alignment = "center",
					vertical_alignment   = "center",
					size                 = { BAR_WIDTH, BAR_HEIGHT },
					color                = BG_COLOR,
					offset               = { 0, 5, 1 },
				},
			},
			-- HP bar fill
			{
				pass_type = "rect",
				style_id  = "hp_fill",
				style     = {
					horizontal_alignment = "left",
					vertical_alignment   = "center",
					size                 = { BAR_WIDTH, BAR_HEIGHT },
					color                = HP_COLOR,
					-- Anchor the fill to the LEFT edge of the bar background.
					-- The bg uses center alignment, so its left edge is at
					-- widget_center_x - BAR_WIDTH/2 = -70 from widget center.
					-- Our widget alignment for this pass is "left" so its
					-- origin is widget_left = widget_center_x - 100. Difference
					-- between widget_left and bar's left edge is +30. So
					-- offset.x = 30 places the fill aligned with the bar bg.
					offset               = { 30, 5, 2 },
				},
			},
			-- Peril bar background
			{
				pass_type = "rect",
				style_id  = "peril_bg",
				style     = {
					horizontal_alignment = "center",
					vertical_alignment   = "center",
					size                 = { BAR_WIDTH, BAR_HEIGHT },
					color                = BG_COLOR,
					offset               = { 0, 14, 1 },
				},
			},
			-- Peril bar fill
			{
				pass_type = "rect",
				style_id  = "peril_fill",
				style     = {
					horizontal_alignment = "left",
					vertical_alignment   = "center",
					size                 = { BAR_WIDTH, BAR_HEIGHT },
					color                = PERIL_COLOR,
					offset               = { 30, 14, 2 },
				},
			},
		}, "ghost_beacon_area"),
	},
}

local HudElementGhostBeacon = class("HudElementGhostBeacon", "HudElementBase")

HudElementGhostBeacon.init = function(self, parent, draw_layer, start_scale)
	HudElementGhostBeacon.super.init(self, parent, draw_layer, start_scale, ui_definitions)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if widget then
		widget.visible = false
		widget.offset = widget.offset or { 0, 0, 0 }
	end
end

HudElementGhostBeacon.set_active = function(self, active)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget then return end
	widget.visible = active
end

-- Caller passes the raw projected screen pixel (HUD-logical, since use_hud_scale
-- is true and the caller has already multiplied by inverse_scale). Widget is
-- 200x60 anchored top-left; subtract half-extents so the projection point is
-- the visual center.
local HALF_W, HALF_H = 100, 30
HudElementGhostBeacon.set_offset = function(self, x, y)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget or not widget.offset then return end
	widget.offset[1] = (x or 0) - HALF_W
	widget.offset[2] = (y or 0) - HALF_H
end

-- Update the dynamic widget content from a replayer last_state frame.
-- state = { t, p, y, hp, peril, w, d, ... }
HudElementGhostBeacon.set_state = function(self, state)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget or not state then return end
	local style = widget.style
	if not style then return end

	-- HP fill width: BAR_WIDTH * hp (clamp 0..1).
	local hp = math.max(0, math.min(1, state.hp or 0))
	if style.hp_fill and style.hp_fill.size then
		style.hp_fill.size[1] = BAR_WIDTH * hp
	end

	-- Peril fill: same idea. Peril is 0 for non-Psyker; we keep the bg
	-- visible regardless, but the fill is just zero-width.
	local peril = math.max(0, math.min(1, state.peril or 0))
	if style.peril_fill and style.peril_fill.size then
		style.peril_fill.size[1] = BAR_WIDTH * peril
	end

	-- Defensive: rect-size mutations are usually picked up without a dirty
	-- flag, but we mark dirty anyway in case the renderer caches anything.
	widget.dirty = true
end

-- Update the player name. Called once when the ghost is loaded; not per-frame.
HudElementGhostBeacon.set_name = function(self, name)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget then return end
	if widget.content and widget.content.name ~= nil then
		widget.content.name = tostring(name or "Ghost")
		widget.dirty = true
	end
end

return HudElementGhostBeacon
