# Catch laspistol push — design

Status: design
Date: 2026-05-17

## Goal

Extend `KeepYourHead` to suppress the laspistol special-attack input (`weapon_extra_pressed` / `_hold`, default V) at or above the peril threshold, because a Psyker wielding either laspistol variant gets routed to an `action_psyker_push` branch that generates enough peril to pop the head when fired at lockout.

## Background

Both laspistol templates in source — `laspistol_p1_m1` (Lucius MK III, "standard") and `laspistol_p1_m3` (Lucius MK II, "heavy") — define two parallel push actions:

- `action_normal_push` — non-warp melee push, no peril.
- `action_psyker_push` — peril-generating push, gated by `action_condition_func` that returns `archetype.name == "psyker"`.

The input-to-action chain routes `weapon_extra_pressed` through `special_action_push`, with both actions listed as candidates and Darktide picking the first one whose `action_condition_func` passes. A Psyker is always served `action_psyker_push`; other archetypes always get `action_normal_push`. The empirical observation: firing this special on a Psyker at peril lockout pops the head, matching the pre-action `>= 100%` rule that the existing mod already gates against for force-sword `weapon_extra`.

The fix mirrors the force-sword gate: block `weapon_extra_pressed` / `_hold` when the wielded weapon is a laspistol and peril is at threshold.

## Code change

All three changes live in `KeepYourHead/scripts/mods/KeepYourHead/`.

### `KeepYourHead.lua`

1. Add weapon-name predicate beside the existing `is_force_sword` / `is_force_staff` helpers:

   ```lua
   local function is_laspistol(weapon_name)
       return weapon_name ~= "" and string_find(weapon_name, "laspistol", 1, true) ~= nil
   end
   ```

   The substring `laspistol` matches both `laspistol_p1_m1` and `laspistol_p1_m3`. No future Fatshark laspistol variant would deviate.

2. Read the new setting in the `mod.settings` table (default `true`):

   ```lua
   block_laspistol_push = mod:get("block_laspistol_push"),
   ```

   …with the same `if mod.settings.X == nil then mod.settings.X = true end` pattern as the other booleans. No change needed in `mod.on_setting_changed` — the generic `else` branch (`mod.settings[setting_id] = mod:get(setting_id)`) handles booleans without special-casing.

3. Rewrite the existing `weapon_extra` branch in `should_block`. Currently:

   ```lua
   if settings.block_force_sword and BLOCKED_INPUTS_WEAPON_EXTRA[action_name] then
       return peril >= base
   end
   ```

   Becomes:

   ```lua
   if BLOCKED_INPUTS_WEAPON_EXTRA[action_name] then
       if settings.block_force_sword   and is_force_sword(weapon_name)   then return peril >= base end
       if settings.block_laspistol_push and is_laspistol(weapon_name)    then return peril >= base end
   end
   ```

   This adds the laspistol gate AND fixes a latent overreach in the existing branch: today, `block_force_sword = true` blocks `weapon_extra` for *any* wielded weapon (chainsword V, autopistol V, etc.), not just force swords. Narrowing the existing condition with `is_force_sword(weapon_name)` is a correctness improvement with no UX impact for typical Psyker play (a Psyker at the front line almost always has a force weapon wielded). Combined with the new laspistol gate, V is now blocked exactly when the wielded weapon's special action costs peril.

### `KeepYourHead_data.lua`

Add a checkbox sub-widget to the existing `group_blocking` group, between `block_force_sword` and `block_force_staff_fire`:

```lua
{
    setting_id    = "block_laspistol_push",
    type          = "checkbox",
    default_value = true,
},
```

### `KeepYourHead_localization.lua`

Add two entries beside the existing `block_force_sword` block (English only — matches the rest of the file, which has no other locales populated):

```lua
block_laspistol_push = {
    en = "Block Laspistol Push",
},
block_laspistol_push_description = {
    en = "Block laspistol special (V) at or above the threshold. A Psyker wielding either laspistol gets the psychic push variant, which costs peril.",
},
```

Update `mod_description` to mention laspistol coverage so the in-options summary stays accurate:

```
en = "Blocks inputs that would increase peril when peril is ≥ a threshold (default 99.8). Includes blitzes, staffs, force sword ignite and push-attack, and laspistol psychic push."
```

## Non-changes

- `HudElementKeepYourHeadWarning.lua` — no change. `is_warning_active()` already probes `weapon_extra_pressed` against `should_block`, so the laspistol gate lights up the predictive HUD automatically.
- Crystalline Will, Warp Unbound, vent-ready, hub-mode short-circuits — no change. They live upstream in `read_local_psyker_state` and short-circuit `should_block` for every input, including the new gate.
- Per-frame state cache — no change. `is_laspistol(weapon_name)` reads from the cached weapon name, no new extension reads added.
- HUD layout / scenegraph / scale — no change.

## Testing

Manual checks in Psykhanium (solo-server, peril mutations safe):

1. **Heavy laspistol** wielded by Psyker, peril raised to ≥ 99.8% via charged staff RMB or staff LMB cycling. Press V → no push fires, HUD warning is visible.
2. Same setup, peril at 90% → V fires the psyker push normally; HUD warning is off.
3. **Standard laspistol**: repeat checks 1 and 2.
4. **Non-laspistol non-force weapon** (e.g. chainsword): peril at 99.8%, V fires the normal chainsword special (verifies the latent-overreach fix didn't regress normal play). HUD warning is off (no peril-spending V).
5. **Force sword V** (existing gate): peril at 99.8%, V is blocked. HUD warning on. Below threshold, V fires normally.
6. **Vent-ready short-circuit**: Psyker with Scrier's Gaze equipped + off cooldown, heavy laspistol wielded, peril at 99.8%. V should fire (entire mod stands down per existing `disable_when_vent_ready` setting).
7. **`block_laspistol_push` off**: peril at 99.8% with laspistol → V fires normally (gate respects the toggle).

Mission verification: one Damnation run with heavy laspistol equipped — confirm no head-pops during normal play.

## Out of scope

- Source verification of *which* mechanism inside `action_psyker_push` adds peril (charge template, action handler, talent, buff). The user's empirical observation that the action pops the head is sufficient — the input-layer gate is mechanism-agnostic.
- Any change to the existing chainsword / autopistol / similar non-warp specials. None of them route to a peril-generating action branch (no `action_psyker_push` variant in their templates).
- Localization for non-English locales. The existing file is English-only; this design follows suit.
