# GhostRunner v0 — Design

A Darktide mod that records solo runs and lets you replay them as a "ghost" overlaid on a live solo run, in race or spectator framing. The first piece of a longer arc that ends in live ghost co-op (a v1 milestone).

## Goals

- **Capture**: while playing a solo mission via SoloPlay, sample the local player's position, orientation, HP, peril, wounds, and downed-state at 20 Hz; write to a `.run` file in the user's AppData.
- **Replay**: load a `.run` file, auto-set SoloPlay's mission params to match it, attempt to pin the level seed, and during the resulting solo mission render a HUD beacon + nameplate at the recorded player's position with their HP / peril / wounds shown.
- **Race feedback**: a small HUD timer showing the ghost's elapsed time and the live player's delta against it.
- **Architecture seam**: structure the renderer's input around an abstract `RemotePlayerSource`, so v1 (live co-op) can plug in a network source without touching the renderer.

## Out of scope (v0)

- Live co-op / network transport / peer pairing — the source abstraction leaves the seam clean for v1.
- Spawning a real character unit at the ghost's position (HUD beacon only).
- Follow camera / free-fly spectator (spectator = "stand still and watch" in v0).
- Multi-ghost replay (one ghost at a time).
- Run-file compression (text JSONL is the v0 format).
- Ghost-picker custom UI — chat commands suffice for v0.
- Recording in Psykhanium, hub, or prologue (gated by `SoloPlay.is_soloplay()`).
- Cross-version run migration (schema-version gate refuses too-new files).

## Hard dependency

`SoloPlay`. Without it, there's no moddable solo mission to record from. Declared in `GhostRunner_data.lua` so DMF refuses to load GhostRunner if SoloPlay is missing or disabled.

## Architecture

### Module layout

```
GhostRunner/
├── GhostRunner.mod
└── scripts/mods/GhostRunner/
    ├── GhostRunner.lua              -- mod lifecycle, hook installation, mod.update glue
    ├── GhostRunner_data.lua         -- DMF mod options definition
    ├── GhostRunner_localization.lua -- strings
    ├── recorder.lua                 -- captures local state, manages .run file writes
    ├── replayer.lua                 -- consumes a RemotePlayerSource on a clock, drives renderer
    ├── source.lua                   -- RemotePlayerSource interface; ReplaySource and MockSource impls
    ├── run_file.lua                 -- read/write JSONL .run files; index.json maintenance
    └── renderer.lua                 -- HUD beacon, nameplate (HP/peril/wounds), race timer widget
```

### Data flow

```
                    ┌── RemotePlayerSource ◄── ReplaySource (v0)
                    │                       ◄── MockSource (testing only)
                    │                       ◄── NetworkSource (v1)
                    │
[local player] ──► Recorder ──► .run file on disk
                    │
                    └── replayer.active_source ──► Renderer ──► HUD widgets
```

The `RemotePlayerSource` interface emits a stream of frames `{p, y, hp, peril, w, d}` at a clock that the consumer (Replayer) advances. The Renderer doesn't know whether frames came from a file or a network — that's the seam for v1.

### Module responsibilities

| Module | Owns | Does not own |
|---|---|---|
| `recorder` | per-frame sampling state, the open file handle, flush policy | rendering, replay, UI |
| `replayer` | the active source, elapsed time, frame indexing, interpolation | sampling, rendering, file I/O |
| `source` | the interface + concrete `ReplaySource`/`MockSource` | the file format details (delegates to `run_file`) |
| `run_file` | JSONL read/write, index.json maintenance, filesystem paths | source semantics, replay timing |
| `renderer` | DMF widgets for beacon, nameplate, race timer | data ingestion |
| `GhostRunner.lua` | hook installation, mod.update fan-out to recorder/replayer/renderer | per-module logic |

## Hook surface

Verified against the Aussiemon source mirror.

