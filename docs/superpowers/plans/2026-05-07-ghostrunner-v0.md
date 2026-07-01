# GhostRunner v0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Darktide mod that records solo runs to JSONL files and replays them as a HUD-beacon "ghost" overlaid on a live solo run, with race-timer feedback.

**Architecture:** DMF mod with hard dependency on SoloPlay. Per-frame sampling of local player state at 20Hz writes a JSONL `.run` file. Replay loads a `.run` into memory, advances on a clock, drives a HUD beacon + nameplate via interpolation. Source-of-state is abstracted (`RemotePlayerSource`) so v1 live co-op can plug in a network source without touching the renderer.

**Tech Stack:** Lua (Bitsquid fork), Darktide Mod Framework (DMF), `cjson` for serialization, `Mods.lua.io` for filesystem, DMF widgets for HUD.

**Spec:** [`docs/superpowers/specs/2026-05-07-ghostrunner-v0-design.md`](../specs/2026-05-07-ghostrunner-v0-design.md)

---

## Testing model (read first)

Lua mods in Darktide can't be unit-tested in CI — they run inside the game process, with no Lua test framework. The substitute pattern in this plan:

- **Pure-data modules** (run_file, source, interpolation): include a temporary `mod:command(...)` that exercises the module against synthetic data and prints results to console. The engineer runs the command in-game (chat: `/<cmd>`) and visually verifies the console output. These verification commands are kept in code through development and removed in the final cleanup task.
- **In-game modules** (recorder, replayer, renderer, GhostRunner.lua): verification is "play a solo mission and observe the expected behavior in the console log."
- **Linting:** every task ends with `luacheck <files>` before commit. Treat warnings as errors unless `.luacheckrc` already excludes them.

Console log location: `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\console-<latest>.log`. Newest by mtime is the current session. Per CLAUDE.md, `print(...)` from a mod lands here.

Live iteration: run `symlink_mods.bat` once as Administrator. After that, edits in `quick_chat/.../scripts/...` are live in the game's mod folder via symlink. DMF supports hot-reload — toggle the mod off/on in the F4 menu after edits.

---

## File structure

All paths relative to repo root.

| Path | Responsibility |
|---|---|
| `GhostRunner/GhostRunner.mod` | DMF entry point (the `new_mod` registration) |
| `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` | Mod lifecycle, hook installation, `mod.update` fan-out |
| `GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua` | DMF mod options definition |
| `GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua` | Strings |
| `GhostRunner/scripts/mods/GhostRunner/fs.lua` | Filesystem helpers (path resolution, read/write/mkdir wrappers) |
| `GhostRunner/scripts/mods/GhostRunner/run_file.lua` | JSONL `.run` read/write, `index.json` maintenance |
| `GhostRunner/scripts/mods/GhostRunner/source.lua` | `RemotePlayerSource` interface + `ReplaySource` + `MockSource` |
| `GhostRunner/scripts/mods/GhostRunner/interpolation.lua` | Pure math (lerp, yaw_lerp, frame_at_t) |
| `GhostRunner/scripts/mods/GhostRunner/recorder.lua` | Sampling state machine, file handle lifecycle |
| `GhostRunner/scripts/mods/GhostRunner/replayer.lua` | Source consumption, mission auto-set, seed pinning |
| `GhostRunner/scripts/mods/GhostRunner/renderer.lua` | HUD beacon, nameplate, race timer |
| `GhostRunner/scripts/mods/GhostRunner/commands.lua` | Chat commands `/ghost list`/`load`/`clear`/`info` |

The repo will also have these new entries:

| Path | Responsibility |
|---|---|
| `symlink_mods.bat` (modify) | Add `GhostRunner` to the symlink loop |

---

## Task 1: Mod skeleton

Set up the DMF-required scaffolding. Mod loads, prints a hello banner, doesn't do anything else.

**Files:**
- Create: `GhostRunner/GhostRunner.mod`
- Create: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`
- Create: `GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua`
- Create: `GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua`
- Modify: `symlink_mods.bat` (add GhostRunner to the symlink set)

- [ ] **Step 1: Create `GhostRunner/GhostRunner.mod`**

```lua
return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`GhostRunner` encountered an error loading the Darktide Mod Framework.")

        new_mod("GhostRunner", {
            mod_script       = "GhostRunner/scripts/mods/GhostRunner/GhostRunner",
            mod_data         = "GhostRunner/scripts/mods/GhostRunner/GhostRunner_data",
            mod_localization = "GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization",
        })
    end,
    packages = {},
}
```

- [ ] **Step 2: Create `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`**

```lua
local mod = get_mod("GhostRunner")

mod:info("GhostRunner v0 loaded")

-- Hard dependency check: SoloPlay must be present and enabled.
local SoloPlay = get_mod("SoloPlay")
if not SoloPlay then
    mod:error("GhostRunner requires the SoloPlay mod to be installed and enabled.")
    return
end

mod.SoloPlay = SoloPlay

return mod
```

- [ ] **Step 3: Create `GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua`**

Minimal data file. Real options come in Task 9.

```lua
return {
    name = "GhostRunner",
    description = "mod_description",
    is_togglable = true,
    options = {
        widgets = {},
    },
}
```

- [ ] **Step 4: Create `GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua`**

```lua
return {
    mod_description = {
        en = "Record solo runs and replay them as a ghost.",
    },
}
```

- [ ] **Step 5: Add GhostRunner to `symlink_mods.bat`**

Read the existing file, locate the loop / list of mod folder names being symlinked, add `GhostRunner` next to the existing entries (`quick_chat`, `WitchLeash`).

- [ ] **Step 6: Re-run `symlink_mods.bat` as Administrator**

Verify the `GhostRunner` symlink appears in `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\`.

- [ ] **Step 7: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

Expected: no errors. (Warnings about unused vars are acceptable since the entry point is intentionally bare.)

- [ ] **Step 8: Smoke test in-game**

Launch Darktide. Open F4 mod menu. GhostRunner should appear and be toggleable.

Tail the latest console log:

```powershell
Get-Content (Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Fatshark\Darktide\console_logs\" -Filter "console-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName -Wait -Tail 50
```

Expected lines:
- `[Lua] INFO [Mod][GhostRunner] GhostRunner v0 loaded`

If SoloPlay is *not* installed, expect:
- `[Lua] ERROR [Mod][GhostRunner] GhostRunner requires the SoloPlay mod to be installed and enabled.`

- [ ] **Step 9: Commit**

```bash
git add GhostRunner/ symlink_mods.bat
git commit -m "feat(ghostrunner): add mod skeleton

Loads via DMF, declares hard dependency on SoloPlay,
checks at load time. No functionality yet."
```

---

## Task 2: Filesystem helpers

Provide path resolution + safe wrappers for `Mods.lua.io`. Handles AppData path discovery and `mkdir -p` semantics.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/fs.lua`

- [ ] **Step 1: Create `fs.lua`**

```lua
local mod = get_mod("GhostRunner")

local fs = {}

-- Discover %APPDATA% via popen — Mods.lua.io.popen is available per DLS pattern.
-- os.getenv reliability is uncertain in Bitsquid Lua, so we use the popen route.
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
    return fs.runs_root .. "\\" .. filename
end

fs.index_path = function()
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

-- Open Explorer at the runs folder (used by the keybind in Task 9).
fs.open_runs_folder = function()
    if not fs.runs_root then return end
    Mods.lua.io.popen(string.format('explorer "%s"', fs.runs_root))
end

return fs
```

- [ ] **Step 2: Wire `fs.lua` to load from the entry point**

In `GhostRunner.lua`, after the SoloPlay check, add:

```lua
mod.fs = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/fs")
mod.fs.ensure_runs_folder()
mod:info("GhostRunner runs folder: " .. tostring(mod.fs.runs_root))
```

- [ ] **Step 3: Add a verification command**

Append to `GhostRunner.lua`:

```lua
mod:command("ghost_test_fs", "GhostRunner: verify filesystem helpers", function()
    mod:info("[fs] runs_root: " .. tostring(mod.fs.runs_root))
    mod:info("[fs] runs_path('foo.run'): " .. tostring(mod.fs.runs_path("foo.run")))
    mod:info("[fs] index_path: " .. tostring(mod.fs.index_path()))
    mod:info("[fs] list_run_files: count=" .. tostring(#mod.fs.list_run_files()))
end)
```

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 5: Smoke test in-game**

Launch Darktide. Reload mods (F4 → toggle GhostRunner off and on, or restart game).

Open chat (Y), type: `/ghost_test_fs`

Tail the console log. Expected output (paths will differ):

```
[fs] runs_root: C:\Users\<you>\AppData\Roaming\Fatshark\Darktide\GhostRunner\runs
[fs] runs_path('foo.run'): C:\Users\<you>\AppData\Roaming\Fatshark\Darktide\GhostRunner\runs\foo.run
[fs] index_path: C:\Users\<you>\AppData\Roaming\Fatshark\Darktide\GhostRunner\runs\index.json
[fs] list_run_files: count=0
```

Verify the runs folder exists in Explorer at the printed path.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): filesystem helpers + AppData path discovery"
```

---

## Task 3: run_file.lua — write/read JSONL

Implements the on-disk format from spec §4. Pure data module — fully testable with verification commands.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/run_file.lua`

