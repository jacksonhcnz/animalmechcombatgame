class_name OptionsMenu
extends Control
## The Options screen: Visuals, Controls, Audio and Gameplay tabs. Changes are held in a draft until
## "Apply settings" saves and applies them; Cancel throws the draft away. Display changes ask for
## confirmation and go back on their own if nobody confirms in time.

const TABS: Array[String] = ["Visuals", "Controls", "Audio", "Gameplay"]
const TAB_KEYS := {
	"Visuals": ["display_mode", "resolution", "quality", "fps_limit", "vsync", "motion_blur", "show_fps", "show_minimap"],
	"Controls": ["mouse_sens", "invert_y", "bindings"],
	"Audio": ["master_volume", "music_volume", "effects_volume", "voice_volume", "output_device", "mute_unfocused"],
	"Gameplay": ["hud_scale", "subtitles", "camera_shake", "damage_numbers", "color_vision", "sprint_mode"],
}
const DISPLAY_KEYS: Array[String] = ["display_mode", "resolution", "vsync", "fps_limit", "quality"]
const CONFIRM_SECONDS := 10

## The remappable actions: title, description and the input actions one key cap sets.
const BINDING_ROWS := [
	{"title": "Movement", "desc": "Forward, left, backward, right.", "caps": [["move_forward"], ["turn_left"], ["move_back"], ["turn_right"]]},
	{"title": "Strafe", "desc": "Sidestep left and right.", "caps": [["strafe_left"], ["strafe_right"]]},
	{"title": "Jump / climb", "desc": "Jump, climb and boost.", "caps": [["jump", "ascend"]]},
	{"title": "Sprint", "desc": "Run faster, or throttle up when flying.", "caps": [["sprint"]]},
	{"title": "Crouch / descend", "desc": "Descend, or slow down when flying.", "caps": [["descend"]]},
	{"title": "Primary weapon", "desc": "Fire your primary weapon.", "caps": [["fire_primary"]]},
	{"title": "Secondary weapon", "desc": "Fire your secondary weapon.", "caps": [["fire_secondary"]]},
	{"title": "Melee", "desc": "Bite, claw or strike.", "caps": [["fire_melee"]]},
	{"title": "Air bomb", "desc": "Drop the Hawk's bomb.", "caps": [["fire_bomb"]]},
	{"title": "Use equipment", "desc": "Switch the sniper scope on and off.", "caps": [["use_equipment"]]},
	{"title": "Toggle view", "desc": "Cockpit or third person.", "caps": [["toggle_view"]]},
	{"title": "Centre aim", "desc": "Point the weapons straight ahead.", "caps": [["center_aim"]]},
]

var _draft: Dictionary = {}
var _tab: String = "Visuals"
var _tab_buttons: Dictionary = {}
var _left: PanelContainer
var _right: PanelContainer
var _status: Label
var _apply_button: Button
var _overlay: Control
var _listening: Array = []
var _listening_button: Button
var _binding_note: String = ""
var _confirm_left: int = 0
var _confirm_timer: Timer
var _before_apply: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	InputSetup.ensure_actions()
	_draft = Settings.snapshot()
	var column := UiKit.page(self)
	UiKit.header(column)
	column.add_child(UiKit.link_button("←   Main menu", UiKit.DIM, _cancel, true))
	column.add_child(UiKit.mono("System / Preferences"))
	var title_row := UiKit.hbox(column, 0)
	var title := UiKit.heading("Options", 56)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var hint := UiKit.label("Make the battlefield feel like home.", 15, UiKit.DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	title_row.add_child(hint)

	var tabs := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 0)
	column.add_child(tabs)
	var tab_row := UiKit.hbox(tabs, 0)
	for name in TABS:
		var b := Button.new()
		b.text = name.to_upper()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_override("font", UiKit.mono_font())
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: _show_tab(name))
		tab_row.add_child(b)
		_tab_buttons[name] = b

	var body := UiKit.hbox(column, 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left = UiKit.panel(UiKit.PANEL, UiKit.BORDER, 22)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 2.2
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_left)
	_right = UiKit.panel(UiKit.PANEL, UiKit.BORDER, 22)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.size_flags_stretch_ratio = 1.0
	body.add_child(_right)

	var footer := UiKit.hbox(column, 16)
	var reset := UiKit.outline_button("", _reset_tab)
	reset.text = "Reset tab to defaults"
	for child in reset.get_children():
		child.queue_free()
	reset.custom_minimum_size = Vector2(210, 44)
	footer.add_child(reset)
	_status = UiKit.mono("", UiKit.DIM, 10)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_status)
	var cancel := UiKit.outline_button("", _cancel)
	cancel.text = "Cancel"
	for child in cancel.get_children():
		child.queue_free()
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.custom_minimum_size = Vector2(150, 44)
	footer.add_child(cancel)
	_apply_button = UiKit.primary_button("Apply settings", _apply)
	_apply_button.custom_minimum_size = Vector2(230, 44)
	footer.add_child(_apply_button)

	_confirm_timer = Timer.new()
	_confirm_timer.wait_time = 1.0
	_confirm_timer.timeout.connect(_confirm_tick)
	add_child(_confirm_timer)
	_show_tab("Visuals")


