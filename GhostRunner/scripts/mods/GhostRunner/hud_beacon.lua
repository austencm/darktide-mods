local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

-- Codepoint -> UTF-8 byte string. Bitsquid Lua's `\u{XXXX}` escape support
-- is uncertain, so encode by hand at mod load time.
local function cp(n)
    if n < 0x80 then return string.char(n) end
    if n < 0x800 then
        return string.char(0xC0 + math.floor(n / 0x40),
                           0x80 + (n % 0x40))
    end
    return string.char(0xE0 + math.floor(n / 0x1000),
                       0x80 + math.floor(n / 0x40) % 0x40,
                       0x80 + (n % 0x40))
end

-- PUA codepoints for class glyphs (detailed variants).
-- From scripts/settings/ui/ui_settings.lua lines 508-555 (per project memory).
local CLASS_GLYPHS = {
    veteran = cp(0xE01A),
    zealot  = cp(0xE01B),
    psyker  = cp(0xE01C),
    ogryn   = cp(0xE01D),
    adamant = cp(0xE050),
}

-- States in which we render NO status text. Sourced from
-- scripts/settings/player_character/player_character_states.lua.
-- Everything not in this set OR the hub-only set falls through to the
-- status formatter.
local ALIVE_STATES = {
    walking = true, sprinting = true, jumping = true, falling = true,
    sliding = true, dodging = true, stunned = true, interacting = true,
    minigame = true, lunging = true, exploding = true,
    ledge_hanging = true, ledge_hanging_falling = true,
    ledge_hanging_pull_up = true, ledge_vaulting = true,
    ladder_climbing = true, ladder_top_entering = true, ladder_top_leaving = true,
    -- Hub-only states (won't appear in missions, but treat as alive defensively):
    hub_companion_interaction = true, hub_emote = true, hub_jog = true,
}

-- Verb-only display per disabled state. Anything missing here falls back to
-- the uppercase-with-spaces formatter (so future state names display
-- *something* until this table is updated).
local STATUS_TEXT = {
    knocked_down   = "DOWN",
    hogtied        = "HOGTIED",
    pounced        = "POUNCED",
    netted         = "NETTED",
    consumed       = "CONSUMED",
    grabbed        = "GRABBED",
    mutant_charged = "GRABBED",
    warp_grabbed   = "WARP GRABBED",
    vortex_grabbed = "VORTEX GRABBED",
    catapulted     = "CATAPULTED",
    dead           = "DEAD",
}

local function status_text_for(state)
    if not state or ALIVE_STATES[state] then return "" end
    return STATUS_TEXT[state] or state:upper():gsub("_", " ")
end

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
			-- Backing rect for legibility. Color is set per-frame in set_state
			-- (neutral dark when alive, dark red when disabled).
			{
				pass_type = "rect",
				style_id  = "backing",
				style     = {
					horizontal_alignment = "center",
					vertical_alignment   = "center",
					size                 = { 196, 56 },   -- inset from widget bounds; grows in Task 8
					color                = { 140, 0, 0, 0 },
					offset               = { 0, 0, 0 },
				},
			},
			-- Class icon (top, left of name). The glyph is in the Darktide PUA range;
			-- proxima_nova_bold's font-fallback chain resolves it via darktide_custom_regular.
			{
				pass_type = "text",
				style_id  = "class_icon",
				value_id  = "class_icon",
				value     = "",  -- set via set_class()
				style     = {
					font_size                 = 22,
					font_type                 = "proxima_nova_bold",
					text_horizontal_alignment = "center",
					text_vertical_alignment   = "center",
					horizontal_alignment      = "center",
					vertical_alignment        = "top",
					text_color                = { 255, 255, 255, 255 },
					drop_shadow               = true,
					offset                    = { -50, 0, 1 },  -- centered then nudged left
				},
			},
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
			-- Status row (verb-only when disabled, empty when alive). Always reserved
			-- vertical space so the widget doesn't bounce when state changes.
			{
				pass_type = "text",
				style_id  = "status_row",
				value_id  = "status_row",
				value     = "",
				style     = {
					font_size                 = 12,
					font_type                 = "proxima_nova_bold",
					text_horizontal_alignment = "center",
					text_vertical_alignment   = "center",
					horizontal_alignment      = "center",
					vertical_alignment        = "top",
					text_color                = { 255, 255, 80, 80 },   -- bright red
					drop_shadow               = true,
					offset                    = { 0, 22, 1 },           -- 22px below top
				},
			},
			-- HP bar background. Pushed further below center to leave clear
			-- space under the name text (which extends below the top of the
			-- widget by the font's baseline + descender).
			{
				pass_type = "rect",
				style_id  = "hp_bg",
				style     = {
					horizontal_alignment = "center",
					vertical_alignment   = "center",
					size                 = { BAR_WIDTH, BAR_HEIGHT },
					color                = BG_COLOR,
					offset               = { 0, 14, 1 },
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
					offset               = { 30, 14, 2 },
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
					offset               = { 0, 23, 1 },
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
					offset               = { 30, 23, 2 },
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

-- Widget bounds: 200 (W) x 60 (H) for now -- grows in Task 8.
-- Anchor: bottom edge of widget sits just above the projection point.
-- The projection point is the head's world->screen pixel; the pole's tip
-- terminates there too, so the panel visually rests atop the pole.
local HALF_W = 100
local POLE_GAP = 6  -- pixels between projection point and bottom of widget
HudElementGhostBeacon.set_offset = function(self, x, y)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget or not widget.offset then return end
	local widget_h = (widget.content and widget.content.size and widget.content.size[2]) or 60
	widget.offset[1] = (x or 0) - HALF_W
	widget.offset[2] = (y or 0) - widget_h - POLE_GAP
end

-- Update the dynamic widget content from a replayer last_state frame.
-- state = { t, p, y, hp, peril, w, d, ... }
HudElementGhostBeacon.set_state = function(self, state)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget or not state then return end
	local style   = widget.style
	local content = widget.content
	if not style or not content then return end

	-- HP / peril fills come from the existing v0 passes; replaced in Task 8.
	local hp = math.max(0, math.min(1, state.hp or 0))
	if style.hp_fill and style.hp_fill.size then
		style.hp_fill.size[1] = BAR_WIDTH * hp
	end
	-- (Old peril update intentionally left until Task 8 -- harmless if peril field is nil.)
	local peril = math.max(0, math.min(1, state.peril or 0))
	if style.peril_fill and style.peril_fill.size then
		style.peril_fill.size[1] = BAR_WIDTH * peril
	end

	-- Status row + alarm tint. Treat missing state.st as alive (avoids a
	-- one-frame alarm flash before the first interpolated frame arrives).
	local is_alive = state.st == nil or ALIVE_STATES[state.st]
	content.status_row = status_text_for(state.st)
	if style.name and style.name.text_color then
		style.name.text_color = is_alive
			and { 255, 255, 255, 255 }
			or { 255, 255, 80, 80 }   -- bright red
	end
	if style.backing and style.backing.color then
		style.backing.color = is_alive
			and { 140, 0, 0, 0 }      -- neutral dark
			or { 160, 120, 0, 0 }     -- dark red
	end

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

-- Update the class icon. Called once when the ghost is loaded; not per-frame.
-- Unknown class -> empty string (icon hidden).
HudElementGhostBeacon.set_class = function(self, class_name)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget then return end
	local glyph = CLASS_GLYPHS[class_name] or ""
	if widget.content and widget.content.class_icon ~= nil then
		widget.content.class_icon = glyph
		widget.dirty = true
	end
end

return HudElementGhostBeacon
