class_name Hud
extends CanvasLayer
## On-screen display for the local player. The ruleset decides what is shown:
## `hud` controls the status panels and `crosshair` the crosshair. A hardcore ruleset
## turns both off. Cockpit instruments that replace the HUD come in a later milestone.
##
## F3 toggles a developer overlay. It is a debugging tool and not part of the game rules.

var debug_visible: bool = false

var _mech: Mech
var _rules: Ruleset
var _panels: Control
var _crosshair: Control
var _parts_label: Label
var _weapons_label: Label
var _info_label: Label
var _timer_label: Label
var _message_label: Label
var _debug_label: Label
var _timer_value: float = -1.0
var _debug_extra: String = ""


func _ready() -> void:
	_panels = Control.new()
	_panels.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panels)

	_info_label = _make_label(_panels, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_timer_label = _make_label(_panels, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	_timer_label.add_theme_font_size_override("font_size", 28)
	_parts_label = _make_label(_panels, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_weapons_label = _make_label(_panels, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_add_bar(_crosshair, Vector2(-9, -1), Vector2(18, 2))
	_add_bar(_crosshair, Vector2(-1, -9), Vector2(2, 18))

	# Messages stay visible in every ruleset: they are state, not HUD.
	_message_label = _make_label(self, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.add_theme_font_size_override("font_size", 32)

	_debug_label = _make_label(self, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_debug_label.visible = false
	_apply_rules()


## Shows information for this mech under this ruleset.
func bind(mech: Mech, rules: Ruleset) -> void:
	_mech = mech
	_rules = rules
	_timer_value = -1.0
	_message_label.text = ""
	_apply_rules()


## Shows a short message that clears itself, unless something else replaced it meanwhile.
func flash(text: String, seconds: float = 1.5) -> void:
	_message_label.text = text
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(_message_label) and _message_label.text == text:
		_message_label.text = ""


func set_timer(seconds_left: float) -> void:
	_timer_value = seconds_left


func show_message(text: String) -> void:
	_message_label.text = text


func set_debug_extra(text: String) -> void:
	_debug_extra = text


func panels_visible() -> bool:
	return _panels.visible


func crosshair_visible() -> bool:
	return _crosshair.visible


func toggle_debug() -> void:
	debug_visible = not debug_visible
	_debug_label.visible = debug_visible


func _process(_delta: float) -> void:
	if _mech == null or not is_instance_valid(_mech):
		return
	if _panels.visible:
		_info_label.text = "%s  |  %s  |  %s view" % [
			_mech.def["name"],
			_rules.display_name,
			"third-person" if _mech.view_third_person else "cockpit",
		]
		_timer_label.text = _format_time(_timer_value) if _timer_value >= 0.0 else ""
		_parts_label.text = _parts_text()
		_weapons_label.text = _weapons_text()
	if debug_visible:
		_debug_label.text = "DEBUG (developer overlay)\nFPS %d\nBalance version %d\nTeam %d\n%s" % [
			Engine.get_frames_per_second(),
			GameData.balance_version(),
			_mech.team,
			_debug_extra,
		]


func _apply_rules() -> void:
	if _panels == null:
		return
	_panels.visible = _rules != null and _rules.hud
	_crosshair.visible = _rules != null and _rules.crosshair


func _parts_text() -> String:
	var lines: Array[String] = ["HEALTH %d%%" % roundi(_mech.damage.total_ratio() * 100.0)]
	if _rules.location_damage:
		for part in _mech.def["parts"]:
			var id: String = part["id"]
			var status := "OFFLINE" if _mech.damage.is_part_disabled(id) else "%d%%" % roundi(_mech.damage.part_ratio(id) * 100.0)
			var crippled := " (crippled)" if _mech.damage.is_crippled(id) and not _mech.damage.is_part_disabled(id) else ""
			lines.append("%s  %s%s" % [part["name"], status, crippled])
	return "\n".join(lines)


func _weapons_text() -> String:
	var lines: Array[String] = []
	for weapon in _mech.weapons:
		var ammo_text := "-"
		if not weapon.is_melee():
			ammo_text = str(weapon.ammo) if _rules.ammo_limits else "unlimited"
		var online := _mech.damage.mount_online(weapon.mount_id)
		lines.append("%s  %s%s" % [weapon.def["name"], ammo_text, "" if online else "  OFFLINE"])
	return "\n".join(lines)


func _format_time(seconds: float) -> String:
	var total := int(ceil(seconds))
	return "%d:%02d" % [total / 60, total % 60]


## Creates a label pinned to a screen corner or edge. Anchored layouts keep it in place
## when the window is resized, and it grows away from the edge it is pinned to.
func _make_label(parent: Node, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color("#f4f4f4"))
	label.add_theme_color_override("font_outline_color", Color("#101010"))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	match preset:
		Control.PRESET_BOTTOM_LEFT:
			label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			label.grow_vertical = Control.GROW_DIRECTION_BEGIN
			label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_TOP_RIGHT:
			label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER:
			label.grow_horizontal = Control.GROW_DIRECTION_BOTH
			label.grow_vertical = Control.GROW_DIRECTION_BOTH
	return label


func _add_bar(parent: Control, pos: Vector2, size: Vector2) -> void:
	var bar := ColorRect.new()
	bar.color = Color("#f4f4f4")
	bar.position = pos
	bar.size = size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
