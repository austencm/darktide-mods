local mod = get_mod("KeepYourHead")

-- Single client-side input gate. The mod hooks ONLY InputService — every other
-- piece of state (peril, wielded weapon, equipped abilities) is read lazily
-- through extension components inside the input hook. This avoids the
-- `PlayerUnitWeaponExtension` / `PlayerUnitAbilityExtension` `fixed_update`
-- hooks that were causing engine-level access violations during boot.

-- Hot-path locals. The Fatshark Lua optimizing guide flags repeated global
-- lookups as worth caching when the call site fires hundreds of times per
-- frame, which is exactly what the input hook does.
local string_find = string.find
local math_min    = math.min
local type_of     = type

-- Debug logger: writes to both in-game chat and Darktide's console log so the
-- user can review without trying to copy text out of the in-game chat panel.
-- Darktide sandboxes `io.*` so file writes via io.open crash; `print` is the
-- standard sandbox-safe path. The output lands in
--   %USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\
-- in a per-session file named `console-<timestamp>-<guid>.log` — open the
-- newest file and search for "KeepYourHead". pcall guards in case `print` is
-- missing in some configurations.
local function debug_log(line)
	mod:echo(line)
	pcall(print, "[KeepYourHead] " .. line)
end

local PERIL_FREE_ABILITIES = {
	psyker_discharge_shout          = true, -- Venting Shriek
	psyker_discharge_shout_improved = true,
	psyker_overcharge_stance        = true, -- Scrier's Gaze
	psyker_force_field              = true, -- Telekine Shield
	psyker_force_field_improved     = true,
	psyker_force_field_dome         = true,
	-- NOTE: `psyker_throwing_knives` is the internal id for Assail (psychic
	-- daggers), not the Zealot's free-knives blitz. Despite the name, it does
	-- spend peril, so we keep it OUT of this list.
}

-- Subset of PERIL_FREE_ABILITIES that actively REDUCE peril (Telekine Shield
-- is defensive but doesn't vent, so it's intentionally excluded). When one
-- of these is equipped AND off cooldown, the player has an emergency-vent
-- option and the mod can stop running interference.
local VENT_ABILITIES = {
	psyker_discharge_shout          = true, -- Venting Shriek
	psyker_discharge_shout_improved = true,
	psyker_overcharge_stance        = true, -- Scrier's Gaze
}

-- Some abilities have a tighter explosion margin than the user's general
-- threshold can guard. Brain Rupture explodes the caster at >= 97% peril, so
-- we cap its effective threshold there regardless of the slider setting.
-- Note: Brain Rupture's internal id is `psyker_smite` — Darktide reuses the
-- Smite ability code for the blitz, despite the display name being different.
local ABILITY_THRESHOLD_OVERRIDES = {
	psyker_smite                = 0.97, -- Brain Rupture (when in blitz slot)
	psyker_brain_burst          = 0.97,
	psyker_brain_burst_improved = 0.97,
	psyker_brain_rupture        = 0.97,
}

local function ability_override_threshold(name)
	if not name or name == "" then return nil end
	local explicit = ABILITY_THRESHOLD_OVERRIDES[name]
	if explicit then return explicit end
	-- Fallback: catch renames Fatshark hasn't shipped yet.
	if string_find(name, "brain", 1, true) then return 0.97 end
	return nil
end

local BLOCKED_INPUTS_WEAPON_EXTRA = {
	weapon_extra_pressed = true,
	weapon_extra_hold    = true,
}

local BLOCKED_INPUTS_PRIMARY = {
	action_one_pressed = true,
	action_one_hold    = true,
}

local BLOCKED_INPUTS_COMBAT_ABILITY = {
	combat_ability_pressed = true,
	combat_ability_hold    = true,
}

local BLOCKED_INPUTS_GRENADE_ABILITY = {
	grenade_ability_pressed = true,
	grenade_ability_hold    = true,
}

-- Fast lookup: any input we might block. Lets us short-circuit before reading
-- player components for inputs we never care about (movement, dodge, jump,
-- etc.) — input_hook fires hundreds of times per frame.
local ANY_BLOCKED_INPUT = {}
for k in pairs(BLOCKED_INPUTS_WEAPON_EXTRA)     do ANY_BLOCKED_INPUT[k] = true end
for k in pairs(BLOCKED_INPUTS_PRIMARY)          do ANY_BLOCKED_INPUT[k] = true end
for k in pairs(BLOCKED_INPUTS_COMBAT_ABILITY)   do ANY_BLOCKED_INPUT[k] = true end
for k in pairs(BLOCKED_INPUTS_GRENADE_ABILITY)  do ANY_BLOCKED_INPUT[k] = true end

