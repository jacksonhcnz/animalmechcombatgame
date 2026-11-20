extends SceneTree
## Settings: defaults, saving and loading, bindings, audio buses and the Options screen.
## Run with:  godot --headless --path . --script tests/settings_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("FAIL: settings test timed out")
		quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _run() -> void:
	Settings.path = "user://settings_test.json"
	if FileAccess.file_exists(Settings.path):
		DirAccess.remove_absolute(Settings.path)
	Settings.reload()
	_check(Settings.get_value("master_volume") == 0.8, "default master volume")
	_check(Settings.hud_scale() == 1.0, "default HUD scale is 100%")

	# The pilot name is kept between runs.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	LaunchConfig.player_name = "Ace"
	GameSettings.save_settings()
	LaunchConfig.player_name = "Pilot"
	GameSettings.load_settings()
	_check(LaunchConfig.player_name == "Ace", "pilot name survives a restart")
	LaunchConfig.player_name = "Pilot"
	LaunchConfig.name_from_args = true
	GameSettings.load_settings()
	_check(LaunchConfig.player_name == "Pilot", "a --name on the command line wins over the saved name")
	LaunchConfig.name_from_args = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))

	# Save, change, reload.
	Settings.values["mouse_sens"] = 2.0
	Settings.values["resolution"] = "1920x1080"
	Settings.values["bindings"] = {"jump": {"kind": "key", "code": KEY_J}}
	Settings.save()
	Settings.values["mouse_sens"] = 1.0
	Settings.reload()
	_check(Settings.get_value("mouse_sens") == 2.0, "mouse sensitivity survives a reload")
	_check(Settings.get_value("resolution") == "1920x1080", "resolution survives a reload")

	# Bad values are put right.
	var file := FileAccess.open(Settings.path, FileAccess.WRITE)
	file.store_string('{"resolution": "9x9", "mouse_sens": 99, "quality": "ultra", "master_volume": 5}')
	file.close()
	Settings.reload()
	_check(Settings.get_value("resolution") == "1920x1080", "unknown resolution falls back")
	_check(Settings.get_value("mouse_sens") == 3.0, "sensitivity is clamped")
	_check(Settings.get_value("quality") == "medium", "unknown quality falls back")
	_check(Settings.get_value("master_volume") == 1.0, "volume is clamped")

	# Key bindings reach the input map.
	InputSetup.ensure_actions()
	Settings.values["bindings"] = {"jump": {"kind": "key", "code": KEY_J}}
	Settings.apply_bindings()
	var jump_keys: Array = InputMap.action_get_events("jump").filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	_check(jump_keys.size() == 1 and jump_keys[0].physical_keycode == KEY_J, "jump is rebound to J")
	Settings.values["bindings"] = {}
	InputSetup.ensure_actions()
	Settings.apply_bindings({"jump": InputSetup.default_binding("jump")})
	_check(InputMap.action_get_events("jump").any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_SPACE), "jump goes back to Space")

	# Shadows follow the graphics quality, and the FPS counter is off by default.
	_check(Settings.get_value("show_fps") == false, "FPS counter off by default")
	var sun := DirectionalLight3D.new()
	Settings.values["quality"] = "low"
	Settings.apply_light(sun)
	_check(not sun.shadow_enabled, "Low turns shadows off")
	Settings.values["quality"] = "medium"
	Settings.apply_light(sun)
	_check(sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Medium uses two shadow cascades")
	Settings.values["quality"] = "high"
	Settings.apply_light(sun)
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "High uses four shadow cascades")
	sun.free()

	# Audio buses.
	Settings.values["music_volume"] = 0.5
	Settings.apply_audio()
	var music := AudioServer.get_bus_index("Music")
	_check(music != -1, "a Music bus exists")
	_check(absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.5)) < 0.01, "music volume reaches the bus")

	# The Options screen builds each tab, and Apply saves.
	Settings.reload()
	var menu: Node = load("res://scenes/options_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	for tab in ["Visuals", "Controls", "Audio", "Gameplay"]:
		menu._show_tab(tab)
		await process_frame
		_check(menu._left.get_child_count() > 0 and menu._right.get_child_count() > 0, "%s tab builds" % tab)
	menu._draft["invert_y"] = true
	menu._draft["sprint_mode"] = "toggle"
	menu._apply()
	_check(Settings.get_value("invert_y") == true and Settings.get_value("sprint_mode") == "toggle", "Apply keeps the changes")
	Settings.reload()
	_check(Settings.get_value("invert_y") == true, "Apply writes them to disk")
	menu._show_tab("Gameplay")
	menu._reset_tab()
	_check(menu._draft["sprint_mode"] == "hold", "Reset tab restores defaults")
	_check(menu._draft["invert_y"] == true, "Reset tab leaves other tabs alone")
	DirAccess.remove_absolute(Settings.path)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