func _unhandled_key_input(event: InputEvent) -> void:
	_listen(event)


func _input(event: InputEvent) -> void:
	if not _listening.is_empty() and event is InputEventMouseButton:
		_listen(event)


## While a key cap is waiting, the next key or mouse button becomes its binding (Esc cancels).
func _listen(event: InputEvent) -> void:
	if _listening.is_empty():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_stop_listening()
		get_viewport().set_input_as_handled()
		return
	var binding := Settings.binding_from_event(event)
	if binding.is_empty():
		return
	get_viewport().set_input_as_handled()
	var actions := _listening.duplicate()
	var clash := _clash(actions, binding)
	var bindings: Dictionary = _draft["bindings"]
	for action in actions:
		bindings[action] = binding
	_binding_note = "" if clash == "" else "Warning: %s is already used for %s." % [Settings.binding_text(binding), clash]
	_stop_listening()
	_changed()
	_show_tab("Controls")


func _stop_listening() -> void:
	_listening = []
	_listening_button = null


## The title of another row that already uses this binding, or "".
func _clash(actions: Array, binding: Dictionary) -> String:
	for row in BINDING_ROWS:
		for cap in row["caps"]:
			if cap == actions or cap.has(actions[0]):
				continue
			if Settings.binding_for(cap[0], _draft["bindings"]) == binding:
				return str(row["title"])
	return ""


func _dirty() -> bool:
	return _draft != Settings.snapshot()


func _changed() -> void:
	var dirty := _dirty()
	_status.text = "Changes not yet applied" if dirty else "All changes applied"
	_status.add_theme_color_override("font_color", UiKit.LIME if dirty else UiKit.DIM)
	_status.text = _status.text.to_upper()


func _cancel() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _reset_tab() -> void:
	for key in TAB_KEYS[_tab]:
		_draft[key] = Settings.DEFAULTS[key].duplicate(true) if Settings.DEFAULTS[key] is Dictionary else Settings.DEFAULTS[key]
	_binding_note = ""
	_changed()
	_show_tab(_tab)


func _apply() -> void:
	if not _dirty():
		return
	_before_apply = Settings.snapshot()
	var display_changed := false
	for key in DISPLAY_KEYS:
		if _draft[key] != _before_apply[key]:
			display_changed = true
	Settings.replace_all(_draft)
	Settings.save()
	Settings.apply_all()
	_changed()
	if display_changed and DisplayServer.get_name() != "headless":
		_ask_keep()


## "Keep these display settings?" with a countdown; doing nothing puts the old settings back.
func _ask_keep() -> void:
	_confirm_left = CONFIRM_SECONDS
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(centre)
	var panel := UiKit.panel(UiKit.PANEL, UiKit.LIME, 24)
	centre.add_child(panel)
	var box := UiKit.vbox(panel, 12)
	box.add_child(UiKit.mono("Display changed"))
	box.add_child(UiKit.heading("Keep these settings?", 30))
	var countdown := UiKit.label("", 14, UiKit.DIM)
	countdown.name = "Countdown"
	box.add_child(countdown)
	var row := UiKit.hbox(box, 12)
	var keep := UiKit.primary_button("Keep", _keep_display)
	keep.custom_minimum_size = Vector2(160, 44)
	row.add_child(keep)
	var revert := UiKit.outline_button("Revert", _revert_display)
	revert.custom_minimum_size = Vector2(160, 44)
	row.add_child(revert)
	add_child(_overlay)
	_update_countdown()
	_confirm_timer.start()


