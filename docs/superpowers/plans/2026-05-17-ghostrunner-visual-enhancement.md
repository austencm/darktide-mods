# GhostRunner Visual Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade GhostRunner's ghost representation from a foot-anchored 2D nameplate to a three-part visual: an in-world `LineObject` trail and vertical pole, plus a head-anchored nameplate with class icon, status row, and toughness/HP-with-wounds/ability bars. Bump file format to schema 2 with size optimizations.

**Architecture:** Pure client-side rendering (no spawned units / no engine extensions modified), so it works in MP-safely. Three concerns are kept separate: `world_renderer.lua` (new) owns a `LineObject` for the duration of a replay; `hud_beacon.lua` (modified) carries all 2D UI; the recorder/run_file/interpolation layer carries schema-2 data with backwards compat for schema-1 ghosts.

**Tech Stack:** Lua (Bitsquid fork), Darktide Mod Framework (DMF), `cjson` for serialization, `LineObject` API for 3D drawing, DMF widgets for HUD.

**Spec:** [`docs/superpowers/specs/2026-05-17-ghostrunner-visual-enhancement-design.md`](../specs/2026-05-17-ghostrunner-visual-enhancement-design.md)

---

## Testing model (read first)

Lua mods in Darktide can't be unit-tested in CI — they run inside the game process, with no Lua test framework. The substitute pattern in this plan:

- **Pure-data modules** (run_file, interpolation): include a temporary `mod:command(...)` that exercises the module against synthetic data and prints results to console. The engineer runs the command in-game (chat: `/<cmd>`) and visually verifies the console output. These verification commands are kept in code through development and removed in the final cleanup task (Task 10).
- **In-game modules** (recorder, replayer, world_renderer, hud_beacon): verification is "play a solo mission and observe the expected behavior in the console log AND on screen."
- **No automated linting** assumed — the existing project doesn't have `.luacheckrc`. Just `mod:info` everything you want to verify; the console log catches it.

**Console log location:** `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\console-<latest>.log`. Newest by mtime is the current session. `print(...)` and `mod:info(...)` land here.

**Live iteration:** the existing mod is already symlinked into the Darktide mods folder per the v0 setup. Edits land live; toggle the mod off/on in F4 → Mods to reload after edits. **Set `allow_rehooking = true` in `GhostRunner_data.lua` if not already there** (per the existing CLAUDE.md memory — without it, Ctrl+Shift+R silently discards new hook handlers).

**Hot-reload restart:** if you change the HUD beacon's widget definition (Tasks 5–8), reloading via F4 may not pick it up reliably. Restart the game between widget-definition changes to be safe.

---

## File structure

All paths relative to repo root.

### New files

| Path | Responsibility |
|---|---|
| `GhostRunner/scripts/mods/GhostRunner/world_renderer.lua` | Owns one `LineObject` per replay session. Builds trail segments + pole each frame, dispatches to the level world. Lifecycle tied to `replayer.arm` / `replayer.disarm`. |

### Modified files

| Path | What changes |
|---|---|
| `GhostRunner/scripts/mods/GhostRunner/run_file.lua` | Writer emits schema 2 with abbreviated keys, no `"type":"f"` discriminator, numeric rounding. Reader accepts schema 1 (translated) and schema 2 (direct). |
| `GhostRunner/scripts/mods/GhostRunner/recorder.lua` | Captures `wmax` in metadata; per-frame reads of toughness fraction, combat-ability cooldown progress, CSM state name. Removes peril and `d` boolean. |
| `GhostRunner/scripts/mods/GhostRunner/interpolation.lua` | Lerps `to` and `ab` like `hp`; steps `st` like the removed `d`; `pg` rename (was `prog`). |
| `GhostRunner/scripts/mods/GhostRunner/replayer.lua` | On arm: create `world_renderer`, call new `beacon:set_class(meta.class)` and `beacon:set_wmax(meta.wmax)`. On disarm: destroy `world_renderer`. |
| `GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua` | Widget definition redesigned: class icon (top), name + status row, three bars (toughness / HP-with-wound-segments / ability). New `set_class`, `set_wmax`, restructured `set_state`. Bottom-anchored offset math. |
| `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` | Per-frame update block projects from head position (foot + offset based on state). Calls into `world_renderer.tick` and the new beacon setters. |
| `GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua` | New settings: "Show ghost trail" (checkbox), "Trail duration" (slider), "Show ghost nameplate" (checkbox). |
| `GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua` | Strings for the three new settings. |

---

## Verified-from-source facts

These are the APIs/values pinned during the planning verification pass. Use these exactly — don't re-research.

**Toughness** (`scripts/extension_systems/toughness/player_unit_toughness_extension.lua`):
```lua
local toughness_ext = ScriptUnit.has_extension(unit, "toughness_system")
local to = toughness_ext:current_toughness_percent()   -- 0..1
```

**Health/wounds** (`scripts/extension_systems/health/health_extension.lua`):
```lua
-- Per frame (already used in v0):
local hp = health_ext:current_health_percent()         -- 0..1
local w  = health_ext:num_wounds()                     -- int

-- Once at recorder start (new):
local wmax = health_ext:max_wounds()                   -- int
```

**Combat ability cooldown** (`scripts/extension_systems/ability/player_unit_ability_extension.lua`, formula mirrored from `scripts/ui/hud/elements/player_ability/hud_element_player_ability.lua`):
```lua
local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
local ab = 0
if ability_ext and ability_ext:ability_is_equipped("combat_ability") then
    local remaining = ability_ext:remaining_ability_cooldown("combat_ability")
    local max = ability_ext:max_ability_cooldown("combat_ability")
    if max and max > 0 then
        ab = 1 - (remaining / max)
        if ab == 0 then ab = 1 end   -- vanilla HUD quirk: just-finished bumps to 1
    else
        ab = 1   -- no cooldown means always ready
    end
end
```

**CSM state** (full enum from `scripts/settings/player_character/player_character_states.lua`):

Alive states (status row stays empty):
```
walking, sprinting, jumping, falling, sliding, dodging, stunned,
interacting, minigame, lunging, exploding,
ledge_hanging, ledge_hanging_falling, ledge_hanging_pull_up, ledge_vaulting,
ladder_climbing, ladder_top_entering, ladder_top_leaving
```

Disabled states (status row shows verb, pole drops to 0.5m, name+backing turn red):
```
knocked_down, hogtied, pounced, netted, consumed, grabbed, mutant_charged,
warp_grabbed, vortex_grabbed, catapulted, dead
```

