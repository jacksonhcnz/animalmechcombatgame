class_name Settings
extends RefCounted
## The player's options: display, controls, audio and gameplay comfort. Saved to user://settings.json
## and applied at start-up and whenever the Options screen applies them. Missing or invalid values
## fall back to the defaults, so an old or hand-edited file never breaks the game.

static var path: String = "user://settings.json"

const RESOLUTIONS: Array[String] = ["1152x648", "1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const FPS_LIMITS: Array[int] = [30, 60, 120, 144, 240, 0]
const HUD_SCALES: Array[int] = [75, 100, 125, 150]
const DISPLAY_MODES: Array[String] = ["windowed", "borderless", "fullscreen"]
const QUALITIES: Array[String] = ["low", "medium", "high"]
const SHAKE_LEVELS: Array[String] = ["off", "reduced", "full"]
const COLOR_MODES: Array[String] = ["off", "protanopia", "deuteranopia", "tritanopia"]
const SPRINT_MODES: Array[String] = ["hold", "toggle"]
const AUDIO_BUSES := {"master_volume": "Master", "music_volume": "Music", "effects_volume": "Effects", "voice_volume": "Voice"}

const DEFAULTS := {
	"display_mode": "windowed", "resolution": "1152x648", "quality": "high", "fps_limit": 144,
	"vsync": false, "motion_blur": false,
	"mouse_sens": 1.0, "invert_y": false, "bindings": {},
	"master_volume": 0.8, "music_volume": 0.4, "effects_volume": 0.9, "voice_volume": 0.75,
	"output_device": "Default", "mute_unfocused": true,
	"hud_scale": 100, "subtitles": true, "camera_shake": "reduced", "damage_numbers": true,
	"color_vision": "off", "sprint_mode": "hold",
}

static var values: Dictionary = {}
static var _focus_node: Node


static func get_value(key: String) -> Variant:
	_ensure()
	return values.get(key, DEFAULTS[key])


static func _ensure() -> void:
	if values.is_empty():
		reload()


## Reads the file again (or the defaults when there is none).
static func reload() -> void:
	values = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	for key in DEFAULTS:
		if not parsed.has(key):
			continue
		var wanted: Variant = parsed[key]
		var fallback: Variant = DEFAULTS[key]
		if typeof(wanted) == typeof(fallback) or (fallback is float and wanted is int) or (fallback is int and wanted is float):
			values[key] = int(wanted) if fallback is int else wanted
	values["bindings"] = _clean_bindings(values["bindings"])
	for key in ["display_mode", "quality", "camera_shake", "color_vision", "sprint_mode"]:
		var list: Array = {"display_mode": DISPLAY_MODES, "quality": QUALITIES, "camera_shake": SHAKE_LEVELS, "color_vision": COLOR_MODES, "sprint_mode": SPRINT_MODES}[key]
		if not list.has(values[key]):
			values[key] = DEFAULTS[key]
	if not RESOLUTIONS.has(values["resolution"]):
		values["resolution"] = DEFAULTS["resolution"]
	if not FPS_LIMITS.has(values["fps_limit"]):
		values["fps_limit"] = DEFAULTS["fps_limit"]
	if not HUD_SCALES.has(values["hud_scale"]):
		values["hud_scale"] = DEFAULTS["hud_scale"]
	values["mouse_sens"] = clampf(float(values["mouse_sens"]), 0.2, 3.0)
	for key in AUDIO_BUSES:
		values[key] = clampf(float(values[key]), 0.0, 1.0)


static func save() -> void:
	_ensure()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(values, "\t"))


## A copy of the current values to edit without changing anything yet.
static func snapshot() -> Dictionary:
	_ensure()
	return values.duplicate(true)


static func replace_all(new_values: Dictionary) -> void:
	values = new_values.duplicate(true)


static func mouse_sens() -> float:
	return float(get_value("mouse_sens"))


static func hud_scale() -> float:
	return float(int(get_value("hud_scale"))) / 100.0


# ---------------------------------------------------------------- key bindings