func _update_countdown() -> void:
	var label := _overlay.find_child("Countdown", true, false) as Label
	if label != null:
		label.text = "Going back to the old display settings in %d seconds." % _confirm_left


func _confirm_tick() -> void:
	_confirm_left -= 1
	if _confirm_left <= 0:
		_revert_display()
	elif _overlay != null:
		_update_countdown()


func _close_overlay() -> void:
	_confirm_timer.stop()
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _keep_display() -> void:
	_close_overlay()


func _revert_display() -> void:
	_close_overlay()
	for key in DISPLAY_KEYS:
		Settings.values[key] = _before_apply[key]
		_draft[key] = _before_apply[key]
	Settings.save()
	Settings.apply_all()
	_changed()
	_show_tab(_tab)


# ------------------------------------------------------------------ tab pages

func _show_tab(tab: String) -> void:
	_tab = tab
	_stop_listening()
	for name in _tab_buttons:
		var b: Button = _tab_buttons[name]
		var on: bool = name == tab
		var fill := UiKit.LIME_SOFT if on else UiKit.PANEL
		for key in ["normal", "hover", "pressed", "focus"]:
			var style := UiKit.box(fill, fill, 0, 0, 0)
			style.border_width_bottom = 2 if on else 0
			style.border_color = UiKit.LIME
			b.add_theme_stylebox_override(key, style)
		b.add_theme_color_override("font_color", UiKit.LIME if on else UiKit.TEXT)
		b.add_theme_color_override("font_hover_color", UiKit.LIME if on else UiKit.TEXT)
		b.add_theme_color_override("font_pressed_color", UiKit.LIME)
		b.add_theme_color_override("font_focus_color", UiKit.LIME if on else UiKit.TEXT)
	for child in _left.get_children():
		child.queue_free()
	for child in _right.get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left.add_child(scroll)
	var box := UiKit.vbox(scroll, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox(box, 0)
	var captions := {"Visuals": ["Display & performance", "Current value"], "Controls": ["Keyboard & mouse", "Binding / value"], "Audio": ["Volume & output", "Level / value"], "Gameplay": ["HUD & play preferences", "Current value"]}
	var caption := UiKit.mono(captions[tab][0])
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caption)
	head.add_child(UiKit.mono(captions[tab][1], UiKit.DIM, 10))
	UiKit.spacer(box, 8)
	match tab:
		"Visuals":
			_build_visuals(box)
		"Controls":
			_build_controls(box)
		"Audio":
			_build_audio(box)
		_:
			_build_gameplay(box)
	_build_side()
	_changed()


## One setting: a title and a line of help on the left, its control on the right, a rule beneath.
func _row(parent: Control, title: String, desc: String, control: Control) -> void:
	UiKit.rule(parent)
	var row := UiKit.hbox(parent, 12)
	row.custom_minimum_size = Vector2(0, 52)
	var text := UiKit.vbox(row, 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_child(UiKit.label(title, 15))
	text.add_child(UiKit.label(desc, 12, UiKit.DIM))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)


func _dropdown(key: String, labels: Array, values: Array) -> OptionButton:
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(210, 40)
	UiKit.style_input(pick)
	pick.custom_minimum_size = Vector2(210, 40)
	for i in labels.size():
		pick.add_item(str(labels[i]))
		pick.set_item_metadata(i, values[i])
	pick.select(maxi(0, values.find(_draft[key])))
	pick.item_selected.connect(func(i: int) -> void:
		_draft[key] = pick.get_item_metadata(i)
		_changed()
		if _tab == "Visuals":
			_build_side_only())
	return pick


func _switch(key: String) -> UiKit.Toggle:
	var t := UiKit.Toggle.new(bool(_draft[key]))
	t.toggled.connect(func(on: bool) -> void:
		_draft[key] = on
		_changed())
	return t


