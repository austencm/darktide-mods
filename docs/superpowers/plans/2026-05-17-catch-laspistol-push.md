# Catch Laspistol Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the `KeepYourHead` DMF mod to suppress the laspistol special-attack input (`weapon_extra_pressed` / `_hold`) at or above the peril threshold, because a Psyker wielding either laspistol variant routes the special through `action_psyker_push`, which generates peril and pops the head at lockout.

**Architecture:** Single input-layer gate. Adds one weapon-name predicate (`is_laspistol`) and one new boolean setting (`block_laspistol_push`), and rewrites the existing `weapon_extra` branch in `should_block` to dispatch on wielded weapon. Mod is client-side only and reads peril/weapon/ability state lazily inside the existing `InputService:_get` / `_get_simulate` hook. No new hooks, no new HUD elements, no extension changes.

**Tech Stack:** Lua (Darktide Bitsquid-fork LuaJIT), Darktide Mod Framework (DMF). Game install at `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\`. Mod folder is `KeepYourHead/`. Console logs at `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\console-<timestamp>-<guid>.log`. There is no automated test framework — verification is manual in-game.

**Spec:** [docs/superpowers/specs/2026-05-17-catch-laspistol-push-design.md](../specs/2026-05-17-catch-laspistol-push-design.md)

---

## File map

All edits are inside `KeepYourHead/scripts/mods/KeepYourHead/`:

- **Modify:** `KeepYourHead.lua` — add `is_laspistol` helper, add `block_laspistol_push` to settings table + default initializer, rewrite `weapon_extra` branch in `should_block`.
- **Modify:** `KeepYourHead_data.lua` — add `block_laspistol_push` checkbox sub-widget inside the `group_blocking` group.
- **Modify:** `KeepYourHead_localization.lua` — add `block_laspistol_push` + `block_laspistol_push_description` entries; update `mod_description` to mention laspistol coverage.

No new files. No file deletions.

---

## Task 1: Add `is_laspistol` predicate and `block_laspistol_push` setting

**Files:**
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua`

This task lands the helper, the new setting key with its default, and the localization/data widget. No behavior change yet — the new setting is read but not consulted by `should_block`. Splitting this out from the gate rewrite keeps Task 1 a pure additive change and Task 2 a focused logic change.

- [ ] **Step 1.1: Add `is_laspistol` helper beside `is_force_sword`**

In `KeepYourHead.lua`, find this existing block (currently around lines 285–287):

```lua
local function is_force_sword(weapon_name)
	return weapon_name ~= "" and string_find(weapon_name, "forcesword", 1, true) ~= nil
end
```

