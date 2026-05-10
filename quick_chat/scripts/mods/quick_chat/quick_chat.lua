--[[
    title: quick_chat
    author: Zombine
    date: 08/06/2023
    version: 1.2.7
]]
local mod = get_mod("quick_chat")
local ChatManagerConstants = require("scripts/foundation/managers/chat/chat_manager_constants")
local UISettings = require("scripts/settings/ui/ui_settings")

mod:io_dofile("quick_chat/scripts/mods/quick_chat/quick_chat_debug")

mod._memory = mod:persistent_table("quick_chat")

for _, setting in ipairs(mod._messages) do
    local id = setting.id

    mod["trigger_" .. id] = function()
        local ui_manager = Managers.ui

        if not ui_manager:chat_using_input() and
           not ui_manager:view_active("dmf_options_view") and
           not ui_manager:view_active("options_view") then
            mod.send_preset_message(id, "hotkey")
        end
    end
end

mod._is_in_hub = function()
    local game_mode_manager = Managers.state.game_mode

    if not game_mode_manager then
        return false
    end

    return game_mode_manager:game_mode_name() == "hub"
end

mod._get_message_by_id = function(id)
    for _, setting in ipairs(mod._messages) do
        if setting.id == id then
            local message = ""

            if type(setting.message) == "table" then
                message = setting.message[math.random(#setting.message)]
            else
                message = setting.message
            end

            return message
        end
    end
end

-- ##################################################
-- Inline-token substitution
-- ##################################################
--
-- :name:       → glyph from mod._icons[name]
-- [color]…[/]  → {#color(R,G,B)}…<resume>
--
-- Closing tag's name is decorative — [/], [/red], [/anything] all close.
-- Unknown names and malformed tokens pass through as literal text.
--
-- Lua's %w is alphanumeric only and does NOT include underscore.
-- Identifier-like names (color/icon names with snake_case) need
-- [%w_]+ to match — kept generic so future palette additions with
-- underscores still resolve.

mod._substitute_icons = function(text)
    return (string.gsub(text, ":([%w_]+):", function(name)
        return mod._icons and mod._icons[name]
    end))
end

mod._substitute_colors = function(text, resume)
    return (string.gsub(text, "%[([%w_]+)%](.-)%[/[%w_]*%]", function(name, body)
        local rgba = mod._colors and mod._colors[name]
        if not rgba then
            return nil
        end
        return string.format("{#color(%d,%d,%d)}%s%s",
            rgba[2], rgba[3], rgba[4], body, resume or "{#reset()}")
    end))
end

mod._replace_place_holder = function(message, character_name, color)
    if not character_name then
        local player = Managers.player:local_player(1)
        character_name = player:name()
    end

    if color then
        character_name = string.format("{#color(%s,%s,%s)}%s{#reset()}", color[2], color[3], color[4], character_name)
    end

    if character_name then
        message = string.gsub(message, "%[name%]", character_name)
    end

    -- Inline tokens. Preset path has no outer color, so color closes with
    -- bare {#reset()}.
    message = mod._substitute_icons(message)
    message = mod._substitute_colors(message, "{#reset()}")

    return message
end

mod.send_preset_message = function(id, message_type, character_name, color)
    local cooldown = mod._cooldown[message_type]
    local t = Managers.time:time("main")
    local latest_t = mod._latest_t[message_type]
    local message = mod._get_message_by_id(id)
    local channel_handle = mod._memory.channel_handle
    local check_mode = mod:get("enable_check_mode")
    local enable_in_hub = mod:get("enable_in_hub")

    if not t or
       not message or
       #message == 0 or
       not check_mode and not channel_handle or
       not enable_in_hub and mod._is_in_hub() or
       cooldown and latest_t and t - latest_t < cooldown then
        return
    end

    if cooldown ~= 0 then
        mod._latest_t[message_type] = t
    end

    message = mod._replace_place_holder(message, character_name, color)

    if check_mode then
        mod:echo(message)
    else
        Managers.chat:send_channel_message(channel_handle, message)
    end
end

local get_channel_handle = function(self)
    mod._memory.channel_handle = self._selected_channel_handle
end

mod:hook_safe("ConstantElementChat", "_on_disconnect_from_channel", get_channel_handle)
mod:hook_safe("ConstantElementChat", "_next_connected_channel_handle", get_channel_handle)

-- Inject inline tokens (and optionally a default color) into messages the
-- user types into the in-game chat input. The chat element scrubs {#...}
-- tags off the input text before sending, so we can't inject markup
-- upstream. Instead we wrap Managers.chat.send_channel_message for the
-- duration of the input handler and substitute at the manager boundary —
-- this catches the typed-and-submitted path; preset hotkey messages and
-- other programmatic sends go through _replace_place_holder instead.
local function _wrap_typed_chat(func, self, ...)
    local default_color_tag = ""
    if mod._colors then
        local color_name = mod:get("default_chat_color")
        if color_name and color_name ~= "none" then
            local rgba = mod._colors[color_name]
            if rgba then
                default_color_tag = string.format("{#color(%d,%d,%d)}",
                    rgba[2], rgba[3], rgba[4])
            end
        end
    end

    local check_mode = mod:get("enable_check_mode")

    -- In Psykhanium / Meat Grinder (game_mode_name = training_grounds /
    -- shooting_range, host_singleplay) there's no Vivox session, so
    -- ConstantElementChat._handle_active_chat_input gates Enter on
    --   can_send_message = self._selected_channel_handle and #input_text > 0
    -- and dead-ends the keystroke before send_channel_message is reached.
    -- When check mode is on we don't actually need a real channel — inject a
    -- sentinel handle for the duration of the input handler so the engine
    -- attempts the send; our manager-level wrap intercepts with mod:echo.
    local restored_handle = false
    if check_mode and not self._selected_channel_handle then
        self._selected_channel_handle = "quick_chat_check_mode"
        restored_handle = true
    end

    local chat_mgr = Managers.chat
    local orig = chat_mgr.send_channel_message
    chat_mgr.send_channel_message = function(mgr, handle, text, ...)
        text = mod._substitute_icons(text)
        text = mod._substitute_colors(text,
            default_color_tag ~= "" and default_color_tag or "{#reset()}")
        if default_color_tag ~= "" then
            text = default_color_tag .. text .. "{#reset()}"
        end
        if check_mode then
            mod:echo(text)
            return
        end
        return orig(mgr, handle, text, ...)
    end
    local ok, err = pcall(func, self, ...)
    chat_mgr.send_channel_message = orig
    if restored_handle then
        self._selected_channel_handle = nil
    end
    if not ok then
        error(err)
    end
end

mod:hook("ConstantElementChat", "_handle_active_chat_input", _wrap_typed_chat)
mod:hook("ConstantElementChat", "_handle_console_input", _wrap_typed_chat)

-- ##################################################
-- Color cycle hotkey
-- ##################################################
--
-- Cycles default_chat_color through "none" + every key in mod._colors
-- (alphabetical). The preview line below reflects the new value next frame.

mod._color_cycle = nil

local function _build_color_cycle()
    local order = { "none" }
    if mod._colors then
        local names = {}
        for name, _ in pairs(mod._colors) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            order[#order + 1] = name
        end
    end
    return order
end

local function _cycle_color(direction)
    if not mod._color_cycle then
        mod._color_cycle = _build_color_cycle()
    end
    local cycle = mod._color_cycle
    local current = mod:get("default_chat_color") or "none"
    local idx = 1
    for i, name in ipairs(cycle) do
        if name == current then
            idx = i
            break
        end
    end
    -- ((idx - 1 + direction) mod N) + 1 wraps cleanly in both directions.
    local next_idx = ((idx - 1 + direction) % #cycle) + 1
    mod:set("default_chat_color", cycle[next_idx])
end

mod.trigger_cycle_chat_color = function() _cycle_color(1) end
mod.trigger_cycle_chat_color_backward = function() _cycle_color(-1) end

-- ##################################################
-- Live preview line above the chat input
-- ##################################################
--
-- Renders a small text row above the input field showing the fully
-- substituted version of what's currently typed (icons, colors, default
-- color wrap). Replaces a separate "current color" indicator. Style and
-- positioning live in HudElementChatPreview.lua; this file only computes
-- the preview text and pushes it via the registered HUD element.

local function _build_default_color_tag()
    local color_name = mod:get("default_chat_color")
    if not color_name or color_name == "none" or not mod._colors then
        return ""
    end
    local rgba = mod._colors[color_name]
    if not rgba then
        return ""
    end
    return string.format("{#color(%d,%d,%d)}", rgba[2], rgba[3], rgba[4])
end

local function _build_preview_text(raw_text)
    local default_color_tag = _build_default_color_tag()
    if not raw_text or #raw_text == 0 then
        if default_color_tag ~= "" then
            return default_color_tag .. "(preview){#reset()}"
        end
        return "(preview)"
    end
    local text = mod._substitute_icons(raw_text)
    text = mod._substitute_colors(text,
        default_color_tag ~= "" and default_color_tag or "{#reset()}")
    if default_color_tag ~= "" then
        text = default_color_tag .. text .. "{#reset()}"
    end
    return text
end

-- Preview line via a registered HUD element. Rendering goes through the
-- standard widget pipeline (HudElementBase + UIWidget.draw), which
-- handles begin_pass/end_pass and render_settings consistently. Earlier
-- attempts crashed because we listed "in_hub" in visibility_groups —
-- that's not a valid group; ui_hud.lua then errored every frame on the
-- failed lookup, flooding the Windows console buffer until the engine
-- watchdog fired. Valid groups (from hud_elements_player.lua):
--   "alive", "dead", "communication_wheel", "tactical_overlay",
--   "player_in_danger_zone".

-- Make the HUD-element registration idempotent across DMF reloads
-- (Ctrl+Shift+R). DMF's auto-cleanup only fires on UIHud:destroy, so on
-- a hot reload the previous injection is still in _player_hud._elements
-- and re-registering hits "element_already_exists" once per frame — which
-- floods the console and triggers the engine's 16s deadlock watchdog.
local dmf = get_mod("DMF")
if dmf and dmf.remove_injected_hud_elements then
    pcall(dmf.remove_injected_hud_elements, mod)
end

mod:register_hud_element({
    class_name = "HudElementChatPreview",
    filename = "quick_chat/scripts/mods/quick_chat/HudElementChatPreview",
    use_hud_scale = false,
    visibility_groups = { "alive", "dead" },
})

-- Capture the chat element ref on each per-frame _handle_input call,
-- not on init. The chat element is constructed during game boot before
-- this mod's hooks are registered, so an init hook would never fire.
-- _handle_input runs every frame from ConstantElementChat.update, so this
-- always captures the current ref. (DMF uses the same pattern in
-- logging.lua to grab _chat_element for mod:echo.)
mod._chat_element_ref = nil
mod:hook_safe("ConstantElementChat", "_handle_input", function(self)
    mod._chat_element_ref = self
end)

mod.update = function(dt)
    local chat_element = mod._chat_element_ref
    if not chat_element then return end

    local ui_manager = Managers.ui
    local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
    if not hud then return end
    local hud_element = hud:element("HudElementChatPreview")
    if not hud_element or not hud_element.set_active then return end

    local input_widget = chat_element._input_field_widget
    local is_writing = input_widget
        and input_widget.content
        and input_widget.content.is_writing
    if not is_writing then
        hud_element:set_active(false)
        return
    end

    local raw_text = input_widget.content.input_text
    if not raw_text or #raw_text == 0 then
        hud_element:set_active(false)
        return
    end

    hud_element:set_text(_build_preview_text(raw_text))
    hud_element:set_active(true)
end

-- ##################################################
-- Events
-- ##################################################

local send_message_on_event = function(setting_id, message_type, character_name, color)
    local message_id = mod:get(setting_id)

    if not message_id or message_id == "none" then
        return
    end

    mod.debug.echo_kv("message", message_id)
    mod.send_preset_message(message_id, message_type, character_name, color)
end

-- player join

mod:hook_safe("ConstantElementChat", "cb_chat_manager_participant_added", function(self, channel_handle, participant)
    local channel = Managers.chat:sessions()[channel_handle]

    if channel.tag ~= ChatManagerConstants.ChannelTag.HUB and not participant.is_text_muted_for_me then
        send_message_on_event("auto_player_joined", "join", participant.displayname)
    end

end)

mod:hook_safe("ConstantElementChat", "_on_connect_to_channel", function(self, channel_handle)
    get_channel_handle(self)

    local channel = Managers.chat:sessions()[channel_handle]

    if channel.tag == ChatManagerConstants.ChannelTag.MISSION then
        send_message_on_event("auto_late_joined", "join")
    end
end)

-- Intro, Outro

mod:hook_safe("CinematicSceneExtension", "setup_from_component", function(self)
    local name = self._cinematic_name

    if string.match(name, "[io][nu]tro_") then
        if mod._cutscene_loaded[name] then
            if name == "intro_abc" then
                send_message_on_event("auto_mission_started", "cinematic")
            elseif name == "outro_win" then
                send_message_on_event("auto_mission_completed", "cinematic")
            elseif name == "outro_fail" then
                send_message_on_event("auto_mission_failed", "cinematic")
            end
        else
            mod._cutscene_loaded[name] = true
        end
    end
end)

-- Tagged (self)

mod:hook_safe("HudElementSmartTagging", "_add_smart_tag_presentation", function(self, tag_instance)
    local target_unit = tag_instance:target_unit()
    local target_type = target_unit and Unit.get_data(target_unit, "smart_tag_target_type")

    mod.debug.echo_kv("target_type", target_type)

    local parent = self._parent
    local player = parent:player()
    local tagger_player = tag_instance:tagger_player()
    local is_my_tag = tagger_player and tagger_player:unique_id() == player:unique_id()

    if not is_my_tag then
        return
    end

    if target_type == "pickup" then
        local pickup_name = Unit.get_data(target_unit, "pickup_type")
        local event_id = "auto_tagged_" .. pickup_name
        local message_type = nil

        if pickup_name == "tome" or
           pickup_name == "grimoire" then
            message_type = "tag_book"
        elseif
           pickup_name == "medical_crate_pocketable" or
           pickup_name == "medical_crate_deployable" or
           pickup_name == "ammo_cache_pocketable" or
           pickup_name == "ammo_cache_deployable" then
            message_type = "tag_crate"
        end

        mod.debug.echo_kv("pickup_name", pickup_name)
        mod.debug.echo_kv("message_type", message_type)

        if message_type then
            send_message_on_event(event_id, message_type)
        end
    elseif target_type == "breed" then
        local unit_data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
        local breed = unit_data_ext and unit_data_ext:breed()
        local breed_name = breed and breed.name

        mod.debug.echo_kv("breed_name", breed_name)

        if breed_name == "chaos_daemonhost" then
            send_message_on_event("auto_tagged_daemonhost", "tag_daemonhost")
        end
    end
end)

-- Psyker Head Exploded

mod:hook_safe("ActionOverloadExplosion", "_explode", function(self, action_settings)
    mod:echo(action_settings.overload_type)
    
    -- Psyker peril vs. Ogryn overheat share this action class
    if action_settings.overload_type ~= "warp_charge" then
        return
    end

    local player = self._player
    local is_local = player == Managers.player:local_player(1)
    mod:echo(is_local)
    
    if is_local then
        -- Local player exploded
        send_message_on_event("auto_psyker_exploded_self", "psyker_explode")
    else
        -- Teammate exploded
        local slot_color = mod:get("enable_slot_color")
            and player:slot()
            and UISettings.player_slot_colors[player:slot()]
        send_message_on_event("auto_psyker_exploded_teammate", "psyker_explode", player:name(), slot_color)
    end
end)

-- Deployed Crates

local is_local_player = function(player)
    return player == Managers.player:local_player(1)
end

mod:hook_safe("Unit", "animation_event", function(unit, event)
    if event == "drop" then
        local player = Managers.player:player_by_unit(unit)

        if player and player:is_human_controlled() then
            mod._owner_session_id = player:session_id()
        end
    end
end)

mod:hook_safe("Unit", "flow_event", function(unit, event)
    if event == "lua_deploy" and mod._owner_session_id then
        local player = Managers.player:player_from_session_id(mod._owner_session_id)

        if not player then
            return
        end

        local player_slot = player.slot and player:slot()
        local player_name = player._profile and player:name()
        local slot_color = mod:get("enable_slot_color") and player_slot and UISettings.player_slot_colors[player_slot]
        local suffix = is_local_player(player) and "self" or "others"
        local event_id = "auto_deployed_:s:_" .. suffix
        local message_type = "deploy_"

        if Unit.has_data(unit, "pickup_type") then
            event_id = string.gsub(event_id, ":s:", Unit.get_data(unit, "pickup_type"))
            message_type = message_type .. "ammo"
        else
            event_id = string.gsub(event_id, ":s:", "medical_crate_deployable")
            message_type = message_type .. "med"
        end

        mod._owner_session_id = nil
        mod.debug.echo_kv("message_type", message_type)
        mod.debug.echo_kv("event_id", event_id)

        if player_name then
            send_message_on_event(event_id, message_type, player_name, slot_color)
        end
    end
end)

-- ##################################################
-- Utilities
-- ##################################################

local _init = function()
    mod._cutscene_loaded = {}
    mod._latest_t = {}
    mod._owner_session_id = nil
end

mod.on_all_mods_loaded = function()
    _init()
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == "StateLoading" and status == "enter" then
        _init()
    end
end