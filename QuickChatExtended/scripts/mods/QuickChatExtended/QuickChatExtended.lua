local mod = get_mod("QuickChatExtended")

local UISettings = require("scripts/settings/ui/ui_settings")

-- ##################################################
-- Constants
-- ##################################################

-- Seconds a player must remain in a disabled state before the auto-event
-- fires. Gives teammates a chance to rescue silently.
local DISABLED_FIRE_DELAY = 3

-- Catapulted "spectacular flight" thresholds. Fires if EITHER bound is hit.
local CATAPULT_MIN_AIRTIME  = 1.5
local CATAPULT_MIN_DISTANCE = 12

-- Catapults arriving from a grab/disable state are enemy-throws (mutant
-- slam, daemonhost release, etc.), not explosions. Skip those.
local GRAB_PREVIOUS_STATES = {
    mutant_charged = true,
    vortex_grabbed = true,
    warp_grabbed   = true,
    grabbed        = true,
    hogtied        = true,
}

-- State class name -> our event setting id.
local DISABLED_STATES = {
    PlayerCharacterStateKnockedDown   = "auto_player_knocked_down",
    PlayerCharacterStateLedgeHanging  = "auto_player_ledge_hanging",
    PlayerCharacterStateNetted        = "auto_player_netted",
    PlayerCharacterStatePounced       = "auto_player_pounced",
    PlayerCharacterStateConsumed      = "auto_player_consumed",
    PlayerCharacterStateWarpGrabbed   = "auto_player_warp_grabbed",
    PlayerCharacterStateVortexGrabbed = "auto_player_vortex_grabbed",
}

-- ##################################################
-- Debug
-- ##################################################

-- Echo a single line to local chat when "enable_debug_mode" is on. Used
-- throughout to trace scheduling, cancellations, and dispatch decisions.
local function _debug(msg)
    if mod:get("enable_debug_mode") then
        mod:echo("[QCE] " .. tostring(msg))
    end
end

-- ##################################################
-- Cross-mod integration
-- ##################################################

-- Push cooldown buckets into quick_chat's mod-owned state and wrap
-- _replace_place_holder so we can substitute [airtime] / [distance] in
-- the catapult preset message via a transient send context.
mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc then return end

    if qc._cooldown then
        qc._cooldown.tag_daemonhost  = qc._cooldown.tag_daemonhost  or 30
        qc._cooldown.psyker_explode  = qc._cooldown.psyker_explode  or 5
        qc._cooldown.player_disabled = qc._cooldown.player_disabled or 30
        qc._cooldown.catapulted      = qc._cooldown.catapulted      or 30
    end

    if qc._replace_place_holder and not qc._quick_chat_extended_patched then
        local original = qc._replace_place_holder
        qc._replace_place_holder = function(message, character_name, color)
            message = original(message, character_name, color)
            local ctx = mod._send_context
            if ctx then
                if ctx.airtime then
                    message = string.gsub(message, "%[airtime%]", ctx.airtime)
                end
                if ctx.distance then
                    message = string.gsub(message, "%[distance%]", ctx.distance)
                end
            end
            return message
        end
        qc._quick_chat_extended_patched = true
    end
end

-- ##################################################
-- Helpers
-- ##################################################

local function _is_local_player(unit)
    local player_mgr = Managers.player
    if not player_mgr then return false end
    local player = player_mgr:player_by_unit(unit)
    return player and player == player_mgr:local_player_safe(1)
end

local function _send(setting_id, message_type, character_name, color)
    local qc = get_mod("quick_chat")
    if not qc or not qc.send_preset_message then return end
    local preset_id = mod:get(setting_id)
    if not preset_id or preset_id == "none" then return end
    qc.send_preset_message(preset_id, message_type, character_name, color)
end

-- For disabled events: try the specific preset first, fall back to the
-- generic "auto_player_disabled" if the specific one is unset.
local function _dispatch_disabled(event_id)
    local preset_id = mod:get(event_id)
    if not preset_id or preset_id == "none" then
        preset_id = mod:get("auto_player_disabled")
    end
    if not preset_id or preset_id == "none" then return end
    local qc = get_mod("quick_chat")
    if not qc or not qc.send_preset_message then return end
    qc.send_preset_message(preset_id, "player_disabled")
end

-- Pending-fire tracking for the rescue-grace window. Cleared if the
-- player exits the disabled state before the delay elapses.
mod._pending_disabled = {}

local function _schedule_disabled(state_key, event_id)
    local t = Managers.time and Managers.time:time("main")
    if not t then return end
    mod._pending_disabled[state_key] = {
        event_id  = event_id,
        fire_time = t + DISABLED_FIRE_DELAY,
    }
    _debug("scheduled " .. event_id .. " in " .. DISABLED_FIRE_DELAY .. "s")
