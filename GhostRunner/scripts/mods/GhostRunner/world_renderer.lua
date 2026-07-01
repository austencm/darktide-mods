local mod = get_mod("GhostRunner")

local world_renderer = {}

-- Colors are constructed via Color(alpha, r, g, b) per Bitsquid convention.
-- If hues come out wrong in-game, swap to Color(r, g, b, a) -- both
-- signatures exist across engine versions.
local TRAIL_RGB = { 255, 255, 80 }    -- bright yellow-white
local POLE_COLOR = { 220, 200, 40 }   -- darker, more saturated companion
local POLE_ALPHA = 255

local HEAD_OFFSET_ALIVE = 1.8
local HEAD_OFFSET_DOWN = 0.5

-- Downed-state set: states where the player is on the ground.
-- Pole shrinks; nameplate drops. Sourced from
-- scripts/settings/player_character/player_character_states.lua.
local DOWN_STATES = {
	knocked_down = true, hogtied = true, pounced = true, netted = true,
	consumed = true, grabbed = true, mutant_charged = true,
	warp_grabbed = true, vortex_grabbed = true, catapulted = true,
	dead = true,
}

world_renderer.head_offset_for_state = function(state)
	return DOWN_STATES[state] and HEAD_OFFSET_DOWN or HEAD_OFFSET_ALIVE
end

-- Returns the level world, or nil if not yet available.
local function _level_world()
	return Managers.world and Managers.world:world("level_world")
end

local _state = {
	line_object = nil,
	drawer = nil,
	world = nil,
}

-- Drop cached handles without touching them (used when the world died
-- under us by a level/session transition; handles are stale and any
-- engine call on them would crash).
local function _invalidate()
	_state.line_object = nil
	_state.drawer = nil
	_state.world = nil
end

world_renderer.create = function()
	if _state.line_object then return true end
	local world = _level_world()
	if not world then
		mod:warning("world_renderer: level_world not available; deferring creation")
		return false
	end
	-- DebugDrawer wraps the raw line_object handle. ALL per-frame draw
	-- calls (line, sphere, reset, update) go through the drawer; direct
	-- LineObject.add_line/reset/dispatch only work in editor mode and
	-- crash at runtime ("LineObject expected, got userdata" -- the raw
	-- handle has no LineObject metatable until DebugDrawer attaches it).
	-- Pattern verified against bot_jump_assist.lua + damage_volume.lua.
	local ok_lo, lo = pcall(World.create_line_object, world)
	if not ok_lo or not lo then
		mod:warning("world_renderer: World.create_line_object failed")
		return false
	end
	local ok_dd, drawer = pcall(DebugDrawer, lo, "retained")
	if not ok_dd or not drawer then
		mod:warning("world_renderer: DebugDrawer constructor failed")
		pcall(World.destroy_line_object, world, lo)
		return false
	end
	_state.world = world
	_state.line_object = lo
	_state.drawer = drawer
	mod:info("world_renderer: created LineObject + DebugDrawer")
	return true
end

world_renderer.destroy = function()
	if _state.line_object and _state.world then
		-- pcall around the destroy: if the engine API is missing or the
		-- world died under us already, prefer leaking the LineObject to
		-- crashing the disarm path. The engine reclaims everything when
		-- the world itself dies.
		pcall(World.destroy_line_object, _state.world, _state.line_object)
		mod:info("world_renderer: destroyed LineObject")
	end
	_invalidate()
end

-- Per-frame draw. Called from mod.update while replayer is playing.
--
-- frames        : the full frame array from the loaded ghost (for trail history)
-- current_idx   : interpolator's current index into frames
-- current_state : the interpolated last_state (provides current foot p + st)
-- trail_duration: seconds of recorded history to render as trail
world_renderer.tick = function(frames, current_idx, current_state, trail_duration)
	-- Validate the cached world handle every frame. Level transitions and
	-- session changes (hub -> lobby -> mission) destroy the level_world
	-- out from under us; cached handles become "Bad pointer" and any
	-- engine call on them is undefined behavior. If the live level_world
	-- no longer matches our cache, drop the handles WITHOUT trying to
	-- destroy them (the engine already reclaimed them when the old world
	-- died); the next create() call rebuilds.
	local live_world = _level_world()
	if _state.world and live_world ~= _state.world then
		_invalidate()
	end

	if not _state.drawer then
		if not world_renderer.create() then return end
	end
	if not current_state or not current_state.p then return end

	local drawer = _state.drawer
	local world = _state.world
	drawer:reset()

	-- TRAIL: walk back from current frame, build segments while within
	-- trail_duration of the interpolated `t`. Alpha-ramp by age.
	local now_t = current_state.t or 0
	local prev = current_state.p
	local i = current_idx
	while i >= 1 do
		local f = frames[i]
		if not f then break end
		local age = now_t - (f.t or 0)
		if age > trail_duration then break end
		local alpha_byte = math.max(0, math.floor(255 * (1 - age / trail_duration)))
		if alpha_byte > 0 and f.p then
			local color = Color(alpha_byte, TRAIL_RGB[1], TRAIL_RGB[2], TRAIL_RGB[3])
			drawer:line(
				Vector3(prev[1], prev[2], prev[3]),
				Vector3(f.p[1], f.p[2], f.p[3]),
				color)
			prev = f.p
		end
		i = i - 1
	end

	-- POLE: from current foot up to head offset.
	local foot = current_state.p
	local head_z = foot[3] + world_renderer.head_offset_for_state(current_state.st)
	local pole_col = Color(POLE_ALPHA, POLE_COLOR[1], POLE_COLOR[2], POLE_COLOR[3])
	drawer:line(
		Vector3(foot[1], foot[2], foot[3]),
		Vector3(foot[1], foot[2], head_z),
		pole_col)

	drawer:update(world)
end

return world_renderer