func _slider_row(key: String, low: float, high: float, step: float, as_percent: bool) -> Control:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 14)
	var s := UiKit.slider(float(_draft[key]) * (100.0 if as_percent else 1.0), low, high, step)
	holder.add_child(s)
	var value := UiKit.mono("", UiKit.TEXT, 12)
	value.custom_minimum_size = Vector2(52, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(value)
	var show := func(v: float) -> void:
		value.text = ("%d%%" % roundi(v)) if as_percent else ("%.2f" % v)
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		_draft[key] = v / 100.0 if as_percent else v
		show.call(v)
		_changed())
	return holder


func _build_visuals(box: Control) -> void:
	_row(box, "Display mode", "Choose how the game fills your screen.", _dropdown("display_mode", ["Windowed", "Borderless", "Full screen"], Settings.DISPLAY_MODES))
	var res_labels := []
	for r in Settings.RESOLUTIONS:
		res_labels.append(r.replace("x", " × "))
	_row(box, "Resolution", "Window size when playing windowed.", _dropdown("resolution", res_labels, Settings.RESOLUTIONS))
	_row(box, "Graphics quality", "Low: no shadows. Medium: lighter shadows. High: full.", _dropdown("quality", ["Low", "Medium", "High"], Settings.QUALITIES))
	var fps_labels := []
	for f in Settings.FPS_LIMITS:
		fps_labels.append("Unlimited" if f == 0 else "%d FPS" % f)
	_row(box, "Frame rate limit", "Set the maximum number of frames per second.", _dropdown("fps_limit", fps_labels, Settings.FPS_LIMITS))
	_row(box, "V-sync", "Reduce screen tearing.", _switch("vsync"))
	_row(box, "Motion blur", "Blur the view during movement.", _switch("motion_blur"))
	_row(box, "FPS counter", "Show frames per second in the corner.", _switch("show_fps"))
	_row(box, "Sound minimap", "Show a radar of the sounds around you in the top-right corner.", _switch("show_minimap"))


func _build_controls(box: Control) -> void:
	for row in BINDING_ROWS:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 8)
		for cap in row["caps"]:
			caps.add_child(_key_cap(cap))
		_row(box, row["title"], row["desc"], caps)
	_row(box, "Mouse sensitivity", "Adjust aiming speed.", _slider_row("mouse_sens", 0.2, 3.0, 0.05, false))
	_row(box, "Invert mouse Y-axis", "Reverse vertical aiming direction.", _switch("invert_y"))


func _key_cap(actions: Array) -> Button:
	var b := Button.new()
	var binding := Settings.binding_for(actions[0], _draft["bindings"])
	var waiting := _listening == actions
	b.text = "..." if waiting else Settings.binding_text(binding)
	b.custom_minimum_size = Vector2(52, 38)
	b.add_theme_font_override("font", UiKit.mono_font())
	b.add_theme_font_size_override("font_size", 11)
	for key in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(key, UiKit.box(UiKit.INNER, UiKit.LIME if waiting else UiKit.BORDER.lightened(0.2), 8))
	b.add_theme_color_override("font_color", UiKit.LIME if waiting else UiKit.TEXT)
	b.add_theme_color_override("font_hover_color", UiKit.LIME)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void:
		_listening = actions.duplicate()
		_binding_note = "Press a key or mouse button for this action. Esc cancels."
		_show_tab("Controls"))
	return b


func _build_audio(box: Control) -> void:
	_row(box, "Master volume", "Overall volume for all game audio.", _slider_row("master_volume", 0.0, 100.0, 1.0, true))
	_row(box, "Music volume", "Menu and in-match music.", _slider_row("music_volume", 0.0, 100.0, 1.0, true))
	_row(box, "Effects volume", "Weapons, impacts and environmental sounds.", _slider_row("effects_volume", 0.0, 100.0, 1.0, true))
	_row(box, "Voice volume", "Pilot callouts and voice lines.", _slider_row("voice_volume", 0.0, 100.0, 1.0, true))
	var devices: Array = Array(AudioServer.get_output_device_list())
	if not devices.has("Default"):
		devices.push_front("Default")
	var labels: Array = devices.map(func(d: String) -> String: return "System default" if d == "Default" else d)
	if not devices.has(_draft["output_device"]):
		_draft["output_device"] = "Default"
	_row(box, "Output device", "Choose where game audio is played.", _dropdown("output_device", labels, devices))
	_row(box, "Mute when unfocused", "Silence audio while the game is in the background.", _switch("mute_unfocused"))