mod.settings = {
	peril_threshold               = (mod:get("peril_threshold") or 99.8) / 100,
	block_force_sword             = mod:get("block_force_sword"),
	block_force_staff_fire        = mod:get("block_force_staff_fire"),
	block_warp_ability            = mod:get("block_warp_ability"),
	disable_with_crystalline_will = mod:get("disable_with_crystalline_will"),
	disable_when_vent_ready       = mod:get("disable_when_vent_ready"),
	allow_inferno_fire_with_vent  = mod:get("allow_inferno_fire_with_vent"),
	inferno_fire_duration         = mod:get("inferno_fire_duration") or 4,
	show_warning_hud              = mod:get("show_warning_hud"),
	hud_offset_x                  = mod:get("hud_offset_x") or 0,
	hud_offset_y                  = mod:get("hud_offset_y") or 0,
	hud_scale                     = mod:get("hud_scale") or 100,
	debug_dump                    = mod:get("debug_dump"),
}
if mod.settings.block_force_sword             == nil then mod.settings.block_force_sword             = true  end
if mod.settings.block_force_staff_fire        == nil then mod.settings.block_force_staff_fire        = true  end
if mod.settings.block_warp_ability            == nil then mod.settings.block_warp_ability            = true  end
if mod.settings.disable_with_crystalline_will == nil then mod.settings.disable_with_crystalline_will = true  end
if mod.settings.disable_when_vent_ready       == nil then mod.settings.disable_when_vent_ready       = true  end
if mod.settings.allow_inferno_fire_with_vent  == nil then mod.settings.allow_inferno_fire_with_vent  = false end
if mod.settings.show_warning_hud              == nil then mod.settings.show_warning_hud              = true  end
if mod.settings.debug_dump                    == nil then mod.settings.debug_dump                    = false end

mod.on_setting_changed = function(setting_id)
	if setting_id == "peril_threshold" then
		mod.settings.peril_threshold = (mod:get("peril_threshold") or 99.8) / 100
	elseif setting_id == "hud_offset_x" or setting_id == "hud_offset_y" then
		mod.settings[setting_id] = mod:get(setting_id) or 0
	elseif setting_id == "hud_scale" then
		mod.settings.hud_scale = mod:get("hud_scale") or 100
	elseif setting_id == "inferno_fire_duration" then
		mod.settings.inferno_fire_duration = mod:get("inferno_fire_duration") or 4
	else
		mod.settings[setting_id] = mod:get(setting_id)
	end
end

local is_in_hub = false

-- Cached on lifecycle hooks (DMF fires both during cold start + on every state
-- transition). Default false: stay disengaged until the local player is
-- confirmed Psyker. Gates the input hook, mod.update, and the HUD element's
-- validation_function so non-Psyker characters pay effectively zero per-frame
-- cost — no extension walks, no HUD widget instantiation.
local is_local_player_psyker = false

local function check_is_in_hub()
	local game_mode_manager = Managers.state and Managers.state.game_mode
	local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
	return game_mode_name == "hub"
end

local function check_is_local_player_psyker()
	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1)
	local unit = player and player.player_unit
	if not unit or not Unit.alive(unit) then return false end
	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data then return false end
	return unit_data:read_component("warp_charge") ~= nil
end

local function unit_is_psyker(unit)
	if not unit or not Unit.alive(unit) then return false end
	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	return unit_data and unit_data:read_component("warp_charge") ~= nil
end

-- Engine `assign_player_unit_ownership` fires from `PlayerUnitSpawnManager`
-- AFTER `player.player_unit = unit` is set and all extensions are live, on
-- both server and client. This is the only signal that reliably catches
-- character swaps that bypass the hub (e.g. SoloPlay-style direct re-entry
-- into Psykhanium after picking a different class) — game_state_changed
-- alone fires before the new player_unit is in place. Counterpart
-- `player_unit_despawned` flips us back off so the cache doesn't lie about
-- a stale unit during the between-missions gap. The mod stays subscribed
-- for the whole game session; EventManager has no per-state teardown.
local event_subscriber = {}

