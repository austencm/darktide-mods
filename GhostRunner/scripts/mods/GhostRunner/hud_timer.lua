local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local FONT_SIZE = 20
local PANEL_WIDTH = 220
local PANEL_HEIGHT = 50
-- Margin from the screen edge.
local MARGIN_RIGHT = 24
local MARGIN_BOTTOM = 80  -- above the chat / objective HUD area

local NEUTRAL = { 255, 255, 255, 255 }
local AHEAD   = { 255, 130, 230, 130 }  -- soft green
local BEHIND  = { 255, 230, 130, 130 }  -- soft red
local LABEL_COLOR = { 230, 200, 200, 200 }

local ui_definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		ghost_timer_area = {
			parent             = "screen",
			vertical_alignment = "bottom",
			horizontal_alignment = "right",
			size               = { PANEL_WIDTH, PANEL_HEIGHT },
			position           = { -MARGIN_RIGHT, -MARGIN_BOTTOM, 5 },
		},
	},
	widget_definitions = {
		timer = UIWidget.create_definition({
			-- Ghost time line
			{
				pass_type = "text",
				style_id  = "ghost_time",
				value_id  = "ghost_time",
				value     = "Ghost: 0:00",
				style     = {
					font_size                 = FONT_SIZE,
					font_type                 = "proxima_nova_bold",
					text_horizontal_alignment = "right",
					text_vertical_alignment   = "top",
					horizontal_alignment      = "right",
					vertical_alignment        = "top",
					text_color                = LABEL_COLOR,
					drop_shadow               = true,
					offset                    = { 0, 0, 1 },
				},
			},
			-- Progress comparison line (replaces wall-clock delta).
			{
				pass_type = "text",
				style_id  = "progress",
				value_id  = "progress",
				value     = "Progress: -- / --",
				style     = {
					font_size                 = FONT_SIZE,
					font_type                 = "proxima_nova_bold",
					text_horizontal_alignment = "right",
					text_vertical_alignment   = "top",
					horizontal_alignment      = "right",
					vertical_alignment        = "top",
					text_color                = NEUTRAL,
					drop_shadow               = true,
					offset                    = { 0, 24, 1 },
				},
			},
		}, "ghost_timer_area"),
	},
}

local HudElementGhostTimer = class("HudElementGhostTimer", "HudElementBase")

HudElementGhostTimer.init = function(self, parent, draw_layer, start_scale)
	HudElementGhostTimer.super.init(self, parent, draw_layer, start_scale, ui_definitions)
	local widget = self._widgets_by_name and self._widgets_by_name.timer
	if widget then
		widget.visible = false
	end
end

HudElementGhostTimer.set_active = function(self, active)
	local widget = self._widgets_by_name and self._widgets_by_name.timer
	if not widget then return end
	widget.visible = active
end

local function _format_mmss(secs)
	secs = math.max(0, math.floor(secs or 0))
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%d:%02d", m, s)
end

-- state = { ghost_t = number, live_prog = number|nil, ghost_prog = number|nil }
HudElementGhostTimer.set_state = function(self, state)
	local widget = self._widgets_by_name and self._widgets_by_name.timer
	if not widget or not widget.content or not widget.style then return end

	local ghost_t = state and state.ghost_t or 0
	widget.content.ghost_time = "Ghost: " .. _format_mmss(ghost_t)

	-- Progress line: live% / ghost% with color-coded delta.
	local live_prog = state and state.live_prog
	local ghost_prog = state and state.ghost_prog

	if not live_prog or not ghost_prog then
		widget.content.progress = "Progress: -- / --"
		if widget.style.progress and widget.style.progress.text_color then
			widget.style.progress.text_color[1] = NEUTRAL[1]
			widget.style.progress.text_color[2] = NEUTRAL[2]
			widget.style.progress.text_color[3] = NEUTRAL[3]
			widget.style.progress.text_color[4] = NEUTRAL[4]
		end
	else
		-- Both progress values are 0..1 from furthest_travel_percentage.
		-- (If they exceed 1, they're absolute distances from the fallback
		-- path -- still comparable, just shown as decimal not percentage.)
		local live_pct = math.floor(live_prog * 100 + 0.5)
		local ghost_pct = math.floor(ghost_prog * 100 + 0.5)
		widget.content.progress = string.format("Progress: %d%% / %d%%", live_pct, ghost_pct)

		-- Color: ahead (live > ghost) green, behind red, neutral white.
		local diff = live_prog - ghost_prog
		local color
		if diff > 0.005 then
			color = AHEAD
		elseif diff < -0.005 then
			color = BEHIND
		else
			color = NEUTRAL
		end
		if widget.style.progress and widget.style.progress.text_color then
			widget.style.progress.text_color[1] = color[1]
			widget.style.progress.text_color[2] = color[2]
			widget.style.progress.text_color[3] = color[3]
			widget.style.progress.text_color[4] = color[4]
		end
	end

	-- Per CLAUDE.md: text widgets cache glyph metrics; mutating the value
	-- (which can change rendered width) needs widget.dirty to re-measure.
	widget.dirty = true
end

return HudElementGhostTimer
