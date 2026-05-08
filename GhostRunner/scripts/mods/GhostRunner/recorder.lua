local mod = get_mod("GhostRunner")
local fs = mod.fs
local run_file = mod.run_file

local recorder = {}

local STATE = { idle = "idle", recording = "recording", finalized = "finalized" }

local _state = {
	name = STATE.idle,
	writer = nil,
	player_unit = nil,
	start_t = 0,
	last_sample_t = 0,
	accumulator = 0,
	flush_accumulator = 0,
	flush_frame_count = 0,
	seed = nil,  -- captured at start
	metadata = nil,
	filename = nil,
}

local SAMPLE_INTERVAL = 0.05  -- 20 Hz
local FLUSH_INTERVAL = 5.0
local FLUSH_FRAME_THRESHOLD = 100

-- Public state accessors for /ghost_status command.
recorder.state = function() return _state.name end
recorder.elapsed = function() return _state.last_sample_t end

local function _now_iso()
	-- ISO-8601 with milliseconds — used for both filename and metadata.
	-- Lua's os.time/os.date give second precision; we add ms via
	-- os.clock() fractional remainder (cheap, monotonic-ish per session).
	local secs = os.time()
	local ms = math.floor((os.clock() % 1) * 1000)
	local stamp = os.date("!%Y-%m-%dT%H-%M-%S", secs)
	return string.format("%s.%03dZ", stamp, ms)
end

local function _filename_from_iso(iso)
	-- iso uses dashes already (we used %H-%M-%S above for filename safety).
	return iso .. ".run"
end

-- Read current SoloPlay mission params for the metadata block.
local function _read_mission_metadata()
	local sp = mod.SoloPlay
	-- TODO during implementation: verify these are the exact keys; cross-ref
	-- SoloPlay.lua gen_normal_mission_context for the canonical names.
	return {
		name = sp:get("choose_mission") or "unknown",
		difficulty = sp:get("choose_difficulty"),
		circumstance = sp:get("choose_circumstance"),
		side = sp:get("choose_side_mission"),
		giver = sp:get("choose_mission_giver"),
		havoc = nil,  -- TODO: capture havoc fields if we're in havoc mode
		seed = nil,   -- filled in by caller after reading from game state
	}
end

local function _read_level_seed()
	-- Spec §4: "Managers.state.game_mode.shared_state.level_seed (or wherever it surfaces)"
	-- shared_state lives on the game mode; check both common locations.
	local gm_mgr = Managers.state and Managers.state.game_mode
	if gm_mgr and gm_mgr._game_mode and gm_mgr._game_mode._shared_state then
		return gm_mgr._game_mode._shared_state.level_seed
	end
	if gm_mgr and gm_mgr.shared_state then
		return gm_mgr.shared_state.level_seed
	end
	return nil
end

local function _read_local_player_name_and_class()
	local local_player = Managers.player and Managers.player:local_player(1)
	if not local_player then return "Unknown", "unknown" end
	local profile = local_player.profile and local_player:profile()
	local name = profile and profile.character_id or "Unknown"
	local class = profile and profile.archetype and profile.archetype.name or "unknown"
	return name, class
end

recorder.start = function(player, player_unit)
	if _state.name ~= STATE.idle then
		mod:warning("recorder: start called in non-idle state; ignoring")
		return
	end

	local iso = _now_iso()
	local filename = _filename_from_iso(iso)

	local mission = _read_mission_metadata()
	mission.seed = _read_level_seed()

	local player_name, class = _read_local_player_name_and_class()

	local meta = {
		player = player_name,
		class = class,
		mission = mission,
		recorded_at = iso,
	}

	local writer, err = run_file.create_writer(filename, meta)
	if not writer then
		mod:error("recorder: could not create writer: " .. tostring(err))
		return
	end

	_state.name = STATE.recording
	_state.writer = writer
	_state.player_unit = player_unit
	_state.start_t = 0
	_state.last_sample_t = 0
	_state.accumulator = 0
	_state.flush_accumulator = 0
	_state.flush_frame_count = 0
	_state.seed = mission.seed
	_state.metadata = meta
	_state.filename = filename

	mod:info(string.format("recorder: started %s (mission=%s seed=%s)",
		filename, tostring(mission.name), tostring(mission.seed)))
end

-- Sampling implementation comes in Task 7.
recorder.tick = function(dt)
	-- intentionally empty until Task 7
end

-- Finalization comes in Task 8.
recorder.stop_and_save = function(outcome, on_shutdown)
	-- intentionally empty until Task 8
end

-- Internal helper exposed for diagnostics.
recorder._dump = function()
	mod:info("recorder._state: " .. cjson.encode({
		name = _state.name,
		filename = _state.filename,
		seed = _state.seed,
		last_sample_t = _state.last_sample_t,
	}))
end

return recorder