event_subscriber.on_assign_player_unit_ownership = function(self, player, unit)
	local local_player = Managers.player and Managers.player:local_player(1)
	if player ~= local_player then return end
	is_local_player_psyker = unit_is_psyker(unit)
end

event_subscriber.on_player_unit_despawned = function(self, player)
	local local_player = Managers.player and Managers.player:local_player(1)
	if player ~= local_player then return end
	is_local_player_psyker = false
end

local function ensure_event_subscriptions()
	local event_manager = Managers.event
	if not event_manager then return end
	-- Unregister-then-register is idempotent on EventManager (unregister no-ops
	-- if not present), so we can call this freely on lifecycle hooks without
	-- ending up with duplicate callbacks.
	event_manager:unregister(event_subscriber, "assign_player_unit_ownership")
	event_manager:register(event_subscriber, "assign_player_unit_ownership", "on_assign_player_unit_ownership")
	event_manager:unregister(event_subscriber, "player_unit_despawned")
	event_manager:register(event_subscriber, "player_unit_despawned", "on_player_unit_despawned")
end

mod.on_game_state_changed = function(status, state_name)
	is_in_hub = check_is_in_hub()
	ensure_event_subscriptions()
	is_local_player_psyker = check_is_local_player_psyker()
end

mod.on_all_mods_loaded = function()
	is_in_hub = check_is_in_hub()
	ensure_event_subscriptions()
	is_local_player_psyker = check_is_local_player_psyker()
end

-- Warp Unbound (talent that powers up Scrier's Gaze) grants the buff
-- `psyker_overcharge_stance_infinite_casting` for ~10–11 seconds. While this
-- buff is active, the player can cast freely without peril exploding them, so
-- we should disable all blocking. The duration isn't hardcoded — we just check
-- whether the buff template is present in the buff extension.
local WARP_UNBOUND_BUFF = "psyker_overcharge_stance_infinite_casting"

-- Crystalline Will (passive talent) replaces the lethal head-pop with a
-- survivable explosion that costs a corruption health segment. With this
-- talent selected the player can't actually die from peril overload, so the
-- mod's blocking is unnecessary. Talent id from talent_settings_psyker.lua.
local CRYSTALLINE_WILL_TALENT = "psyker_alternative_peril_explosion"

local function has_crystalline_will(player)
	if not player then return false end
	local profile = player.profile and player:profile()
	if not profile or not profile.talents then return false end
	return profile.talents[CRYSTALLINE_WILL_TALENT] ~= nil
end

local function has_warp_unbound_grace(unit)
	local buff_ext = unit and ScriptUnit.has_extension(unit, "buff_system")
	local buffs_by_index = buff_ext and buff_ext._buffs_by_index
	if not buffs_by_index then return false end
	for _, buff in pairs(buffs_by_index) do
		local template = buff and buff.template and buff:template()
		if template and template.name == WARP_UNBOUND_BUFF then
			return true
		end
	end
	return false
end

local function read_local_psyker_state()
	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1)
	local unit = player and player.player_unit
	if not unit or not Unit.alive(unit) then return nil end

	local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
	if not unit_data then return nil end

	local warp_charge = unit_data:read_component("warp_charge")
	if not warp_charge then return nil end -- not a Psyker

	if mod.settings.disable_with_crystalline_will and has_crystalline_will(player) then
		return nil -- talent makes peril overload survivable; nothing to block
	end

	if has_warp_unbound_grace(unit) then
		return nil -- Warp Unbound active: skip all blocking until the buff expires
	end

	-- Read abilities once: used for both the vent-ready short-circuit and
	-- the return value consumed by should_block.
	local combat_ability_name = ""
	local grenade_ability_name = ""
	local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
	if ability_ext and ability_ext._equipped_abilities then
		local equipped = ability_ext._equipped_abilities
		if equipped.combat_ability and equipped.combat_ability.name then
			combat_ability_name = equipped.combat_ability.name
		end
		if equipped.grenade_ability and equipped.grenade_ability.name then
			grenade_ability_name = equipped.grenade_ability.name
		end
	end

	-- Vent-ready short-circuit: if the player has Venting Shriek or
	-- Scrier's Gaze equipped AND off cooldown, they have an emergency
	-- bail-out and don't need the mod's interference.
	if mod.settings.disable_when_vent_ready
		and ability_ext
		and ability_ext.remaining_ability_charges
		and VENT_ABILITIES[combat_ability_name]
	then
		local charges = ability_ext:remaining_ability_charges("combat_ability") or 0
		if charges > 0 then
			return nil
		end
	end

	local peril = warp_charge.current_percentage or 0

	local weapon_template_name = ""
	local weapon_ext = ScriptUnit.has_extension(unit, "weapon_system")
	if weapon_ext and weapon_ext._weapons then
		local inventory = unit_data:read_component("inventory")
		local wielded_slot = inventory and inventory.wielded_slot
		local slot_weapon = wielded_slot and weapon_ext._weapons[wielded_slot]
		local weapon_template = slot_weapon and slot_weapon.weapon_template
		if weapon_template and weapon_template.name then
			weapon_template_name = weapon_template.name
		end
	end

	return peril, weapon_template_name, combat_ability_name, grenade_ability_name
