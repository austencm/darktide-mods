local mod = get_mod("GhostRunner")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	-- Allow mod:hook to replace existing handlers in place on Ctrl+Shift+R hot
	-- reload. Without this, DMF warns and silently retains the original
	-- handler — making dev iteration on hooked code (recorder, replayer, etc.)
	-- require a full game restart per change.
	allow_rehooking = true,
	options = {
		widgets = {},
	},
}
