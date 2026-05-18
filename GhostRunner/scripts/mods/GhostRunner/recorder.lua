local mod = get_mod("GhostRunner")
local fs = mod.fs
local run_file = mod.run_file

local recorder = {}

-- Two states are sufficient: idle (no mission, ready to start) and recording
-- (capturing a live mission). The design spec described a "finalized" interim
-- state but both terminate-recording paths (stop_and_save and _abandon) reset
-- straight to idle since nothing distinguishes them externally.
local STATE = { idle = "idle", recording = "recording" }

local _state = {
	name = STATE.idle,
	writer = nil,
	player_unit = nil,
	start_t = 0,
	last_sample_t = 0,
	accumulator = 0,
	flush_accumulator = 0,
	flush_frame_count = 0,
	seed = nil,           -- captured at start (whatever seed the engine reported)
	seed_pinned = false,  -- true only if Task 12 forced this seed (replay determinism)
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

-- Read current mission params for the metadata block. In solo, SoloPlay's
-- settings are the canonical source (the user just set them). In MP, the
-- engine's mechanism_data has the real mission; SoloPlay's settings are
-- stale UI state. We branch on is_soloplay().
local function _read_mission_metadata()
	local sp = mod.SoloPlay
	local is_solo = sp and sp.is_soloplay and sp.is_soloplay()

	if is_solo then
		-- Mechanism_data has resistance populated in solo too (SoloPlay's
		-- gen_normal_mission_context writes it). Use it as the canonical
		-- source for resistance regardless of branch.
		local mechanism = Managers.mechanism and Managers.mechanism:current_mechanism()
		local md = mechanism and mechanism:mechanism_data() or {}
		return {
			name = sp:get("choose_mission") or "unknown",
			difficulty = sp:get("choose_difficulty"),
			resistance = md.resistance,
			circumstance = sp:get("choose_circumstance"),
			side = sp:get("choose_side_mission"),
			giver = sp:get("choose_mission_giver"),
			havoc = nil,
			seed = nil,   -- filled in by caller after reading from game state
		}
	end

	-- MP path: read from the mechanism's mechanism_data.
	-- Field names verified against SoloPlay.lua gen_normal_mission_context:
	--   mission_name, challenge, resistance, circumstance_name,
	--   side_mission, mission_giver_vo_override, havoc_data.
	local mechanism = Managers.mechanism and Managers.mechanism:current_mechanism()
	local md = mechanism and mechanism:mechanism_data() or {}

	-- Normalise to our schema. Defensive fallbacks for when the mechanism
	-- layer isn't yet ready or fields differ.
	return {
		name = md.mission_name or "unknown",
		difficulty = md.challenge,
		resistance = md.resistance,
		circumstance = md.circumstance_name or "default",
		side = md.side_mission or "default",
		giver = md.mission_giver_vo_override or "default",
		havoc = md.havoc_data,
		seed = nil,   -- filled in by caller after reading from game state
	}
end

local function _read_level_seed()
	-- The engine assigns shared_state.level_seed from
	--   GameParameters.level_seed or Managers.connection:session_seed()
	-- (see scripts/game_states/game/state_gameplay.lua). The shared_state
	-- table itself is local to that init function and not exposed on a
	-- manager, so we read from the same two sources directly.
	if GameParameters and GameParameters.level_seed then
		return GameParameters.level_seed
	end
	if Managers.connection and Managers.connection.session_seed then
		local ok, seed = pcall(Managers.connection.session_seed, Managers.connection)
		if ok and seed then return seed end
	end
	return nil
end

local function _read_local_player_name_and_class()
	local local_player = Managers.player and Managers.player:local_player(1)
	if not local_player then return "Unknown", "unknown" end
	local profile = local_player.profile and local_player:profile()
	-- profile.name is the display name (e.g. "Sergeant Rho").
	-- character_id is a UUID; useful only as a unique fallback.
	local name = profile and (profile.name or profile.character_id) or "Unknown"
	local class = profile and profile.archetype and profile.archetype.name or "unknown"
	return name, class
end

local function _read_max_wounds(player_unit)
	-- Read once at recorder start. Used in the wound-segmented HP bar.
	local hp_ext = ScriptUnit.has_extension(player_unit, "health_system")
	if hp_ext and hp_ext.max_wounds then
		local ok, val = pcall(hp_ext.max_wounds, hp_ext)
		if ok and val then return val end
	end
	return nil  -- absent metadata is acceptable; renderer falls back to un-segmented bar
end

recorder.start = function(player, player_unit)
	-- Contract: stop_and_save (Task 8) must reset _state.name to idle on
	-- finalize, otherwise back-to-back missions silently skip recording.
	if _state.name ~= STATE.idle then
		mod:warning("recorder: start called in non-idle state; ignoring")
		return
	end

	local iso = _now_iso()
	local filename = _filename_from_iso(iso)

	local mission = _read_mission_metadata()
	mission.seed = _read_level_seed()

	local player_name, class = _read_local_player_name_and_class()
	local wmax = _read_max_wounds(player_unit)

	local meta = {
		player = player_name,
		class = class,
		wmax = wmax,
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
	-- Task 12: if the replayer pinned a seed before this mission started,
	-- the recording's footer should reflect that the level RNG was forced
	-- to a known value.
	_state.seed_pinned = (mod.replayer and mod.replayer.is_seed_pinned and mod.replayer.is_seed_pinned()) or false
	_state.metadata = meta
	_state.filename = filename

	mod:info(string.format("recorder: started %s (mission=%s seed=%s)",
		filename, tostring(mission.name), tostring(mission.seed)))
end

local function _read_state(unit)
	-- Position (foot/root).
	local pos = Unit.world_position(unit, 1)
	local p = { Vector3.to_elements(pos) }

	-- Yaw.
	local rot = Unit.local_rotation(unit, 1)
	local y = Quaternion.yaw(rot)

	-- HP fraction.
	local hp = 0
	local hp_ext = ScriptUnit.has_extension(unit, "health_system")
	if hp_ext and hp_ext.current_health_percent then
		hp = hp_ext:current_health_percent() or 0
	end

	-- Toughness fraction.
	local to = 0
	local toughness_ext = ScriptUnit.has_extension(unit, "toughness_system")
	if toughness_ext and toughness_ext.current_toughness_percent then
		to = toughness_ext:current_toughness_percent() or 0
	end

	-- Combat-ability cooldown progress (1.0 = ready, 0.0 = just used / on cooldown).
	-- Mirrors hud_element_player_ability.lua formula: 1 - remaining/max,
	-- with a quirk: when 0 (just finished), bump to 1.
	local ab = 0
	local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
	if ability_ext and ability_ext.ability_is_equipped
	   and ability_ext:ability_is_equipped("combat_ability") then
		local rem = ability_ext:remaining_ability_cooldown("combat_ability")
		local max = ability_ext:max_ability_cooldown("combat_ability")
		if max and max > 0 then
			ab = 1 - (rem / max)
			if ab == 0 then ab = 1 end
		else
			ab = 1
		end
	end

	-- Wounds remaining (kept for parity with vanilla; segmentation visual
	-- only uses hp + max_wounds, but `w` is useful for status/debug).
	local w = 0
	if hp_ext and hp_ext.num_wounds then
		w = hp_ext:num_wounds() or 0
	end

	-- CSM state name (replaces v0's boolean `d`).
	local st = "walking"
	local csm = ScriptUnit.has_extension(unit, "character_state_machine_system")
	if csm and csm.current_state then
		local ok, val = pcall(csm.current_state, csm)
		if ok and val then st = val end
	end

	-- Main-path progress (unchanged from v0).
	local pg = nil
	local main_path = Managers.state and Managers.state.main_path
	if main_path then
		local ok_p, val = pcall(main_path.furthest_travel_percentage, main_path, 1)
		if ok_p and val then pg = val end
	end

	return p, y, hp, to, ab, w, st, pg
end

recorder.tick = function(dt)
	if _state.name ~= STATE.recording then return end
	if not Unit.alive(_state.player_unit) then
		recorder._abandon("aborted")
		return
	end

	_state.accumulator = _state.accumulator + dt
	_state.flush_accumulator = _state.flush_accumulator + dt

	while _state.accumulator >= SAMPLE_INTERVAL do
		_state.accumulator = _state.accumulator - SAMPLE_INTERVAL
		_state.last_sample_t = _state.last_sample_t + SAMPLE_INTERVAL

		-- pcall returns (true, ...results) on success, (false, errmsg) on failure.
		-- On failure the failed sample is dropped and we exit the while loop;
		-- the next tick will resume normally on the next sample boundary.
		local ok, err_or_p, y, hp, to, ab, w, st, pg = pcall(_read_state, _state.player_unit)
		if not ok then
			mod:warning("recorder: read_state failed: " .. tostring(err_or_p))
			return
		end
		local p = err_or_p

		_state.writer:append_frame({
			t = _state.last_sample_t,
			p = p,
			y = y,
			hp = hp,
			to = to,
			ab = ab,
			w = w,
			st = st,
			pg = pg,
		})
		_state.flush_frame_count = _state.flush_frame_count + 1
	end

	if _state.flush_frame_count >= FLUSH_FRAME_THRESHOLD
	   or _state.flush_accumulator >= FLUSH_INTERVAL then
		_state.writer:flush()
		_state.flush_accumulator = 0
		_state.flush_frame_count = 0
	end
end

-- Reset to idle for the next mission. Both stop_and_save and _abandon
-- terminate a recording, and BOTH must end with name = STATE.idle so the
-- recorder.start guard accepts the next mission's spawn hook. Without
-- this, _abandon used to leave state in "finalized" and the next mission
-- silently no-op'd with "recorder: start called in non-idle state".
local function _reset_to_idle()
	_state.name = STATE.idle
	_state.player_unit = nil
	_state.last_sample_t = 0
	_state.accumulator = 0
	_state.flush_accumulator = 0
	_state.flush_frame_count = 0
end

recorder._abandon = function(outcome)
	if _state.name ~= STATE.recording then return end
	if _state.writer then
		_state.writer:finalize(outcome or "aborted",
			_state.last_sample_t, _state.seed_pinned, false)
		run_file.append_to_index(_state.filename, run_file.read(_state.filename))
		_state.writer = nil
	end
	mod:info(string.format("recorder: abandoned (outcome=%s, %.2fs)",
		outcome or "aborted", _state.last_sample_t))
	_reset_to_idle()
end

recorder.stop_and_save = function(outcome, on_shutdown)
	if _state.name ~= STATE.recording then return end
	if not _state.writer then return end

	_state.writer:flush()
	local mapped_outcome
	if outcome == "completed" or outcome == "complete" or outcome == "won" then
		mapped_outcome = "completed"
	elseif outcome == "fail" or outcome == "failed" or outcome == "lost" then
		mapped_outcome = "failed"
	else
		mapped_outcome = "aborted"
	end

	_state.writer:finalize(mapped_outcome, _state.last_sample_t,
		_state.seed_pinned, on_shutdown)
	_state.writer = nil

	-- Reload the just-written file to populate the index entry from canonical data.
	local data = run_file.read(_state.filename)
	if data then
		run_file.append_to_index(_state.filename, data)
	end

	mod:info(string.format("recorder: saved %s (outcome=%s, %.2fs)",
		_state.filename, mapped_outcome, _state.last_sample_t))
	mod:notify(string.format("Run saved: %s (%.0fs)",
		mapped_outcome, _state.last_sample_t))

	_reset_to_idle()
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