```lua
-- Start recording: when local player gets a body in a soloplay mission
mod:hook(CLASS.GameModeManager, "on_player_unit_spawn",
    function(func, self, player, player_unit, is_respawn)
        func(self, player, player_unit, is_respawn)
        if is_respawn then return end
        if Managers.player:local_player(1):player_unit() ~= player_unit then return end
        if not get_mod("SoloPlay").is_soloplay() then return end
        if not mod:get("record_runs") then return end
        Recorder.start(player, player_unit)
    end)

-- Stop & save: when the game mode tears down (covers complete / fail / abort)
mod:hook_require("scripts/managers/game_mode/game_modes/game_mode_base",
    function(GameModeBase)
        mod:hook(GameModeBase, "mission_cleanup",
            function(func, self, on_shutdown)
                local outcome = self:_state()  -- "complete" / "fail" / "leaving_game"
                Recorder.stop_and_save(outcome, on_shutdown)
                func(self, on_shutdown)
            end)
    end)

-- Per-frame: vanilla DMF
mod.update = function(dt)
    Recorder.tick(dt)
    Replayer.tick(dt)
    Renderer.tick(dt)
end
```

Notes:
- `GameModeManager` is global as `CLASS.GameModeManager` — hookable directly.
- `GameModeBase` is `local`-returned (per CLAUDE.md gotcha) — must use `mod:hook_require`.
- The "first spawn" gate uses `is_respawn == false` AND identity check against `Managers.player:local_player(1):player_unit()`.

Source: [game_mode_manager.lua:317](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/game_mode/game_mode_manager.lua) and [game_mode_base.lua](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/game_mode/game_modes/game_mode_base.lua).

## Run file format

### Storage

- Path: `%APPDATA%\Fatshark\Darktide\GhostRunner\runs\` — same parent as `console_logs`. Survives mod reinstall.
- AppData path discovered at mod load via `Mods.lua.io.popen("echo %APPDATA%")` (the DLS pattern; `os.getenv` reliability is uncertain in Bitsquid Lua).
- Filename: `<ISO-8601-timestamp-with-ms>.run` — e.g. `2026-05-07T14-32-11.847Z.run`. Sortable, descriptive metadata lives inside the file.
- Companion file: `runs/index.json` — fast lookup for `/ghost list`, rebuilt from folder scan on corruption.

### Wire format: JSON Lines

One JSON object per line. First line is metadata, subsequent lines are frames, last line is a footer.

```jsonl
{"type":"meta","schema":1,"player":"AustenC","class":"psyker","mission":{"name":"throneside_damnation","difficulty":5,"circumstance":"default","side":"scriptures","giver":"morrow","havoc":null,"seed":1234567890},"recorded_at":"2026-05-07T14:32:11.847Z"}
{"type":"f","t":0.05,"p":[12.5,47.2,1.8],"y":1.57,"hp":1.0,"peril":0,"w":3,"d":false}
{"type":"f","t":0.10,"p":[12.7,47.2,1.8],"y":1.57,"hp":1.0,"peril":0,"w":3,"d":false}
...
{"type":"end","outcome":"completed","duration":403.7,"seed_pinned":true,"on_shutdown":false}
```

**Why JSONL:**
- Append-friendly — every line up to a crash is valid; no partial-array nightmare.
- Debuggable — open in Notepad, see exactly what's there.
- `cjson` is global (encode/decode in one call).
- Schema-versioned for forward compatibility.

**Tradeoff:** ~150 bytes per frame at 20 Hz = ~3 KB/sec ≈ 1.8 MB for a 10-minute run. Acceptable for v0; binary frames are a v1 option if file sizes complain.

### Per-frame fields

| Key | Type | Meaning |
|---|---|---|
| `type` | `"f"` | discriminator |
| `t` | float | seconds since first sample (player_unit_spawn) |
| `p` | `[x,y,z]` | world position (Vector3) |
| `y` | float | yaw in radians |
| `hp` | 0..1 | HP fraction (`current/max`) |
| `peril` | 0..1 | warp_charge fraction (0 if not psyker) |
| `w` | int | wounds remaining |
| `d` | bool | downed/dead state flag |

Pitch and weapon-id deferred to v1 (not needed for HUD beacon + bars).

### Per-sample reads

| Field | Read site (sketch — exact APIs verified at implementation time) |
|---|---|
| `p` | `Vector3.to_array(Unit.world_position(unit, 1))` |
| `y` | `Quaternion.yaw(Unit.local_rotation(unit, 1))` |
| `hp` | `health_extension:current_health_percent()` (or `:current()` / `:max()`) |
| `peril` | `unit_data:read_component("warp_charge").current_percentage` (per CLAUDE.md) |
| `w` | wounds component on the health/state extension |
| `d` | character state machine `:current_state()` ∈ `{"knocked_down", "dead", "hogtied"}` |

### Metadata header

```json
{
  "type": "meta",
  "schema": 1,
  "player": "<character name>",
  "class": "psyker | zealot | veteran | ogryn | adamant",
  "mission": {
    "name": "<level id>",
    "difficulty": 1..5,
    "circumstance": "<id or default>",
    "side": "<side mission id or none>",
    "giver": "<mission giver id>",
    "havoc": null | { "<havoc fields>" },
    "seed": <int>
  },
  "recorded_at": "<ISO-8601>"
}
```

`mission.seed` captures `Managers.state.game_mode.shared_state.level_seed` (or wherever it surfaces; verified at implementation). Used for replay seed pinning.

### End footer

```json
{
  "type": "end",
  "outcome": "completed | failed | aborted",
  "duration": <float seconds>,
  "seed_pinned": true | false,
  "on_shutdown": true | false
}
```

`seed_pinned` reflects whether the *recorded* run had a seed we could later pin (we always know the seed at record time — this records whether seed determinism was confirmed working). `on_shutdown` distinguishes clean cleanup from process-shutdown teardown.

### Index file

`runs/index.json`:

```json
{
  "schema": 1,
  "runs": [
    { "file": "...", "mission": "...", "difficulty": 5, "class": "...",
      "duration": 403.7, "outcome": "completed",
      "recorded_at": "...", "seed": 12345, "seed_pinned": true },
    ...
  ]
}
```

Updated atomically each time a recording finalizes (write to `index.json.tmp`, rename). Rebuilt by scanning the folder if missing or corrupt.

## Recording behavior

### State machine

```
[idle] ──on_player_unit_spawn (gated)──► [recording] ──mission_cleanup──► [finalized] ──► [idle]
                                          │
                                          └──unit invalid──► finalize as "aborted"
