-- luacheck config for Darktide mods (DMF + Darktide engine globals).
-- Adapted from https://github.com/ronvoluted/darktide-mods/blob/main/.luacheckrc

max_line_length = 120

include_files = {
	"**/scripts/",
}

ignore = {
	"12.",      -- "Setting a read-only global variable / read-only field of a global variable"
	"542",      -- empty if branches (sometimes intentional)
	"21./.*_",  -- unused vars ending with _
	"211/dmf",  -- the unused `dmf` mod object
	"212/self", -- unused `self`
	"611",      -- "line contains only whitespace"
}

std = "+DT+DMF"

stds["DMF"] = {
	globals = {
		"new_mod", "get_mod", "DMFMod", "DMFModsKeyMap", "DMFOptionsView", "VT1",
	},
}

stds["DT"] = {
	read_globals = {
		string = { fields = { "split", "starts_with" } },
		table = { fields = {
			"merge", "table_to_array", "mirror_table", "tostring", "is_empty", "array_to_table", "reverse", "shuffle",
			"merge_recursive", "unpack_map", "remove_unordered_items", "append", "mirror_array_inplace", "size", "dump",
			"clear_array", "append_varargs", "find", "for_each", "crop", "mirror_array", "set", "create_copy", "clone",
			"contains", "add_meta_logging", "table_as_sorted_string_arrays", "clone_instance", "max", "clear",
			"find_by_key",
		} },
		math = { fields = {
			"ease_exp", "lerp", "polar_to_cartesian", "smoothstep", "easeCubic", "round", "point_is_inside_2d_triangle",
			"radians_to_degrees", "circular_to_square_coordinates", "uuid", "easeInCubic", "round_with_precision",
			"clamp", "get_uniformly_random_point_inside_sector", "angle_lerp", "ease_out_exp", "rand_normal",
			"bounce", "point_is_inside_2d_box", "catmullrom", "clamp_direction", "ease_in_exp", "random_seed",
			"sign", "degrees_to_radians", "sirp", "ease_pulse", "cartesian_to_polar", "ease_out_quad",
			"easeOutCubic", "radian_lerp", "auto_lerp", "rand_utf8_string", "point_is_inside_oobb",
		} },
		"Crashify", "Keyboard", "Mouse", "Application", "Color", "Quaternion", "Vector3", "Vector2",
		"RESOLUTION_LOOKUP", "Managers", "Unit", "ScriptUnit", "get_mod",
	},
}
