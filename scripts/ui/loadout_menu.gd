class_name LoadoutMenu
extends Control
## Pick a mech, then see its four loadout boxes. "Use" marks the loadout taken into
## matches, and "Edit" renames a box and sets its four slots. Saved by LoadoutStore.

var _mech_pick: OptionButton
var _rows: VBoxContainer
var _editor: VBoxContainer
var _name_edit: LineEdit
var _pickers: Dictionary = {}
var _weight_label: Label
var _save_button: Button
var _editing: int = -1
var _use_group := ButtonGroup.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var back := ColorRect.new()
	back.color = Color(0.1, 0.12, 0.14)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "LOADOUTS"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var mech_row := HBoxContainer.new()
	var mech_label := Label.new()
	mech_label.text = "Mech"
	mech_label.custom_minimum_size = Vector2(90, 0)
	mech_row.add_child(mech_label)
	_mech_pick = OptionButton.new()
	_mech_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in GameData.ids("mechs"):
		_mech_pick.add_item(id)
	var current := GameData.ids("mechs").find(LaunchConfig.mech_id)
	_mech_pick.select(maxi(0, current))
	_mech_pick.item_selected.connect(func(_i: int) -> void:
		LaunchConfig.mech_id = _mech_id()
		_close_editor()
		_refresh())
	mech_row.add_child(_mech_pick)
	box.add_child(mech_row)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)

	_build_editor(box)
	var done := Button.new()
	done.text = "Back to main menu"
	done.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	box.add_child(done)
	_refresh()


func _mech_id() -> String:
	return _mech_pick.get_item_text(_mech_pick.selected)


func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var mech_id := _mech_id()
	var active := LoadoutStore.active_index(mech_id)
	var slots := LoadoutStore.slots(mech_id)
	for i in LoadoutStore.SLOT_COUNT:
		var row := HBoxContainer.new()
		var use := Button.new()
		use.text = "Use"
		use.toggle_mode = true
		use.button_group = _use_group
		use.button_pressed = i == active
		use.custom_minimum_size = Vector2(60, 0)
		use.pressed.connect(func() -> void: LoadoutStore.set_active(mech_id, i))
		row.add_child(use)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = str(slots[i]["name"])
		name_label.add_theme_font_size_override("font_size", 18)
		info.add_child(name_label)
		var detail := Label.new()
		detail.text = LoadoutStore.summary(slots[i]["loadout"])
		detail.modulate = Color(0.8, 0.85, 0.9)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(detail)
		row.add_child(info)
		var edit := Button.new()
		edit.text = "Edit"
		edit.custom_minimum_size = Vector2(70, 0)
		edit.pressed.connect(func() -> void: _open_editor(i))
		row.add_child(edit)
		_rows.add_child(row)


func _build_editor(parent: Control) -> void:
	_editor = VBoxContainer.new()
	_editor.visible = false
	_editor.add_theme_constant_override("separation", 6)
	parent.add_child(_editor)
	_editor.add_child(HSeparator.new())
	_name_edit = _labelled("Name", LineEdit.new()) as LineEdit
	_name_edit.max_length = LoadoutStore.NAME_LENGTH
	for slot in Loadout.SLOTS:
		var pick := _labelled(slot.capitalize(), OptionButton.new()) as OptionButton
		for id in Loadout.options(slot):
			pick.add_item(str(Loadout.item(slot, id).get("name", id)))
			pick.set_item_metadata(pick.item_count - 1, id)
		pick.item_selected.connect(func(_i: int) -> void: _update_weight())
		_pickers[slot] = pick
	_weight_label = Label.new()
	_editor.add_child(_weight_label)
	var buttons := HBoxContainer.new()
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_on_save)
	buttons.add_child(_save_button)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close_editor)
	buttons.add_child(cancel)
	_editor.add_child(buttons)


func _labelled(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(90, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	_editor.add_child(row)
	return control


func _open_editor(index: int) -> void:
	_editing = index
	var slot: Dictionary = LoadoutStore.slots(_mech_id())[index]
	_name_edit.text = str(slot["name"])
	for s in Loadout.SLOTS:
		var pick: OptionButton = _pickers[s]
		pick.select(maxi(0, Loadout.options(s).find(slot["loadout"][s])))
	_editor.visible = true
	_update_weight()


func _close_editor() -> void:
	_editing = -1
	_editor.visible = false


func _chosen() -> Dictionary:
	var choice := {}
	for s in Loadout.SLOTS:
		var pick: OptionButton = _pickers[s]
		choice[s] = pick.get_item_metadata(pick.selected)
	return choice


## Shows the weight against the mech's carry capacity and blocks saving a loadout it cannot carry.
func _update_weight() -> void:
	var mech_def := GameData.get_entry("mechs", _mech_id())
	var used := Loadout.weight(mech_def, _chosen())
	var capacity := Points.carry_capacity(mech_def)
	var ok := used <= capacity
	_weight_label.text = "Carrying %.0f of %.0f%s" % [used, capacity, "" if ok else "  - too heavy for this mech"]
	_weight_label.modulate = Color.WHITE if ok else Color(1.0, 0.5, 0.4)
	_save_button.disabled = not ok


func _on_save() -> void:
	if _editing < 0:
		return
	LoadoutStore.save_slot(_mech_id(), _editing, _name_edit.text, _chosen())
	_close_editor()
	_refresh()
