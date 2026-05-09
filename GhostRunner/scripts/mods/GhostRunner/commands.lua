local mod = get_mod("GhostRunner")
local run_file = mod.run_file

local commands = {}

-- _selected_ghost: { filename, data } — set by /ghost load, cleared by /ghost clear.
-- Replayer (Task 11+) will read this. For now it's just stored.
mod._selected_ghost = nil

local function _format_duration(secs)
	secs = math.floor(secs or 0)
	local m = math.floor(secs / 60)
	local s = secs % 60
	return string.format("%d:%02d", m, s)
end

local function _color(text, r, g, b)
	return string.format("{#color(%d,%d,%d,255)}%s{#reset()}", r, g, b, text)
end

commands.cmd_list = function()
	local idx = run_file.read_index()
	if #idx.runs == 0 then
		mod:echo("GhostRunner: no saved runs yet.")
		return
	end
	mod:echo(_color("GhostRunner -- saved runs (newest first):", 200, 200, 255))
	for i, e in ipairs(idx.runs) do
		local sel_marker = ""
		if mod._selected_ghost and mod._selected_ghost.filename == e.file then
			sel_marker = _color(" [LOADED]", 100, 230, 100)
		end
		local line = string.format("%d. %s D%s  %s  %s  %s  %s%s",
			i, e.mission or "?", tostring(e.difficulty or "?"),
			_format_duration(e.duration),
			e.outcome or "?",
			e.recorded_at or "?",
			e.class or "?",
			sel_marker)
		mod:echo(line)
	end
end

commands.cmd_load = function(arg)
	if not arg or arg == "" then
		mod:echo("Usage: /ghost load <number-from-list> or <filename>")
		return
	end

	local idx = run_file.read_index()
	local entry

	-- Numeric -> index into list.
	local num = tonumber(arg)
	if num and idx.runs[num] then
		entry = idx.runs[num]
	else
		-- Try as filename (with or without .run).
		local target = arg
		if not target:match("%.run$") then target = target .. ".run" end
		for _, e in ipairs(idx.runs) do
			if e.file == target then entry = e; break end
		end
	end

	if not entry then
		mod:echo("Could not find that run. Try /ghost list.")
		return
	end

	local data, read_err = run_file.read(entry.file)
	if not data then
		mod:echo("Could not read " .. entry.file .. ": " .. tostring(read_err))
		return
	end

	mod._selected_ghost = { filename = entry.file, data = data }

	-- Auto-set mission params via SoloPlay.
	local sp = mod.SoloPlay
	local m = data.metadata.mission
	if m and m.name and sp then
		pcall(function() sp:set("choose_mission", m.name) end)
		pcall(function() sp:set("choose_difficulty", m.difficulty) end)
		pcall(function() sp:set("choose_circumstance", m.circumstance or "default") end)
		pcall(function() sp:set("choose_side_mission", m.side or "default") end)
		pcall(function() sp:set("choose_mission_giver", m.giver or "default") end)
	end

	mod.replayer.arm_with_selected_ghost()

	mod:echo(string.format("Loaded: %s D%s (%s, %s). Mission params auto-set. Hit Start in SoloPlay.",
		m and m.name or "?",
		tostring(m and m.difficulty or "?"),
		_format_duration(data.footer and data.footer.duration or 0),
		data.footer and data.footer.outcome or "partial"))
end

commands.cmd_clear = function()
	mod._selected_ghost = nil
	mod.replayer.disarm()
	mod:echo("Ghost cleared.")
end

commands.cmd_info = function()
	if not mod._selected_ghost then
		mod:echo("No ghost loaded. Use /ghost load <n> after /ghost list.")
		return
	end
	local g = mod._selected_ghost
	local m = g.data.metadata.mission
	local dur = g.data.footer and g.data.footer.duration or 0
	mod:echo(string.format("Ghost: %s D%s  duration=%s  frames=%d  seed=%s%s",
		m and m.name or "?",
		tostring(m and m.difficulty or "?"),
		_format_duration(dur),
		#g.data.frames,
		tostring(m and m.seed or "?"),
		g.data.partial and " [partial]" or ""))
end

return commands