end

local function is_force_staff(weapon_name)
	return weapon_name ~= "" and string_find(weapon_name, "forcestaff", 1, true) ~= nil
end

-- The Inferno / Purgatus Force Staff (the flame-stream one) is the only staff
-- with a sustained fire — head-pop is suppressed for the fire duration, so
-- a player whose vent ability comes off cooldown during that window can fire
-- safely. In current Darktide its template name is `forcestaff_p2*` (the
-- p1/p2/p3/p4 numbering does NOT correspond to the order one might guess
-- from the in-game patterns).
local function is_inferno_staff(weapon_name)
	return weapon_name ~= "" and string_find(weapon_name, "forcestaff_p2", 1, true) ~= nil
end

local function get_local_player_unit()
	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1)
	return player and player.player_unit
end

local function get_vent_cooldown_remaining()
	local unit = get_local_player_unit()
	if not unit then return nil end
	local ability_ext = ScriptUnit.has_extension(unit, "ability_system")
	if not ability_ext or not ability_ext.remaining_ability_cooldown then return nil end
	return ability_ext:remaining_ability_cooldown("combat_ability")
end

-- Force swords (one- and two-handed) all have "forcesword" in their template
-- name. Push attacks on these weapons generate peril, unlike push attacks on
-- non-warp melee weapons which are free.
local function is_force_sword(weapon_name)
	return weapon_name ~= "" and string_find(weapon_name, "forcesword", 1, true) ~= nil
end

-- Tracks whether the player is currently holding RMB (block stance). The
-- basic push (RMB + LMB) is free. The push *attack* is the follow-up swing
-- — `action_one_pressed` again while RMB is still held, within the combat
-- chain window after the basic push. That follow-up is what generates peril
-- on a force sword. We mirror block state from the input hook and timestamp
-- the last allowed push so should_block can tell "first press this stance"
-- (basic push, free) from "second press inside the chain window" (push
-- attack, blocked).
local is_blocking_with_rmb = false
local last_push_t = -1
local PUSH_ATTACK_WINDOW = 0.8 -- seconds; combat chain window after a push

local function is_peril_spending_ability(name)
	if not name or name == "" then return false end
	return not PERIL_FREE_ABILITIES[name]
end

-- Per-frame cache for the player state read. Within a single frame the input
-- hook + the warning-HUD probe call should_block ~12 times; without caching
-- each one re-walks ScriptUnit extensions and components. We use the main
-- timer as cache token since it's stable per frame.
local _state_t = -1
local _peril, _weapon_name, _combat_ability, _grenade_ability

local function read_local_psyker_state_cached()
	local time_manager = Managers.time
	if not time_manager then
		return read_local_psyker_state()
	end
	local now = time_manager:time("main")
	if _state_t == now then
		return _peril, _weapon_name, _combat_ability, _grenade_ability
	end
	_state_t = now
	_peril, _weapon_name, _combat_ability, _grenade_ability = read_local_psyker_state()
	return _peril, _weapon_name, _combat_ability, _grenade_ability
end