func _build_gameplay(box: Control) -> void:
	_row(box, "HUD scale", "Adjust the size of in-game information.", _dropdown("hud_scale", ["75%", "100%", "125%", "150%"], Settings.HUD_SCALES))
	_row(box, "Subtitles", "Display captions for spoken dialogue.", _switch("subtitles"))
	_row(box, "Camera shake", "Control camera movement from impacts.", _dropdown("camera_shake", ["Off", "Reduced", "Full"], Settings.SHAKE_LEVELS))
	_row(box, "Damage numbers", "Show damage dealt to enemy mechs.", _switch("damage_numbers"))
	_row(box, "Color vision mode", "Adjust gameplay indicators for visibility.", _dropdown("color_vision", ["Off", "Protanopia", "Deuteranopia", "Tritanopia"], Settings.COLOR_MODES))
	_row(box, "Sprint behavior", "Hold or toggle the sprint input.", _dropdown("sprint_mode", ["Hold", "Toggle"], Settings.SPRINT_MODES))


# ------------------------------------------------------------ side panel

func _build_side_only() -> void:
	for child in _right.get_children():
		child.queue_free()
	_build_side()


func _build_side() -> void:
	var box := UiKit.vbox(_right, 10)
	match _tab:
		"Visuals":
			var parts := str(_draft["resolution"]).split("x")
			var w := int(parts[0])
			var h := int(parts[1])
			var mode_names := {"windowed": "Windowed", "borderless": "Borderless", "fullscreen": "Full screen"}
			box.add_child(UiKit.mono("Display profile"))
			box.add_child(UiKit.heading("%d × %d" % [w, h], 44))
			box.add_child(UiKit.label("%s  /  %s" % [mode_names[_draft["display_mode"]], _aspect(w, h)], 13, UiKit.DIM))
			_side_tip(box, "Clarity first", "Keep your target in focus.", "Turn off motion blur for a cleaner view during fast turns and close-range combat.", "Display changes require confirmation before they are kept.")
		"Controls":
			box.add_child(UiKit.mono("Input profile"))
			box.add_child(UiKit.heading("Keyboard + mouse", 38))
			box.add_child(UiKit.label("Precision starts with a familiar setup.", 13, UiKit.DIM))
			_side_tip(box, "Make it yours", "Every action within reach.", "Select a binding to assign another key or mouse button. A warning appears if that input is already in use.", _binding_note if _binding_note != "" else "LMB: left mouse button\nRMB: right mouse button")
		"Audio":
			box.add_child(UiKit.mono("Output profile"))
			var device := str(_draft["output_device"])
			box.add_child(UiKit.heading("System default" if device == "Default" else device, 38))
			box.add_child(UiKit.label("Use the audio device selected by your system.", 13, UiKit.DIM))
			_side_tip(box, "Hear the battlefield", "Let the important sounds through.", "Keep effects above music to make incoming fire and nearby combat easier to hear.", "Master volume affects every audio channel.")
		_:
			box.add_child(UiKit.mono("Pilot preferences"))
			box.add_child(UiKit.heading("Your comfort. Your call.", 38))
			box.add_child(UiKit.label("Tune how information looks and feels.", 13, UiKit.DIM))
			_side_tip(box, "Built around you", "Stay focused on the fight.", "Use a comfortable HUD size and reduce camera shake to keep combat information easy to follow.", "Match rules are set separately by the host.")


func _side_tip(box: VBoxContainer, caption: String, headline: String, text: String, note: String) -> void:
	UiKit.rule(box)
	box.add_child(UiKit.mono(caption))
	box.add_child(UiKit.label(headline, 18))
	var body := UiKit.label(text, 13, UiKit.DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	UiKit.spacer(box)
	var holder := UiKit.panel(UiKit.INNER, UiKit.BORDER, 12)
	box.add_child(holder)
	var n := UiKit.label(note, 12, UiKit.DIM)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(n)


func _aspect(w: int, h: int) -> String:
	var divisor := _gcd(w, h)
	return "%d:%d" % [w / divisor, h / divisor]


func _gcd(a: int, b: int) -> int:
	return a if b == 0 else _gcd(b, a % b)