Hub-only (won't appear during missions — ignore): `hub_companion_interaction`, `hub_emote`, `hub_jog`.

**LineObject lifecycle** (verified from `scripts/components/cover.lua`):
```lua
local world = Managers.world:world("level_world")
local lo = World.create_line_object(world)

-- Per frame:
LineObject.reset(lo)
LineObject.add_line(lo, color_quat, vec_from, vec_to)
LineObject.dispatch(world, lo)   -- NOTE: world FIRST, then line_object — type stubs lie

-- Cleanup:
World.destroy_line_object(world, lo)
```

`color_quat` is a Quaternion-like 4-component color produced by `Color(r, g, b, a)` or `Quaternion(r, g, b, a)`. In Bitsquid: `Color(alpha, red, green, blue)` order. Verify call signature in step (Task 4) — both orderings exist in different engine versions.

**Wound segmentation formula** (verified from `scripts/ui/hud/elements/player_panel_base/hud_element_player_panel_base.lua` lines 1460-1500):

```lua
-- num_segments = max_wounds (the HP bar is divided into max_wounds segments)
-- Each segment fills LEFT to RIGHT as hp increases; rightmost empty first.
-- This formula does NOT use `w` (current wounds) — wound visualization is
-- purely derived from hp + max_wounds.

local step = 1 / max_wounds
for i = 1, max_wounds do
    local end_v = i * step
    local start_v = end_v - step
    local fill_fraction = math.clamp((hp - start_v) / step, 0, 1)
    -- segment[i] is filled by `fill_fraction` (0..1) of its slot width
end

-- Vanilla quirk: when knocked_down, vanilla overrides num_segments to 1
-- so the bar collapses to one segment. Mirror this in our impl.
```

---

## Task 1: Schema 2 — recorder + writer (data plumbing)

Capture toughness, combat-ability cooldown, CSM state, and max-wounds. Write schema 2 with abbreviated keys, no frame discriminator, numeric rounding. Drop peril and the `d` boolean.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/recorder.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/run_file.lua`

- [ ] **Step 1: Add `round_to` helper and a numeric-rounding pre-pass in `run_file.lua`**

Open [run_file.lua](GhostRunner/scripts/mods/GhostRunner/run_file.lua). Above the `run_file = {}` line, add:

```lua
-- Round numeric values to N decimals via format+tonumber round-trip.
-- The tonumber strips trailing zeros: 0.50000 -> 0.5, 12.534823 -> 12.53.
-- Stays within JSON-valid output; lets cjson.encode use minimal representation.
local function round_to(n, decimals)
    if type(n) ~= "number" then return n end
    return tonumber(string.format("%." .. decimals .. "f", n))
end
```

- [ ] **Step 2: Bump `SCHEMA_VERSION` to 2**

In [run_file.lua](GhostRunner/scripts/mods/GhostRunner/run_file.lua), change:

```lua
local SCHEMA_VERSION = 1
```

to:

```lua
local SCHEMA_VERSION = 2
```

- [ ] **Step 3: Update `create_writer` to write `wmax` in metadata**

Find the `meta` table built inside `run_file.create_writer` (around line 30). Replace it with:

```lua
local meta = {
    type = "meta",
    schema = SCHEMA_VERSION,
    player = metadata.player,
    class = metadata.class,
    wmax = metadata.wmax,   -- NEW: max wounds for the recorded player
    mission = metadata.mission,
    recorded_at = metadata.recorded_at,
}
```

- [ ] **Step 4: Replace `Writer:append_frame` to write schema-2 frames (no discriminator, abbreviated keys, rounded values)**

Find `function Writer:append_frame(frame)` (around line 43). Replace its entire body with:

```lua
function Writer:append_frame(frame)
    if self._closed then return end
    -- Schema 2 frame format: no `type` discriminator (loader infers from
    -- the absence of `schema` and `outcome`). Abbreviated keys. Numeric
    -- rounding via round_to() so cjson emits minimal representation.
    local p = frame.p
    local row = {
        t  = round_to(frame.t, 3),
        p  = p and { round_to(p[1], 2), round_to(p[2], 2), round_to(p[3], 2) } or nil,
        y  = round_to(frame.y, 3),
        hp = round_to(frame.hp, 3),
        to = round_to(frame.to, 3),
        ab = round_to(frame.ab, 3),
        w  = frame.w,
        st = frame.st,
        pg = round_to(frame.pg, 4),
    }
    self._handle:write(cjson.encode(row) .. "\n")
end
```

- [ ] **Step 5: Update `recorder.lua` to capture max_wounds in metadata at start**

Open [recorder.lua](GhostRunner/scripts/mods/GhostRunner/recorder.lua). Find `_read_local_player_name_and_class` (around line 114). Add a new helper directly below it:

```lua
local function _read_max_wounds(player_unit)
    -- Read once at recorder start. Used in the wound-segmented HP bar.
    local hp_ext = ScriptUnit.has_extension(player_unit, "health_system")
    if hp_ext and hp_ext.max_wounds then
        local ok, val = pcall(hp_ext.max_wounds, hp_ext)
        if ok and val then return val end
    end
    return nil  -- absent metadata is acceptable; renderer falls back to un-segmented bar
end
```

- [ ] **Step 6: Write `wmax` into metadata in `recorder.start`**

In `recorder.start` (around line 125), find:

```lua
local player_name, class = _read_local_player_name_and_class()

local meta = {
    player = player_name,
    class = class,
    mission = mission,
    recorded_at = iso,
}
```

Replace with:

```lua
local player_name, class = _read_local_player_name_and_class()
local wmax = _read_max_wounds(player_unit)

local meta = {
    player = player_name,
    class = class,
    wmax = wmax,
    mission = mission,
    recorded_at = iso,
}
```

- [ ] **Step 7: Replace `_read_state` in `recorder.lua` to capture toughness, combat-ability, state — drop peril + `d`**

In [recorder.lua](GhostRunner/scripts/mods/GhostRunner/recorder.lua) find `local function _read_state(unit)` (around line 174) and replace the entire function with:

```lua
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
```

- [ ] **Step 8: Update `recorder.tick` call site to handle new return shape**

In `recorder.tick` (around line 239), find:

```lua
local ok, err_or_p, y, hp, peril, w, d, prog = pcall(_read_state, _state.player_unit)
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
    peril = peril,
    w = w,
    d = d,
    prog = prog,
})
```

Replace with:

```lua
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
```

- [ ] **Step 9: Smoke-test record a solo mission**

Boot Darktide. Start a solo mission via SoloPlay. Drop into the level for ~30 seconds, then abort to hub.

In `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\`, open the newest `console-*.log` and grep for `recorder: saved`. Confirm the new `.run` file was written.

Open the `.run` file at `%APPDATA%\Fatshark\Darktide\GhostRunner\runs\<timestamp>.run` in a text editor. Verify:
- Line 1 (metadata): `"schema":2`, `"wmax":<int>` is present (likely `2` or `3`).
- Frame lines: NO `"type":"f"` field. Contain `"to":..., "ab":..., "st":"<state>"`. NO `"peril"`, NO `"d"`. Numeric values look rounded (e.g. position has 2 decimals).
- Last line (footer): `"type":"end"` present (footer keeps its discriminator).

A line should look approximately like:
```jsonl
{"t":1.5,"p":[12.53,47.24,1.82],"y":1.57,"hp":1.0,"to":0.8,"ab":1.0,"w":3,"st":"walking","pg":0.234}
```

- [ ] **Step 10: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/recorder.lua GhostRunner/scripts/mods/GhostRunner/run_file.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): schema 2 recorder + writer

Captures toughness, combat-ability cooldown, CSM state, and max-wounds.
Drops peril and the d boolean. Tier 1+2 format optimizations: numeric
rounding, abbreviated keys (tough->to, ability->ab, state->st, prog->pg),
no type discriminator on frame lines. ~35% file-size reduction.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Loader — schema 1 + schema 2 backwards compat

Update the reader to handle BOTH old schema-1 files and new schema-2 files. Schema-1 frames are translated on read: `d=true → st="knocked_down"`, `peril` dropped, `to`/`ab` left absent.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/run_file.lua`

- [ ] **Step 1: Replace the `run_file.read` parser with schema-aware logic**

In [run_file.lua](GhostRunner/scripts/mods/GhostRunner/run_file.lua) find `run_file.read = function(filename)` (around line 89). Replace the for-loop body (the line-type discrimination) with this:

Find:

```lua
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
```

Replace with:

```lua
for line in handle:lines() do
    if line and #line > 0 then
        local ok, obj = pcall(cjson.decode, line)
        if ok and type(obj) == "table" then
            -- Schema-2 line-type inference: meta has `schema`, footer has
            -- `outcome`, anything else is a frame. The explicit `type` field
            -- is kept on meta+footer for forward compat & file debugging
            -- but no longer required on frames (Tier 2 byte savings).
            if obj.schema or obj.type == "meta" then
                meta = obj
            elseif obj.outcome or obj.type == "end" then
                footer = obj
            else
                frames[#frames + 1] = obj
            end
        end
    end
end
```

- [ ] **Step 2: Add a schema-1-to-schema-2 frame translator**

In [run_file.lua](GhostRunner/scripts/mods/GhostRunner/run_file.lua) above the `run_file.read` function, add:

```lua
-- Translate a schema-1 frame to schema-2 in-place fields. Old recordings
-- have explicit `type:"f"`, `d` (bool), `peril`, and `prog`. New code
-- expects `st` (string), no peril, `pg` instead of `prog`.
local function _translate_schema1_frame(f)
    if f.d ~= nil then
        f.st = f.d and "knocked_down" or "walking"
        f.d = nil
    end
    if f.prog ~= nil then
        f.pg = f.prog
        f.prog = nil
    end
    -- peril simply dropped on read; nothing renders it anymore
    f.peril = nil
    -- to and ab left absent — renderer hides those bars for schema-1 ghosts
    return f
end
```

- [ ] **Step 3: Apply the translator after parsing, based on meta.schema**

In `run_file.read`, after the frames are gathered but before `return { metadata = meta, ... }`, insert:

```lua
-- Translate schema-1 frames forward. Schema 2 frames pass through.
if meta and meta.schema == 1 then
    for i = 1, #frames do
        _translate_schema1_frame(frames[i])
    end
end
```