end

local function _cancel_disabled(state_key)
    if mod._pending_disabled[state_key] then
        _debug("cancelled " .. mod._pending_disabled[state_key].event_id .. " (rescued)")
        mod._pending_disabled[state_key] = nil
    end
end

mod.update = function(dt)
    local t = Managers.time and Managers.time:time("main")
    if not t then return end
    for state_key, pending in pairs(mod._pending_disabled) do
        if t >= pending.fire_time then
            _debug("firing " .. pending.event_id)
            _dispatch_disabled(pending.event_id)
            mod._pending_disabled[state_key] = nil
        end
    end
end

-- ##################################################
-- Daemonhost auto-tag
-- ##################################################

mod:hook_safe("HudElementSmartTagging", "_add_smart_tag_presentation", function(self, tag_instance)
    local target_unit = tag_instance:target_unit()
    if not target_unit then return end

    local target_type = Unit.get_data(target_unit, "smart_tag_target_type")
    if target_type ~= "breed" then return end

    local parent = self._parent
    local player = parent:player()
    local tagger_player = tag_instance:tagger_player()
    local is_my_tag = tagger_player and tagger_player:unique_id() == player:unique_id()
    if not is_my_tag then return end

    local unit_data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
    local breed = unit_data_ext and unit_data_ext:breed()
    local breed_name = breed and breed.name
    if breed_name ~= "chaos_daemonhost" then return end

    _debug("daemonhost tagged")
    _send("auto_tagged_daemonhost", "tag_daemonhost")
end)

-- ##################################################
-- Psyker head-exploded
-- ##################################################

mod:hook_safe("ActionOverloadExplosion", "_explode", function(self, action_settings)
    -- Psyker peril vs Ogryn overheat share this action class.
    if action_settings.overload_type ~= "warp_charge" then return end

    local player = self._player
    if not player then return end

    if player == Managers.player:local_player(1) then
        _debug("psyker exploded: self")
        _send("auto_psyker_exploded_self", "psyker_explode")
    else
        -- Read enable_slot_color from quick_chat directly — it's a global
        -- "color teammate names" preference users set in one place rather
        -- than per-mod.
        local qc = get_mod("quick_chat")
        local slot_color = qc and qc:get("enable_slot_color")
            and player:slot()
            and UISettings.player_slot_colors[player:slot()]
        _debug("psyker exploded: teammate=" .. tostring(player:name()))
        _send("auto_psyker_exploded_teammate", "psyker_explode", player:name(), slot_color)
    end
end)

-- ##################################################
-- Player disabled (one hook pair per disabled state)
-- ##################################################

for class_name, event_id in pairs(DISABLED_STATES) do
    mod:hook_safe(class_name, "on_enter", function(self, unit, dt, t, previous_state, params)
        if not _is_local_player(unit) then return end
        _schedule_disabled(class_name, event_id)
    end)
    mod:hook_safe(class_name, "on_exit", function(self, unit, t, next_state)
        if not _is_local_player(unit) then return end
        _cancel_disabled(class_name)
    end)
end

-- ##################################################
-- Catapulted by explosion (heuristic: previous state is not a grab)
-- ##################################################

mod._catapult_start = nil
mod._send_context = nil

mod:hook_safe("PlayerCharacterStateCatapulted", "on_enter",
    function(self, unit, dt, t, previous_state, params)
        if not _is_local_player(unit) then return end
        if GRAB_PREVIOUS_STATES[previous_state] then
            _debug("catapult skipped: previous=" .. tostring(previous_state))
            mod._catapult_start = nil
            return
        end
        _debug("catapult start (previous=" .. tostring(previous_state) .. ")")
        mod._catapult_start = {
            time = t,
            pos  = Vector3Box(Unit.local_position(unit, 1)),
        }
    end)

mod:hook_safe("PlayerCharacterStateCatapulted", "on_exit",
    function(self, unit, t, next_state)
        if not _is_local_player(unit) then return end
        local start = mod._catapult_start
        if not start then return end
        mod._catapult_start = nil

        local airtime  = t - start.time
        local end_pos  = Unit.local_position(unit, 1)
        local distance = Vector3.distance(start.pos:unbox(), end_pos)

        if airtime < CATAPULT_MIN_AIRTIME and distance < CATAPULT_MIN_DISTANCE then
            _debug(string.format("catapult below threshold: airtime=%.1f distance=%.0f",
                airtime, distance))
            return
        end

        _debug(string.format("catapult firing: airtime=%.1f distance=%.0f",
            airtime, distance))
        mod._send_context = {
            airtime  = string.format("%.1f", airtime),
            distance = string.format("%.0f", distance),
        }
        _send("auto_player_catapulted", "catapulted")
        mod._send_context = nil
    end)
