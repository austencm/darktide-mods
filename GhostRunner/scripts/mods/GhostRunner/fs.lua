local mod = get_mod("GhostRunner")

local fs = {}

-- Discover %APPDATA% via popen — Mods.lua.io.popen is available per DLS pattern.
-- os.getenv reliability is uncertain in Bitsquid's Lua fork, so we use the popen route.
local function _read_appdata()
	local handle = Mods.lua.io.popen("echo %APPDATA%")
	if not handle then return nil end
	local out = handle:read("*l")
	handle:close()
	if not out then return nil end
	return out:gsub("\r$", "")  -- strip trailing carriage return
end

local _appdata = _read_appdata()
if not _appdata then
	mod:error("Could not resolve %%APPDATA%% via popen")
end

fs.runs_root = _appdata and (_appdata .. "\\Fatshark\\Darktide\\GhostRunner\\runs")

-- Create the runs folder if it doesn't exist (mkdir is idempotent on Windows
-- when the folder already exists; we silently swallow the error).
fs.ensure_runs_folder = function()
	if not fs.runs_root then return false end
	local handle = Mods.lua.io.popen(string.format('mkdir "%s" 2>nul', fs.runs_root))
	if handle then handle:close() end
	return true
end

fs.runs_path = function(filename)
	if not fs.runs_root then return nil end
	return fs.runs_root .. "\\" .. filename
end

fs.index_path = function()
	if not fs.runs_root then return nil end
	return fs.runs_root .. "\\index.json"
end

-- Open a file for reading or writing. Returns handle or nil.
fs.open_read = function(path)
	return Mods.lua.io.open(path, "rb")
end

fs.open_append = function(path)
	return Mods.lua.io.open(path, "ab")
end

fs.open_write = function(path)
	return Mods.lua.io.open(path, "wb")
end

-- List files matching pattern in the runs folder, via `dir /B`.
fs.list_run_files = function()
	if not fs.runs_root then return {} end
	local handle = Mods.lua.io.popen(string.format('dir /B "%s\\*.run" 2>nul', fs.runs_root))
	if not handle then return {} end
	local files = {}
	for line in handle:lines() do
		files[#files + 1] = line
	end
	handle:close()
	return files
end

-- Delete a .run file from the runs folder. Returns true if the operation
-- was attempted (regardless of success on the OS side -- popen doesn't
-- expose exit code reliably). Returns false if the path couldn't be built.
fs.delete_run_file = function(filename)
	local path = fs.runs_path(filename)
	if not path then return false end
	local handle = Mods.lua.io.popen(string.format('del /F "%s" 2>nul', path))
	if handle then handle:close() end
	return true
end

-- Open Explorer at the runs folder (used by the keybind in Task 9).
fs.open_runs_folder = function()
	if not fs.runs_root then return end
	local handle = Mods.lua.io.popen(string.format('explorer "%s"', fs.runs_root))
	if handle then handle:close() end
end

return fs
