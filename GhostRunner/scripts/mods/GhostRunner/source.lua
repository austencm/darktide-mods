local mod = get_mod("GhostRunner")
-- Reuse the interpolation table loaded by GhostRunner.lua (mod:io_dofile has no
-- cache, so re-running it here would parse + execute the file a second time
-- per mod load).
local interpolation = mod.interpolation

local source = {}

-- ReplaySource: backed by a parsed .run file.
--   :advance(dt) -> updates internal elapsed, returns (state, finished)
--   :metadata() -> the meta block
local ReplaySource = {}
ReplaySource.__index = ReplaySource

source.create_replay_source = function(run_data)
	local self = setmetatable({}, ReplaySource)
	self._frames = run_data.frames
	self._meta = run_data.metadata
	self._elapsed = 0
	self._idx = 1
	return self
end

function ReplaySource:advance(dt)
	self._elapsed = self._elapsed + dt
	local state, new_idx, finished =
		interpolation.frame_at(self._frames, self._idx, self._elapsed)
	self._idx = new_idx
	return state, finished
end

function ReplaySource:metadata()
	return self._meta
end

function ReplaySource:elapsed()
	return self._elapsed
end

function ReplaySource:duration()
	if #self._frames == 0 then return 0 end
	return self._frames[#self._frames].t
end

-- Trail walk-back needs read access to the full frame array and the
-- interpolator's current cursor; exposed as proper methods so callers don't
-- reach into private fields.
function ReplaySource:frames()
	return self._frames
end

function ReplaySource:current_idx()
	return self._idx
end

-- MockSource: scripted state for dev work without a .run file.
local MockSource = {}
MockSource.__index = MockSource

source.create_mock_source = function()
	local self = setmetatable({}, MockSource)
	self._elapsed = 0
	return self
end

function MockSource:advance(dt)
	self._elapsed = self._elapsed + dt
	-- A simple oscillating walker for dev visualization.
	local x = 10.0 + math.sin(self._elapsed) * 5.0
	local z = 1.8
	return {
		t = self._elapsed,
		p = { x, 20.0, z },
		y = math.sin(self._elapsed * 0.5),
		hp = 0.5 + 0.5 * math.sin(self._elapsed * 0.3),
		to = 0.5 + 0.5 * math.sin(self._elapsed * 0.7),
		ab = 0.5 + 0.5 * math.sin(self._elapsed * 0.4),
		w = 3,
		st = "walking",
	}, false
end

function MockSource:metadata()
	return { player = "Mock", class = "psyker", mission = { name = "mock" } }
end

-- MockSource doesn't back a frame array; trail rendering will no-op when
-- frames() returns nil (the world_renderer guard handles this).
function MockSource:frames() return nil end
function MockSource:current_idx() return nil end

return source