local function should_block(action_name)
	if is_in_hub then return false end
	if not ANY_BLOCKED_INPUT[action_name] then return false end

	local peril, weapon_name, combat_ability, grenade_ability = read_local_psyker_state_cached()
	if not peril then return false end -- not a Psyker

	local settings = mod.settings
	local base = settings.peril_threshold

	if settings.block_force_sword and BLOCKED_INPUTS_WEAPON_EXTRA[action_name] then
		return peril >= base
	end

	-- LMB cases: force-staff fire OR an ability-as-weapon being cast (Brain
	-- Rupture, Smite-as-blitz, etc. — Darktide swaps the wielded "weapon"
	-- template name to the ability id for the duration of the cast).
	if BLOCKED_INPUTS_PRIMARY[action_name] then
		if settings.block_force_staff_fire and is_force_staff(weapon_name) then
			-- Diagnostic: log all the inputs to the override decision once
			-- per press. Lets us pinpoint whether allow_setting is off,
			-- inferno detection failed, vent isn't equipped, or the
			-- cooldown API returned nil.
			if settings.debug_dump and action_name == "action_one_pressed" then
				local remaining = get_vent_cooldown_remaining()
				debug_log(string.format(
					"[KeepYourHead] force-staff-fire weapon=%s allow=%s inferno=%s vent_match=%s combat=%s cooldown=%s duration=%s peril=%.3f",
					weapon_name,
					tostring(settings.allow_inferno_fire_with_vent == true),
					tostring(is_inferno_staff(weapon_name) == true),
					tostring(VENT_ABILITIES[combat_ability] == true),
					combat_ability ~= "" and combat_ability or "<none>",
					tostring(remaining),
					tostring(settings.inferno_fire_duration or 4),
					peril
				))
			end
			-- Inferno-staff override: head-pop is suppressed during its
			-- sustained fire. If the equipped vent ability (Venting Shriek
			-- or Scrier's Gaze) will come off cooldown within the fire
			-- duration, allow firing — the player can vent before lockout.
			if settings.allow_inferno_fire_with_vent and is_inferno_staff(weapon_name) then
				local remaining = get_vent_cooldown_remaining()
				if VENT_ABILITIES[combat_ability]
					and remaining
					and remaining < (settings.inferno_fire_duration or 4)
				then
					return false
				end
			end
			return peril >= base
		end
		-- Push attack on force swords: a second `action_one_pressed` while RMB
		-- is held (within the combat chain window after a basic push) routes
		-- through to the push attack, which costs peril. We allow the first
		-- press (basic push, free) and only block if the player has already
		-- pushed recently in this stance.
		if settings.block_force_sword
			and action_name == "action_one_pressed"
			and is_blocking_with_rmb
			and is_force_sword(weapon_name)
			and last_push_t >= 0
		then
			local time_manager = Managers.time
			local now = time_manager and time_manager:time("main") or 0
			if (now - last_push_t) < PUSH_ATTACK_WINDOW then
				return peril >= base
			end
		end
		if settings.block_warp_ability and weapon_name ~= "" then
			if weapon_name == grenade_ability and is_peril_spending_ability(grenade_ability) then
				local override = ability_override_threshold(grenade_ability)
				local effective = override and math_min(base, override) or base
				return peril >= effective
			end
			if weapon_name == combat_ability and is_peril_spending_ability(combat_ability) then
				local override = ability_override_threshold(combat_ability)
				local effective = override and math_min(base, override) or base
				return peril >= effective
			end
		end
	end

	if settings.block_warp_ability
		and BLOCKED_INPUTS_COMBAT_ABILITY[action_name]
		and is_peril_spending_ability(combat_ability)
	then
		local override = ability_override_threshold(combat_ability)
		local effective = override and math_min(base, override) or base
		return peril >= effective
	end

	if settings.block_warp_ability
		and BLOCKED_INPUTS_GRENADE_ABILITY[action_name]
		and is_peril_spending_ability(grenade_ability)
	then
		local override = ability_override_threshold(grenade_ability)
		local effective = override and math_min(base, override) or base
		return peril >= effective
	end

	return false
end

-- Cheap rate limit so the debug dump doesn't spam every frame a hold input
-- returns true. We only want one echo per discrete press.
local last_dump_action = nil
local last_dump_t = 0

local function maybe_dump_debug(action_name, pressed)
	if not mod.settings.debug_dump then return end
	if not pressed then return end
	-- Only dump for ability-flavored actions; ignore movement/dodge/etc.
	if not (action_name == "combat_ability_pressed"
		or action_name == "combat_ability_hold"
		or action_name == "grenade_ability_pressed"
		or action_name == "grenade_ability_hold"
		or action_name == "weapon_extra_pressed"
		or action_name == "action_one_pressed"
		or action_name == "action_two_pressed") then
		return
	end
	-- Coalesce: skip duplicates of the same action within ~0.25s.
	local now = (Managers.time and Managers.time:time("main")) or 0
	if action_name == last_dump_action and (now - last_dump_t) < 0.25 then return end
	last_dump_action = action_name
	last_dump_t = now

	local peril, weapon_name, combat_ability, grenade_ability = read_local_psyker_state()
	if not peril then return end
	debug_log(string.format(
		"[KeepYourHead] action=%s peril=%.3f weapon=%s combat=%s grenade=%s",
		action_name,
		peril,
		weapon_name ~= "" and weapon_name or "<none>",
		combat_ability ~= "" and combat_ability or "<none>",
		grenade_ability ~= "" and grenade_ability or "<none>"
	))
end

local function input_hook(func, self, action_name)
	local out = func(self, action_name)
	-- Track block stance for push-attack detection. action_two_hold returns
	-- truthy every frame the block input is held; we mirror that into a flag
	-- read by should_block when evaluating action_one_pressed. On stance
	-- release we forget any previous push so the next stance starts fresh.
	if action_name == "action_two_hold" then
		local now_blocking = (out == true) or (type_of(out) == "number" and out > 0)
		if is_blocking_with_rmb and not now_blocking then
			last_push_t = -1
		end
		is_blocking_with_rmb = now_blocking
	end
	-- Non-Psyker short-circuit: bail before any extension reads or should_block
	-- work. Stance tracking above stays current so a mid-session swap into a
	-- Psyker character has correct push-attack chain state on the next input.
	if not is_local_player_psyker then return out end
	-- Skip the pressed-derivation entirely when debug dump is off (the hot
	-- path for normal play). When on, derive once and reuse out_type for the
	-- return-value coercion so we don't call type(out) twice.
	if mod.settings.debug_dump then
		maybe_dump_debug(action_name, (out == true) or (type_of(out) == "number" and out > 0))
	end
	if should_block(action_name) then
		return type_of(out) == "number" and 0 or false
	end
	-- Input passed through. If it was a basic push (LMB pressed while RMB
	-- held, NOT blocked above), timestamp it so the next press inside the
	-- chain window is recognized as a push attack.
	if action_name == "action_one_pressed"
		and is_blocking_with_rmb
		and ((out == true) or (type_of(out) == "number" and out > 0))
	then
		local time_manager = Managers.time
		if time_manager then
			last_push_t = time_manager:time("main")
		end
	end
	return out
end

-- Predictive HUD: returns true when peril is at or above the lowest threshold
-- that any currently-gated input would be blocked at. Reuses should_block so
-- the warning state matches actual blocking exactly — no drift.
local WARNING_PROBE_INPUTS = {
	"weapon_extra_pressed",
	"action_one_pressed",
	"combat_ability_pressed",
	"grenade_ability_pressed",
}
local NUM_WARNING_PROBES = #WARNING_PROBE_INPUTS

mod.is_warning_active = function()
	if not mod.settings.show_warning_hud then return false end
	for i = 1, NUM_WARNING_PROBES do
		if should_block(WARNING_PROBE_INPUTS[i]) then return true end
	end
	return false
end

mod:hook("InputService", "_get", input_hook)
mod:hook("InputService", "_get_simulate", input_hook)

mod:register_hud_element({
	class_name = "HudElementKeepYourHeadWarning",
	filename = "KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning",
	use_hud_scale = true,
	visibility_groups = {
		"alive",
	},
	validation_function = function(params)
		local game_mode_manager = Managers.state and Managers.state.game_mode
		local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
		if game_mode_name == "hub" then return false end
		return check_is_local_player_psyker()
	end,
})

-- Per-frame poller: pushes is_warning_active() into the HUD element's setter.
-- DMF calls mod.update(dt) every frame; we look up the element through the UI
-- manager's HUD and toggle its widget visibility. No-ops if the HUD or element
-- isn't up yet (e.g. during the initial mission load).
mod.update = function(dt)
	if not is_local_player_psyker then return end
	local ui_manager = Managers.ui
	local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
	if not hud then return end
	local element = hud:element("HudElementKeepYourHeadWarning")
	if not element or not element.set_active then return end
	element:set_active(mod.is_warning_active())
	if element.set_offset then
		element:set_offset(mod.settings.hud_offset_x or 0, mod.settings.hud_offset_y or 0)
	end
	if element.set_scale then
		element:set_scale((mod.settings.hud_scale or 100) / 100)
	end
end
