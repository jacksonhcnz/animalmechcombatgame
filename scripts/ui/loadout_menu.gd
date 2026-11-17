class_name LoadoutMenu
extends Control
## Pick a mech, pick one of its four loadouts (the equipped one goes into matches), and edit a
## loadout's name and four slots. Saved by LoadoutStore.

var _mech_pick: OptionButton
var _side: VBoxContainer
var _cards: HBoxContainer
var _summary: PanelContainer
var _editor: PanelContainer
var _footer_left: Label
var _footer_right: Label
var _name_edit: LineEdit
var _pickers: Dictionary = {}
var _weight_label: Label
var _weight_bar_holder: VBoxContainer
var _save_button: Button
var _editing: int = -1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var column := UiKit.page(self)
	UiKit.header(column)
	column.add_child(UiKit.link_button("←   Main menu", UiKit.DIM, func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"), true))
	column.add_child(UiKit.mono("01 / Prepare"))
	var title_row := UiKit.hbox(column, 0)
	var title := UiKit.heading("Build your advantage.", 50)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var hint := UiKit.label("Choose a mech, then select one of its four loadouts.", 15, UiKit.DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(hint)

	var body := UiKit.hbox(column, 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_side(body)
	var main := UiKit.vbox(body, 14)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading_row := UiKit.hbox(main, 0)
	var choose := UiKit.mono("2. Choose loadout")
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(choose)
	heading_row.add_child(UiKit.mono("%d slots per mech" % LoadoutStore.SLOT_COUNT, UiKit.DIM, 10))
	_cards = UiKit.hbox(main, 14)
	_summary = UiKit.panel(UiKit.PANEL, UiKit.BORDER, 22)
	main.add_child(_summary)
	_build_editor(main)

	var footer := UiKit.hbox(column, 0)
	_footer_left = UiKit.mono("", UiKit.DIM, 10)
	_footer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_footer_left)
	_footer_right = UiKit.mono("", UiKit.LIME, 11)
	footer.add_child(_footer_right)
	_refresh()


func _mech_id() -> String:
	return str(_mech_pick.get_item_metadata(_mech_pick.selected))


func _build_side(parent: Control) -> void:
	var panel := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 20)
	panel.custom_minimum_size = Vector2(260, 0)
	parent.add_child(panel)
	var box := UiKit.vbox(panel, 10)
	box.add_child(UiKit.mono("1. Select mech"))
	_mech_pick = OptionButton.new()
	for id in GameData.ids("mechs"):
		_mech_pick.add_item(UiKit.mech_name(id))
		_mech_pick.set_item_metadata(_mech_pick.item_count - 1, id)
	_mech_pick.select(maxi(0, GameData.ids("mechs").find(LaunchConfig.mech_id)))
	UiKit.style_input(_mech_pick)
	_mech_pick.item_selected.connect(func(_i: int) -> void:
		LaunchConfig.mech_id = _mech_id()
		_close_editor()
		_refresh())
	box.add_child(_mech_pick)
	UiKit.rule(box)
	_side = UiKit.vbox(box, 6)


func _refresh() -> void:
	var mech_id := _mech_id()
	var mech_def := GameData.get_entry("mechs", mech_id)
	var active := LoadoutStore.active_index(mech_id)
	var slots := LoadoutStore.slots(mech_id)
	var active_name := str(slots[active]["name"])

	for child in _side.get_children():
		child.queue_free()
	_side.add_child(UiKit.heading(UiKit.mech_name(mech_id), 30))
	_side.add_child(UiKit.mono("Carrying capacity", UiKit.DIM, 10))
	_side.add_child(UiKit.heading("%.0f" % Points.carry_capacity(mech_def), 64))
	UiKit.rule(_side)
	_side.add_child(UiKit.mono("Current configuration", UiKit.DIM, 10))
	_side.add_child(UiKit.label(active_name, 20, UiKit.LIME))
	var note := UiKit.label("Changes apply only to the selected mech.", 13, UiKit.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(note)

	for child in _cards.get_children():
		child.queue_free()
	for i in LoadoutStore.SLOT_COUNT:
		_cards.add_child(_card(mech_id, i, slots[i], i == active))
	_fill_summary(mech_def, slots[active], active)
	_footer_left.text = "%s / %d loadout slots" % [UiKit.mech_name(mech_id), LoadoutStore.SLOT_COUNT]
	_footer_right.text = "Equipped: %s" % active_name


## A slot with nothing chosen yet: still the starting weapons under the starting name.
func _is_configured(index: int, slot: Dictionary, equipped: bool) -> bool:
	return equipped or str(slot["name"]) != "Loadout %d" % (index + 1) or slot["loadout"] != Loadout.default_loadout()


func _card(mech_id: String, index: int, slot: Dictionary, equipped: bool) -> Control:
	var configured := _is_configured(index, slot, equipped)
	var panel := UiKit.panel(UiKit.LIME_SOFT if equipped else UiKit.PANEL, UiKit.LIME if equipped else UiKit.BORDER, 18)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(150, 0)
	var box := UiKit.vbox(panel, 8)
	var top := UiKit.hbox(box, 0)
	var number := UiKit.mono("%02d" % (index + 1), UiKit.DIM, 11)
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(number)
	if equipped:
		top.add_child(UiKit.mono("Equipped"))
	box.add_child(UiKit.heading(str(slot["name"]), 26))
	var detail := UiKit.vbox(box, 2)
	detail.custom_minimum_size = Vector2(0, 40)
	if configured:
		for slot_id in ["primary", "secondary"]:
			detail.add_child(UiKit.label(str(Loadout.item(slot_id, slot["loadout"][slot_id]).get("name", "")), 13, UiKit.DIM))
	else:
		detail.add_child(UiKit.label("Not configured", 13, UiKit.DIM))
	UiKit.rule(box)
	var go: Callable
	var text := "Selected"
	if equipped:
		go = func() -> void: pass
	elif configured:
		text = "Use this loadout"
		go = func() -> void:
			LoadoutStore.set_active(mech_id, index)
			_close_editor()
			_refresh()
	else:
		text = "Configure loadout"
		go = func() -> void:
			LoadoutStore.set_active(mech_id, index)
			_refresh()
			_open_editor(index)
	var link := UiKit.link_button(text + "   →", UiKit.LIME if equipped else UiKit.TEXT, go)
	link.add_theme_font_size_override("font_size", 13)
	box.add_child(link)
	return panel


func _fill_summary(mech_def: Dictionary, slot: Dictionary, index: int) -> void:
	for child in _summary.get_children():
		child.queue_free()
	_summary.visible = _editing < 0
	var box := UiKit.vbox(_summary, 14)
	var top := UiKit.hbox(box, 0)
	var heading := UiKit.mono("%s / Equipment" % slot["name"])
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var used := Loadout.weight(mech_def, slot["loadout"])
	var capacity := Points.carry_capacity(mech_def)
	var carry := UiKit.vbox(top, 4)
	carry.custom_minimum_size = Vector2(200, 0)
	carry.add_child(UiKit.mono("Carrying %.0f / %.0f" % [used, capacity], UiKit.TEXT, 11))
	carry.add_child(UiKit.progress(used, capacity))
	var columns := UiKit.hbox(box, 12)
	var labels := {"primary": "Primary weapon", "secondary": "Secondary weapon", "equipment": "Equipment", "perk": "Perk"}
	var none_text := {"equipment": "None equipped", "perk": "None selected"}
	for slot_id in Loadout.SLOTS:
		var col := UiKit.vbox(columns, 6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.mono(labels[slot_id], UiKit.DIM, 10))
		var chosen: String = slot["loadout"][slot_id]
		if chosen == "none":
			col.add_child(UiKit.label(none_text[slot_id], 22, UiKit.DIM))
		else:
			col.add_child(UiKit.label(str(Loadout.item(slot_id, chosen).get("name", chosen)), 22))
	UiKit.rule(box)
	var bottom := UiKit.hbox(box, 0)
	var ready := UiKit.label("This loadout is equipped and ready for the test range or a match.", 14, UiKit.DIM)
	ready.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(ready)
	var edit := UiKit.primary_button("Edit loadout", func() -> void: _open_editor(index))
	edit.custom_minimum_size = Vector2(240, 44)
	bottom.add_child(edit)


func _build_editor(parent: Control) -> void:
	_editor = UiKit.panel(UiKit.PANEL, UiKit.LIME, 22)
	_editor.visible = false
	parent.add_child(_editor)
	var box := UiKit.vbox(_editor, 12)
	box.add_child(UiKit.mono("Edit loadout"))
	var name_row := UiKit.hbox(box, 12)
	var name_label := UiKit.mono("Name", UiKit.DIM, 10)
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.max_length = LoadoutStore.NAME_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_input(_name_edit)
	name_row.add_child(_name_edit)
	var grid := UiKit.hbox(box, 12)
	var labels := {"primary": "Primary weapon", "secondary": "Secondary weapon", "equipment": "Equipment", "perk": "Perk"}
	for slot in Loadout.SLOTS:
		var col := UiKit.vbox(grid, 6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.mono(labels[slot], UiKit.DIM, 10))
		var pick := OptionButton.new()
		UiKit.style_input(pick)
		pick.item_selected.connect(func(_i: int) -> void:
			_sync_two_slot(slot)
			_update_weight())
		col.add_child(pick)
		_pickers[slot] = pick
	_weight_label = UiKit.mono("", UiKit.TEXT, 12)
	box.add_child(_weight_label)
	_weight_bar_holder = UiKit.vbox(box, 0)
	var buttons := UiKit.hbox(box, 12)
	_save_button = UiKit.primary_button("Save", _on_save)
	_save_button.custom_minimum_size = Vector2(200, 44)
	buttons.add_child(_save_button)
	var cancel := UiKit.outline_button("Cancel", _close_editor)
	cancel.custom_minimum_size = Vector2(200, 44)
	buttons.add_child(cancel)


## Fills a picker with what this mech may carry (some weapons and gear are for one mech only).
func _fill_picker(slot: String) -> void:
	var pick: OptionButton = _pickers[slot]
	pick.clear()
	for id in Loadout.options(slot, _mech_id()):
		pick.add_item(str(Loadout.item(slot, id).get("name", id)))
		pick.set_item_metadata(pick.item_count - 1, id)


func _open_editor(index: int) -> void:
	_editing = index
	for s in Loadout.SLOTS:
		_fill_picker(s)
	var slot: Dictionary = LoadoutStore.slots(_mech_id())[index]
	_name_edit.text = str(slot["name"])
	for s in Loadout.SLOTS:
		var pick: OptionButton = _pickers[s]
		pick.select(maxi(0, Loadout.options(s, _mech_id()).find(slot["loadout"][s])))
	_summary.visible = false
	_editor.visible = true
	_update_weight()


## A two-slot weapon (the ion cannon) takes both weapon slots: picking it in one fills the other,
## and picking something else in one slot lets the other go back to its default.
func _sync_two_slot(changed: String) -> void:
	if changed != "primary" and changed != "secondary":
		return
	var other := "secondary" if changed == "primary" else "primary"
	var chosen: String = _pickers[changed].get_item_metadata(_pickers[changed].selected)
	var other_pick: OptionButton = _pickers[other]
	var other_id: String = other_pick.get_item_metadata(other_pick.selected)
	if Loadout.is_two_slot(chosen):
		other_pick.select(maxi(0, Loadout.options(other, _mech_id()).find(chosen)))
	elif Loadout.is_two_slot(other_id):
		other_pick.select(maxi(0, Loadout.options(other, _mech_id()).find(Loadout.DEFAULT[other])))


func _close_editor() -> void:
	_editing = -1
	_editor.visible = false
	_summary.visible = true


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
	_weight_label.text = ("Carrying %.0f / %.0f%s" % [used, capacity, "" if ok else "   -   too heavy for this mech"]).to_upper()
	_weight_label.add_theme_color_override("font_color", UiKit.TEXT if ok else Color("ff7a5c"))
	for child in _weight_bar_holder.get_children():
		child.queue_free()
	_weight_bar_holder.add_child(UiKit.progress(used, capacity))
	_save_button.disabled = not ok


func _on_save() -> void:
	if _editing < 0:
		return
	LoadoutStore.save_slot(_mech_id(), _editing, _name_edit.text, _chosen())
	_close_editor()
	_refresh()