- [ ] **Step 4: Loosen the schema-version-too-new check**

In `run_file.read` find:

```lua
if meta.schema and meta.schema > SCHEMA_VERSION then
    return nil, string.format("unsupported schema version %d in %s", meta.schema, filename)
end
```

That's already correct given `SCHEMA_VERSION = 2` — it'll refuse schema-3+ runs from the future. Confirm it's there and unchanged. (No edit needed; this step is verification only.)

- [ ] **Step 5: Add a temporary verification command `/ghost_test_translate`**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua), add a new command below the existing `/ghost_status` registration:

```lua
-- TEMP (removed in Task 10 cleanup): verify schema-1 frame translation.
mod:command("ghost_test_translate", "GhostRunner dev: schema-1 frame translation test", function()
    -- Synthesize a schema-1-looking frame in memory.
    local frame1_old = {
        type = "f", t = 1.5, p = {1, 2, 3}, y = 0.5,
        hp = 0.8, peril = 0.3, w = 3, d = true, prog = 0.1,
    }
    -- Round-trip through cjson to match what comes off disk.
    local round = cjson.decode(cjson.encode(frame1_old))
    -- Apply the read-side path by calling run_file.read on a synthesized file...
    -- Actually simpler: directly invoke the (now internal) translator if exported.
    -- Since _translate_schema1_frame is file-local, just verify by reading a
    -- real schema-1 ghost file from the user's runs/ directory.
    local index = mod.run_file.read_index()
    local schema1_filename = nil
    for _, entry in ipairs(index.runs or {}) do
        local r = mod.run_file.read(entry.file)
        if r and r.metadata.schema == 1 then
            schema1_filename = entry.file
            break
        end
    end
    if not schema1_filename then
        mod:echo("No schema-1 ghost in runs/. Test inconclusive — manually verify with a fresh recording (will be schema 2).")
        return
    end
    local data = mod.run_file.read(schema1_filename)
    if not data then
        mod:echo("Schema-1 file failed to parse: " .. tostring(schema1_filename))
        return
    end
    local f1 = data.frames[1]
    mod:echo(string.format("Schema-1 loaded: %s | first frame: t=%.2f hp=%.2f st=%s pg=%s d=%s peril=%s",
        schema1_filename, f1.t or 0, f1.hp or 0,
        tostring(f1.st), tostring(f1.pg),
        tostring(f1.d), tostring(f1.peril)))
    mod:echo("Expected: st=walking or knocked_down (translated from d); d=nil; peril=nil")
end)
```

- [ ] **Step 6: Smoke-test the translator**

Restart Darktide (or F4 → reload). In chat: `/ghost_test_translate`.

Two acceptable outcomes:
- "No schema-1 ghost in runs/" — that's fine if all your old ghosts were already deleted; verify the schema-2 path works by checking a freshly recorded run (the one from Task 1 should still load fine with `/ghost load 1`).
- "Schema-1 loaded: ... st=walking d=nil peril=nil" — translator works.

Either way, also confirm: `/ghost load 1` (the most recent schema-2 ghost). Should load without errors in the console log.

- [ ] **Step 7: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/run_file.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): loader supports schema 1 + schema 2

Reader infers line type from field shape (schema/outcome/else=frame),
so schema-2 frames can drop the type discriminator. Schema-1 frames
are translated forward on load: d -> st, peril dropped, prog -> pg.
Includes /ghost_test_translate dev command.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Interpolation — lerp `to`/`ab`, step `st`, rename `prog`→`pg`

Make the interpolator carry the new schema-2 fields end-to-end so the renderer sees consistent state.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/interpolation.lua`

- [ ] **Step 1: Update `interpolation.frame_at` to include new fields**

In [interpolation.lua](GhostRunner/scripts/mods/GhostRunner/interpolation.lua) find the `interp` table built at the bottom of `frame_at` (around line 50). Replace the entire `local interp = {...}` block with:

```lua
local interp = {
    t  = elapsed,
    p  = interpolation.lerp_v3(a.p, b.p, alpha),
    y  = interpolation.lerp_yaw(a.y, b.y, alpha),
    hp = interpolation.lerp(a.hp or 0, b.hp or 0, alpha),
    to = interpolation.lerp(a.to or 0, b.to or 0, alpha),
    ab = interpolation.lerp(a.ab or 0, b.ab or 0, alpha),
    w  = a.w,                                  -- step function (rarely changes)
    st = a.st or "walking",                    -- step function (replaces v0 `d`)
    pg = (a.pg and b.pg) and interpolation.lerp(a.pg, b.pg, alpha) or a.pg,
}
```

Note: the `or 0` and `or "walking"` defaults handle schema-1 frames where `to`/`ab`/`st` are absent (renderer side will hide the corresponding bars).

- [ ] **Step 2: Add a temporary verification command `/ghost_test_interp`**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua), add:

```lua
-- TEMP (removed in Task 10 cleanup): verify interpolator handles schema-2 fields.
mod:command("ghost_test_interp", "GhostRunner dev: interpolation test", function()
    local frames = {
        { t = 0.0, p = {0,0,0}, y = 0,   hp = 1.0, to = 1.0, ab = 1.0, w = 3, st = "walking",     pg = 0.0 },
        { t = 1.0, p = {1,0,0}, y = 0.5, hp = 0.8, to = 0.5, ab = 0.5, w = 3, st = "sprinting",   pg = 0.1 },
        { t = 2.0, p = {2,0,0}, y = 1.0, hp = 0.4, to = 0.0, ab = 0.0, w = 2, st = "knocked_down",pg = 0.2 },
    }
    -- Sample at t=0.5 (between frame 1 and 2):
    local s, idx, fin = mod.interpolation.frame_at(frames, 1, 0.5)
    mod:echo(string.format("@t=0.5: p=(%.2f,%.2f,%.2f) hp=%.2f to=%.2f ab=%.2f st=%s pg=%.2f",
        s.p[1], s.p[2], s.p[3], s.hp, s.to, s.ab, tostring(s.st), s.pg))
    mod:echo("Expected: p=(0.5,0,0) hp=0.9 to=0.75 ab=0.75 st=walking pg=0.05")
    -- Sample at t=1.5 (between frame 2 and 3):
    local s2 = mod.interpolation.frame_at(frames, 2, 1.5)
    mod:echo(string.format("@t=1.5: hp=%.2f to=%.2f ab=%.2f st=%s",
        s2.hp, s2.to, s2.ab, tostring(s2.st)))
    mod:echo("Expected: hp=0.6 to=0.25 ab=0.25 st=sprinting")
end)
```

- [ ] **Step 3: Smoke-test the interpolator**

Reload the mod. In chat: `/ghost_test_interp`. Verify both echo lines match the "Expected" values printed alongside them.

- [ ] **Step 4: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/interpolation.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): interpolator lerps toughness/ability, steps state

Schema-2 fields propagate through interpolation: to/ab lerp like hp,
st steps like the old d boolean, pg replaces prog. Defaults handle
schema-1 frames where new fields are absent. Includes /ghost_test_interp
dev command.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `world_renderer.lua` — LineObject trail + pole

Add the new module that owns a `LineObject` for the duration of a replay and draws the ground trail + vertical pole each frame.

**Files:**
- Create: `GhostRunner/scripts/mods/GhostRunner/world_renderer.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` (load + wire)
- Modify: `GhostRunner/scripts/mods/GhostRunner/replayer.lua` (lifecycle hooks)

- [ ] **Step 1: Create `world_renderer.lua` with module scaffolding**

Create the file [GhostRunner/scripts/mods/GhostRunner/world_renderer.lua](GhostRunner/scripts/mods/GhostRunner/world_renderer.lua):

```lua
local mod = get_mod("GhostRunner")

local world_renderer = {}

-- Colors are { alpha, r, g, b } per Bitsquid's Color() / Quaternion() ctor
-- (verify call signature in Step 4 -- if wrong order, swap to { r, g, b, alpha }).
local TRAIL_RGB = { 255, 255, 80 }    -- bright yellow-white
local POLE_COLOR = { 220, 200, 40 }   -- darker, more saturated companion
local POLE_ALPHA = 255

local HEAD_OFFSET_ALIVE = 1.8
local HEAD_OFFSET_DOWN = 0.5

