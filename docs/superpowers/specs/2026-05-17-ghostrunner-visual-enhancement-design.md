# GhostRunner — Visual Enhancement (v0.1) — Design

A visual upgrade to the ghost representation in GhostRunner v0. Replaces the floor-anchored 2D HUD nameplate with a three-part visual: an in-world ground trail showing the ghost's recent path, a vertical pole rising from the ghost's foot position to head height, and a head-anchored nameplate carrying a class icon, name, status indicator, and three bars (toughness, HP-with-wounds, ability). Pure client-side rendering — no spawned units, no engine extensions modified — so it works in any session type (solo or MP) without affecting authoritative game state.

## Goals

- Move the existing nameplate from foot height to head height; reuse the same projection pipeline.
- Add a 3D world overlay (`LineObject`) drawing a fading trail behind the ghost and a vertical pole connecting foot to head.
- Replace the existing peril bar with toughness + ability bars; render HP with wound segmentation matching vanilla Darktide.
- Add a class identity icon (Darktide PUA glyph) and a verb-only status row to the nameplate.
- Bump the run-file schema from `1` to `2` to carry the new fields, and apply file-size optimizations (numeric rounding + shorter keys + dropped discriminator) while staying within JSONL.

## Out of scope

- Spawning a player husk, character unit, or any other engine entity. (Considered, rejected — would corrupt MP session state and was already out of scope in v0.)
- Using the engine's outline / skeleton-hologram render modes. (Considered, rejected — they're coupled to real `Unit`s with character meshes; without spawning a unit we can't drive them.)
- Replay in MP missions. (The recorder already captures MP runs via the `record_online_missions` toggle, but the replayer remains gated on `is_solo` as today; lifting that gate is its own piece of work.)
- Per-joint skeleton reconstruction. (We don't record joint transforms, and faking them with `LineObject` lines looks cartoonish.)
- Schema-1-style "delta encoding" or binary frames. (Out of scope for v0.1; still v1 candidates.)
- Recording crouch state. (Not currently captured; downed-vs-standing is the only height distinction this design honours.)

## Hard dependency

Same as v0: `SoloPlay`. No new mod dependencies.

## Architecture

### New module

```
GhostRunner/scripts/mods/GhostRunner/
├── world_renderer.lua    -- owns a LineObject; per-frame trail + pole rendering
```

### Module responsibilities (additions)

| Module | New responsibilities |
|---|---|
| `world_renderer` | Holds a `LineObject` for the duration of a replay. Each tick: reset, build trail segments from the most recent frames within the trail-duration window, add the vertical pole, dispatch. Created on `replayer.arm`, destroyed on `replayer.disarm`. |
| `recorder` | Reads new per-frame fields (`to`, `ab`, `st`) and new metadata fields (`wmax`). Writes schema 2. |
| `replayer` | Carries the new fields through `last_state`. Supports schema 1 (legacy) by setting absent fields to defaults so the renderer degrades gracefully. |
| `hud_beacon` | New widget passes: class icon (top), status row (between name and bars), three bars (toughness / HP-with-wounds / ability). Backing rect with state-conditional tint. |
| `GhostRunner.lua` | Per-frame update block: projects from head, anchors nameplate bottom-edge to projected point, drives `world_renderer`, drives new beacon setters. |

### Data flow (additions to the v0 diagram)

```
[Replayer] ──► last_state (now includes to, ab, st) ──┬─► HudElementGhostBeacon (head-projected)
                                                                  └─► world_renderer (LineObject trail + pole)
```

The `RemotePlayerSource` interface is unchanged. v1's `NetworkSource` will produce the same shape of state and feed both renderers transparently.

## Run file format — schema 2

### Backwards compatibility

Schema 1 runs still load. Loader maps absent fields to defaults so the renderer degrades gracefully:

| Schema 1 field | Schema 2 treatment when loading schema 1 |
|---|---|
| `d` (bool) | Translated: `d=true` → `st="knocked_down"`; `d=false` → `st="walking"` |
| `peril` | Dropped on read; peril bar is no longer rendered |
| (no `wmax`) | HP renders as a single un-segmented bar |
| (no `to`) | Toughness bar hidden |
| (no `ab`) | Ability bar hidden |

New recordings always write schema 2.

### Wire format optimizations

All schema-2 changes are bundled with two file-size optimizations:

**Numeric rounding** (Tier 1):

| Field | Precision | Format |
|---|---|---|
| `p` | 2 decimals | cm-precision; gameplay movement granularity is ~10 cm |
| `y` | 3 decimals | ~0.06° angular resolution |
| `hp` / `to` / `ab` | 3 decimals | 0.1%, below visible threshold |
| `t` | 3 decimals | ms-precision |
| `pg` | 4 decimals | tighter for race-timer delta math |

Implementation pattern: round to the target precision with `string.format`, immediately `tonumber()` to get back a number with the trailing zeros stripped, then let `cjson.encode` serialize the minimal representation. `0.5` stays `0.5`; `0.50000000001` becomes `0.5`; `12.534823974` becomes `12.53`.

**Shorter keys + dropped discriminator** (Tier 2):

- `tough` → `to`
- `ability` → `ab`
- `state` → `st`
- `prog` → `pg`
- `"type":"f"` is dropped from every frame line.

Line-type inference rules:
- First line has `"schema"` → metadata header.
- Last line has `"outcome"` → footer.
- Everything in between → frame.

Combined Tier 1 + 2: ~115 bytes/frame → ~70 bytes/frame (~35–40% reduction). A 10-minute run drops from ~1.4 MB to ~850 KB.

### Schema 2 wire format

**Metadata header** (one new field: `wmax`):

```jsonl
{"type":"meta","schema":2,"player":"AustenC","class":"psyker","wmax":2,"mission":{"name":"throneside_damnation","difficulty":5,"resistance":3,"circumstance":"default","side":"default","giver":"default","havoc":null,"seed":1234567890},"recorded_at":"2026-05-17T14-32-11.847Z"}
```

`wmax`: max wounds the player started with (read once at recorder start). Used to render HP-bar segmentation.

**Frame line** (no `type` discriminator; abbreviated keys):

```jsonl
{"t":1.5,"p":[12.53,47.24,1.82],"y":1.57,"hp":1.0,"to":0.8,"ab":0.6,"w":3,"st":"walking","pg":0.234}
```

| Key | Type | Meaning |
|---|---|---|
| `t` | float | seconds since first sample |
| `p` | `[x,y,z]` | world position (Vector3) |
| `y` | float | yaw in radians |
| `hp` | 0..1 | HP fraction (`current/max`) |
| `to` | 0..1 | toughness fraction (`current/max`) |
| `ab` | 0..1 | combat-ability cooldown progress (1.0 = ready) |
| `w` | int | wounds remaining |
| `st` | string | character state machine state (verbatim from `csm:current_state()`) |
| `pg` | 0..1 or null | main-path travel fraction |

**Footer** (unchanged from schema 1):

```jsonl
{"type":"end","outcome":"completed","duration":403.7,"seed_pinned":true,"on_shutdown":false}
```

### Per-sample reads (additions)

| Field | Read site | Verify at implementation |
|---|---|---|
| `wmax` (metadata) | `health_extension:max_wounds()` or the `health` component's `max_wounds` field | Find canonical source in vanilla teammate-panel HUD code. |
| `to` (per-frame) | `unit_data:read_component("toughness")` — fields likely `current_toughness` + `max_toughness`, OR a `toughness_extension` with a percentage getter | Read `scripts/extension_systems/toughness/*` to pin the actual API. |
| `ab` (per-frame) | `unit_data:read_component("combat_ability")` — likely has `cooldown_started_at_t` and `cooldown_duration`; compute `(t_now - started) / duration` clamped `[0, 1]`. | Read `scripts/extension_systems/ability/*` for the actual field names and how the active-ability phase is exposed. |
| `st` (per-frame) | `csm:current_state()` written verbatim (replaces the v0 `d` boolean) | Enumerate alive vs disabled state names in `scripts/extension_systems/character_state_machine/character_states/*`. |

All reads wrapped in `pcall` per the existing recorder pattern; on failure, the field is omitted/defaulted and recording continues.

## World rendering — `world_renderer.lua`

### Lifecycle

- **Created on `replayer.arm_with_selected_ghost`:** `World.create_line_object(world)`. The target world is `Managers.world:world("level_world")` (verify the exact key during implementation; debug worlds may render on top while level world is depth-tested — we want the level world for the trail-on-floor case to read naturally).
- **Destroyed on `replayer.disarm`:** call the appropriate destroy function for `LineObject` (the type-def doesn't list one explicitly; if no explicit destroy exists, drop the reference and accept the small per-session cost).
- **Dispatched per frame from `mod.update`**, only while `replayer.state() == "playing"`.

### Per-frame algorithm

```
1. LineObject.reset(lo)
2. Compute current interpolated foot position (already in last_state.p)
3. Walk backward through frames from current index, collecting positions
   until either:
     - accumulated recorded time exceeds trail_duration setting, OR
     - we hit frame 1
4. For each consecutive pair (older, newer) in the collected list:
     age = current_t - older.t          -- seconds since that frame
     alpha = max(0, 1 - age / trail_duration)   -- fade
     color = (trail_rgb..., 255 * alpha)
     LineObject.add_line(lo, color, newer.p, older.p)
5. Add the vertical pole:
     foot = last_state.p
     head_z = foot.z + head_offset(last_state.st)
     LineObject.add_line(lo, pole_color, foot, (foot.x, foot.y, head_z))
6. LineObject.dispatch(lo, world)
```

Where `head_offset` returns `0.5` for any state in the downed set, else `1.8`.

### Colors

- **Trail:** `(255, 255, 80, alpha)` — bright yellow-white, alpha-ramped by segment age.
- **Pole:** `(220, 200, 40, 255)` — same hue family, slightly darker and more saturated so it doesn't blend into the trail at low camera angles.

Exact RGB values are constants in one place; trivially tweakable post-implementation in-game.

### Performance

At 20 Hz × 4s trail = ~80 trail segments + 1 pole = ~81 `add_line` calls per frame. Trivial. Trail is fully bounded regardless of mission length.

### Visibility through walls — known unknown

`LineObject`'s type definition does not expose a "always render on top" flag. Behaviour will likely be depth-tested by default if we dispatch to `level_world`. Acceptable degradation:

- Trail-on-floor stays visible because the camera is normally above it.
- Pole may be occluded when the ghost is behind a wall — but the head-anchored nameplate (drawn as HUD, always on top) remains visible. The user can still spot the ghost by its floating nameplate even when its pole and trail are hidden.

If a debug-world dispatch option is found during planning that gives "always on top" for free, switch to it.

## Nameplate — updated `hud_beacon.lua`

### Layout

```
┌──────────────────────────────────┐  ← backing rect (state-dependent tint)
│         [☩]  AustenC             │  ← row 1: icon + name
│      ⚠ NETTED                    │  ← row 2: status row (reserved height, empty when alive)
│      ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░           │  ← row 3: TOUGHNESS bar
│      ▓▓▓│▓▓▓│▓▓░│░░░             │  ← row 4: HP bar with wound segments
│      ▓▓▓▓▓▓▓▓░░░░░░░             │  ← row 5: ABILITY bar
└──────────────────────────────────┘
                  │  ← pole (3D LineObject)
               (foot)
                  ╲ trail
```

Widget bounds: 200×86 (height grew from 60 → 86 to fit status row + extra bar).

### Anchoring

- Nameplate projects from the **head position** in 3D world space: `(p.x, p.y, p.z + head_offset)` where `head_offset` is the same `0.5 / 1.8` as the pole top.
- Widget bottom-edge anchored to the projection point (was: widget center). Math change in `set_offset`: from `widget.offset[2] = y - HALF_H` to `widget.offset[2] = y - HEIGHT - PAD` where `PAD ~= 6px` so the pole tip terminates just below the panel.

### Element details

**Class icon:**
- Top row, inline left of name.
- `font_type = "proxima_nova_bold"`, `font_size = 22` (slightly larger than the name's 18).
- Value: PUA codepoint for the class, rendered via Darktide's font fallback chain to `darktide_custom_regular`.
- Codepoint table (detailed-variant glyphs from `scripts/settings/ui/ui_settings.lua`):

  | class | codepoint |
  |---|---|
  | `veteran` | `U+E01A` |
  | `zealot` | `U+E01B` |
  | `psyker` | `U+E01C` |
  | `ogryn` | `U+E01D` |
  | `adamant` | `U+E050` |

- UTF-8 encoding helper (Bitsquid Lua's `\u{XXXX}` support is uncertain — compute bytes at mod load):

  ```lua
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
  local CLASS_GLYPHS = {
      veteran = cp(0xE01A), zealot = cp(0xE01B), psyker = cp(0xE01C),
      ogryn = cp(0xE01D), adamant = cp(0xE050),
  }
  ```

- Unknown class → empty string; everything else still renders.

**Name text:**
- Unchanged from v0 except color is now driven by state (white when alive, bright red when not).

**Status row:**
- Always reserved height (~14 px) so the widget doesn't bounce when the ghost goes down.
- 12 pt, drop-shadowed, red `(255, 80, 80, 255)`.
- Empty string when `st == "alive"` (or any non-downed state).
- Mapping table (verb-only):

  | state | display text |
  |---|---|
  | `walking` / `sprinting` / `jumping` / `crouching` / `sliding` / `falling` / `dodging` / `vaulting` / `ladder_climbing` / etc. | *empty* |
  | `knocked_down` | `DOWN` |
  | `hogtied` | `HOGTIED` |
  | `netted` | `NETTED` |
  | `pounced` | `POUNCED` |
  | `lunging` / `mutant_charged` | `GRABBED` |
  | `consumed` | `CONSUMED` |
  | `dead` | `DEAD` |
  | *(unrecognized)* | `state:upper():gsub("_", " ")` — fallback so future patches still display *something* |

  Alive-set and exact spellings verified at planning by enumerating `scripts/extension_systems/character_state_machine/character_states/*`.

**Bars:**

| Bar | Source | Color | Width | Notes |
|---|---|---|---|---|
| Toughness (top) | `to` | `(255, 220, 220, 220)` silver-white | 140×6 | Standard fill bar |
| HP (middle) | `hp` + `w` + `wmax` | `(255, 220, 60, 60)` red | 140×6 | Segmented into `wmax` sections by thin dark vertical lines. Filled / actively-depleting / lost-wound section relationship mirrors the vanilla player HUD's HP bar — exact mapping between `hp`, `w`, and segment fill verified at implementation against `scripts/ui/hud/elements/player_panel/*` (or equivalent). Schema-1 ghosts (no `wmax`) render a single un-segmented bar. |
| Ability (bottom) | `ab` | `(255, 200, 80, 220)` gold | 140×6 | Fills 0 → 1 as cooldown ticks; 1.0 = ready |

**Backing rect:**

- Alive: `(0, 0, 0, 140)` neutral dark, semi-transparent.
- Not alive (any disabled state): `(120, 0, 0, 160)` dark red — the whole panel reads as "alarm" at a glance.
- Backing covers the full widget bounds with a few-pixel inset margin.

### New beacon setters

| Method | When called | What it does |
|---|---|---|
| `set_class(class_name)` | Once on `arm_with_selected_ghost`, alongside `set_name` | Writes the glyph into the class-icon widget pass |
| `set_wmax(n)` | Once on arm | Pre-computes the segmentation geometry for the HP bar |
| `set_state(state)` (replaces v0's `set_state(state_table)`) | Per frame | Drives status-row text, name color, backing tint, and the three bar fills — combines what `set_state` did before with the new state-aware visuals |

The per-frame setter signature is the only breaking change to `hud_beacon`'s external API; internal pass count grows but the widget remains a single `UIWidget.create_definition`.

## Recorder changes

Three changes to [recorder.lua](GhostRunner/scripts/mods/GhostRunner/recorder.lua):

1. **At `recorder.start`:** read max wounds via the health extension/component and write it as `meta.wmax`. Default to `nil` if unreadable — the recording is still valid, just won't show HP segments on replay.
2. **In `_read_state`:** add three reads — toughness fraction (`to`), combat-ability cooldown progress (`ab`), CSM state string (`st`). Remove the `d` boolean and the peril read. Each read individually `pcall`-wrapped so one missing extension doesn't kill the whole frame.
3. **Before writing frames and metadata:** apply the numeric-rounding pre-pass (`round_to_n_decimals` per field), drop the `"type":"f"` discriminator from frame writes. Keep `"type":"meta"` / `"type":"end"` on the header and footer for self-documentation (and to support the line-type inference rules).

The flush policy, accumulator math, lifecycle, and `_abandon` / `stop_and_save` paths are unchanged.

## Replayer changes

Two changes to [replayer.lua](GhostRunner/scripts/mods/GhostRunner/replayer.lua):

1. **Loader (in [run_file.lua](GhostRunner/scripts/mods/GhostRunner/run_file.lua) — the parser):** accept schema 1 and schema 2. For schema 1 lines, on-load translation: `d=true → st="knocked_down"`, `d=false → st="walking"`. Drop `peril`. `to`/`ab` left absent.
2. **`last_state` shape:** add `to`, `ab`, `st`. The interpolator gains lerps for `to` and `ab` (same pattern as `hp`); `st` is a step function (same pattern as the old `d`). Existing `hp`/`y`/`p`/`pg`/`w`/`peril` (now removed) paths cleaned up; `prog` → `pg` field rename throughout in-memory state.

The `arm` / `disarm` flow is unchanged except that:

- `arm` calls into `world_renderer.create()` to allocate the `LineObject`.
- `disarm` calls into `world_renderer.destroy()` to release it.
- `arm` also calls `beacon:set_class(meta.class)` and `beacon:set_wmax(meta.wmax)` after the existing `set_name`.

## DMF settings — additions

Under the existing "Replay" header in `GhostRunner_data.lua`:

```
├── [checkbox] Show ghost trail            (default: on)
├── [slider]   Trail duration (seconds)    (default: 4.0, range 1.0–10.0, step 0.5)
└── [checkbox] Show ghost nameplate        (default: on)
```

- "Show ghost trail" toggles the entire `world_renderer` (trail + pole). Off = pure HUD ghost like v0 but with head-anchoring.
- "Show ghost nameplate" toggles the existing HUD beacon. Off = pole+trail only with no nameplate. (Useful if the user finds the floating panel intrusive.)
- Trail duration is the time-based "last N seconds" window. 4.0 default reads as a comet tail without becoming a route map.

## Edge cases

| Scenario | Behaviour |
|---|---|
| Schema 1 ghost loaded | Renders with new layout but: HP bar un-segmented (no `wmax`); toughness + ability bars hidden; downed-detection works via translated `d → st` mapping. |
| Ghost has unknown `class` field | Class icon renders as empty string. Rest of nameplate normal. |
| Recorder can't read toughness/ability/wmax (unsupported class? mid-load frame?) | Field omitted from that frame / metadata. Replayer treats it as the schema-1 case for that field. |
| `csm:current_state()` returns nil / errors | `pcall` catches; recorder writes nothing for `st` on that frame; replayer defaults to last seen value (or `"walking"` if first frame). |
| Ghost is behind a wall | Pole likely occluded (depth test). Trail-on-floor mostly visible (camera typically above). Head-anchored nameplate always visible (HUD layer). |
| Replayer state goes `playing → finished` | `world_renderer` is still allocated but stops drawing because the per-frame guard checks `replayer.state() == "playing"`. Destroyed on `disarm` (which fires at `mission_cleanup`). |
| User toggles "Show ghost trail" mid-mission | `world_renderer` lifecycle stays tied to replayer arm/disarm; the per-frame draw block checks the setting before dispatching. Toggle takes effect on the next frame. |
| Ghost has no `t=0` frame within trail-window distance (early replay) | Trail walk-back hits frame 1 and stops; trail just renders fewer segments. |
| Crouching ghost | Pole stays at 1.8m (crouch not recorded). Cosmetic only — pole appears to float above the head when crouched. Acceptable v0.1 limitation. |

## Performance budget

| Subsystem | Per-frame cost |
|---|---|
| Trail build (walk-back + ~80 add_line) | sub-millisecond |
| Pole (1 add_line) | negligible |
| LineObject dispatch | engine call; bounded by ~81 segments |
| Beacon update (3 bars + name + status) | similar to current 2-bar widget; well under the existing HUD overhead |
| Schema-2 frame parse (loader, one-shot at arm) | shorter lines parse faster, not slower |

No new per-tick allocation in the steady state — `LineObject.reset` clears in-place; trail segments are computed into a single buffer.

## Verification items for the planning pass

These are the items the design intentionally defers to implementation because they require source-mirror reads or in-engine verification:

1. **Exact toughness component / extension API** — field names for current and max toughness.
2. **Exact combat-ability cooldown API** — how to compute the 0..1 cooldown progress; whether mid-cast is exposed as a separate state.
3. **Max-wounds API** — confirm the canonical source the vanilla HUD uses.
4. **Vanilla HP-bar wound segmentation visual** — confirm the relationship between `current_health`, `current_wounds`, and `max_wounds` that the player HUD uses, so our segmented bar mirrors it.
5. **CSM state-name enumeration** — full list of "alive" states vs "disabled" states, exact spellings (`netted` vs `trapped` vs `hogtied`, etc.). Sourced from `scripts/extension_systems/character_state_machine/character_states/*`.
6. **`LineObject.destroy` (or equivalent)** — whether there's a sanctioned cleanup call to avoid leaking line objects across replay arm/disarm cycles.
7. **World selection** — confirm `Managers.world:world("level_world")` is the right target; whether a debug-world dispatch gives "always on top" without ill side-effects.

Each will be resolved during the planning pass by reading the relevant files from the Darktide source mirror (per the `reference_darktide_modding.md` memory: `curl -fsSL https://raw.githubusercontent.com/Aussiemon/Darktide-Source-Code/master/<path>.lua`).

## Future direction (post-v0.1)

- **MP replay** — lift the `is_solo` gate on `replayer.on_local_player_spawn`. Recording already works in MP; the rendering pipeline in this design works in MP. Outstanding question: mission auto-set and seed-pinning are no-ops in MP, so the user would have to ghost-race only on missions they happen to join with the matching name.
- **Pitch and crouch in the recording** — would let the pole tip track head height more accurately during crouches and give a v1 weapon-aim direction indicator.
- **Class-specific ability semantics** — a richer ability bar could show charge stacks for classes that have them, or split the bar into segments for multi-charge blitzes (when blitz comes back into scope).
- **Engine-skeleton attempt** — only feasible if a future design decision adds husk spawning, and only relevant if MP-corruption risks can be mitigated. Treat as a separate research project.
