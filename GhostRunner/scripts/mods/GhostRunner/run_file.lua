local mod = get_mod("GhostRunner")
local fs = mod.fs

local SCHEMA_VERSION = 1

local run_file = {}

-- A "writer" is an object that holds an open file handle and can be
-- fed metadata/frames/footer.
local Writer = {}
Writer.__index = Writer

run_file.create_writer = function(filename, metadata)
	local path = fs.runs_path(filename)
	if not path then
		return nil, "fs.runs_path returned nil (runs_root unavailable)"
	end
	local handle = fs.open_write(path)
	if not handle then
		return nil, "could not open " .. path
	end

	local self = setmetatable({}, Writer)
	self._handle = handle
	self._path = path
	self._closed = false

	-- Write metadata as the first line.
	local meta = {
		type = "meta",
		schema = SCHEMA_VERSION,
		player = metadata.player,
		class = metadata.class,
		mission = metadata.mission,
		recorded_at = metadata.recorded_at,
	}
	handle:write(cjson.encode(meta) .. "\n")

	return self
end

-- Append a frame. Caller is responsible for flush cadence.
function Writer:append_frame(frame)
	if self._closed then return end
	-- frame is { t, p (Vector3 or {x,y,z}), y, hp, peril, w, d }
	local row = {
		type = "f",
		t = frame.t,
		p = frame.p,
		y = frame.y,
		hp = frame.hp,
		peril = frame.peril,
		w = frame.w,
		d = frame.d,
	}
	self._handle:write(cjson.encode(row) .. "\n")
end

-- Flush the OS-level buffer. Lua I/O handle auto-flushes on close, but
-- we want explicit periodic flushes for crash-safety.
function Writer:flush()
	if self._closed then return end
	self._handle:flush()
end

-- Write the footer and close.
function Writer:finalize(outcome, duration, seed_pinned, on_shutdown)
	if self._closed then return end
	local footer = {
		type = "end",
		outcome = outcome,
		duration = duration,
		seed_pinned = seed_pinned,
		on_shutdown = on_shutdown,
	}
	self._handle:write(cjson.encode(footer) .. "\n")
	self._handle:close()
	self._closed = true
end

function Writer:abandon()
	if self._closed then return end
	self._handle:close()
	self._closed = true
end

-- Read a complete .run file. Returns {metadata, frames, footer, partial} or nil + error.
run_file.read = function(filename)
	local path = fs.runs_path(filename)
	if not path then
		return nil, "fs.runs_path returned nil"
	end
	local handle = fs.open_read(path)
	if not handle then
		return nil, "could not open " .. path
	end

	local meta, footer
	local frames = {}

	for line in handle:lines() do
		if line and #line > 0 then
			local ok, obj = pcall(cjson.decode, line)
			if ok and type(obj) == "table" then
				if obj.type == "meta" then
					meta = obj
				elseif obj.type == "f" then
					frames[#frames + 1] = obj
				elseif obj.type == "end" then
					footer = obj
				end
			end
		end
	end

	handle:close()

	if not meta then
		return nil, "no metadata header in " .. filename
	end

	if meta.schema and meta.schema > SCHEMA_VERSION then
		return nil, string.format("unsupported schema version %d in %s", meta.schema, filename)
	end

	-- Sort frames by t ascending (defensive -- JSONL is naturally ordered).
	table.sort(frames, function(a, b) return a.t < b.t end)

	return {
		metadata = meta,
		frames = frames,
		footer = footer,  -- nil if recording was abandoned
		partial = footer == nil,
	}
end

run_file.SCHEMA_VERSION = SCHEMA_VERSION

return run_file