```

### Gates for entering `recording`

All must be true:
1. `is_respawn == false` (first spawn, not a rescue)
2. `Managers.player:local_player(1):player_unit() == player_unit` (it's our player)
3. `get_mod("SoloPlay").is_soloplay()` (solo session)
4. `mod:get("record_runs")` (user setting; default on)
5. Recorder state is `idle` (defensive)

### Time anchor

`t = 0` at the first sample after spawn. Subsequent samples are seconds elapsed since that anchor. Replayer uses the same anchor for symmetry.

### Sample tick (accumulator)

```lua
local SAMPLE_INTERVAL = 0.05  -- 20 Hz
local accumulator = 0

mod.update = function(dt)
    Recorder.tick(dt)  -- and Replayer.tick, Renderer.tick
end

Recorder.tick = function(dt)
    if state ~= "recording" then return end
    accumulator = accumulator + dt
    while accumulator >= SAMPLE_INTERVAL do
        accumulator = accumulator - SAMPLE_INTERVAL
        Recorder.sample()
    end
end
```

### Defensive sampling

```lua
Recorder.sample = function()
    if not Unit.alive(Recorder.player_unit) then
        Recorder.finalize("aborted")
        return
    end
    -- Read fields, build frame table, append to buffer.
    -- Flush if buffer >= 100 frames OR last_flush > 5s ago.
end
```

### Flush policy

- Frames buffered in a Lua table.
- Flush every 100 frames OR every 5 seconds of recording, whichever first.
- File handle stays open from `start` to `finalize`.
- Write failures (disk full, permission) → recorder transitions to `idle`, partial file remains, user notified.

### Finalization

On `mission_cleanup`:
1. Flush remaining frames.
2. Read game_mode_state to determine outcome (`complete`/`fail`/`leaving_game`).
3. Write `"end"` footer.
4. Close file.
5. Append/update `index.json` entry atomically.
6. Transition to `finalized` → `idle`.

## Replay behavior

### State machine

```
[idle]
  │
  ├─ user selects ghost ─► [armed] (load file into memory)
  │
[armed]
  │
  ├─ on_player_unit_spawn + mission match ─► [playing]
  ├─ on_player_unit_spawn + mismatch ─► [idle] + notify
  │
[playing]
  │
  ├─ tick advances elapsed; renders interpolated frame
  ├─ elapsed > last_frame.t ─► [finished] (renderer hides beacon)
  ├─ mission_cleanup ─► [idle]
  │
[finished]
  │
  └─ mission_cleanup ─► [idle]