-- Downed-state set: states where the player is on the ground.
-- Pole shrinks; nameplate drops. Sourced from
-- scripts/settings/player_character/player_character_states.lua.
local DOWN_STATES = {
    knocked_down = true, hogtied = true, pounced = true, netted = true,
    consumed = true, grabbed = true, mutant_charged = true,
    warp_grabbed = true, vortex_grabbed = true, catapulted = true,
    dead = true,
}

world_renderer.head_offset_for_state = function(state)
    return DOWN_STATES[state] and HEAD_OFFSET_DOWN or HEAD_OFFSET_ALIVE
end

-- Returns the level world, or nil if not yet available.
local function _level_world()
    return Managers.world and Managers.world:world("level_world")
end

local _state = {
    line_object = nil,
    world = nil,
}

world_renderer.create = function()
    if _state.line_object then return true end
    local world = _level_world()
    if not world then
        mod:warning("world_renderer: level_world not available; deferring creation")
        return false
    end
    _state.world = world
    _state.line_object = World.create_line_object(world)
    mod:info("world_renderer: created LineObject")
    return true
end

world_renderer.destroy = function()
    if _state.line_object and _state.world then
        World.destroy_line_object(_state.world, _state.line_object)
        mod:info("world_renderer: destroyed LineObject")
    end
    _state.line_object = nil
    _state.world = nil
end

return world_renderer
```

- [ ] **Step 2: Load the module in `GhostRunner.lua`**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua) find the existing module-loading block (around line 14):

```lua
mod.run_file = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/run_file")
mod.interpolation = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/interpolation")
mod.source = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/source")

mod.recorder = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/recorder")

mod.commands = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/commands")

mod.replayer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/replayer")
```

Add the world_renderer load BEFORE `mod.replayer` (replayer references world_renderer):

```lua
mod.run_file = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/run_file")
mod.interpolation = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/interpolation")
mod.source = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/source")

mod.recorder = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/recorder")

mod.commands = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/commands")

mod.world_renderer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/world_renderer")

mod.replayer = mod:io_dofile("GhostRunner/scripts/mods/GhostRunner/replayer")
```

- [ ] **Step 3: Wire lifecycle into replayer arm/disarm**

In [replayer.lua](GhostRunner/scripts/mods/GhostRunner/replayer.lua) find `replayer.arm_with_selected_ghost = function()` (around line 119). At the bottom of the function, just before `return true`, add:

```lua
    -- Spin up the in-world renderer (trail + pole). Falls back gracefully
    -- if level_world isn't yet available (the per-frame tick retries).
    if mod.world_renderer then
        mod.world_renderer.create()
    end

    return true
```

Find `replayer.disarm = function()` (around line 142). Replace its body with:

```lua
replayer.disarm = function()
    _state.name = STATE.idle
    _state.source = nil
    _state.last_state = nil
    replayer.unpin_seed()
    if mod.world_renderer then
        mod.world_renderer.destroy()
    end
end
```

- [ ] **Step 4: Add `world_renderer.tick(state, trail_duration)` to draw trail+pole each frame**

Append to `world_renderer.lua`:

```lua
-- Per-frame draw. Called from mod.update while replayer is playing.
--
-- frames        : the full frame array from the loaded ghost (for trail history)
-- current_idx   : interpolator's current index into frames
-- current_state : the interpolated last_state (provides current foot p + st)
-- trail_duration: seconds of recorded history to render as trail
world_renderer.tick = function(frames, current_idx, current_state, trail_duration)
    if not _state.line_object then
        -- Try to create now if it failed earlier (e.g. early replay frames).
        if not world_renderer.create() then return end
    end
    if not current_state or not current_state.p then return end

    local lo = _state.line_object
    local world = _state.world
    LineObject.reset(lo)

    -- TRAIL: walk back from current frame, build segments while within
    -- trail_duration of the interpolated `t`. Alpha-ramp by age.
    local now_t = current_state.t or 0
    local prev = current_state.p
    local i = current_idx
    while i >= 1 do
        local f = frames[i]
        if not f then break end
        local age = now_t - (f.t or 0)
        if age > trail_duration then break end
        local alpha_byte = math.max(0, math.floor(255 * (1 - age / trail_duration)))
        if alpha_byte > 0 and f.p then
            -- Color ctor: Bitsquid's Color(a, r, g, b). If colors look wrong
            -- after first run, swap to Color(r, g, b, a) -- both signatures
            -- exist in different engine versions.
            local color = Color(alpha_byte, TRAIL_RGB[1], TRAIL_RGB[2], TRAIL_RGB[3])
            LineObject.add_line(lo, color,
                Vector3(prev[1], prev[2], prev[3]),
                Vector3(f.p[1], f.p[2], f.p[3]))
            prev = f.p
        end
        i = i - 1
    end

    -- POLE: from current foot up to head offset.
    local foot = current_state.p
    local head_z = foot[3] + world_renderer.head_offset_for_state(current_state.st)
    local pole_col = Color(POLE_ALPHA, POLE_COLOR[1], POLE_COLOR[2], POLE_COLOR[3])
    LineObject.add_line(lo, pole_col,
        Vector3(foot[1], foot[2], foot[3]),
        Vector3(foot[1], foot[2], head_z))

    LineObject.dispatch(world, lo)
end
```

- [ ] **Step 5: Drive the tick from `mod.update`**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua) find `mod.update = function(dt)` (around line 111). After the existing `ok2, err2 = pcall(mod.replayer.tick, dt)` block but BEFORE the HUD beacon block (`local ok3, err3 = pcall(function() ... end)`), insert:

```lua
    -- World renderer (trail + pole). No-op if not playing.
    local okwr, errwr = pcall(function()
        if mod.replayer.state() ~= "playing" then return end
        local source = mod.replayer.source and mod.replayer.source()
        -- We need access to the source's internal frames + idx for trail
        -- walk-back. Expose minimal accessors instead of grabbing internals.
        local frames = mod.replayer.frames and mod.replayer.frames()
        local idx = mod.replayer.idx and mod.replayer.idx()
        local last = mod.replayer.last_state()
        if not frames or not idx or not last then return end
        local trail_duration = 4.0   -- TODO: read from settings in Task 9
        mod.world_renderer.tick(frames, idx, last, trail_duration)
    end)
    if not okwr then mod:warning("world_renderer.tick error: " .. tostring(errwr)) end
```

- [ ] **Step 6: Expose `frames()` and `idx()` accessors on `replayer.lua`**

In [replayer.lua](GhostRunner/scripts/mods/GhostRunner/replayer.lua) below the existing accessors (around line 19):

```lua
replayer.state = function() return _state.name end
replayer.last_state = function() return _state.last_state end
```

Add:

```lua
replayer.frames = function()
    return _state.source and _state.source._frames or nil
end

replayer.idx = function()
    return _state.source and _state.source._idx or nil
end
```

The `_frames` and `_idx` fields are set by `source.create_replay_source` in [source.lua](GhostRunner/scripts/mods/GhostRunner/source.lua) — they're already there.

- [ ] **Step 7: Smoke-test in solo**

Boot Darktide. Load a ghost (`/ghost list`, `/ghost load 1`). Start a solo mission matching the ghost's mission.

Verify in-game:
- A bright yellow-white trail line appears on the floor showing the ghost's recent path.
- A darker yellow vertical pole rises from the ghost's foot position to about head height.
- When the recorded player was downed/disabled, the pole shortens to ~0.5m.

If colors are wrong (e.g. blue or invisible), swap the `Color(a, r, g, b)` call order to `Color(r, g, b, a)` in `world_renderer.tick`'s color construction. Recompile and re-test.

Also verify in console log: no `world_renderer.tick error` warnings.

- [ ] **Step 8: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/world_renderer.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua GhostRunner/scripts/mods/GhostRunner/replayer.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): world_renderer module -- LineObject trail + pole

New module owns a LineObject for the duration of a replay. Per-frame:
walks back through recent frames within trail_duration to build a
fading trail of segments; adds a vertical pole from foot to head height
(or 0.5m when ghost is in a disabled state). Wired into replayer
arm/disarm and into mod.update.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Nameplate — class icon

Add the class glyph (PUA codepoint) as a new text pass on the beacon widget, drawn left of the name on the top row.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/replayer.lua` (call new setter on arm)

- [ ] **Step 1: Add `cp()` helper and CLASS_GLYPHS table at the top of `hud_beacon.lua`**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua), at the very top after the existing `require` lines (around line 3), add:

