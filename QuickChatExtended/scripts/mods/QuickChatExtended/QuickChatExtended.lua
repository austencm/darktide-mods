local mod = get_mod("QuickChatExtended")

-- Push cooldown buckets into quick_chat's mod-owned state. Safe because
-- _cooldown is a regular field on the mod instance (not DMF mod_data).
mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc or not qc._cooldown then
        return
    end
    qc._cooldown.tag_daemonhost = qc._cooldown.tag_daemonhost or 30
    qc._cooldown.psyker_explode = qc._cooldown.psyker_explode or 5
end

-- ##################################################
-- Helpers
-- ##################################################

local function _send(setting_id, message_type, character_name, color)
    local qc = get_mod("quick_chat")
    if not qc or not qc.send_preset_message then
        return
    end
    local preset_id = mod:get(setting_id)
    if not preset_id or preset_id == "none" then
        return
    end
    qc.send_preset_message(preset_id, message_type, character_name, color)
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

    _send("auto_tagged_daemonhost", "tag_daemonhost")
end)

-- ##################################################
-- Psyker head-exploded
-- ##################################################

local UISettings = require("scripts/settings/ui/ui_settings")

mod:hook_safe("ActionOverloadExplosion", "_explode", function(self, action_settings)
    -- Psyker peril vs Ogryn overheat share this action class.
    if action_settings.overload_type ~= "warp_charge" then return end

    local player = self._player
    if not player then return end

    if player == Managers.player:local_player(1) then
        _send("auto_psyker_exploded_self", "psyker_explode")
    else
        -- Read enable_slot_color from quick_chat directly — it's a global
        -- "color teammate names" preference users set in one place rather
        -- than per-mod.
        local qc = get_mod("quick_chat")
        local slot_color = qc and qc:get("enable_slot_color")
            and player:slot()
            and UISettings.player_slot_colors[player:slot()]
        _send("auto_psyker_exploded_teammate", "psyker_explode", player:name(), slot_color)
    end
end)
