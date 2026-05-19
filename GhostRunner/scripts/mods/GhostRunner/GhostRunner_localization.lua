return {
	mod_name = {
		en = "Ghost Runner",
	},
	mod_description = {
		en = "Record solo runs and replay them as a ghost.",
	},

	header_recording = {
		en = "Recording",
	},
	header_recording_description = {
		en = "How and when GhostRunner records your runs.",
	},
	header_replay = {
		en = "Replay",
	},
	header_replay_description = {
		en = "How a loaded ghost is shown in your live run.",
	},
	header_files = {
		en = "Files",
	},
	header_files_description = {
		en = "Where GhostRunner stores recordings.",
	},

	record_runs = {
		en = "Record runs automatically",
	},
	record_runs_tooltip = {
		en = "When ON, every solo mission is recorded to a .run file in your AppData folder.",
	},

	record_online_missions = {
		en = "Record online missions",
	},
	record_online_missions_tooltip = {
		en = "When ON, runs in regular online (Fatshark-server) missions are recorded too. " ..
			"Default OFF: only SoloPlay solo missions record. " ..
			"Online recordings can be loaded as ghosts in solo replay later. " ..
			"This is recording only -- replay still requires solo.",
	},

	replay_mode = {
		en = "Replay mode",
	},
	replay_mode_tooltip = {
		en = "Off: no ghost. Race: play normally with a ghost overlay. " ..
			"Spectator: stand still and watch the ghost. (Race and Spectator " ..
			"are functionally identical in v0 -- choose by intent.)",
	},
	replay_mode_off = {
		en = "Off",
	},
	replay_mode_race = {
		en = "Race",
	},
	replay_mode_spectator = {
		en = "Spectator",
	},

	show_race_timer = {
		en = "Show race timer HUD",
	},
	show_race_timer_tooltip = {
		en = "Display a small widget showing ghost time and your delta.",
	},

	show_ghost_trail = {
		en = "Show ghost trail",
	},
	show_ghost_trail_tooltip = {
		en = "Draw a 3D trail and vertical pole at the ghost's recorded position.",
	},

	trail_duration = {
		en = "Trail duration (seconds)",
	},
	trail_duration_tooltip = {
		en = "How many seconds of recent history are shown as the ghost's trail. Shorter = more like a comet tail; longer = more like a route map.",
	},

	show_ghost_nameplate = {
		en = "Show ghost nameplate",
	},
	show_ghost_nameplate_tooltip = {
		en = "Show the floating panel with the ghost's name, status, and bars.",
	},

	open_runs_folder = {
		en = "Open runs folder",
	},
	open_runs_folder_tooltip = {
		en = "Press to open the .run files folder in Explorer.",
	},
}