```lua
-- Codepoint -> UTF-8 byte string. Bitsquid Lua's `\u{XXXX}` escape support
-- is uncertain, so encode by hand at mod load time.
local function cp(n)
    if n < 0x80 then return string.char(n) end
    if n < 0x800 then
        return string.char(0xC0 + math.floor(n / 0x40),
                           0x80 + (n % 0x40))
    end
    return string.char(0xE0 + math.floor(n / 0x1000),
                       0x80 + math.floor(n / 0x40) % 0x40,
                       0x80 + (n % 0x40))
end

-- PUA codepoints for class glyphs (detailed variants).
-- From scripts/settings/ui/ui_settings.lua lines 508-555 (per project memory).
local CLASS_GLYPHS = {
    veteran = cp(0xE01A),
    zealot  = cp(0xE01B),
    psyker  = cp(0xE01C),
    ogryn   = cp(0xE01D),
    adamant = cp(0xE050),
}
```

- [ ] **Step 2: Add a class_icon text pass to the widget definition**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) find the `widget_definitions` block (around line 32). Inside the `UIWidget.create_definition({...}, "ghost_beacon_area")` array of passes, BEFORE the existing name pass, add a new pass:

```lua
-- Class icon (top, left of name). The glyph is in the Darktide PUA range;
-- proxima_nova_bold's font-fallback chain resolves it via darktide_custom_regular.
{
    pass_type = "text",
    style_id  = "class_icon",
    value_id  = "class_icon",
    value     = "",  -- set via set_class()
    style     = {
        font_size                 = 22,
        font_type                 = "proxima_nova_bold",
        text_horizontal_alignment = "center",
        text_vertical_alignment   = "center",
        horizontal_alignment      = "center",
        vertical_alignment        = "top",
        text_color                = { 255, 255, 255, 255 },
        drop_shadow               = true,
        offset                    = { -50, 0, 1 },  -- centered then nudged left
    },
},
```

- [ ] **Step 3: Add `HudElementGhostBeacon:set_class(class_name)` method**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) after the existing `set_name` method (around line 162), add:

```lua
-- Update the class icon. Called once when the ghost is loaded; not per-frame.
-- Unknown class -> empty string (icon hidden).
HudElementGhostBeacon.set_class = function(self, class_name)
    local widget = self._widgets_by_name and self._widgets_by_name.beacon
    if not widget then return end
    local glyph = CLASS_GLYPHS[class_name] or ""
    if widget.content and widget.content.class_icon ~= nil then
        widget.content.class_icon = glyph
        widget.dirty = true
    end
end
```

- [ ] **Step 4: Call `set_class` from replayer.arm**

In [replayer.lua](GhostRunner/scripts/mods/GhostRunner/replayer.lua) find `replayer.arm_with_selected_ghost` (around line 119). After `_state.source = source_module.create_replay_source(...)` and before the seed-pin call, add:

```lua
    -- Push class identity into the HUD beacon (rendered as a PUA glyph).
    local ui_manager = Managers.ui
    local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
    local beacon = hud and hud:element("HudElementGhostBeacon")
    if beacon and beacon.set_class and mod._selected_ghost then
        local class = mod._selected_ghost.data.metadata.class
        beacon:set_class(class)
    end
```

Note: `arm_with_selected_ghost` runs after mission load when the HUD exists. If the HUD beacon isn't yet ready at arm time, the `if beacon and beacon.set_class` guard returns silently and the icon will simply be missing until the next ghost load. Acceptable.

- [ ] **Step 5: Smoke-test in solo**

Reload mod. Load a ghost recorded as a Psyker (`/ghost load 1` — pick one). Start a solo mission.

Expected:
- The nameplate above the ghost's head (still feet-anchored at this point — head-anchoring lands in Task 6) shows the Psyker class icon (a glowing skull-like glyph) to the left of the player's name.

If you see a blank space or a `??` glyph: the font fallback chain might not be picking up `darktide_custom_regular`. Verify `font_type = "proxima_nova_bold"` in the widget definition. If still blank: try changing `font_type` to `"machine_medium"` or `"darktide_custom_regular"` directly (some font setups don't propagate the fallback chain to all parents).

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua GhostRunner/scripts/mods/GhostRunner/replayer.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): nameplate class icon

PUA codepoint glyph rendered via Darktide font fallback chain to
darktide_custom_regular. Glyph map covers veteran/zealot/psyker/ogryn/adamant.
Set once at ghost load via beacon:set_class(class).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Nameplate — head-anchored projection

Move the nameplate from foot height to head height in 3D, and switch the widget anchor from center-on-projection to bottom-edge-on-projection so the pole tip terminates just below the panel.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` (projection math)
- Modify: `GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua` (set_offset anchor)

- [ ] **Step 1: Project the world position from head, not foot, in `mod.update`**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua) find the HUD beacon update block (around line 127). Locate:

```lua
-- Project to screen. Hide if behind the camera or out of frustum.
local world_pos = Vector3(s.p[1], s.p[2], s.p[3])
```

Replace with:

```lua
-- Project to screen at HEAD position (foot + offset that varies with state).
-- Same offset used by world_renderer for the top of the pole, so the
-- nameplate sits exactly atop the pole.
local head_offset = mod.world_renderer
    and mod.world_renderer.head_offset_for_state(s.st)
    or 1.8
local world_pos = Vector3(s.p[1], s.p[2], s.p[3] + head_offset)
```

- [ ] **Step 2: Change `set_offset` anchor from center to bottom-edge**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) find:

```lua
local HALF_W, HALF_H = 100, 30
HudElementGhostBeacon.set_offset = function(self, x, y)
    local widget = self._widgets_by_name and self._widgets_by_name.beacon
    if not widget or not widget.offset then return end
    widget.offset[1] = (x or 0) - HALF_W
    widget.offset[2] = (y or 0) - HALF_H
end
```

Replace with:

```lua
-- Widget bounds: 200 (W) x 60 (H) for now -- grows in Task 8.
-- Anchor: bottom edge of widget sits just above the projection point.
-- The projection point is the head's world->screen pixel; the pole's tip
-- terminates there too, so the panel visually rests atop the pole.
local HALF_W = 100
local POLE_GAP = 6  -- pixels between projection point and bottom of widget
HudElementGhostBeacon.set_offset = function(self, x, y)
    local widget = self._widgets_by_name and self._widgets_by_name.beacon
    if not widget or not widget.offset then return end
    local widget_h = (widget.content and widget.content.size and widget.content.size[2]) or 60
    widget.offset[1] = (x or 0) - HALF_W
    widget.offset[2] = (y or 0) - widget_h - POLE_GAP
end
```

(`widget.content.size[2]` is the auto-tracked widget height; falls back to 60 if not set. Task 8 will grow it to 86.)

- [ ] **Step 3: Smoke-test in solo**

Reload, load a ghost, start solo mission.

Expected:
- Nameplate now floats roughly at head height (about 1.8m above the ground at the ghost's position).
- The pole from Task 4 visually connects the floor to just below the nameplate.
- When the ghost is downed (you can test by ghosting a run where you got downed): nameplate drops to ~0.5m above the floor and the pole shortens to match.

If the nameplate is now wildly mispositioned (e.g. floating in space far from the ghost), double-check that `s.p[3]` (third element) is the vertical axis in Darktide — it should be Z (up). If it's Y instead, swap to `s.p[2]` accordingly.

- [ ] **Step 4: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): nameplate anchored to head position

Projects from foot.z + head_offset (1.8m, or 0.5m when ghost is in a
disabled state). Widget anchors at its bottom edge just above the
projection point so it sits atop the pole tip cleanly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Nameplate — status row + alarm tint when disabled

Add a verb-only status row between name and bars. When the ghost is in a disabled state, the row shows the verb (`DOWN`, `NETTED`, `POUNCED`, etc.); the name text recolors red; the backing rect tints dark red.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua`