```

### Loading a ghost

1. Open the `.run` file via `Mods.lua.io.open(path, "rb")`.
2. Read all lines, parse each via `cjson.decode`.
3. Validate: metadata header present, schema_version supported, ≥1 frame.
4. Sort frames by `t` ascending (defensive).
5. Store in memory (`{metadata, frames[]}`), close file handle.
6. Transition to `armed`.

For a 10-minute run at 20 Hz that's ~12K frames in a Lua table. ~1MB resident. Negligible.

### Mission auto-set on ghost load

When user loads a ghost, GhostRunner pushes ghost.mission params into SoloPlay's settings:

```lua
local sp = get_mod("SoloPlay")
local m = ghost.metadata.mission
sp:set("choose_mission", m.name)
sp:set("choose_difficulty", m.difficulty)
sp:set("choose_circumstance", m.circumstance)
sp:set("choose_side_mission", m.side)
sp:set("choose_mission_giver", m.giver)
-- Mirror to havoc_* keys if m.havoc ~= nil
```

### Seed pinning

Attempt: `GameParameters.level_seed = m.seed` before mission start.

If `GameParameters` is read-only at runtime (verified during implementation), fallback: hook `Managers.connection:session_seed()` to return `m.seed` while replay is armed.

If neither path works, log a warning and continue — replay still works (ghost is data, not simulation), it's just less fair on initial spawns/pickups. The `seed_pinned` outcome flag captures whether the attempt succeeded.

### Tick / interpolation

```lua
Replayer.tick = function(dt)
    if state ~= "playing" then return end
    elapsed = elapsed + dt

    while idx + 1 <= #frames and frames[idx + 1].t <= elapsed do
        idx = idx + 1
    end

    if idx >= #frames then
        state = "finished"
        Renderer.hide_remote_player()
        return
    end

    local a, b = frames[idx], frames[idx + 1]
    local alpha = (elapsed - a.t) / (b.t - a.t)
    local interp = _interpolate(a, b, alpha)
    Renderer.update_remote_player(interp)
end
```

- Linear lerp on `p` (Vector3), `hp`, `peril`.
- Angular-wrap-aware lerp on `y`.
- Step function on `d` (snap to nearest frame).

### Time anchor

`elapsed = 0` at `on_player_unit_spawn` — same anchor the recorder uses, so the live and ghost playthroughs align temporally from the moment the player gets a body.

### End-of-stream

- Replay finishes (elapsed > last frame.t): `Renderer.hide_remote_player()`, chat notification `"Ghost finished at 6:43.21."`, mission continues.
- Live mission ends mid-replay: `mission_cleanup` tears down the replayer; ghost data released from memory.
- Live mission outlasts ghost: ghost just stays hidden for the rest.

### Race vs Spectator (v0)

Functionally identical at the mod level — both load the ghost into the live solo mission and render it. The setting is a UI label for intent-signaling; player engages or stands still by their own choice. v1 may add real spectator features (disable mission-fail-on-death, follow camera).

## UI

### DMF mod options panel

```
GhostRunner
├── [header] Recording
│   └── [checkbox] Record runs automatically  (default: on)
│
├── [header] Replay
│   ├── [dropdown] Replay mode: Off / Race / Spectator  (default: Off)
│   ├── [checkbox] Show race timer HUD  (default: on)
│   └── [description] To pick a ghost, open chat and type /ghost list
│
└── [header] Files
    ├── [keybind] Open runs folder  (default: unbound)
    └── [description] Run files: %APPDATA%\Fatshark\Darktide\GhostRunner\runs\
