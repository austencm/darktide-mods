local mod = get_mod("KeepYourHead")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			-- Top-level: the one knob that affects every gate.
			{
				setting_id      = "peril_threshold",
				type            = "numeric",
				default_value   = 99.8,
				range           = { 50, 100 },
				decimals_number = 1,
			},

			-- What inputs to gate.
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

			-- When to step out of the way entirely.
			{
				setting_id  = "group_smart_disable",
				type        = "group",
				sub_widgets = {
					{
						setting_id    = "disable_with_crystalline_will",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "disable_when_vent_ready",
						type          = "checkbox",
						default_value = true,
					},
				},
			},

			-- Inferno (Purgatus) Force Staff special case: allow firing if vent
			-- recovers within the staff's flame-stream duration.
			{
				setting_id  = "group_inferno",
				type        = "group",
				sub_widgets = {
					{
						setting_id    = "allow_inferno_fire_with_vent",
						type          = "checkbox",
						default_value = false,
					},
					{
						setting_id      = "inferno_fire_duration",
						type            = "numeric",
						default_value   = 4,
						range           = { 1, 10 },
						decimals_number = 1,
					},
				},
			},

			-- Predictive HUD warning + its position/size.
			{
				setting_id  = "group_hud",
				type        = "group",
				sub_widgets = {
					{
						setting_id    = "show_warning_hud",
						type          = "checkbox",
						default_value = true,
					},
					{
						setting_id    = "hud_offset_x",
						type          = "numeric",
						default_value = 0,
						range         = { -500, 500 },
					},
					{
						setting_id    = "hud_offset_y",
						type          = "numeric",
						default_value = 0,
						range         = { -500, 500 },
					},
					{
						setting_id    = "hud_scale",
						type          = "numeric",
						default_value = 100,
						range         = { 50, 300 },
					},
				},
			},

			-- Diagnostics.
			{
				setting_id  = "group_debug",
				type        = "group",
				sub_widgets = {
					{
						setting_id    = "debug_dump",
						type          = "checkbox",
						default_value = false,
					},
				},
			},
		},
	},
}