- [ ] **Step 1: Add a backing-rect pass to the widget definition**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) find `widget_definitions.beacon = UIWidget.create_definition({...}` (around line 33). At the START of the passes array (so it's drawn first / behind everything), insert:

```lua
-- Backing rect for legibility. Color is set per-frame in set_state
-- (neutral dark when alive, dark red when disabled).
{
    pass_type = "rect",
    style_id  = "backing",
    style     = {
        horizontal_alignment = "center",
        vertical_alignment   = "center",
        size                 = { 196, 56 },   -- inset from widget bounds; grows in Task 8
        color                = { 140, 0, 0, 0 },
        offset               = { 0, 0, 0 },
    },
},
```

- [ ] **Step 2: Add a status_row text pass to the widget definition**

In the same passes array, AFTER the existing name pass (which renders at top), add:

```lua
-- Status row (verb-only when disabled, empty when alive). Always reserved
-- vertical space so the widget doesn't bounce when state changes.
{
    pass_type = "text",
    style_id  = "status_row",
    value_id  = "status_row",
    value     = "",
    style     = {
        font_size                 = 12,
        font_type                 = "proxima_nova_bold",
        text_horizontal_alignment = "center",
        text_vertical_alignment   = "center",
        horizontal_alignment      = "center",
        vertical_alignment        = "top",
        text_color                = { 255, 255, 80, 80 },   -- bright red
        drop_shadow               = true,
        offset                    = { 0, 22, 1 },           -- 22px below top
    },
},
```

- [ ] **Step 3: Add STATUS_TEXT mapping table and ALIVE_STATES set**

Below the `CLASS_GLYPHS` table you added in Task 5, add:

```lua
-- States in which we render NO status text. Sourced from
-- scripts/settings/player_character/player_character_states.lua.
-- Everything not in this set OR the hub-only set falls through to the
-- status formatter.
local ALIVE_STATES = {
    walking = true, sprinting = true, jumping = true, falling = true,
    sliding = true, dodging = true, stunned = true, interacting = true,
    minigame = true, lunging = true, exploding = true,
    ledge_hanging = true, ledge_hanging_falling = true,
    ledge_hanging_pull_up = true, ledge_vaulting = true,
    ladder_climbing = true, ladder_top_entering = true, ladder_top_leaving = true,
    -- Hub-only states (won't appear in missions, but treat as alive defensively):
    hub_companion_interaction = true, hub_emote = true, hub_jog = true,
}

-- Verb-only display per disabled state. Anything missing here falls back to
-- the uppercase-with-spaces formatter (so future state names display
-- *something* until this table is updated).
local STATUS_TEXT = {
    knocked_down   = "DOWN",
    hogtied        = "HOGTIED",
    pounced        = "POUNCED",
    netted         = "NETTED",
    consumed       = "CONSUMED",
    grabbed        = "GRABBED",
    mutant_charged = "GRABBED",
    warp_grabbed   = "WARP GRABBED",
    vortex_grabbed = "VORTEX GRABBED",
    catapulted     = "CATAPULTED",
    dead           = "DEAD",
}

local function status_text_for(state)
    if not state or ALIVE_STATES[state] then return "" end
    return STATUS_TEXT[state] or state:upper():gsub("_", " ")
end
```

- [ ] **Step 4: Update `set_state` to drive status row + alarm tint**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) find `HudElementGhostBeacon.set_state` (around line 137). Replace its body with:

```lua
HudElementGhostBeacon.set_state = function(self, state)
    local widget = self._widgets_by_name and self._widgets_by_name.beacon
    if not widget or not state then return end
    local style   = widget.style
    local content = widget.content
    if not style or not content then return end

    -- HP / peril fills come from the existing v0 passes; replaced in Task 8.
    local hp = math.max(0, math.min(1, state.hp or 0))
    if style.hp_fill and style.hp_fill.size then
        style.hp_fill.size[1] = 140 * hp
    end
    -- (Old peril update intentionally left until Task 8 -- harmless if peril field is nil.)
    local peril = math.max(0, math.min(1, state.peril or 0))
    if style.peril_fill and style.peril_fill.size then
        style.peril_fill.size[1] = 140 * peril
    end

    -- NEW: status row + alarm tint.
    local is_alive = ALIVE_STATES[state.st]
    content.status_row = status_text_for(state.st)
    if style.name and style.name.text_color then
        if is_alive then
            style.name.text_color = { 255, 255, 255, 255 }
        else
            style.name.text_color = { 255, 255, 80, 80 }   -- bright red
        end
    end
    if style.backing and style.backing.color then
        if is_alive then
            style.backing.color = { 140, 0, 0, 0 }          -- neutral dark
        else
            style.backing.color = { 160, 120, 0, 0 }        -- dark red
        end
    end

    widget.dirty = true
end
```

Note: text_color and rect color in Bitsquid Lua are `{a, r, g, b}` (alpha first). Verify in-game; if colors look swapped, change to `{r, g, b, a}`.

- [ ] **Step 5: Smoke-test in solo**

Need a ghost that goes through a disabled state. Either:
- Record one fresh: play a solo mission, intentionally let yourself get downed by enemies, then quit / abort. Load that ghost.
- Or just observe `dead` state at end-of-mission ghosts.

Expected during replay:
- While ghost is `walking`/`sprinting`/etc.: status row is empty, name text is white, backing is neutral dark.
- When ghost enters `knocked_down`: status row shows `DOWN`, name turns red, backing tints dark red. Pole shortens (already wired in Task 4).
- When recording shows `netted`, `pounced`, etc.: appropriate verb shown.

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): nameplate status row + alarm tint when disabled

Adds verb-only status text (DOWN, NETTED, POUNCED, CONSUMED, etc.) shown
between name and bars when ghost is in a non-alive CSM state. Name text
turns red and backing rect tints dark red as additional alarm cues.
ALIVE_STATES set and STATUS_TEXT table sourced from vanilla player
character states enumeration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Nameplate — bar overhaul (toughness / HP-wounds / ability)

Remove the peril bar. Add toughness (top) and combat-ability (bottom) bars. Rebuild the HP bar with wound segmentation matching the vanilla formula.

This is the biggest single task — it rebuilds the widget bar passes from scratch.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua`

- [ ] **Step 1: Define the new bar constants near the top of `hud_beacon.lua`**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) above the existing `local ui_definitions = {...}` (around line 21), update the existing color constants block:

```lua
local NAME_FONT_SIZE = 18
local BAR_WIDTH = 140
local BAR_HEIGHT = 6
local BAR_SPACING = 9     -- vertical pixel spacing between bars
local SEGMENT_SPACING = 2 -- thin gap between HP wound segments
local MAX_WOUND_SEGMENTS = 5   -- enough for any class (ogryn caps at 5)

local BG_COLOR        = { 200, 30, 30, 30 }     -- semi-transparent dark bar backing
local HP_COLOR        = { 255, 220, 60, 60 }    -- red (vanilla)
local TOUGHNESS_COLOR = { 220, 220, 220, 255 }  -- pale silver-white
local ABILITY_COLOR   = { 220, 200, 80, 255 }   -- gold
local NAME_COLOR      = { 255, 255, 255, 255 }
```

Delete the old `HP_COLOR` and `PERIL_COLOR` definitions if you still have them.

- [ ] **Step 2: Add the `_build_segment_passes` helper above `ui_definitions`**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua), ABOVE the existing `local ui_definitions = {...}` block (and below the constants from Step 1), insert this helper:

```lua
-- Programmatically build N wound-segment fill rect passes. Each segment
-- can shrink to show partial fill, and hide entirely when wmax < its index.
-- Layout (size + x-offset) is set per frame in _layout_hp_segments (below).
local function _build_segment_passes()
    local passes = {}
    for i = 1, MAX_WOUND_SEGMENTS do
        passes[#passes + 1] = {
            pass_type = "rect",
            style_id  = "hp_seg_" .. i,
            style     = {
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                size                 = { 0, BAR_HEIGHT },   -- width set per frame
                color                = HP_COLOR,
                offset               = { 30, 45, 2 },        -- x set per frame
            },
        }
    end
    return passes
end

