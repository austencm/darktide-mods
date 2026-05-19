local mod = get_mod("GhostRunner")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	-- Allow mod:hook to replace existing handlers in place on Ctrl+Shift+R hot
	-- reload. Without this, DMF warns and silently retains the original
	-- handler -- making dev iteration on hooked code (recorder, replayer, etc.)
	-- require a full game restart per change.
	allow_rehooking = true,
	options = {
		widgets = {
			{
				setting_id = "header_recording",
				type = "group",
				sub_widgets = {
					{
						setting_id = "record_runs",
						type = "checkbox",
						default_value = true,
						title = "record_runs",
						tooltip = "record_runs_tooltip",
					},
					{
						setting_id = "record_online_missions",
						type = "checkbox",
						default_value = false,
						title = "record_online_missions",
						tooltip = "record_online_missions_tooltip",
					},
				},
			},
			{
				setting_id = "header_replay",
				type = "group",
				sub_widgets = {
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
					{
						setting_id = "show_ghost_trail",
						type = "checkbox",
						default_value = true,
						title = "show_ghost_trail",
						tooltip = "show_ghost_trail_tooltip",
					},
					{
						setting_id = "trail_duration",
						type = "numeric",
						default_value = 4.0,
						range = { 1.0, 10.0 },
						step = 0.5,
						decimals_number = 1,
						title = "trail_duration",
						tooltip = "trail_duration_tooltip",
					},
					{
						setting_id = "show_ghost_nameplate",
						type = "checkbox",
						default_value = true,
						title = "show_ghost_nameplate",
						tooltip = "show_ghost_nameplate_tooltip",
					},
				},
			},
			{
				setting_id = "header_files",
				type = "group",
				sub_widgets = {
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
		},
	},
}
