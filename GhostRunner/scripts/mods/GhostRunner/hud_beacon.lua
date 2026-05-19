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
local BAR_SPACING = 9     -- vertical pixel spacing between bars
local SEGMENT_SPACING = 2 -- thin gap between HP wound segments
local MAX_WOUND_SEGMENTS = 5   -- enough for any class (ogryn caps at 5)

local BG_COLOR        = { 200, 30, 30, 30 }     -- semi-transparent dark bar backing
local HP_COLOR        = { 255, 220, 60, 60 }    -- red (vanilla)
local TOUGHNESS_COLOR = { 220, 220, 220, 255 }  -- pale silver-white
local ABILITY_COLOR   = { 220, 200, 80, 255 }   -- gold
local NAME_COLOR      = { 255, 255, 255, 255 }

-- Programmatically build N wound-segment fill rect passes. Each segment
-- can shrink to show partial fill, and hide entirely when wmax < its index.
-- Layout (size + x-offset) is set per frame in _layout_hp_segments (below).
local function _build_segment_passes()
    local passes = {}
    for i = 1, MAX_WOUND_SEGMENTS do
        passes[#passes + 1] = {
            pass_type = "rect",
            style_id  = "hp_seg_" .. i,
            style     = {
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                size                 = { 0, BAR_HEIGHT },   -- width set per frame
                color                = HP_COLOR,
                offset               = { 30, 45, 2 },        -- x set per frame
            },
        }
    end
    return passes
end

