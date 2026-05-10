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
	-- frame is { t, p (Vector3 or {x,y,z}), y, hp, peril, w, d, prog }
	local row = {
		type = "f",
		t = frame.t,
		p = frame.p,
		y = frame.y,
		hp = frame.hp,
		peril = frame.peril,
		w = frame.w,
		d = frame.d,
		prog = frame.prog,
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
		return nil, "metadata header missing or unparseable in " .. filename
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

-- Index entry shape: { file, mission, difficulty, class, duration, outcome, recorded_at, seed, seed_pinned }

local function _index_entry_from_run(filename, data)
	return {
		file = filename,
		mission = data.metadata.mission and data.metadata.mission.name or "unknown",
		difficulty = data.metadata.mission and data.metadata.mission.difficulty,
		resistance = data.metadata.mission and data.metadata.mission.resistance,
		class = data.metadata.class,
		duration = data.footer and data.footer.duration or 0,
		outcome = data.footer and data.footer.outcome or "partial",
		recorded_at = data.metadata.recorded_at,
		seed = data.metadata.mission and data.metadata.mission.seed,
		seed_pinned = data.footer and data.footer.seed_pinned or false,
	}
end

run_file.read_index = function()
	local index_path = fs.index_path()
	if not index_path then
		return { schema = SCHEMA_VERSION, runs = {} }
	end
	local handle = fs.open_read(index_path)
	if not handle then
		return { schema = SCHEMA_VERSION, runs = {} }
	end
	local content = handle:read("*a")
	handle:close()
	if not content or #content == 0 then
		return { schema = SCHEMA_VERSION, runs = {} }
	end
	local ok, obj = pcall(cjson.decode, content)
	if not ok or type(obj) ~= "table" or type(obj.runs) ~= "table" then
		mod:warning("index.json present but malformed; treating as empty (run /ghost rebuild_index to repair)")
		return { schema = SCHEMA_VERSION, runs = {} }
	end
	return obj
end

run_file.write_index = function(index)
	local index_path = fs.index_path()
	if not index_path then return false end
	-- Atomic write: write to .tmp, then rename via `move /Y`.
	local tmp_path = index_path .. ".tmp"
	local handle = fs.open_write(tmp_path)
	if not handle then return false end
	handle:write(cjson.encode(index))
	handle:close()
	local move_handle = Mods.lua.io.popen(string.format(
		'move /Y "%s" "%s" 2>nul', tmp_path, index_path))
	if move_handle then move_handle:close() end
	return true
end

run_file.append_to_index = function(filename, data)
	local index = run_file.read_index()
	-- Remove any existing entry for this filename (shouldn't happen, but be safe).
	local kept = {}
	for _, e in ipairs(index.runs) do
		if e.file ~= filename then kept[#kept + 1] = e end
	end
	kept[#kept + 1] = _index_entry_from_run(filename, data)
	index.runs = kept
	-- Sort by recorded_at descending (newest first).
	table.sort(index.runs, function(a, b)
		return (a.recorded_at or "") > (b.recorded_at or "")
	end)
	return run_file.write_index(index)
end

-- Rebuild index by scanning the runs folder. Slow if many runs; rare path.
run_file.rebuild_index = function()
	local files = fs.list_run_files()
	local entries = {}
	for _, filename in ipairs(files) do
		local data = run_file.read(filename)
		if data then
			entries[#entries + 1] = _index_entry_from_run(filename, data)
		end
	end
	table.sort(entries, function(a, b)
		return (a.recorded_at or "") > (b.recorded_at or "")
	end)
	return run_file.write_index({ schema = SCHEMA_VERSION, runs = entries })
end

run_file.SCHEMA_VERSION = SCHEMA_VERSION

return run_file
