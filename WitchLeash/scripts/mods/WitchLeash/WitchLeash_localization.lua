return {
	mod_name = {
		en = "Witch Leash",
	},
	mod_description = {
		en = "Blocks inputs that would increase peril when peril is ≥ a threshold (default 99.8). Includes blitzes, staffs, and force sword ignite and push-attack.",
	},

	group_blocking = {
		en = "Input Blocking",
	},
	group_blocking_description = {
		en = "Which peril-generating inputs to gate.",
	},
	group_smart_disable = {
		en = "Smart Disable",
	},
	group_smart_disable_description = {
		en = "Conditions under which the mod stops blocking entirely (talents or ability state that make peril overload survivable/recoverable).",
	},
	group_inferno = {
		en = "Inferno Staff",
	},
	group_inferno_description = {
		en = "Inferno Staff suppresses overload for the duration of its charged attack. If your vent ability comes off cooldown within this window, the cast is safe.",
	},
	group_hud = {
		en = "HUD Warning",
	},
	group_hud_description = {
		en = "The on-screen 'DANGER' indicator and its position/size.",
	},
	group_debug = {
		en = "Debug",
	},
	group_debug_description = {
		en = "Diagnostic output for troubleshooting. Leave off during normal play.",
	},
	peril_threshold = {
		en = "Peril Threshold (%%)",
	},
	peril_threshold_description = {
		en = "Block peril-generating inputs at or above this percentage. **Recommended: 99.8.** Your head explodes only when you generate peril while *already* at 100%. 99.8% catches that with a 0.2% buffer for float precision and one-frame race conditions. Lower the slider only if you want a paranoid buffer -- it'll just block actions earlier than necessary. Brain Rupture is the exception: it causes overload at peril ≥ 97%, gated automatically regardless of this setting.",
	},
	block_force_sword = {
		en = "Block Force Sword",
	},
	block_force_sword_description = {
		en = "Block peril-generating inputs on force swords at or above the threshold. Covers ignite/charge and push attacks. Basic pushes, light melee, and heavy melee always work.",
	},
	block_force_staff_fire = {
		en = "Block Staff",
	},
	block_force_staff_fire_description = {
		en = "Block primary attack at or above the threshold when a force staff is wielded. Stops both instant LMB attacks and the LMB-fire of a held RMB charge.",
	},
	block_warp_ability = {
		en = "Block Blitz",
	},
	block_warp_ability_description = {
		en = "Block Smite, Brain Rupture, Assail usage at or above the threshold. Brain Rupture always triggers overload at ≥ 97% peril.",
	},
	disable_with_crystalline_will = {
		en = "Disable With Crystalline Will",
	},
	disable_with_crystalline_will_description = {
		en = "When enabled, the mod won't do anything while Crystalline Will is active.",
	},
	disable_when_vent_ready = {
		en = "Disable When Vent Ability Is Ready",
	},
	disable_when_vent_ready_description = {
		en = "When the equipped combat ability is Shriek or Scrier's Gaze AND it's off cooldown, allow intentional overloads. Don't listen to the voices, sibling.",
	},
	allow_inferno_fire_with_vent = {
		en = "Aggressive Inferno Mode",
	},
	allow_inferno_fire_with_vent_description = {
		en = "If your equipped vent ability (Shriek / Scrier's Gaze) will come off cooldown within charged attack duration estimate, allow firing -- you can vent before overload.",
	},
	inferno_fire_duration = {
		en = "Inferno Fire Duration Estimate (seconds)",
	},
	inferno_fire_duration_description = {
		en = "Aggressive inferno check compares your vent ability's remaining cooldown against this value. Default 4.0.",
	},
	show_warning_hud = {
		en = "Overload HUD Warning",
	},
	show_warning_hud_description = {
		en = "Show a red 'DANGER' indicator below the crosshair when peril is at or above the configured threshold.",
	},
	hud_offset_x = {
		en = "HUD Warning Offset X",
	},
	hud_offset_x_description = {
		en = "Horizontal offset (pixels) for the warning text from its default position below the crosshair. Negative = left, positive = right.",
	},
	hud_offset_y = {
		en = "HUD Warning Offset Y",
	},
	hud_offset_y_description = {
		en = "Vertical offset (pixels) for the warning text from its default position below the crosshair. Negative = up, positive = down.",
	},
	hud_scale = {
		en = "HUD Warning Size (%%)",
	},
	hud_scale_description = {
		en = "Scale the warning text. 100 = default size (font 32), 200 = double size, 50 = half size. Range 50-300.",
	},
	debug_dump = {
		en = "Debug Mode",
	},
	debug_dump_description = {
		en = "When enabled, prints peril / weapon name / equipped ability names to in-game chat AND to Darktide's log each time a relevant input is pressed. Logs live at %USER%\\AppData\\Roaming\\Fatshark\\Darktide\\console_logs\\.",
	},
}