- [ ] **Step 1: Create `run_file.lua`**

```lua
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

-- Read a complete .run file. Returns {metadata, frames, footer} or nil + error.
run_file.read = function(filename)
    local path = fs.runs_path(filename)
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

    -- Sort frames by t ascending (defensive — JSONL is naturally ordered).
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
```

- [ ] **Step 2: Wire `run_file.lua` from entry point**

Add to `GhostRunner.lua` (after `mod.fs = ...`):

```lua
mod.run_file = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/run_file")
```

- [ ] **Step 3: Add a verification command**

Append to `GhostRunner.lua`:

```lua
mod:command("ghost_test_runfile", "GhostRunner: write+read a synthetic .run file", function()
    local filename = "test-synthetic.run"
    local meta = {
        player = "TestPlayer",
        class = "psyker",
        mission = {
            name = "throneside_damnation",
            difficulty = 5,
            circumstance = "default",
            side = nil,
            giver = "morrow",
            havoc = nil,
            seed = 1234567890,
        },
        recorded_at = "2026-05-07T14:32:11.000Z",
    }
    local writer = mod.run_file.create_writer(filename, meta)
    if not writer then
        mod:error("[runfile] writer creation failed")
        return
    end

    for i = 1, 5 do
        writer:append_frame({
            t = i * 0.05,
            p = { 10.0 + i, 20.0, 1.8 },
            y = 1.57,
            hp = 1.0,
            peril = 0.0,
            w = 3,
            d = false,
        })
    end

    writer:finalize("completed", 0.25, true, false)
    mod:info("[runfile] wrote " .. filename)

    local data, err = mod.run_file.read(filename)
    if not data then
        mod:error("[runfile] read failed: " .. tostring(err))
        return
    end

    mod:info(string.format(
        "[runfile] read OK: meta=%s frames=%d footer=%s partial=%s",
        data.metadata.player, #data.frames,
        data.footer and data.footer.outcome or "nil",
        tostring(data.partial)))
end)
```

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 5: Smoke test in-game**

Reload mod. Run `/ghost_test_runfile` in chat.

Expected console output:

```
[runfile] wrote test-synthetic.run
[runfile] read OK: meta=TestPlayer frames=5 footer=completed partial=false
```

Verify `test-synthetic.run` exists in `%APPDATA%\Fatshark\Darktide\GhostRunner\runs\` and open it in a text editor — should be 7 lines (1 meta + 5 frames + 1 footer), each a single JSON object.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): JSONL run file writer + reader"
```

---

## Task 4: Index file maintenance

`runs/index.json` for fast `/ghost list`. Self-healing on corruption (rebuild from folder scan).

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/run_file.lua` (add index functions)

- [ ] **Step 1: Add index helpers to `run_file.lua`**

Append to the bottom of the existing functions, before `return run_file`:

```lua
-- Index entry shape: { file, mission, difficulty, class, duration, outcome, recorded_at, seed, seed_pinned }

local function _index_entry_from_run(filename, data)
    return {
        file = filename,
        mission = data.metadata.mission and data.metadata.mission.name or "unknown",
        difficulty = data.metadata.mission and data.metadata.mission.difficulty,
        class = data.metadata.class,
        duration = data.footer and data.footer.duration or 0,
        outcome = data.footer and data.footer.outcome or "partial",
        recorded_at = data.metadata.recorded_at,
        seed = data.metadata.mission and data.metadata.mission.seed,
        seed_pinned = data.footer and data.footer.seed_pinned or false,
    }
end

run_file.read_index = function()
    local handle = fs.open_read(fs.index_path())
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
        return { schema = SCHEMA_VERSION, runs = {} }
    end
    return obj
end