```

The "Open runs folder" keybind triggers `Mods.lua.io.popen("explorer " .. runs_path)`.

### Chat commands

```
/ghost list                 List saved runs, newest first
/ghost load <n|name>        Load run by index from /ghost list, or by filename
/ghost clear                Unload current ghost
/ghost info                 Show currently loaded ghost details
```

Wired via `mod:command(name, desc, fn)` (the SoloPlay precedent). Output uses `{#color(...)}` chat markup (the only markup that renders in chat per CLAUDE.md).

### `/ghost list` sample output

```
GhostRunner — saved runs (newest first):
1. throneside_damnation D5  6:43  completed  2026-05-07 14:32  psyker
2. consignment_yard D4      8:11  failed     2026-05-07 13:18  psyker
3. archivum_sycorax D5      5:02  completed  2026-05-06 22:04  psyker
```

Currently loaded ghost shown in green.

### In-mission HUD

A small widget (bottom-right or another non-conflicting corner):

```
Ghost: 03:12 / Δ -00:14
```

- Line 1: ghost's elapsed time (M:SS), updated every 100ms.
- Line 2: delta = `live_elapsed - ghost_elapsed`. Negative + green = ahead. Positive + red = behind.

Toggleable via the "Show race timer HUD" checkbox. Hidden when no ghost is loaded.

The remote-player beacon is a world-anchored marker at the ghost's interpolated position, visible through walls (similar to a tagged-target outline). Nameplate above shows: ghost player name, HP bar, peril bar, wounds-pip count. Width and styling follow Darktide's existing teammate nameplates for visual consistency.

### Notifications

`"Ghost loaded"`, `"Ghost mission mismatch — refusing to load"`, `"Recording saved"`, `"Recording stopped: disk write failed"`, `"Ghost finished at <time>"`. Routed via `Managers.event:trigger("event_add_notification_message", ...)`.

## Edge cases

### Mission lifecycle

| Scenario | Behavior |
|---|---|
| Crash mid-mission | Partial run, no `"end"` footer. Loader marks `[partial]`. Replay runs out of frames, beacon hides. |
| Process killed | Same as crash. |
| Mission abort to hub | `mission_cleanup` fires with `on_shutdown=false`. Outcome = `"aborted"`. |
| Mission failure | `mission_cleanup` after state→`fail`. Outcome = `"failed"`. |
| Mission completion | `mission_cleanup` after state→`complete`. Outcome = `"completed"`. |
| Player downed + rescued | `is_respawn=true` ignored. Existing recording continues with monotonic `t`. Frames during downed have `d=true`. |
| Player permanently dead | Recording continues with `d=true` until mission_cleanup. |
| Mission re-enter | `[finalized]` → `[idle]` allows next mission's first spawn to start a new recording. |
| Pause | `dt=0` → accumulator doesn't advance → naturally paused. |

### File system

| Scenario | Behavior |
|---|---|
| Runs folder doesn't exist | Created on first record. |
| Disk full / write fails | Recorder → `idle`, partial file remains, user notified. |
| Permission denied (AppData) | Same. |
| `.run` truncated/corrupt | Loader catches `cjson` errors. Bad metadata → refuse load. Bad frame line → skip. |
| `index.json` missing/corrupt | Rebuild from folder scan. |
| Filename collision | Millisecond-precision timestamps make this effectively impossible. |
| User manually deletes a `.run` | Index goes stale, detected on next load attempt, rebuilt. |

### Schema evolution

- `schema:1` for v0. All `.run` files include `schema` in metadata.
- Loader: `schema > supported` → refuse load with notification. `schema <= supported` → load.
- New optional fields in v1+: read if present, defaulted if absent.
- Mission name renamed in a Darktide patch: auto-set fails, user notified, ghost still loadable but mission must be picked manually.

### Mod compatibility

- SoloPlay missing/disabled: DMF refuses to load GhostRunner (declared dependency).
- SoloPlay API changes: `pcall` around setting writes; graceful failure with notification.
- Other mods hooking the same events: hooks are additive (we always call `func(self, ...)`).
- Other mods modifying extension reads: garbage-in-garbage-out per frame, no crash.

### Performance bounds

- Per-frame sample work: sub-millisecond per second of mission.
- Disk flush every 5s: ~15 KB write.
- In-memory ghost: ~1 MB for a 10-min run.
- Render: 3 widgets total.

## Future direction

### v0.5 (polish)

- Custom mod view replacing chat commands for ghost picking.
- Run management: delete-from-list, rename, tag favorites.
- HUD positioning option (corner picker).

### v1 (live co-op)

The architectural seam is `RemotePlayerSource`. v1 adds:

- `NetworkSource` implementation that receives state from a local helper executable.
- Helper bundled in mod folder, auto-launched via `Mods.lua.io.popen`.
- v1.0 transport: direct IP (LAN/manual). v1.1+: Steam P2P via Steamworks SDK.
- Pairing UX: in-game settings field for peer address; mission-start coordination via helper.
- New widget types in the UI for live status (peer connection state).

The Recorder, run_file, JSONL format, and Renderer are untouched by v1 — only `source.lua` and a new helper executable are added. The seam is intentionally narrow.

### v2+ (further out)

- Multi-ghost replay (race against your top 3 runs simultaneously).
- True spectator mode (disable mission-fail, follow camera, free-fly).
- Shared run leaderboards (requires backend; out of scope for the mod ecosystem alone).
- Ghost-co-op hybrid (a friend can join your ghost-replay session).
