class_name MainMenu
extends Control
## The start screen: the offline test range, hosting a match, joining by address, and
## scanning the local network. The same command-line options as LaunchConfig skip the menu,
## which is how a dedicated server starts.

## A message to show when the menu opens (for example why a connection ended).
static var pending_message: String = ""

var _name_edit: LineEdit
var _address_edit: LineEdit
var _mech_pick: OptionButton
var _ruleset_pick: OptionButton
var _status: Label
var _list: VBoxContainer
var _scanner: LanDiscovery.Scanner


func _ready() -> void:
	if LaunchConfig.from_args(OS.get_cmdline_user_args()):
		_start_match.call_deferred()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_status.text = pending_message
	pending_message = ""


func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.1, 0.12, 0.14)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "ANIMAL MECH COMBAT"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_name_edit = _row(box, "Pilot name", LineEdit.new()) as LineEdit
	_name_edit.text = LaunchConfig.player_name
	_name_edit.max_length = 20
	_mech_pick = _row(box, "Mech", OptionButton.new()) as OptionButton
	for id in GameData.ids("mechs"):
		_mech_pick.add_item(id)
	_ruleset_pick = _row(box, "Ruleset (hosting)", OptionButton.new()) as OptionButton
	for id in GameData.ids("rulesets"):
		_ruleset_pick.add_item(id)
	_ruleset_pick.select(maxi(0, GameData.ids("rulesets").find("standard")))
	_address_edit = _row(box, "Server address", LineEdit.new()) as LineEdit
	_address_edit.text = "127.0.0.1"
	_address_edit.placeholder_text = "address or address:port"

	_button(box, "Test range (offline)", _on_test_range)
	_button(box, "Host a match", _on_host)
	_button(box, "Join by address", _on_join)
	_button(box, "Scan local network", _on_scan)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_button(box, "Quit", func() -> void: get_tree().quit())


func _row(parent: Control, label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	parent.add_child(row)
	return control


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _read_choices() -> void:
	var cleaned := _name_edit.text.strip_edges()
	LaunchConfig.player_name = cleaned if cleaned != "" else "Pilot"
	LaunchConfig.mech_id = _mech_pick.get_item_text(_mech_pick.selected)
	LaunchConfig.ruleset_id = _ruleset_pick.get_item_text(_ruleset_pick.selected)
	LaunchConfig.server_name = "%s's match" % LaunchConfig.player_name


func _on_test_range() -> void:
	get_tree().change_scene_to_file("res://scenes/test_range.tscn")


func _on_host() -> void:
	_read_choices()
	LaunchConfig.mode = LaunchConfig.HOST
	_start_match()


func _on_join() -> void:
	_read_choices()
	var target := _address_edit.text.strip_edges()
	LaunchConfig.port = NetProtocol.DEFAULT_PORT
	if ":" in target:
		LaunchConfig.port = int(target.get_slice(":", 1))
		target = target.get_slice(":", 0)
	LaunchConfig.address = target if target != "" else "127.0.0.1"
	LaunchConfig.mode = LaunchConfig.CLIENT
	_start_match()


func _on_scan() -> void:
	if _scanner == null:
		_scanner = LanDiscovery.Scanner.new()
		add_child(_scanner)
		_scanner.found.connect(_on_found)
	for child in _list.get_children():
		child.queue_free()
	_scanner.results.clear()
	_scanner.scan()
	_status.text = "Scanning..."
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_status) and _scanner.results.is_empty():
		_status.text = "No servers found on this network."


func _on_found(info: Dictionary) -> void:
	_status.text = ""
	var text := "%s  (%s, %d/%d)" % [info.get("name", "?"), info.get("mode", "?"), int(info.get("players", 0)), int(info.get("max_players", 0))]
	var address := str(info["address"])
	var port := int(info.get("port", NetProtocol.DEFAULT_PORT))
	_button(_list, text, func() -> void:
		_address_edit.text = "%s:%d" % [address, port]
		_on_join())


func _start_match() -> void:
	get_tree().change_scene_to_file("res://scenes/match.tscn")
