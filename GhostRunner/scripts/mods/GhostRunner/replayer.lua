local mod = get_mod("GhostRunner")
local source_module = mod.source

local replayer = {}

local STATE = { idle = "idle", armed = "armed", playing = "playing", finished = "finished" }

local _state = {
	name = STATE.idle,
	source = nil,
	last_state = nil,	-- last interpolated frame, for renderer consumption
}

replayer.state = function() return _state.name end
replayer.last_state = function() return _state.last_state end
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

	-- TODO Task 12: attempt to pin the level seed for the upcoming mission
	-- via try_pin_seed(mod._selected_ghost.data.metadata.mission.seed).

	return true
end

replayer.disarm = function()
	_state.name = STATE.idle
	_state.source = nil
	_state.last_state = nil
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
