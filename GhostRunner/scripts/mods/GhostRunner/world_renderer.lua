local mod = get_mod("GhostRunner")

local world_renderer = {}

-- Colors are { alpha, r, g, b } per Bitsquid's Color() / Quaternion() ctor
-- (verify call signature in Step 4 -- if wrong order, swap to { r, g, b, alpha }).
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
    world = nil,
}

world_renderer.create = function()
    if _state.line_object then return true end
    local world = _level_world()
    if not world then
        mod:warning("world_renderer: level_world not available; deferring creation")
        return false
    end
    _state.world = world
    _state.line_object = World.create_line_object(world)
    mod:info("world_renderer: created LineObject")
    return true
end

world_renderer.destroy = function()
    if _state.line_object and _state.world then
        -- pcall: if World.destroy_line_object is missing in this engine
        -- version, OR if the world was already destroyed under us (level
        -- transition / session change), prefer leaking the LineObject over
        -- crashing. The engine reclaims everything when the world dies.
        pcall(World.destroy_line_object, _state.world, _state.line_object)
        mod:info("world_renderer: destroyed LineObject")
    end
    _state.line_object = nil
    _state.world = nil
end

-- Drop the cached LineObject without trying to destroy it (used when the
-- world has already been torn down under us by a level/session transition,
-- so the handle is stale and calling destroy would crash).
local function _invalidate()
    _state.line_object = nil
    _state.world = nil
end

-- Per-frame draw. Called from mod.update while replayer is playing.
--
-- frames        : the full frame array from the loaded ghost (for trail history)
-- current_idx   : interpolator's current index into frames
-- current_state : the interpolated last_state (provides current foot p + st)
-- trail_duration: seconds of recorded history to render as trail
world_renderer.tick = function(frames, current_idx, current_state, trail_duration)
    -- Validate the cached world handle every frame. Level transitions and
    -- session changes (hub -> lobby -> mission) destroy the level_world out
    -- from under us; our cached LineObject and world pointer become stale
    -- ("Bad pointer"). Calling LineObject.reset on a dead handle crashes
    -- the engine (access violation + 16s watchdog). Detect by comparing
    -- the live level_world to our cache; if they differ, drop the stale
    -- handle WITHOUT calling destroy on it (the engine already reclaimed
    -- it when the old world died).
    local live_world = _level_world()
    if _state.world and live_world ~= _state.world then
        _invalidate()
    end

    if not _state.line_object then
        -- Try to create now if it failed earlier (e.g. early replay frames)
        -- or we just invalidated due to a world swap.
        if not world_renderer.create() then return end
    end
    if not current_state or not current_state.p then return end

    local lo = _state.line_object
    local world = _state.world
    LineObject.reset(lo)

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
            -- Color ctor: Bitsquid's Color(a, r, g, b). If colors look wrong
            -- after first run, swap to Color(r, g, b, a) -- both signatures
            -- exist in different engine versions.
            local color = Color(alpha_byte, TRAIL_RGB[1], TRAIL_RGB[2], TRAIL_RGB[3])
            LineObject.add_line(lo, color,
                Vector3(prev[1], prev[2], prev[3]),
                Vector3(f.p[1], f.p[2], f.p[3]))
            prev = f.p
        end
        i = i - 1
    end

    -- POLE: from current foot up to head offset.
    local foot = current_state.p
    local head_z = foot[3] + world_renderer.head_offset_for_state(current_state.st)
    local pole_col = Color(POLE_ALPHA, POLE_COLOR[1], POLE_COLOR[2], POLE_COLOR[3])
    LineObject.add_line(lo, pole_col,
        Vector3(foot[1], foot[2], foot[3]),
        Vector3(foot[1], foot[2], head_z))

    LineObject.dispatch(world, lo)
end

return world_renderer