static func _clean_bindings(raw: Variant) -> Dictionary:
	var clean := {}
	if raw is Dictionary:
		for action in raw:
			var entry: Variant = raw[action]
			if entry is Dictionary and ["key", "mouse"].has(entry.get("kind", "")) and entry.has("code") and InputSetup.has_default(str(action)):
				clean[str(action)] = {"kind": str(entry["kind"]), "code": int(entry["code"])}
	return clean


static func binding_for(action: String, bindings: Dictionary) -> Dictionary:
	if bindings.has(action):
		return bindings[action]
	return InputSetup.default_binding(action)


static func binding_text(binding: Dictionary) -> String:
	if binding.is_empty():
		return "-"
	if binding["kind"] == "key":
		var event := InputEventKey.new()
		event.physical_keycode = binding["code"] as Key
		return event.as_text_physical_keycode().to_upper()
	match int(binding["code"]):
		MOUSE_BUTTON_LEFT:
			return "LMB"
		MOUSE_BUTTON_RIGHT:
			return "RMB"
		MOUSE_BUTTON_MIDDLE:
			return "MMB"
		MOUSE_BUTTON_WHEEL_UP:
			return "WHEEL UP"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "WHEEL DOWN"
	return "MOUSE %d" % int(binding["code"])


## The binding for a key or mouse press, or an empty dictionary for any other event.
static func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return {"kind": "key", "code": code}
	if event is InputEventMouseButton and event.pressed:
		return {"kind": "mouse", "code": int(event.button_index)}
	return {}


## Puts the saved key and mouse bindings into the input map (gamepad bindings are left alone).
static func apply_bindings(bindings: Dictionary = {}) -> void:
	_ensure()
	var source: Dictionary = bindings if not bindings.is_empty() else values["bindings"]
	for action in InputSetup.action_names():
		if not InputMap.has_action(action):
			continue
		var binding := binding_for(action, source)
		if binding.is_empty():
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				InputMap.action_erase_event(action, event)
		InputMap.action_add_event(action, InputSetup.event_for(binding))


# ----------------------------------------------------------------- applying

static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func apply_all() -> void:
	_ensure()
	apply_display()
	apply_quality()
	apply_audio()
	apply_bindings()


static func apply_display() -> void:
	if _headless():
		return
	var mode: String = get_value("display_mode")
	var size_parts := str(get_value("resolution")).split("x")
	var wanted := Vector2i(int(size_parts[0]), int(size_parts[1]))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == "borderless")
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var screen := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
			DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(wanted)
			var screen := DisplayServer.window_get_current_screen()
			var area := DisplayServer.screen_get_usable_rect(screen)
			DisplayServer.window_set_position(area.position + (area.size - wanted) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("fps_limit"))


static func apply_quality() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.root
	match str(get_value("quality")):
		"low":
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.scaling_3d_scale = 0.75
		"medium":
			root.msaa_3d = Viewport.MSAA_2X
			root.scaling_3d_scale = 1.0
		_:
			root.msaa_3d = Viewport.MSAA_4X
			root.scaling_3d_scale = 1.0


static func ensure_buses() -> void:
	for bus_name in ["Music", "Effects", "Voice"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


static func apply_audio() -> void:
	ensure_buses()
	for key in AUDIO_BUSES:
		var index := AudioServer.get_bus_index(AUDIO_BUSES[key])
		var level := float(get_value(key))
		AudioServer.set_bus_volume_db(index, linear_to_db(level) if level > 0.0 else -80.0)
		AudioServer.set_bus_mute(index, level <= 0.0)
	var device := str(get_value("output_device"))
	if AudioServer.get_output_device_list().has(device):
		AudioServer.output_device = device
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and (_focus_node == null or not is_instance_valid(_focus_node)):
		_focus_node = FocusMute.new()
		tree.root.add_child.call_deferred(_focus_node)


## Mutes the game while its window is in the background, if that option is on.
class FocusMute:
	extends Node

	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT and bool(Settings.get_value("mute_unfocused")):
			AudioServer.set_bus_mute(0, true)
		elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
			AudioServer.set_bus_mute(0, float(Settings.get_value("master_volume")) <= 0.0)