Insert directly after it (preserving the existing block's blank-line separation from the comment above):

```lua
-- Both laspistol templates (laspistol_p1_m1, laspistol_p1_m3) define an
-- `action_psyker_push` branch selected only when the wielder is a Psyker
-- (`archetype.name == "psyker"`). That branch generates peril; the standard
-- `action_normal_push` served to other archetypes does not. Substring match
-- on `laspistol` covers both current variants and any future laspistol
-- Fatshark adds with the same dual-push template structure.
local function is_laspistol(weapon_name)
	return weapon_name ~= "" and string_find(weapon_name, "laspistol", 1, true) ~= nil
end
```

- [ ] **Step 1.2: Add `block_laspistol_push` to the `mod.settings` table**

Find the `mod.settings = { ... }` block (currently around lines 101–115). Insert one new line into the table, immediately after `block_force_sword`:

Before:
```lua
mod.settings = {
	peril_threshold               = (mod:get("peril_threshold") or 99.8) / 100,
	block_force_sword             = mod:get("block_force_sword"),
	block_force_staff_fire        = mod:get("block_force_staff_fire"),
```

After:
```lua
mod.settings = {
	peril_threshold               = (mod:get("peril_threshold") or 99.8) / 100,
	block_force_sword             = mod:get("block_force_sword"),
	block_laspistol_push          = mod:get("block_laspistol_push"),
	block_force_staff_fire        = mod:get("block_force_staff_fire"),
```

- [ ] **Step 1.3: Add the `nil` → `true` default initializer**

Find the block of `if mod.settings.X == nil then mod.settings.X = true end` lines (currently around lines 116–123). Insert one new line, immediately after the `block_force_sword` initializer:

Before:
```lua
if mod.settings.block_force_sword             == nil then mod.settings.block_force_sword             = true  end
if mod.settings.block_force_staff_fire        == nil then mod.settings.block_force_staff_fire        = true  end
```

After:
```lua
if mod.settings.block_force_sword             == nil then mod.settings.block_force_sword             = true  end
if mod.settings.block_laspistol_push          == nil then mod.settings.block_laspistol_push          = true  end
if mod.settings.block_force_staff_fire        == nil then mod.settings.block_force_staff_fire        = true  end
```

No edit needed in `mod.on_setting_changed` — the generic `else` branch (`mod.settings[setting_id] = mod:get(setting_id)`) already handles arbitrary boolean setting keys.

- [ ] **Step 1.4: Verify no Lua syntax errors via luacheck**

Run from the worktree root:

```
luacheck KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua --no-color
```

Expected: same warning/error count as before this task (no NEW warnings). The repo's `.luacheckrc` is already configured for DMF/Darktide globals. If luacheck isn't on PATH, skip this step — there's no CI gate for it; the in-game smoke test in Task 4 will catch syntax errors.

- [ ] **Step 1.5: Commit**

```
git add KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua
git commit -m "$(cat <<'EOF'
feat(KeepYourHead): add is_laspistol helper and block_laspistol_push setting key

Pure additive: defines the predicate and reads the new setting with a
default of true, but should_block does not yet consult it. Next task
wires it into the weapon_extra branch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Wire `block_laspistol_push` into `should_block` and narrow the force-sword gate

**Files:**
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua`

This is the behavior change. It also lands the tag-along fix from the spec: today the `weapon_extra` branch fires whenever `block_force_sword = true`, regardless of wielded weapon (so V is blocked on chainsword / autopistol at threshold too). Narrowing the condition with `is_force_sword(weapon_name)` makes the existing gate match its setting's name.

- [ ] **Step 2.1: Rewrite the `weapon_extra` branch in `should_block`**

Find this block (currently lines ~337–339, inside `local function should_block(action_name)`):

```lua
	if settings.block_force_sword and BLOCKED_INPUTS_WEAPON_EXTRA[action_name] then
		return peril >= base
	end
```

Replace with:

```lua
	if BLOCKED_INPUTS_WEAPON_EXTRA[action_name] then
		if settings.block_force_sword   and is_force_sword(weapon_name)   then return peril >= base end
		if settings.block_laspistol_push and is_laspistol(weapon_name)    then return peril >= base end
	end
```

Order matters only marginally — a wielded weapon won't match both predicates simultaneously, but force-sword check is kept first to preserve the existing common case at the cheapest possible cost.

- [ ] **Step 2.2: Sanity-check via grep that `is_laspistol` is now referenced exactly twice (definition + use)**

Run:

```
grep -n "is_laspistol" KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua
```

Expected output: two lines — one `local function is_laspistol(weapon_name)` (definition from Task 1) and one inside `should_block`'s `weapon_extra` branch (this task). If you see only one match, the wire-up didn't land.

- [ ] **Step 2.3: Commit**

```
git add KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua
git commit -m "$(cat <<'EOF'
feat(KeepYourHead): gate laspistol special-attack input at peril threshold

A Psyker wielding either laspistol routes weapon_extra through
action_psyker_push, which generates peril and pops the head at lockout.
Block weapon_extra_pressed/_hold at threshold when a laspistol is
wielded, gated by the new block_laspistol_push setting (default true).

Also narrows the existing block_force_sword weapon_extra gate to
actually require is_force_sword(weapon_name) — previously the V input
was blocked at threshold for any wielded weapon, including non-warp
melee (chainsword, autopistol) where V is free. No UX impact for
typical Psyker play; correctness improvement.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add settings widget + localization

**Files:**
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua`
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua`

This exposes the new toggle in the in-game options menu and updates the mod's user-facing description.

- [ ] **Step 3.1: Add the checkbox widget in `KeepYourHead_data.lua`**

Find the `group_blocking` sub_widgets table (currently around lines 22–38):

```lua
{
	setting_id  = "group_blocking",
	type        = "group",
	sub_widgets = {
		{
			setting_id    = "block_force_sword",
			type          = "checkbox",
			default_value = true,
		},
		{
			setting_id    = "block_force_staff_fire",
			type          = "checkbox",
			default_value = true,
		},
		{
			setting_id    = "block_warp_ability",
			type          = "checkbox",
			default_value = true,
		},
	},
},
```

Insert one new sub-widget between `block_force_sword` and `block_force_staff_fire`:

```lua
{
	setting_id  = "group_blocking",
	type        = "group",
	sub_widgets = {
		{
			setting_id    = "block_force_sword",
			type          = "checkbox",
			default_value = true,
		},
		{
			setting_id    = "block_laspistol_push",
			type          = "checkbox",
			default_value = true,
		},
		{
			setting_id    = "block_force_staff_fire",
			type          = "checkbox",
			default_value = true,
		},
		{
			setting_id    = "block_warp_ability",
			type          = "checkbox",
			default_value = true,
		},
	},
},
```

- [ ] **Step 3.2: Add the two localization entries in `KeepYourHead_localization.lua`**

Find the existing `block_force_sword` localization block (currently lines 45–50):

```lua
block_force_sword = {
	en = "Block Force Sword",
},
block_force_sword_description = {
	en = "Block peril-generating inputs on force swords at or above the threshold. Covers ignite/charge and push attacks. Basic pushes, light melee, and heavy melee always work.",
},
```

Insert two new blocks immediately after it (and before `block_force_staff_fire = {`):

```lua
block_laspistol_push = {
	en = "Block Laspistol Push",
},
block_laspistol_push_description = {
	en = "Block laspistol special (V) at or above the threshold. A Psyker wielding either laspistol gets the psychic push variant, which costs peril.",
},
```

- [ ] **Step 3.3: Update `mod_description` to mention laspistol coverage**

Find the existing `mod_description` block (currently lines 5–7):

```lua
mod_description = {
	en = "Blocks inputs that would increase peril when peril is ≥ a threshold (default 99.8). Includes blitzes, staffs, and force sword ignite and push-attack.",
},
```

Replace the `en` string with:

```lua
mod_description = {
	en = "Blocks inputs that would increase peril when peril is ≥ a threshold (default 99.8). Includes blitzes, staffs, force sword ignite and push-attack, and laspistol psychic push.",
},
```

- [ ] **Step 3.4: Verify no `%` characters were introduced into label strings**

`mod:localize` runs label values through `string.format`, so a bare `%` crashes. Our new strings use no `%`, but quick check:

```
grep -nE "block_laspistol_push|mod_description" KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua
```

Expected: matched lines contain only readable text, no `%` characters (description strings are OK with `%` but label strings are not — the only label here is `"Block Laspistol Push"`).

- [ ] **Step 3.5: Commit**

```
git add KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua
git commit -m "$(cat <<'EOF'
feat(KeepYourHead): expose block_laspistol_push in options menu

Adds the checkbox to the Input Blocking group between block_force_sword
and block_force_staff_fire, plus the corresponding en localization
entries. Updates the mod's description blurb to mention laspistol
coverage.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: In-game smoke test in Psykhanium

**Files:** none modified — manual verification only.

The Psykhanium is the only place a mod author can mutate peril safely (the local client IS the server there per the project's memory of MP server authority). This task runs through the spec's test matrix.

- [ ] **Step 4.1: Ensure symlinks are in place and launch Darktide**

If you've recently added the `KeepYourHead` folder, the symlink into the game's `mods/` directory should already exist (from prior renames). If unsure, run `symlink_mods.bat` as Administrator from the repo root. Then launch Darktide via Steam.

- [ ] **Step 4.2: Verify the new setting appears in the options menu**

In the main menu: Mod Settings → Keep Your Head → Input Blocking group. Confirm "Block Laspistol Push" is present between "Block Force Sword" and "Block Staff", defaulted to ON, and its description text reads as written in Step 3.2.

- [ ] **Step 4.3: Run the test matrix in the Psykhanium**

Equip a Psyker, enter the Psykhanium training mode. For each test case, use the in-game peril controls (or a force staff RMB charge) to raise peril, then attempt the listed input.

| # | Wielded weapon | Peril | Input | Expected | Pass? |
|---|---|---|---|---|---|
| 1 | Heavy laspistol (Lucius MK II) | ≥ 99.8% | V (special_action_push) | Suppressed; HUD warning visible | |
| 2 | Heavy laspistol | ~90% | V | Push fires normally; HUD off | |
| 3 | Standard laspistol (Lucius MK III) | ≥ 99.8% | V | Suppressed; HUD warning visible | |
| 4 | Chainsword (non-laspistol non-force) | ≥ 99.8% | V | Chainsword special fires; HUD off | |
| 5 | Force sword | ≥ 99.8% | V | Suppressed; HUD warning visible | |
| 6 | Force sword | ~90% | V | Force-sword ignite fires; HUD off | |

Case 4 is the regression check for the tag-along fix in Task 2 — before this change, V on a chainsword at high peril was being blocked incorrectly.

- [ ] **Step 4.4: Vent-ready short-circuit check (case 7)**

Equip Scrier's Gaze as combat ability (off cooldown), wield heavy laspistol, raise peril to 99.8%. Press V. **Expected:** push fires (the whole mod stands down because vent is ready, per the existing `disable_when_vent_ready` setting). HUD warning should NOT light up.

- [ ] **Step 4.5: Setting-off check (case 8)**

Toggle "Block Laspistol Push" OFF in the options menu (use Ctrl+Shift+R to reload mods if needed). Re-enter Psykhanium, wield heavy laspistol, raise peril to 99.8%, press V. **Expected:** push fires (gate respects the toggle). HUD warning may still light up if another gate (e.g. force-sword V) would fire at this peril level — that's correct behavior.

- [ ] **Step 4.6: Console-log sanity check**

Open the newest `console-<timestamp>-<guid>.log` file in `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\`. Grep for `KeepYourHead`. **Expected:** no error lines, no `[Lua] ERROR` entries from this mod. If the debug_dump setting is on, you'll see per-press lines with `action=weapon_extra_pressed weapon=laspistol_p1_m3 …` — that's informational, not an error.

- [ ] **Step 4.7: Document any failures**

If any test case fails, do NOT commit further. Capture the symptoms, the most-recent console log excerpt (lines mentioning KeepYourHead), and stop here. The plan executor should report back rather than improvising fixes; an unexpected failure may indicate the empirical premise (laspistol push generates peril) was wrong for some build or talent loadout, and that wants discussion before patching.

If all cases pass, proceed to Task 5.

---

## Task 5: Optional Damnation mission verification

**Files:** none modified — manual verification only.

The Psykhanium runs the local client as server (modded Lua), but real missions run on Fatshark dedicated servers (unmodded Lua). The mod's hook is client-side input gating, so it should work identically in MP, but this task confirms that empirically and that no other code path overrides the gate in a real network session.

- [ ] **Step 5.1: One mission with heavy laspistol equipped**

Queue a Damnation mission (or any difficulty above Sedition) with Psyker class, heavy laspistol secondary. Play normally for one objective at minimum. **Expected:** no head-pops from V presses. If a head-pop occurs during V, capture the console log and STOP — possible client/server desync mode the design didn't anticipate.

- [ ] **Step 5.2: If verified, mark plan complete**

No commit needed for this task — it's verification only. If you reached this point with all checks green, the implementation is done.

---

## Self-review notes

- **Spec coverage:** Each numbered item in the spec's "Code change" and "Testing" sections maps to a task above. The "Non-changes" list is honored: no HUD edits, no extension reads added, no per-frame state cache changes.
- **Placeholder scan:** No TBDs, TODOs, "implement later," or "handle edge cases" instructions. All code blocks are complete.
- **Type consistency:** `is_laspistol` is defined once in Task 1, referenced once in Task 2; setting key `block_laspistol_push` matches across `mod:get(...)`, the `mod.settings` table, the data widget, and both localization entries.