-- Build the complete passes list for the beacon widget. Combines the static
-- passes (backing, icon, name, status row, tough bars, HP bg, ability bars)
-- with the programmatically-generated HP wound segments.
local function _build_all_passes()
    local passes = {
        -- 1. Backing rect (drawn first / underneath). Color set per-frame in set_state.
        {
            pass_type = "rect",
            style_id  = "backing",
            style     = {
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                size                 = { 196, 82 },
                color                = { 140, 0, 0, 0 },
                offset               = { 0, 0, 0 },
            },
        },
        -- 2. Class icon (left of name on top row). PUA glyph via font fallback chain.
        {
            pass_type = "text",
            style_id  = "class_icon",
            value_id  = "class_icon",
            value     = "",   -- set via set_class()
            style     = {
                font_size                 = 22,
                font_type                 = "proxima_nova_bold",
                text_horizontal_alignment = "center",
                text_vertical_alignment   = "center",
                horizontal_alignment      = "center",
                vertical_alignment        = "top",
                text_color                = { 255, 255, 255, 255 },
                drop_shadow               = true,
                offset                    = { -50, 0, 1 },
            },
        },
        -- 3. Name text (centered on top row).
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
        -- 4. Status row (empty when alive; verb text when disabled).
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
                text_color                = { 255, 255, 80, 80 },
                drop_shadow               = true,
                offset                    = { 0, 22, 1 },
            },
        },
        -- 5. Toughness bar (top of the bar stack).
        {
            pass_type = "rect",
            style_id  = "tough_bg",
            style     = {
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                size                 = { BAR_WIDTH, BAR_HEIGHT },
                color                = BG_COLOR,
                offset               = { 0, 36, 1 },
            },
        },
        {
            pass_type = "rect",
            style_id  = "tough_fill",
            style     = {
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                size                 = { BAR_WIDTH, BAR_HEIGHT },
                color                = TOUGHNESS_COLOR,
                offset               = { 30, 36, 2 },
            },
        },
        -- 6. HP bar background (drawn once behind all segments).
        {
            pass_type = "rect",
            style_id  = "hp_bg",
            style     = {
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                size                 = { BAR_WIDTH, BAR_HEIGHT },
                color                = BG_COLOR,
                offset               = { 0, 45, 1 },
            },
        },
    }

    -- 7. HP wound segments (5 max; trimmed per frame to actual wmax).
    for _, seg in ipairs(_build_segment_passes()) do
        passes[#passes + 1] = seg
    end

    -- 8. Ability bar (bottom).
    passes[#passes + 1] = {
        pass_type = "rect",
        style_id  = "ability_bg",
        style     = {
            horizontal_alignment = "center",
            vertical_alignment   = "center",
            size                 = { BAR_WIDTH, BAR_HEIGHT },
            color                = BG_COLOR,
            offset               = { 0, 54, 1 },
        },
    }
    passes[#passes + 1] = {
        pass_type = "rect",
        style_id  = "ability_fill",
        style     = {
            horizontal_alignment = "left",
            vertical_alignment   = "center",
            size                 = { BAR_WIDTH, BAR_HEIGHT },
            color                = ABILITY_COLOR,
            offset               = { 30, 54, 2 },
        },
    }

    return passes
end

local ui_definitions = {
    scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,
        ghost_beacon_area = {
            parent               = "screen",
            vertical_alignment   = "top",
            horizontal_alignment = "left",
            size                 = { 200, 86 },   -- grown from 60 for status row + 3 bars
            position             = { 0, 0, 5 },
        },
    },
    widget_definitions = {
        beacon = UIWidget.create_definition(_build_all_passes(), "ghost_beacon_area"),
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

-- Widget bounds: 200 (W) x 86 (H).
-- Anchor: bottom edge of widget sits just above the projection point.
-- The projection point is the head's world->screen pixel; the pole's tip
-- terminates there too, so the panel visually rests atop the pole.
local HALF_W = 100
local POLE_GAP = 6  -- pixels between projection point and bottom of widget
HudElementGhostBeacon.set_offset = function(self, x, y)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget or not widget.offset then return end
	local widget_h = (widget.content and widget.content.size and widget.content.size[2]) or 86
	widget.offset[1] = (x or 0) - HALF_W
	widget.offset[2] = (y or 0) - widget_h - POLE_GAP
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

-- Pre-stores how many segments the HP bar should display. Schema-1 ghosts
-- (no wmax) fall back to 1, rendering an un-segmented bar.
HudElementGhostBeacon.set_wmax = function(self, wmax)
    self._wmax = (wmax and wmax > 0) and wmax or 1
end

-- Layout the wound-segment passes for a given hp fraction.
-- Sets each segment widget's size + x-offset, hides unused segments.
-- Formula mirrors vanilla scripts/ui/hud/elements/player_panel_base/...:1460-1500.
local function _layout_hp_segments(style, hp, num_segments)
    num_segments = math.max(1, math.min(MAX_WOUND_SEGMENTS, num_segments or 1))
    local step = 1 / num_segments
    local segment_width = (BAR_WIDTH - (num_segments - 1) * SEGMENT_SPACING) / num_segments
    -- The bar's left edge is at offset.x = 30 (the standard inset).
    -- Lay segments left-to-right.
    for i = 1, MAX_WOUND_SEGMENTS do
        local pass = style["hp_seg_" .. i]
        if not pass then
            -- defensive; segment passes should always exist
        elseif i > num_segments then
            -- hide unused segment by setting its width to 0
            if pass.size then pass.size[1] = 0 end
        else
            local end_v = i * step
            local start_v = end_v - step
            local fill = math.max(0, math.min(1, (hp - start_v) / step))
            if pass.size then pass.size[1] = segment_width * fill end
            -- Position this segment's left edge:
            local x = 30 + (i - 1) * (segment_width + SEGMENT_SPACING)
            if pass.offset then pass.offset[1] = x end
        end
    end
end

HudElementGhostBeacon.set_state = function(self, state)
	local widget = self._widgets_by_name and self._widgets_by_name.beacon
	if not widget or not state then return end
	local style   = widget.style
	local content = widget.content
	if not style or not content then return end

	local hp = math.max(0, math.min(1, state.hp or 0))
	local to = math.max(0, math.min(1, state.to or 0))
	local ab = math.max(0, math.min(1, state.ab or 0))

	-- Toughness bar fill.
	if style.tough_fill and style.tough_fill.size then
		style.tough_fill.size[1] = BAR_WIDTH * to
	end

	-- HP bar: vanilla quirk -- when knocked_down, collapse to 1 segment.
	local is_alive = state.st == nil or ALIVE_STATES[state.st]
	local effective_segments = (state.st == "knocked_down") and 1 or (self._wmax or 1)
	_layout_hp_segments(style, hp, effective_segments)

	-- Ability bar fill.
	if style.ability_fill and style.ability_fill.size then
		style.ability_fill.size[1] = BAR_WIDTH * ab
	end

	-- Status row + alarm tints (from Task 7).
	content.status_row = status_text_for(state.st)
	if style.name and style.name.text_color then
		style.name.text_color = is_alive and { 255, 255, 255, 255 } or { 255, 255, 80, 80 }
	end
	if style.backing and style.backing.color then
		style.backing.color = is_alive and { 140, 0, 0, 0 } or { 160, 120, 0, 0 }
	end

	widget.dirty = true
end

return HudElementGhostBeacon