-- Build the complete passes list for the beacon widget. Combines the static
-- passes (backing, icon, name, status row, tough bars, HP bg, ability bars)
-- with the programmatically-generated HP wound segments.
local function _build_all_passes()
    local passes = {
        -- 1. Backing rect (drawn first / underneath). Color set per-frame in set_state.
        {
            pass_type = "rect",
            style_id  = "backing",
            style     = {
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                size                 = { 196, 82 },
                color                = { 140, 0, 0, 0 },
                offset               = { 0, 0, 0 },
            },
        },
        -- 2. Class icon (left of name on top row). PUA glyph via font fallback chain.
        {
            pass_type = "text",
            style_id  = "class_icon",
            value_id  = "class_icon",
            value     = "",   -- set via set_class()
            style     = {
                font_size                 = 22,
                font_type                 = "proxima_nova_bold",
                text_horizontal_alignment = "center",
                text_vertical_alignment   = "center",
                horizontal_alignment      = "center",
                vertical_alignment        = "top",
                text_color                = { 255, 255, 255, 255 },
                drop_shadow               = true,
                offset                    = { -50, 0, 1 },
            },
        },
        -- 3. Name text (centered on top row).
        {
            pass_type = "text",
            style_id  = "name",
            value_id  = "name",
            value     = "Ghost",
            style     = {
                font_size                 = NAME_FONT_SIZE,
                font_type                 = "proxima_nova_bold",
                text_horizontal_alignment = "center",
                text_vertical_alignment   = "center",
                horizontal_alignment      = "center",
                vertical_alignment        = "top",
                text_color                = NAME_COLOR,
                drop_shadow               = true,
                offset                    = { 0, 0, 1 },
            },
        },
        -- 4. Status row (empty when alive; verb text when disabled).
        {
            pass_type = "text",
            style_id  = "status_row",
            value_id  = "status_row",
            value     = "",
            style     = {
                font_size                 = 12,
                font_type                 = "proxima_nova_bold",
                text_horizontal_alignment = "center",
                text_vertical_alignment   = "center",
                horizontal_alignment      = "center",
                vertical_alignment        = "top",
                text_color                = { 255, 255, 80, 80 },
                drop_shadow               = true,
                offset                    = { 0, 22, 1 },
            },
        },
        -- 5. Toughness bar (top of the bar stack).
        {
            pass_type = "rect",
            style_id  = "tough_bg",
            style     = {
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                size                 = { BAR_WIDTH, BAR_HEIGHT },
                color                = BG_COLOR,
                offset               = { 0, 36, 1 },
            },
        },
        {
            pass_type = "rect",
            style_id  = "tough_fill",
            style     = {
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                size                 = { BAR_WIDTH, BAR_HEIGHT },
                color                = TOUGHNESS_COLOR,
                offset               = { 30, 36, 2 },
            },
        },
        -- 6. HP bar background (drawn once behind all segments).
        {
            pass_type = "rect",
            style_id  = "hp_bg",
            style     = {
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                size                 = { BAR_WIDTH, BAR_HEIGHT },
                color                = BG_COLOR,
                offset               = { 0, 45, 1 },
            },
        },
    }

    -- 7. HP wound segments (5 max; trimmed per frame to actual wmax).
    for _, seg in ipairs(_build_segment_passes()) do
        passes[#passes + 1] = seg
    end

    -- 8. Ability bar (bottom).
    passes[#passes + 1] = {
        pass_type = "rect",
        style_id  = "ability_bg",
        style     = {
            horizontal_alignment = "center",
            vertical_alignment   = "center",
            size                 = { BAR_WIDTH, BAR_HEIGHT },
            color                = BG_COLOR,
            offset               = { 0, 54, 1 },
        },
    }
    passes[#passes + 1] = {
        pass_type = "rect",
        style_id  = "ability_fill",
        style     = {
            horizontal_alignment = "left",
            vertical_alignment   = "center",
            size                 = { BAR_WIDTH, BAR_HEIGHT },
            color                = ABILITY_COLOR,
            offset               = { 30, 54, 2 },
        },
    }

    return passes
end
```

- [ ] **Step 3: Replace the entire `local ui_definitions = {...}` block**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua) DELETE the entire existing `local ui_definitions = {...}` block (including everything that Tasks 5 and 7 added — backing rect, class_icon, status_row passes; they're all re-introduced inside `_build_all_passes` above). Replace with this single block:

```lua
local ui_definitions = {
    scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,
        ghost_beacon_area = {
            parent               = "screen",
            vertical_alignment   = "top",
            horizontal_alignment = "left",
            size                 = { 200, 86 },   -- grown from 60 for status row + 3 bars
            position             = { 0, 0, 5 },
        },
    },
    widget_definitions = {
        beacon = UIWidget.create_definition(_build_all_passes(), "ghost_beacon_area"),
    },
}
```

- [ ] **Step 4: Add `set_wmax` setter and a per-frame segment layout helper**

In [hud_beacon.lua](GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua), below `set_class` (added in Task 5), add:

```lua
-- Pre-stores how many segments the HP bar should display. Schema-1 ghosts
-- (no wmax) fall back to 1, rendering an un-segmented bar.
HudElementGhostBeacon.set_wmax = function(self, wmax)
    self._wmax = (wmax and wmax > 0) and wmax or 1
end

-- Layout the wound-segment passes for a given hp fraction.
-- Sets each segment widget's size + x-offset, hides unused segments.
-- Formula mirrors vanilla scripts/ui/hud/elements/player_panel_base/...:1460-1500.
local function _layout_hp_segments(style, hp, num_segments)
    num_segments = math.max(1, math.min(MAX_WOUND_SEGMENTS, num_segments or 1))
    local step = 1 / num_segments
    local segment_width = (BAR_WIDTH - (num_segments - 1) * SEGMENT_SPACING) / num_segments
    -- The bar's left edge is at offset.x = 30 (the standard inset).
    -- Lay segments left-to-right.
    for i = 1, MAX_WOUND_SEGMENTS do
        local pass = style["hp_seg_" .. i]
        if not pass then
            -- defensive; segment passes should always exist
        elseif i > num_segments then
            -- hide unused segment by setting its width to 0
            if pass.size then pass.size[1] = 0 end
        else
            local end_v = i * step
            local start_v = end_v - step
            local fill = math.max(0, math.min(1, (hp - start_v) / step))
            if pass.size then pass.size[1] = segment_width * fill end
            -- Position this segment's left edge:
            local x = 30 + (i - 1) * (segment_width + SEGMENT_SPACING)
            if pass.offset then pass.offset[1] = x end
        end
    end
end
```

- [ ] **Step 5: Replace `set_state` to drive all three bars + segments**

Replace the `set_state` you wrote in Task 7 (the one with peril) with the final version:

```lua
HudElementGhostBeacon.set_state = function(self, state)
    local widget = self._widgets_by_name and self._widgets_by_name.beacon
    if not widget or not state then return end
    local style   = widget.style
    local content = widget.content
    if not style or not content then return end

    local hp = math.max(0, math.min(1, state.hp or 0))
    local to = math.max(0, math.min(1, state.to or 0))
    local ab = math.max(0, math.min(1, state.ab or 0))

    -- Toughness bar fill.
    if style.tough_fill and style.tough_fill.size then
        style.tough_fill.size[1] = BAR_WIDTH * to
    end

    -- HP bar: vanilla quirk -- when knocked_down, collapse to 1 segment.
    local is_alive = ALIVE_STATES[state.st]
    local effective_segments = (state.st == "knocked_down") and 1 or (self._wmax or 1)
    _layout_hp_segments(style, hp, effective_segments)

    -- Ability bar fill.
    if style.ability_fill and style.ability_fill.size then
        style.ability_fill.size[1] = BAR_WIDTH * ab
    end

    -- Status row + alarm tints (from Task 7).
    content.status_row = status_text_for(state.st)
    if style.name and style.name.text_color then
        style.name.text_color = is_alive and { 255, 255, 255, 255 } or { 255, 255, 80, 80 }
    end
    if style.backing and style.backing.color then
        style.backing.color = is_alive and { 140, 0, 0, 0 } or { 160, 120, 0, 0 }
    end

    widget.dirty = true
end
```

- [ ] **Step 6: Call `set_wmax` from replayer.arm**

In [replayer.lua](GhostRunner/scripts/mods/GhostRunner/replayer.lua) inside `arm_with_selected_ghost`, find the `set_class` call you added in Task 5. Right below it, add:

```lua
    if beacon and beacon.set_wmax and mod._selected_ghost then
        beacon:set_wmax(mod._selected_ghost.data.metadata.wmax or 1)
    end