run_file.write_index = function(index)
    -- Atomic write: write to .tmp, then rename.
    local tmp_path = fs.index_path() .. ".tmp"
    local handle = fs.open_write(tmp_path)
    if not handle then return false end
    handle:write(cjson.encode(index))
    handle:close()
    -- Replace existing index. On Windows, rename will fail if dest exists,
    -- so use `move /Y` via popen.
    local move_handle = Mods.lua.io.popen(string.format(
        'move /Y "%s" "%s" 2>nul', tmp_path, fs.index_path()))
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
```

- [ ] **Step 2: Update verification command to exercise the index**

Replace the `/ghost_test_runfile` command body in `GhostRunner.lua` with:

```lua
mod:command("ghost_test_runfile", "GhostRunner: write+read a synthetic .run + index", function()
    local filename = "test-synthetic.run"
    local meta = {
        player = "TestPlayer",
        class = "psyker",
        mission = {
            name = "throneside_damnation",
            difficulty = 5,
            circumstance = "default",
            side = nil,
            giver = "morrow",
            havoc = nil,
            seed = 1234567890,
        },
        recorded_at = "2026-05-07T14:32:11.000Z",
    }
    local writer = mod.run_file.create_writer(filename, meta)
    if not writer then
        mod:error("[runfile] writer creation failed")
        return
    end
    for i = 1, 5 do
        writer:append_frame({
            t = i * 0.05, p = { 10.0 + i, 20.0, 1.8 }, y = 1.57,
            hp = 1.0, peril = 0.0, w = 3, d = false,
        })
    end
    writer:finalize("completed", 0.25, true, false)
    mod:info("[runfile] wrote " .. filename)

    local data = mod.run_file.read(filename)
    mod:info(string.format("[runfile] read: %d frames, outcome=%s",
        #data.frames, data.footer.outcome))

    -- Append to index, read back.
    mod.run_file.append_to_index(filename, data)
    local idx = mod.run_file.read_index()
    mod:info(string.format("[runfile] index has %d entries", #idx.runs))

    -- Rebuild from scan and verify equivalence.
    mod.run_file.rebuild_index()
    local rebuilt = mod.run_file.read_index()
    mod:info(string.format("[runfile] rebuild: %d entries", #rebuilt.runs))
end)
```

- [ ] **Step 3: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/run_file.lua`

- [ ] **Step 4: Smoke test in-game**

Reload mod. Run `/ghost_test_runfile`.

Expected output:

```
[runfile] wrote test-synthetic.run
[runfile] read: 5 frames, outcome=completed
[runfile] index has 1 entries
[runfile] rebuild: 1 entries
```

Verify `index.json` exists in the runs folder and contains the synthetic run's metadata.

- [ ] **Step 5: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/run_file.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua
git commit -m "feat(ghostrunner): index.json maintenance with rebuild fallback"
```

---

## Task 5: Source abstraction + interpolation

The `RemotePlayerSource` interface plus `ReplaySource` (file-backed) and `MockSource` (scripted, used by replayer dev work). Pure data — fully testable.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/interpolation.lua`
- Create: `GhostRunner/scripts/mods/GhostRunner/source.lua`

- [ ] **Step 1: Create `interpolation.lua`**

```lua
local interpolation = {}

interpolation.lerp = function(a, b, t)
    return a + (b - a) * t
end

-- Linear interpolation on a Vector3-as-array {x, y, z}.
interpolation.lerp_v3 = function(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end

-- Angle lerp that takes the shorter arc.
interpolation.lerp_yaw = function(a, b, t)
    local diff = b - a
    -- Wrap diff into [-pi, pi]
    local PI = math.pi
    while diff > PI do diff = diff - 2 * PI end
    while diff < -PI do diff = diff + 2 * PI end
    return a + diff * t
end

-- Given sorted frames and elapsed time, return interpolated state.
-- Caller maintains an `idx` pointer for amortized O(1) advancement.
-- Returns: interpolated_frame, new_idx, finished
interpolation.frame_at = function(frames, idx, elapsed)
    local n = #frames
    if n == 0 then return nil, idx, true end
    if elapsed <= frames[1].t then
        return frames[1], 1, false
    end
    -- Advance idx until frames[idx+1].t > elapsed
    while idx + 1 <= n and frames[idx + 1].t <= elapsed do
        idx = idx + 1
    end
    if idx >= n then
        return frames[n], n, true
    end
    local a = frames[idx]
    local b = frames[idx + 1]
    local span = b.t - a.t
    local alpha = span > 0 and (elapsed - a.t) / span or 0
    local interp = {
        t = elapsed,
        p = interpolation.lerp_v3(a.p, b.p, alpha),
        y = interpolation.lerp_yaw(a.y, b.y, alpha),
        hp = interpolation.lerp(a.hp, b.hp, alpha),
        peril = interpolation.lerp(a.peril, b.peril, alpha),
        w = a.w,            -- step function
        d = a.d,            -- step function
    }
    return interp, idx, false
end

return interpolation
```

- [ ] **Step 2: Create `source.lua`**

```lua
local mod = get_mod("GhostRunner")
local interpolation = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/interpolation")

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
        peril = 0.5 + 0.5 * math.sin(self._elapsed * 0.7),
        w = 3,
        d = false,
    }, false
end

function MockSource:metadata()
    return { player = "Mock", class = "psyker", mission = { name = "mock" } }
end

return source
```

- [ ] **Step 3: Wire from entry point**

Add to `GhostRunner.lua`:

```lua
mod.interpolation = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/interpolation")
mod.source = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/source")
```

- [ ] **Step 4: Add a verification command**

Append to `GhostRunner.lua`:

```lua
mod:command("ghost_test_source", "GhostRunner: exercise ReplaySource and MockSource", function()
    -- ReplaySource against the synthetic file from Task 3-4.
    local data = mod.run_file.read("test-synthetic.run")
    if not data then
        mod:error("[source] need test-synthetic.run; run /ghost_test_runfile first")
        return
    end
    local rs = mod.source.create_replay_source(data)
    mod:info(string.format("[source] replay duration=%.2fs frames=%d",
        rs:duration(), #data.frames))

    -- Walk through 6 advances of 0.04s and print position. Should interpolate.
    for i = 1, 6 do
        local s, finished = rs:advance(0.04)
        mod:info(string.format("[source]   t=%.3f p=(%.2f,%.2f,%.2f) y=%.2f hp=%.2f finished=%s",
            s.t, s.p[1], s.p[2], s.p[3], s.y, s.hp, tostring(finished)))
    end

    -- MockSource sanity.
    local ms = mod.source.create_mock_source()
    for _ = 1, 3 do
        local s = ms:advance(0.5)
        mod:info(string.format("[source][mock] t=%.2f p=(%.2f,%.2f,%.2f)",
            s.t, s.p[1], s.p[2], s.p[3]))
    end
end)
```

- [ ] **Step 5: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 6: Smoke test in-game**

Reload mod. Run `/ghost_test_runfile` first to make sure the synthetic file exists, then `/ghost_test_source`.

Expected: 6 lines showing position interpolating between frames; should advance from t=0.04 → t=0.24, and position should walk from ~(11.0,20,1.8) toward ~(15.0,20,1.8). Final advance should report `finished=true` (since duration is 0.25s).

Mock source should show oscillating positions.

- [ ] **Step 7: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): RemotePlayerSource interface + ReplaySource + MockSource

Includes interpolation primitives (Vector3 lerp, angular yaw lerp, frame_at).
Architectural seam for v1 NetworkSource."
```

---

## Task 6: Recorder skeleton + spawn hook

The recorder state machine. Hooks `on_player_unit_spawn`, gates on SoloPlay, transitions states. Sampling implementation comes in Task 7.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/recorder.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Create `recorder.lua`**

```lua
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
```

- [ ] **Step 2: Wire and install the spawn hook in `GhostRunner.lua`**

Add to `GhostRunner.lua` after the source line:

```lua
mod.recorder = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/recorder")

mod:hook(CLASS.GameModeManager, "on_player_unit_spawn",
    function(func, self, player, player_unit, is_respawn)
        func(self, player, player_unit, is_respawn)

        if is_respawn then return end

        -- Identity: must be the local player.
        local local_player = Managers.player and Managers.player:local_player(1)
        if not local_player or local_player:player_unit() ~= player_unit then
            return
        end

        -- Only in solo sessions.
        if not mod.SoloPlay.is_soloplay() then return end

        -- TODO Task 9: also gate on mod:get("record_runs"). For now always record.
        mod.recorder.start(player, player_unit)
    end)
```

- [ ] **Step 3: Add a status command**

Append to `GhostRunner.lua`:

```lua
mod:command("ghost_status", "GhostRunner: print recorder/replayer status", function()
    mod:info("recorder state: " .. mod.recorder.state())
    mod.recorder._dump()
end)
```

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 5: Smoke test in-game**

Reload mod. Open `/ghost_status` — expect `recorder state: idle`.

Now launch a SoloPlay mission (any mission, any difficulty) via SoloPlay's UI (`/solo` chat command opens the menu). Once you spawn into the level, run `/ghost_status` again.

Expected:
- Console log shows `recorder: started <filename> (mission=<name> seed=<int-or-nil>)`
- `/ghost_status` reports `recorder state: recording`
- A new empty-ish `.run` file appears in the runs folder (it'll have just the metadata line — frames come in Task 7).

If `seed=nil`, that's not a failure for v0 — the `_read_level_seed` paths are best-effort and may need refinement. Note this in the commit message and proceed.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): recorder skeleton + on_player_unit_spawn hook

Recorder state machine, gates (solo + first spawn + local player),
metadata capture from SoloPlay settings, file creation. Sampling and
finalization are stubs."
```

---

## Task 7: Recorder sampling

Per-frame state read + accumulator-driven 20Hz sampling. Frames buffer in memory and append to the open file handle.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/recorder.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Implement `recorder.tick(dt)` and `recorder.sample()`**

Replace the stub `recorder.tick = function(dt) ... end` in `recorder.lua` with:

```lua
local function _read_state(unit)
    -- Position
    local pos = Unit.world_position(unit, 1)
    local p = { Vector3.to_elements(pos) }

    -- Yaw (Quaternion -> yaw)
    local rot = Unit.local_rotation(unit, 1)
    local y = Quaternion.yaw(rot)

    -- HP
    local hp = 0
    local hp_ext = ScriptUnit.has_extension(unit, "health_system")
    if hp_ext then
        -- Try common API surfaces; verified during smoke test.
        if hp_ext.current_health_percent then
            hp = hp_ext:current_health_percent()
        elseif hp_ext.current_health and hp_ext.max_health then
            local cur = hp_ext:current_health()
            local mx = hp_ext:max_health()
            hp = mx > 0 and (cur / mx) or 0
        end
    end

    -- Peril (warp_charge component)
    local peril = 0
    local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
    if unit_data then
        local wc = unit_data:read_component("warp_charge")
        if wc and wc.current_percentage then
            peril = wc.current_percentage
        end
    end

    -- Wounds
    local w = 0
    if hp_ext and hp_ext.num_wounds then
        w = hp_ext:num_wounds()
    elseif unit_data then
        local hc = unit_data:read_component("health")
        w = (hc and hc.current_wounds) or 0
    end

    -- Downed/dead
    local d = false
    local csm = ScriptUnit.has_extension(unit, "character_state_machine_system")
    if csm and csm.current_state then
        local cs = csm:current_state()
        if cs == "knocked_down" or cs == "dead" or cs == "hogtied" or cs == "consumed" then
            d = true
        end
    end

    return p, y, hp, peril, w, d
end

local function _flush(writer)
    writer:flush()
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

        local ok, p, y, hp, peril, w, d = pcall(_read_state, _state.player_unit)
        if not ok then
            mod:warning("recorder: read_state failed: " .. tostring(p))
            return
        end

        _state.writer:append_frame({
            t = _state.last_sample_t,
            p = p,
            y = y,
            hp = hp,
            peril = peril,
            w = w,
            d = d,
        })
        _state.flush_frame_count = _state.flush_frame_count + 1
    end

    if _state.flush_frame_count >= FLUSH_FRAME_THRESHOLD
       or _state.flush_accumulator >= FLUSH_INTERVAL then
        _flush(_state.writer)
        _state.flush_accumulator = 0
        _state.flush_frame_count = 0
    end
end

recorder._abandon = function(outcome)
    if _state.name ~= STATE.recording then return end
    if _state.writer then
        _state.writer:finalize(outcome or "aborted",
            _state.last_sample_t, _state.seed ~= nil, false)
        run_file.append_to_index(_state.filename, run_file.read(_state.filename))
        _state.writer = nil
    end
    _state.name = STATE.finalized
    mod:info(string.format("recorder: abandoned (outcome=%s, %.2fs)",
        outcome or "aborted", _state.last_sample_t))
end
```

- [ ] **Step 2: Wire `recorder.tick(dt)` from `mod.update`**

Add to `GhostRunner.lua` (anywhere after the recorder is loaded):

```lua
mod.update = function(dt)
    mod.recorder.tick(dt)
end
```

- [ ] **Step 3: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/recorder.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 4: Smoke test in-game**

Reload mod. Launch a SoloPlay mission. Walk around for ~30 seconds. Then leave the mission ("Leave Mission" from the system menu) — this triggers `mission_cleanup`, which is still a stub, so the recording will be abandoned mid-flight. That's OK for this task.

Expected:
- Console log shows recording started.
- Console log shows `recorder: abandoned (outcome=aborted, ~30.00s)` after leaving the mission. Wait — `mission_cleanup` isn't wired yet, so this won't fire from `mission_cleanup`. The unit will become invalid eventually and the defensive check will fire. If it doesn't fire cleanly, force it via `/ghost_status` which calls `recorder._dump`, then test exit-to-hub from the mission menu and verify the run file size grows during play.

Critical verification: open the latest `.run` file after walking around. Should contain ~600 frames (30s × 20Hz). Each frame should have plausible XYZ (Darktide world coords are large numbers, often hundreds), HP=1.0 if undamaged, etc.

If `peril` is always 0 even on a Psyker who's casting Brain Burst, the `unit_data:read_component("warp_charge")` path is wrong — investigate via [unit_data_system](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/extension_systems/unit_data/unit_data_system.lua) and update `_read_state`.

If `hp` is always 0, `health_system` extension key may differ — check by listing extensions on a player_unit (add a debug line: `for k, _ in pairs(ScriptUnit.extensions(player_unit)) do print(k) end`).

- [ ] **Step 5: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): recorder sampling at 20Hz + buffered flush

Per-frame reads of position, yaw, HP, peril, wounds, downed state.
Defensive on Unit.alive; abandons gracefully if unit invalidates."
```

---

## Task 8: Recorder finalization (mission_cleanup hook)

Hook the mission-end teardown, write the footer, update the index, transition to idle for the next run.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/recorder.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Implement `recorder.stop_and_save`**

Replace the stub `recorder.stop_and_save` in `recorder.lua`:

```lua
recorder.stop_and_save = function(outcome, on_shutdown)
    if _state.name ~= STATE.recording then return end
    if not _state.writer then return end

    _flush(_state.writer)
    local mapped_outcome
    if outcome == "completed" or outcome == "complete" or outcome == "won" then
        mapped_outcome = "completed"
    elseif outcome == "fail" or outcome == "failed" or outcome == "lost" then
        mapped_outcome = "failed"
    else
        mapped_outcome = "aborted"
    end

    _state.writer:finalize(mapped_outcome, _state.last_sample_t,
        _state.seed ~= nil, on_shutdown)
    _state.writer = nil

    -- Reload the just-written file to populate the index entry from canonical data.
    local data = run_file.read(_state.filename)
    if data then
        run_file.append_to_index(_state.filename, data)
    end

    mod:info(string.format("recorder: saved %s (outcome=%s, %.2fs)",
        _state.filename, mapped_outcome, _state.last_sample_t))

    -- Reset for the next mission.
    _state.name = STATE.idle
    _state.writer = nil
    _state.player_unit = nil
    _state.last_sample_t = 0
    _state.accumulator = 0
    _state.flush_accumulator = 0
    _state.flush_frame_count = 0
end
```

- [ ] **Step 2: Install the `mission_cleanup` hook**

Add to `GhostRunner.lua` (after the on_player_unit_spawn hook):

```lua
mod:hook_require("scripts/managers/game_mode/game_modes/game_mode_base",
    function(GameModeBase)
        mod:hook(GameModeBase, "mission_cleanup",
            function(func, self, on_shutdown)
                local outcome = self._state or "aborted"
                mod.recorder.stop_and_save(outcome, on_shutdown)
                func(self, on_shutdown)
            end)
    end)
```

- [ ] **Step 3: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 4: Smoke test in-game**

Reload mod. Run a SoloPlay mission — try three exit paths:

1. **Complete the mission** (extract). Expected: `recorder: saved <file> (outcome=completed, NNN.NNs)` in console.
2. **Quit to hub mid-mission** ("Leave Mission" → "Yes"). Expected: `recorder: saved <file> (outcome=aborted, NNN.NNs)`.
3. **Wipe** (intentionally die). Expected: `recorder: saved <file> (outcome=failed, NNN.NNs)`.

Each `.run` file should now have a complete footer line. Open in a text editor and verify the last line is `{"type":"end","outcome":...}`.

`/ghost_test_runfile` should still work; the index now has multiple entries. Run `cat` on `index.json` and verify all real runs are listed alongside the test entry.

- [ ] **Step 5: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): finalize recordings on mission_cleanup

Maps game mode state to outcome (completed/failed/aborted), writes
end footer, updates index. Recorder transitions back to idle for next mission."
```

---

## Task 9: DMF settings panel

The user-facing options panel. Adds the `record_runs` toggle that gates the recorder, plus replay-mode dropdown and HUD toggle (used in later tasks).

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` (gate recorder, add keybind handler)

- [ ] **Step 1: Update `GhostRunner_data.lua`**

```lua
return {
    name = "GhostRunner",
    description = "mod_description",
    is_togglable = true,
    options = {
        widgets = {
            { setting_id = "header_recording", widget_type = "group", title = "header_recording" },
            {
                setting_id = "record_runs",
                type = "checkbox",
                default_value = true,
                title = "record_runs",
                tooltip = "record_runs_tooltip",
            },
            { setting_id = "header_replay", widget_type = "group", title = "header_replay" },
            {
                setting_id = "replay_mode",
                type = "dropdown",
                default_value = "off",
                title = "replay_mode",
                tooltip = "replay_mode_tooltip",
                options = {
                    { text = "replay_mode_off",       value = "off" },
                    { text = "replay_mode_race",      value = "race" },
                    { text = "replay_mode_spectator", value = "spectator" },
                },
            },
            {
                setting_id = "show_race_timer",
                type = "checkbox",
                default_value = true,
                title = "show_race_timer",
                tooltip = "show_race_timer_tooltip",
            },
            { setting_id = "header_files", widget_type = "group", title = "header_files" },
            {
                setting_id = "open_runs_folder",
                type = "keybind",
                default_value = {},
                title = "open_runs_folder",
                tooltip = "open_runs_folder_tooltip",
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "open_runs_folder_keybind",
            },
        },
    },
}
```

Note the keybind config style — verify against an existing mod's data file at implementation time. Reference pattern: open `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\dmf\scripts\mods\dmf\modules\ui\options\mod_options.lua` and search for `_type_template_map["keybind"]` to see the exact schema. Concretely: `function_name` references a function exposed on the mod table that DMF will invoke when the bound key fires.

- [ ] **Step 2: Add localization strings**

Replace `GhostRunner_localization.lua`:

```lua
return {
    mod_description = {
        en = "Record solo runs and replay them as a ghost.",
    },
    header_recording = { en = "Recording" },
    header_replay = { en = "Replay" },
    header_files = { en = "Files" },

    record_runs = { en = "Record runs automatically" },
    record_runs_tooltip = {
        en = "When ON, every solo mission is recorded to a .run file in your AppData folder.",
    },

    replay_mode = { en = "Replay mode" },
    replay_mode_tooltip = {
        en = "Off: no ghost. Race: play normally with a ghost overlay. " ..
             "Spectator: stand still and watch the ghost. (Race and Spectator " ..
             "are functionally identical in v0 — choose by intent.)",
    },
    replay_mode_off = { en = "Off" },
    replay_mode_race = { en = "Race" },
    replay_mode_spectator = { en = "Spectator" },

    show_race_timer = { en = "Show race timer HUD" },
    show_race_timer_tooltip = {
        en = "Display a small widget showing ghost time and your delta.",
    },

    open_runs_folder = { en = "Open runs folder" },
    open_runs_folder_tooltip = {
        en = "Press to open the .run files folder in Explorer.",
    },
}
```

- [ ] **Step 3: Gate the recorder on `record_runs` setting**

In `GhostRunner.lua`, modify the `on_player_unit_spawn` hook body to add the gate. Replace the existing gate block with:

```lua
        -- Identity: must be the local player.
        local local_player = Managers.player and Managers.player:local_player(1)
        if not local_player or local_player:player_unit() ~= player_unit then
            return
        end

        -- Only in solo sessions.
        if not mod.SoloPlay.is_soloplay() then return end

        -- User setting.
        if not mod:get("record_runs") then return end

        mod.recorder.start(player, player_unit)
```

- [ ] **Step 4: Implement the keybind callback**

Add to `GhostRunner.lua`:

```lua
mod.open_runs_folder_keybind = function()
    mod.fs.open_runs_folder()
end
```

- [ ] **Step 5: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 6: Smoke test in-game**

Reload mod. Open the F4 mod menu and click GhostRunner's settings. Verify:

- Three section headers (Recording / Replay / Files).
- Checkbox: "Record runs automatically" defaults ON.
- Dropdown: "Replay mode" with three options.
- Checkbox: "Show race timer HUD" defaults ON.
- Keybind: "Open runs folder" — bind a key (e.g., F11), close menu, press it. Explorer should open at the runs folder.

Toggle "Record runs" OFF and start a SoloPlay mission. Verify no `.run` file is created and console doesn't show "recorder: started".

Toggle ON, restart mission, verify recording resumes.

- [ ] **Step 7: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): DMF settings panel + record_runs gate + open-folder keybind"
```

---

## Task 10: Chat commands (/ghost list/load/clear/info)

The ghost picker UX. Wires user-facing commands; the actual replay machinery comes in Tasks 12-15.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/commands.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Create `commands.lua`**

```lua
local mod = get_mod("GhostRunner")
local run_file = mod.run_file

local commands = {}

-- _selected: the currently chosen ghost. Set by /ghost load. Read by replayer.
mod._selected_ghost = nil  -- { filename, data }

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
        mod:notify("GhostRunner: no saved runs yet.")
        return
    end
    mod:notify(_color("GhostRunner — saved runs (newest first):", 200, 200, 255))
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
        mod:notify(line)
    end
end

commands.cmd_load = function(arg)
    if not arg or arg == "" then
        mod:notify("Usage: /ghost load <number-from-list> or <filename>")
        return
    end

    local idx = run_file.read_index()
    local entry

    -- Numeric → index into list.
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
        mod:notify("Could not find that run. Try /ghost list.")
        return
    end

    local data = run_file.read(entry.file)
    if not data then
        mod:notify("Could not read " .. entry.file .. " — maybe corrupt?")
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

    mod:notify(string.format("Loaded: %s D%s (%s, %s). Mission params auto-set. Hit Start in SoloPlay.",
        m and m.name or "?",
        tostring(m and m.difficulty or "?"),
        _format_duration(data.footer and data.footer.duration or 0),
        data.footer and data.footer.outcome or "partial"))
end

commands.cmd_clear = function()
    mod._selected_ghost = nil
    mod:notify("Ghost cleared.")
end

commands.cmd_info = function()
    if not mod._selected_ghost then
        mod:notify("No ghost loaded. Use /ghost load <n> after /ghost list.")
        return
    end
    local g = mod._selected_ghost
    local m = g.data.metadata.mission
    local dur = g.data.footer and g.data.footer.duration or 0
    mod:notify(string.format("Ghost: %s D%s  duration=%s  frames=%d  seed=%s%s",
        m and m.name or "?",
        tostring(m and m.difficulty or "?"),
        _format_duration(dur),
        #g.data.frames,
        tostring(m and m.seed or "?"),
        g.data.partial and " [partial]" or ""))
end

return commands
```

- [ ] **Step 2: Wire commands from entry point**

Add to `GhostRunner.lua` (after `mod.recorder = ...`):

```lua
mod.commands = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/commands")

mod:command("ghost", "GhostRunner: ghost picker — see /ghost help", function(arg)
    arg = arg or ""
    local sub, rest = arg:match("^(%S+)%s*(.*)$")
    sub = sub or ""

    if sub == "list" then
        mod.commands.cmd_list()
    elseif sub == "load" then
        mod.commands.cmd_load(rest)
    elseif sub == "clear" then
        mod.commands.cmd_clear()
    elseif sub == "info" then
        mod.commands.cmd_info()
    elseif sub == "help" or sub == "" then
        mod:notify("Commands: /ghost list | /ghost load <n> | /ghost clear | /ghost info")
    else
        mod:notify("Unknown subcommand. Try /ghost help.")
    end
end)
```

Note: DMF's `mod:command` passes the rest of the chat line as a single string argument, so we parse the first word as the subcommand and the remainder as the arg.

- [ ] **Step 3: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 4: Smoke test in-game**

Make sure you have at least one real run from earlier tasks. If not, run a SoloPlay mission to generate one.

In chat:
- `/ghost help` — expect command summary
- `/ghost list` — expect a colored header + numbered list of runs, newest first
- `/ghost load 1` — expect "Loaded: ..." notification, and SoloPlay's mission selector should now reflect the loaded ghost's mission/difficulty
- `/ghost info` — expect details
- `/ghost clear` — expect "Ghost cleared"
- `/ghost list` again — expect the `[LOADED]` marker is gone

Open SoloPlay's UI (`/solo`) after `/ghost load 1` and verify the mission/difficulty fields match the ghost.

- [ ] **Step 5: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): /ghost chat commands (list, load, clear, info)

Loading a ghost auto-sets SoloPlay mission params via mod:set."
```

---

## Task 11: Replayer skeleton + state machine

State machine that watches for player_unit_spawn and starts feeding a `RemotePlayerSource` into the renderer (next task). Renderer is still a stub here; we just verify state transitions.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/replayer.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Create `replayer.lua`**

```lua
local mod = get_mod("GhostRunner")
local source_module = mod.source

local replayer = {}

local STATE = { idle = "idle", armed = "armed", playing = "playing", finished = "finished" }

local _state = {
    name = STATE.idle,
    source = nil,
    last_state = nil,    -- last interpolated frame, for renderer consumption
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
        replayer.disarm()
        mod:notify("Ghost mission unknown — replay disabled this run.")
        return
    end
    local sp = mod.SoloPlay
    local current_mission = sp:get("choose_mission")
    if current_mission ~= meta.mission.name then
        mod:warning(string.format("replayer: mission mismatch (selected=%s, ghost=%s)",
            tostring(current_mission), meta.mission.name))
        mod:notify("Ghost mission mismatch — replay disabled this run.")
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
            os.date("!%M:%S", _state.source:duration())))
    end
end

return replayer
```

- [ ] **Step 2: Wire replayer + arm on /ghost load + tick from mod.update**

In `GhostRunner.lua`:

```lua
mod.replayer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/replayer")
```

In `commands.lua`'s `cmd_load`, after setting `mod._selected_ghost`, add:

```lua
    mod.replayer.arm_with_selected_ghost()
```

In `commands.lua`'s `cmd_clear`, after `mod._selected_ghost = nil`, add:

```lua
    mod.replayer.disarm()
```

In the `on_player_unit_spawn` hook in `GhostRunner.lua`, after the recorder gating block, add:

```lua
        -- Replayer: try to enter playing state if armed.
        mod.replayer.on_local_player_spawn()
```

Update `mod.update`:

```lua
mod.update = function(dt)
    mod.recorder.tick(dt)
    mod.replayer.tick(dt)
end
```

In the `mission_cleanup` hook, after `recorder.stop_and_save`, add:

```lua
                if mod.replayer.state() ~= "idle" then
                    mod.replayer.disarm()
                end
```

- [ ] **Step 3: Add a status line to the /ghost_status command**

Update the `/ghost_status` command body in `GhostRunner.lua`:

```lua
mod:command("ghost_status", "GhostRunner: print recorder/replayer status", function()
    mod:info("recorder state: " .. mod.recorder.state())
    mod.recorder._dump()
    mod:info(string.format("replayer state: %s, elapsed=%.2fs/%.2fs",
        mod.replayer.state(), mod.replayer.elapsed(), mod.replayer.duration()))
    if mod.replayer.last_state() then
        local s = mod.replayer.last_state()
        mod:info(string.format("replayer last_state: t=%.2f p=(%.1f,%.1f,%.1f) hp=%.2f",
            s.t, s.p[1], s.p[2], s.p[3], s.hp))
    end
end)
```

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 5: Smoke test in-game**

Reload mod. Need at least one ghost in the index.

1. `/ghost load 1` — expect armed
2. Set replay mode to "Race" via the F4 menu (or it stays "off" and replayer stays idle).
3. `/ghost_status` — expect `replayer state: armed`
4. Launch the SAME mission as the ghost. After spawning, `/ghost_status` should report `replayer state: playing`, with `last_state` showing interpolated values.
5. Play for a bit, then leave the mission. `/ghost_status` should return `replayer state: idle`.

Mismatch test:
1. Load a ghost recorded for mission A.
2. Manually change SoloPlay's mission to mission B.
3. Start mission B. Expect notification "Ghost mission mismatch — replay disabled this run." in chat. `/ghost_status` should show `replayer state: idle`.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): replayer state machine

Arms on /ghost load, plays on player_unit_spawn (with mission-match gate),
disarms on mission_cleanup. Renderer not yet wired."
```

---

## Task 12: Seed pinning attempt

Try to force `level_seed` to match the loaded ghost. Best-effort with two fallbacks; logs the outcome.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/replayer.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Add `replayer.try_pin_seed()` and call it on arm**

Add to `replayer.lua` (near the top, before functions):

```lua
local _seed_pin_active = false   -- true if our session_seed override should fire
local _pinned_seed_value = nil
```

Add as new functions:

```lua
local function _try_set_game_parameters_seed(seed)
    -- Path 1: direct write to GameParameters.level_seed.
    local ok = pcall(function()
        rawset(GameParameters, "level_seed", seed)
    end)
    if not ok then return false end
    -- Verify it stuck.
    return GameParameters.level_seed == seed
end

local function _install_session_seed_hook(seed)
    -- Path 2: wrap Managers.connection:session_seed to return our seed
    -- when seed-pin is active.
    if not Managers.connection or not Managers.connection.session_seed then
        return false
    end
    -- Use mod:hook on the live instance via its metatable class.
    -- Instance hooks aren't supported by DMF, so hook the class.
    -- Connection class is at scripts/multiplayer/connection/connection_client.lua,
    -- but session_seed may be on a parent — hook via require path.
    -- For v0 simplicity, monkey-patch the instance method.
    local original = Managers.connection.session_seed
    if Managers.connection.__ghostrunner_seed_patched then return true end
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
        _seed_pin_active = false
        mod:info(string.format("replayer: seed pinned via GameParameters: %d", seed))
        return true
    end

    -- Fallback: session_seed hook.
    if _install_session_seed_hook(seed) then
        _seed_pin_active = true
        _pinned_seed_value = seed
        mod:info(string.format("replayer: seed pinned via session_seed hook: %d", seed))
        return true
    end

    mod:warning("replayer: could not pin seed — replay will use engine seed")
    return false
end

replayer.unpin_seed = function()
    _seed_pin_active = false
    _pinned_seed_value = nil
    -- We deliberately do NOT un-monkey-patch Managers.connection.session_seed —
    -- the patch checks `_seed_pin_active` so it's a no-op when disabled.
end
```

- [ ] **Step 2: Call `try_pin_seed` in `arm_with_selected_ghost`**

At the bottom of `arm_with_selected_ghost`, just before `return true`, add:

```lua
    local m = _state.source:metadata().mission
    replayer.try_pin_seed(m and m.seed)
```

- [ ] **Step 3: Call `unpin_seed` in `disarm`**

Update `disarm`:

```lua
replayer.disarm = function()
    _state.name = STATE.idle
    _state.source = nil
    _state.last_state = nil
    replayer.unpin_seed()
end
```

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/replayer.lua`

- [ ] **Step 5: Smoke test in-game**

Reload mod. `/ghost load 1` (where the loaded ghost has a non-nil seed in metadata).

Expected console output one of:
- `replayer: seed pinned via GameParameters: <seed>`
- `replayer: seed pinned via session_seed hook: <seed>`
- `replayer: could not pin seed — replay will use engine seed`

Launch the matched mission. After spawning, run `/ghost_status` — `recorder._dump` should show the recording's seed, which (if pinning worked) should equal the ghost's seed.

If neither pinning path succeeds, this is OK for v0 — the replay still works as positional data.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/replayer.lua
git commit -m "feat(ghostrunner): seed pinning attempt with two fallbacks

Tries GameParameters.level_seed direct write, falls back to
session_seed monkey-patch. Logs outcome; failure is non-fatal."
```

---

## Task 13: HUD beacon + nameplate (renderer)

The visible ghost. World-anchored marker at the interpolated position with HP/peril/wounds bars.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/renderer.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Research — inspect existing reference implementations**

This task is the riskiest in the plan. Spend time reading working code before writing any. Three concrete references to consult, in order:

1. **`true_level/scripts/mods/true_level/elements/nameplate.lua`** (in your installed-mods folder at `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\true_level\`) — a working DMF HUD element that shows custom info above other players. Closest pattern to what we're building. Read end-to-end before writing.

2. **The world-marker system** — Darktide has `Managers.event:trigger("add_world_marker", ...)` and `register_world_marker_template`. Used by `ForTheEmperor`'s `need_help.lua`. Worth checking whether it's a better primitive than a screen-space widget for the beacon:

   ```bash
   gh api -X GET "search/code" -f q="register_world_marker_template repo:Aussiemon/Darktide-Source-Code path:scripts/managers/ui" --jq '.items[] | .path'
   ```

3. **DMF wiki page**: `https://raw.githubusercontent.com/wiki/Darktide-Mod-Framework/Darktide-Mod-Framework/hud-elements.md` (per CLAUDE.md, fetch as raw markdown).

**Decision criteria:** if the world-marker system supports custom render with bars, prefer it (cleaner than manual world→screen projection). Otherwise, use a custom DMF HUD element + `Camera.world_to_screen` per-tick (the approach the rest of this task assumes).

Document the decision in a one-line comment at the top of `renderer.lua` so future maintainers know which path was chosen.

- [ ] **Step 2: Create `renderer.lua`**

```lua
local mod = get_mod("GhostRunner")

local renderer = {}

-- The renderer is driven from `mod.update`. Each tick it asks the replayer
-- for the latest state and re-positions the HUD widget.
--
-- For v0 we use the screen-space projection approach: the widget is a
-- screen-space DMF HUD element; each tick we project the ghost's world
-- position into screen coords via Camera.world_to_screen and update
-- the widget's `offset` to that screen position.

local _hud_class_name = "GhostRunnerBeacon"
local _hud_element = nil  -- cached lookup

local function _get_hud_element()
    if _hud_element and _hud_element._is_alive ~= false then
        return _hud_element
    end
    local hud = Managers.ui and Managers.ui:get_hud()
    if not hud then return nil end
    _hud_element = hud:element(_hud_class_name)
    return _hud_element
end

renderer.show = function()
    local el = _get_hud_element()
    if el and el.set_active then el:set_active(true) end
end

renderer.hide = function()
    local el = _get_hud_element()
    if el and el.set_active then el:set_active(false) end
end

renderer.tick = function(dt)
    local rs = mod.replayer
    if rs.state() ~= "playing" then
        renderer.hide()
        return
    end

    local s = rs.last_state()
    if not s then return end

    local el = _get_hud_element()
    if not el then return end
    el:set_active(true)
    if el.set_state then el:set_state(s) end
end

return renderer
```

- [ ] **Step 3: Build the simplest viable HUD element first**

Build incrementally. The first version is a HUD element that just prints `"GhostRunner: ghost is at world (X, Y, Z)"` somewhere on screen — no positioning, no bars, no projection. Verify mod can register a HUD element at all. Then iterate.

**3a — Copy `true_level`'s nameplate.lua wholesale into `GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua` as a starting point.** Replace the class name with `GhostRunnerBeacon`. Strip the level-display logic. Keep the widget scaffolding (scenegraph_definition, widget_definitions, init/destroy/update lifecycle).

**3b — Adapt the widget definition to a single text widget that says "GHOST".** Position it at a fixed screen offset for now (e.g., center of screen). Per CLAUDE.md HUD gotchas:
- In `init`, set `widget.visible = false` after `super.init`.
- Implement `set_active(self, active)` that sets `widget.visible = active`.

**3c — Register the element from `GhostRunner.lua`:**

```lua
mod:add_require_path("GhostRunner/scripts/mods/GhostRunner/hud_beacon")
mod:register_hud_element({
    class_name = "GhostRunnerBeacon",
    filename = "GhostRunner/scripts/mods/GhostRunner/hud_beacon",
    visibility_groups = { "alive", "dead" },
    use_hud_scale = true,
    validation_function = function() return mod.replayer.state() == "playing" end,
})
```

(Verify `register_hud_element` syntax — the DMF wiki page `hud-elements` is canonical. If the call signature here is wrong, adapt to match.)

**3d — Test 3a-c in-game.** Race against a ghost. Expect the "GHOST" text widget to appear when replay is playing, hide when not. If this works, you have a foundation; if not, debug the registration / lifecycle before moving on.

- [ ] **Step 4: Add world-to-screen projection**

Update `set_state` (called from `renderer.tick`) to project the ghost's world position into screen coordinates and reposition the widget:

```lua
element.set_state = function(self, state)
    local world = Managers.world and Managers.world:world("level_world")
    if not world then return end
    local viewport = ScriptWorld.viewport(world, "default_viewport")  -- verify name
    local cam = ScriptViewport.camera(viewport)
    if not cam then return end

    local world_pos = Vector3(state.p[1], state.p[2], state.p[3])
    local cam_pos = Camera.world_to_screen(cam, world_pos)

    -- cam_pos returns Vector3 with screen-x, screen-y, depth.
    local screen_x = cam_pos[1] or 0
    local screen_y = cam_pos[2] or 0
    local on_screen = (cam_pos[3] or 1) > 0

    if not on_screen then
        self:set_active(false)
        return
    end

    self:set_active(true)
    for _, w in pairs(self._widgets_by_name) do
        w.offset[1] = screen_x
        w.offset[2] = screen_y
    end
end
```

Exact viewport/camera-access API names need verification — search the Aussiemon source for `ScriptViewport.camera` / `Camera.world_to_screen` / `Managers.world:world` to confirm.

Test: launch race; verify the widget tracks the ghost's position as you move around.

- [ ] **Step 5: Add HP/peril/wound bars**

With positioning working, extend the widget definition to add three bars below the text. Reference [true_level's nameplate](file://C:/Program Files (x86)/Steam/steamapps/common/Warhammer 40,000 DARKTIDE/mods/true_level/scripts/mods/true_level/elements/nameplate.lua) for bar widget patterns — likely `pass_type = "rect"` with a `style.color` driven from state.

For dynamic bar fills (and per CLAUDE.md gotchas):
- Bars are rectangles. Update `widget.style.bar.size[1]` to `state.hp * max_bar_width` etc.
- Texture-color mutations don't need `widget.dirty = true` — but text font_size mutations DO. We have no font_size mutations here.

Test: verify HP bar shrinks as ghost takes damage in the recording, peril bar fills as ghost casts.

This step is iterative — expect 1-2 hours of "looks wrong, tweak, reload, test."

- [ ] **Step 6: Wire renderer.tick from mod.update**

In `GhostRunner.lua`, update `mod.update`:

```lua
mod.update = function(dt)
    mod.recorder.tick(dt)
    mod.replayer.tick(dt)
    mod.renderer.tick(dt)
end

mod.renderer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/renderer")
```

(Make sure the assignment runs before mod.update is set, or handle nil safely.)

- [ ] **Step 7: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 8: Smoke test in-game**

Reload mod. `/ghost load 1`, set replay mode to Race, launch the matching mission.

Expected: a small beacon icon + HP bar + peril bar appears at the ghost's screen-projected position. As you walk around, the beacon stays anchored to the ghost's world position.

When the ghost is behind you (off-screen), the beacon should disappear (or clamp to screen edge — depends on implementation). When the ghost is occluded by geometry, it should still render visible (we want through-walls visibility).

Common issues:
- Beacon at (0,0): `Camera.world_to_screen` failed — check world reference name (`"level_world"` vs other).
- Bars don't update: check `widget.dirty = true` after font_size mutations or other mutations the renderer doesn't auto-detect.
- Widget always invisible: check the visibility flow (`set_active` getting called, `widget.visible` actually setting).

- [ ] **Step 9: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): HUD beacon + nameplate

World-anchored beacon at ghost's interpolated position; HP/peril/wounds
bars. Visible through walls. Hidden when replayer is not in 'playing' state."
```

---

## Task 14: Race timer HUD

Small widget showing ghost elapsed time + delta-from-live.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/renderer.lua`
- Create: `GhostRunner/scripts/mods/GhostRunner/hud_timer.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua`

- [ ] **Step 1: Create `hud_timer.lua`**

A simple text-only HUD widget showing two lines:
```
Ghost: 03:12
Δ -00:14
```

Pattern follows the same DMF HUD element structure as Task 13. Reference an existing simple HUD mod (like a clock or kill-counter mod) for the boilerplate.

```lua
local mod = get_mod("GhostRunner")

local function _format_mmss(secs)
    secs = math.floor(secs or 0)
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%d:%02d", m, s)
end

local function _format_delta(secs)
    secs = math.floor(secs or 0)
    local sign = secs < 0 and "-" or "+"
    secs = math.abs(secs)
    return string.format("%s%d:%02d", sign, math.floor(secs / 60), secs % 60)
end

-- Skeleton — copy the widget structure from an existing simple HUD element
-- like the clock_widget or a similar "two text lines, bottom-right" mod.
-- ...

return element
```

Implementation: copy from an existing simple HUD mod. Plan ~1 hour.

- [ ] **Step 2: Drive the timer from `renderer.tick`**

Update `renderer.tick`:

```lua
renderer.tick = function(dt)
    -- (existing beacon code)
    --
    -- Race timer:
    if mod:get("show_race_timer") and mod.replayer.state() == "playing" then
        local timer_el = _get_hud_element_by_name("GhostRunnerTimer")
        if timer_el and timer_el.set_state then
            timer_el:set_active(true)
            timer_el:set_state({
                ghost_t = mod.replayer.elapsed(),
                delta = mod.recorder.elapsed() - mod.replayer.elapsed(),
            })
        end
    end
end
```

- [ ] **Step 3: Register the timer HUD element**

In `GhostRunner.lua`, alongside the beacon registration:

```lua
mod:add_require_path("GhostRunner/scripts/mods/GhostRunner/hud_timer")
mod:register_hud_element({
    class_name = "GhostRunnerTimer",
    filename = "GhostRunner/scripts/mods/GhostRunner/hud_timer",
    visibility_groups = { "alive", "dead" },
    use_hud_scale = true,
    validation_function = function() return mod.replayer.state() == "playing" end,
})
```

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 5: Smoke test in-game**

Race against a ghost. Expected: a small two-line widget shows ghost time and your delta, in the bottom-right corner. Delta should update each frame.

Toggle "Show race timer HUD" off in F4 menu. Timer should hide.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): race timer HUD with ghost elapsed + delta"
```

---

## Task 15: Mission-end notifications + cleanup

Notifications for save events, end-of-replay, error states. Also remove the `/ghost_test_*` developer commands now that real flows work.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` (remove dev commands)
- Modify: `GhostRunner/scripts/mods/GhostRunner/recorder.lua` (notify on save)
- Modify: `GhostRunner/scripts/mods/GhostRunner/replayer.lua` (notify on finish)

- [ ] **Step 1: Add notification on recorder save**

In `recorder.stop_and_save`, after the `mod:info(...)` save line, add:

```lua
    Managers.event:trigger("event_add_notification_message", "default",
        string.format("Run saved: %s (%.0fs)", mapped_outcome, _state.last_sample_t))
```

- [ ] **Step 2: Add notification on ghost finish**

In `replayer.tick` where it transitions to `STATE.finished`:

```lua
    if finished then
        _state.name = STATE.finished
        Managers.event:trigger("event_add_notification_message", "default",
            string.format("Ghost finished at %s.",
                os.date("!%M:%S", _state.source:duration())))
    end
```

(Replace the existing `mod:notify(...)` if it's there from Task 11.)

- [ ] **Step 3: Remove dev commands**

In `GhostRunner.lua`, remove these `mod:command` blocks:
- `ghost_test_fs`
- `ghost_test_runfile`
- `ghost_test_source`

Keep `ghost_status` — it's useful as a diagnostic in production.

- [ ] **Step 4: Lint**

Run: `luacheck GhostRunner/scripts/mods/GhostRunner/`

- [ ] **Step 5: Smoke test in-game**

Reload mod. Run a SoloPlay mission to completion. Expected: in-game notification "Run saved: completed (NNNs)".

Race against a ghost shorter than your live run. Expected: at the moment the ghost ends, in-game notification "Ghost finished at MM:SS." Beacon disappears.

Verify the dev commands are gone (autocomplete in chat shouldn't show `/ghost_test_*`).

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/
git commit -m "feat(ghostrunner): in-game notifications for save and ghost-finish

Cleanup: removed dev verification commands."
```

---

## Task 16: End-to-end manual test pass

No code — just a structured verification of the full flow against the spec's requirements.

- [ ] **Step 1: Fresh-state test**

Delete the runs folder (`%APPDATA%\Fatshark\Darktide\GhostRunner\runs\`). Reload mod. Start Darktide.

- [ ] **Step 2: First recording**

Launch a SoloPlay mission (any). Play for ~2 minutes. Complete or abort.

Verify:
- ☐ A `.run` file was created with the timestamp filename.
- ☐ `index.json` exists and contains the run.
- ☐ `/ghost list` shows the run.
- ☐ Tail of `.run` file is an `"end"` footer line.
- ☐ Console shows `recorder: started ...` and `recorder: saved ...`.
- ☐ In-game notification "Run saved: ..." appeared.

- [ ] **Step 3: First replay**

`/ghost load 1`. Set replay mode to Race. Launch the same mission.

Verify:
- ☐ SoloPlay's mission selector auto-set to the ghost's mission.
- ☐ `/ghost_status` reports replayer state `armed` then `playing`.
- ☐ Ghost beacon visible at the ghost's recorded position.
- ☐ Beacon moves smoothly as the ghost walks (interpolation working).
- ☐ HP/peril bars on the beacon update over time.
- ☐ Race timer widget visible bottom-right showing ghost time + delta.

- [ ] **Step 4: Mismatch test**

`/ghost load 1`. Open SoloPlay menu. Manually change mission to a different one. Start the mission.

Verify:
- ☐ Notification "Ghost mission mismatch — replay disabled this run."
- ☐ `/ghost_status` reports replayer state `idle`.
- ☐ No beacon appears.

- [ ] **Step 5: Recording-during-replay test**

Race against a ghost. The recorder should be recording your live run alongside the replay.

Verify:
- ☐ A new `.run` file is created for the live run.
- ☐ The new run appears in `/ghost list` after mission end.
- ☐ The new run can itself be loaded as a ghost in a future mission.

- [ ] **Step 6: Settings gate test**

Toggle "Record runs" OFF. Start a mission.

Verify:
- ☐ No `.run` file is created.
- ☐ Console does NOT show `recorder: started`.

Toggle ON. Restart mission.

Verify:
- ☐ Recording resumes.

- [ ] **Step 7: Replay-mode-off test**

Set replay mode to Off. `/ghost load 1`. Start the mission.

Verify:
- ☐ Replayer stays armed but doesn't enter playing.
- ☐ No beacon appears.

- [ ] **Step 8: Folder keybind test**

In F4 menu, bind a key to "Open runs folder". Press it.

Verify:
- ☐ Explorer opens at `%APPDATA%\Fatshark\Darktide\GhostRunner\runs\`.

- [ ] **Step 9: Hub-skip test**

Walk around the Mourningstar hub.

Verify:
- ☐ `/ghost_status` reports recorder state `idle` (not recording in hub).

- [ ] **Step 10: Document any unfixed issues in `KNOWN_ISSUES.md`**

If any of Step 2-9 failed in a way that's a known limitation (e.g., seed pinning didn't work on this engine version), document the issue in a new file `GhostRunner/KNOWN_ISSUES.md` with reproduction steps and the impact.

- [ ] **Step 11: Final commit**

```bash
git add GhostRunner/
git commit -m "test(ghostrunner): v0 manual test pass complete

Verified record/replay loop end-to-end across recording gates,
replay modes, mission-mismatch detection, and folder-keybind."
```

---

## Self-review checklist (for the implementer)

Before declaring v0 done:

- [ ] Spec section 1 (Architecture overview): all 8 modules exist with one clear responsibility each.
- [ ] Spec section 2 (Run file format): JSONL with metadata header, frame array, end footer; AppData path; `index.json` with rebuild fallback.
- [ ] Spec section 3 (Recording behavior): hooked, gated, sampled at 20Hz, finalized on mission_cleanup.
- [ ] Spec section 4 (Replay behavior): state machine, mission auto-set, seed pinning attempt, interpolation, end-of-stream.
- [ ] Spec section 5 (UI): DMF settings panel + 4 chat commands + HUD timer.
- [ ] Spec section 6 (Edge cases): partial files load with `[partial]` marker; mission mismatch refuses; user-deleted file's index entry rebuilds on next list; SoloPlay missing fails clearly.

---

## Out of scope (explicitly NOT in this plan)

These are tracked in spec section "Future direction" and are not built in v0:

- Live co-op via NetworkSource (the architectural seam exists; nothing implements it).
- Custom mod view replacing chat commands.
- Multi-ghost replay.
- True spectator features (mission-fail-disable, follow camera).
- Run-file binary compression.
- Auto-deletion of old runs.
- Ghost interaction (collision, AI noticing).
