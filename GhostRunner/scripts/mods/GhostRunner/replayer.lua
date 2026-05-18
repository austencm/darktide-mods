local mod = get_mod("GhostRunner")
local source_module = mod.source

local replayer = {}

local STATE = { idle = "idle", armed = "armed", playing = "playing", finished = "finished" }

local _state = {
	name = STATE.idle,
	source = nil,
	last_state = nil,	-- last interpolated frame, for renderer consumption
}

local _seed_pin_active = false   -- true while a pinned seed is in effect
local _pinned_seed_value = nil
local _seed_pin_path = nil       -- "game_parameters" | "session_seed_hook" | nil

replayer.state = function() return _state.name end
replayer.last_state = function() return _state.last_state end

replayer.frames = function()
	return _state.source and _state.source._frames or nil
end

replayer.idx = function()
	return _state.source and _state.source._idx or nil
end

replayer.elapsed = function()
	return _state.source and _state.source:elapsed() or 0
end
replayer.duration = function()
	return _state.source and _state.source:duration() or 0
end
replayer.metadata = function()
	return _state.source and _state.source:metadata() or nil
end

local function _format_duration(secs)
	secs = math.floor(secs or 0)
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%d:%02d", m, s)
end

local function _try_set_game_parameters_seed(seed)
	-- Path 1: direct write to GameParameters.level_seed.
	-- GameParameters is loaded at engine startup; whether it's runtime-mutable
	-- is uncertain, so wrap in pcall and verify the write stuck.
	local ok = pcall(function()
		rawset(GameParameters, "level_seed", seed)
	end)
	if not ok then return false end
	return GameParameters.level_seed == seed
end

local function _install_session_seed_hook(seed)
	-- Path 2: wrap Managers.connection:session_seed to return our seed
	-- when seed-pin is active. The hook is installed once and re-used
	-- across arm/disarm cycles via the _seed_pin_active flag.
	if not Managers.connection or not Managers.connection.session_seed then
		return false
	end
	if Managers.connection.__ghostrunner_seed_patched then
		return true
	end
	local original = Managers.connection.session_seed
	Managers.connection.session_seed = function(self, ...)
		if _seed_pin_active and _pinned_seed_value then
			return _pinned_seed_value
		end
		return original(self, ...)
	end
	Managers.connection.__ghostrunner_seed_patched = true
	return true
end

replayer.try_pin_seed = function(seed)
	if not seed then
		mod:warning("replayer: ghost has no seed; cannot pin")
		return false
	end

	-- Try direct path first.
	if _try_set_game_parameters_seed(seed) then
		_seed_pin_active = true
		_pinned_seed_value = seed
		_seed_pin_path = "game_parameters"
		mod:info(string.format("replayer: seed pinned via GameParameters: %d", seed))
		return true
	end

	-- Fallback: session_seed hook.
	if _install_session_seed_hook(seed) then
		_seed_pin_active = true
		_pinned_seed_value = seed
		_seed_pin_path = "session_seed_hook"
		mod:info(string.format("replayer: seed pinned via session_seed hook: %d", seed))
		return true
	end

	mod:warning("replayer: could not pin seed -- replay will use engine seed")
	return false
end

replayer.unpin_seed = function()
	-- If we wrote GameParameters.level_seed, clear it so a subsequent fresh
	-- recording (no ghost loaded) doesn't falsely report seed_pinned=true via
	-- is_seed_pinned()'s GameParameters check.
	if _seed_pin_path == "game_parameters" then
		pcall(function() rawset(GameParameters, "level_seed", nil) end)
	end
	_seed_pin_active = false
	_pinned_seed_value = nil
	_seed_pin_path = nil
	-- We deliberately do NOT un-monkey-patch Managers.connection.session_seed --
	-- the patch checks `_seed_pin_active` so it's a no-op when disabled.
end

-- Public accessor used by the recorder to know whether the seed it's recording
-- was forced (so the .run footer reflects deterministic-replay availability).
-- Reads only the active flag now -- GameParameters.level_seed isn't a
-- reliable signal because we may have failed to write/clear it.
replayer.is_seed_pinned = function()
	return _seed_pin_active
end

replayer.arm_with_selected_ghost = function()
	if not mod._selected_ghost then
		_state.name = STATE.idle
		_state.source = nil
		return false
	end
	if mod:get("replay_mode") == "off" then
		_state.name = STATE.idle
		_state.source = nil
		return false
	end
	_state.source = source_module.create_replay_source(mod._selected_ghost.data)
	_state.name = STATE.armed
	_state.last_state = nil
	mod:info(string.format("replayer: armed with %s (%.1fs)",
		mod._selected_ghost.filename, _state.source:duration()))

	local m = _state.source:metadata().mission
	replayer.try_pin_seed(m and m.seed)

	-- Spin up the in-world renderer (trail + pole). Falls back gracefully
	-- if level_world isn't yet available (the per-frame tick retries).
	if mod.world_renderer then
		mod.world_renderer.create()
	end

	return true
end

replayer.disarm = function()
	_state.name = STATE.idle
	_state.source = nil
	_state.last_state = nil
	replayer.unpin_seed()
	if mod.world_renderer then
		mod.world_renderer.destroy()
	end
end

-- Called from on_player_unit_spawn after the recorder is started.
replayer.on_local_player_spawn = function()
	if _state.name ~= STATE.armed then return end
	if not _state.source then return end

	-- Mission match check.
	local meta = _state.source:metadata()
	if not meta or not meta.mission or not meta.mission.name then
		mod:warning("replayer: ghost has no mission name; refusing to play")
		mod:notify("Ghost has no mission metadata -- replay disabled this run.")
		replayer.disarm()
		return
	end
	local sp = mod.SoloPlay
	local current_mission = sp:get("choose_mission")
	if current_mission ~= meta.mission.name then
		mod:warning(string.format("replayer: mission mismatch (selected=%s, ghost=%s)",
			tostring(current_mission), meta.mission.name))
		mod:notify("Ghost mission mismatch -- replay disabled this run.")
		replayer.disarm()
		return
	end

	_state.name = STATE.playing
	mod:info("replayer: playing")
end

replayer.tick = function(dt)
	if _state.name ~= STATE.playing then return end
	if not _state.source then return end
	local s, finished = _state.source:advance(dt)
	_state.last_state = s
	if finished then
		_state.name = STATE.finished
		mod:notify(string.format("Ghost finished at %s.",
			_format_duration(_state.source:duration())))
	end
end

return replayer