```

- [ ] **Step 7: Smoke-test in solo with both schema-1 and schema-2 ghosts**

Reload mod. Load a SCHEMA-2 ghost (the one recorded in Task 1). Start a solo mission.

Expected:
- Top bar (silver-white): toughness, varying as the recorded ghost's toughness drained/recovered.
- Middle bar (red): HP, divided into `wmax` segments separated by thin dark gaps. Segments deplete from the right as the ghost lost health. When the ghost was knocked_down, the bar visually collapses to 1 segment.
- Bottom bar (gold): combat ability cooldown, fills 0→1 as the ability recharges, snaps to full when ready.

Then load a SCHEMA-1 ghost (any older recording predating Task 1). Expected:
- Toughness bar empty/silent (no `to` data → `to=0`).
- HP bar shows as a single un-segmented red bar (no `wmax` → effective_segments = 1).
- Ability bar empty (no `ab` data → `ab=0`).
- Everything else still works (name, class icon if metadata.class is set, position, pole, trail).

- [ ] **Step 8: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/hud_beacon.lua GhostRunner/scripts/mods/GhostRunner/replayer.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): nameplate bars -- toughness/HP-wounds/ability

Replaces the peril bar with toughness (top, silver) and combat-ability
(bottom, gold). HP bar is now wound-segmented per the vanilla formula
(step_fraction = 1/wmax; segments fill left-to-right). Schema-1 ghosts
gracefully render with a single HP segment and hidden toughness/ability
bars. Widget grows to 200x86.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Settings + localization

Wire the trail/nameplate to DMF settings so the user can toggle and tune them from the F4 menu.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua`
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` (read settings)

- [ ] **Step 1: Add settings to `GhostRunner_data.lua`**

Open [GhostRunner_data.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua). Find the "Replay" header (or nearest equivalent) in the widgets list. Add three new widget entries below the existing replay-related options:

```lua
{
    setting_id   = "show_ghost_trail",
    type         = "checkbox",
    default_value = true,
},
{
    setting_id   = "trail_duration",
    type         = "numeric",
    default_value = 4.0,
    range        = { 1.0, 10.0 },
    step         = 0.5,
    decimals_number = 1,
},
{
    setting_id   = "show_ghost_nameplate",
    type         = "checkbox",
    default_value = true,
},
```

(Adapt to the exact widget-table syntax already in use in the file — if the existing widgets use a slightly different format, copy that pattern.)

- [ ] **Step 2: Add localization strings**

In [GhostRunner_localization.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua), add entries:

```lua
show_ghost_trail = {
    en = "Show ghost trail",
},
show_ghost_trail_description = {
    en = "Draw a 3D trail and vertical pole at the ghost's recorded position.",
},
trail_duration = {
    en = "Trail duration (seconds)",
},
trail_duration_description = {
    en = "How many seconds of recent history are shown as the ghost's trail. Shorter = more like a comet tail; longer = more like a route map.",
},
show_ghost_nameplate = {
    en = "Show ghost nameplate",
},
show_ghost_nameplate_description = {
    en = "Show the floating panel with the ghost's name, status, and bars.",
},
```

Match the existing localization-table format in the file.

- [ ] **Step 3: Gate `world_renderer.tick` on the trail setting**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua) find the `world_renderer.tick` block added in Task 4 Step 5. Update the duration constant + add the gate. Replace:

```lua
local trail_duration = 4.0   -- TODO: read from settings in Task 9
mod.world_renderer.tick(frames, idx, last, trail_duration)
```

With:

```lua
if not mod:get("show_ghost_trail") then return end
local trail_duration = mod:get("trail_duration") or 4.0
mod.world_renderer.tick(frames, idx, last, trail_duration)
```

- [ ] **Step 4: Gate the nameplate update on the nameplate setting**

In the HUD beacon update block in `mod.update` (the `ok3, err3 = pcall(...)` block), at the very top of the inner function, add:

```lua
if not mod:get("show_ghost_nameplate") then
    if element and element.set_active then element:set_active(false) end
    return
end
```

Place it BEFORE the existing `if mod.replayer.state() ~= "playing" then ... return` line so disabling the setting hides the nameplate even during active replay.

- [ ] **Step 5: Smoke-test all three settings**

Reload mod. Load a ghost, start solo mission.

- Toggle "Show ghost trail" off → trail and pole vanish; nameplate remains.
- Toggle "Show ghost trail" on → trail and pole return on next frame.
- Adjust "Trail duration" slider from 1.0 to 10.0 → trail visibly shortens / lengthens.
- Toggle "Show ghost nameplate" off → nameplate vanishes; trail and pole remain.
- Toggle both off → only the foot-position dot remains (no in-world visuals).

- [ ] **Step 6: Commit**

```bash
git add GhostRunner/scripts/mods/GhostRunner/GhostRunner_data.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner_localization.lua GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua
git commit -m "$(cat <<'EOF'
feat(ghostrunner): visual enhancement settings + localization

Three new DMF options under Replay: Show ghost trail (checkbox),
Trail duration (slider, 1-10s, default 4), Show ghost nameplate
(checkbox). Each takes effect on the next frame.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Cleanup

Remove the temporary dev commands; double-check there are no stray peril/`d`/`prog` references; final smoke test of a fresh record-then-replay cycle.

**Files:**
- Modify: `GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua` (remove temp commands)
- Possibly modify: any file with leftover references to removed fields

- [ ] **Step 1: Remove `/ghost_test_translate` and `/ghost_test_interp` from `GhostRunner.lua`**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua), find and delete the two `mod:command(...)` blocks for `"ghost_test_translate"` (added in Task 2) and `"ghost_test_interp"` (added in Task 3). Leave `/ghost_status` in place — it's a real diagnostic command, not a temporary test.

- [ ] **Step 2: Sweep for stale references to removed fields**

Run a search for the removed schema-1 field names across the mod source. From the repo root in PowerShell:

```powershell
Select-String -Path "GhostRunner/scripts/mods/GhostRunner/*.lua" -Pattern "\bperil\b|\bd = |\.d\b|\bprog\b"
```

Expected: NO matches in active code paths. Acceptable matches:
- Comments referencing the v0 `d` boolean or `peril` field for explanation (e.g. in the schema-1 translator).
- The schema-1 translator itself (which legitimately reads `f.d` and `f.peril` and `f.prog` to translate them).

If you find stale references in active per-frame code (recorder, replayer, world_renderer, hud_beacon) — remove them.

- [ ] **Step 3: Update `/ghost_status` to show schema-2 fields**

In [GhostRunner.lua](GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua), find the `/ghost_status` block (around line 263). Update the `last_state` print line. Find:

```lua
local s = mod.replayer.last_state()
if s then
    mod:echo(string.format("  last_state: t=%.2f p=(%.1f,%.1f,%.1f) hp=%.2f",
        s.t, s.p[1], s.p[2], s.p[3], s.hp))
end
```

Replace with:

```lua
local s = mod.replayer.last_state()
if s then
    mod:echo(string.format("  last_state: t=%.2f p=(%.1f,%.1f,%.1f) hp=%.2f to=%.2f ab=%.2f st=%s",
        s.t, s.p[1], s.p[2], s.p[3], s.hp, s.to or 0, s.ab or 0, tostring(s.st)))
end
```

- [ ] **Step 4: Final end-to-end smoke test**

Restart Darktide. Confirm:

1. `/ghost list` shows the latest schema-2 recording from Task 1's smoke test.
2. `/ghost load 1` loads it.
3. Start a fresh solo mission matching the ghost's level/difficulty.
4. **In mission, verify simultaneously visible:**
   - In-world: trail behind ghost (yellow, fading), pole from foot to head height (slightly darker yellow), shortens when ghost downed.
   - Nameplate at head height: class icon, name, status row (verb when disabled, empty when alive), toughness bar (top), HP bar with wound segments (middle), ability bar (bottom). Red tint when ghost is in a non-alive state.
5. `/ghost_status` shows populated schema-2 fields (hp/to/ab/st).
6. Quit to hub. Verify a NEW recording from your live mission was written and appears in `/ghost list` (this is the recorder still working).
7. Load THAT new recording and re-replay it. Verify all visuals still work.

- [ ] **Step 5: Commit cleanup**

```bash
git add GhostRunner/scripts/mods/GhostRunner/GhostRunner.lua
git commit -m "$(cat <<'EOF'
chore(ghostrunner): visual enhancement cleanup

Remove dev test commands (/ghost_test_translate, /ghost_test_interp).
Update /ghost_status to print schema-2 fields. Final end-to-end smoke
test passed: record -> replay round-trip works; both schema-1 and
schema-2 ghosts render correctly.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Done

All ten tasks committed. The branch now contains the full visual enhancement: schema-2 data pipeline, in-world trail + pole, head-anchored nameplate with class icon, status row, alarm tint, and three vanilla-style bars.

Suggested next step: invoke `superpowers:finishing-a-development-branch` to decide between bundle-into-PR vs continued local iteration.
