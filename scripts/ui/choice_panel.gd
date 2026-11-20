class_name ChoicePanel
extends CanvasLayer
## Shown in the break between rounds: pick a mech and one of its four saved loadouts for the next
## round, then press Ready. The choice is sent as soon as it changes; the server has the last word.

signal chosen(mech_id: String, loadout: Dictionary)
signal ready_pressed

var _root: Control
var _body: VBoxContainer
var _mech: String = ""
var _slot: int = 0
var _ready_sent: bool = false


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var anchor := CenterContainer.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.offset_top = 230.0
	_root.add_child(anchor)
	var panel := UiKit.panel(Color(UiKit.PANEL, 0.94), UiKit.BORDER, 18)
	panel.custom_minimum_size = Vector2(760, 0)
	anchor.add_child(panel)
	_body = UiKit.vbox(panel, 10)


func is_open() -> bool:
	return _root != null and _root.visible


## Shows the panel with `mech_id` selected (the mech the pilot is flying now).
func open(mech_id: String) -> void:
	if is_open():
		return
	_mech = mech_id
	_slot = LoadoutStore.active_index(mech_id)
	_ready_sent = false
	_build()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	for child in _body.get_children():
		child.queue_free()
	_body.add_child(UiKit.mono("Next round", UiKit.LIME, 11))
	_body.add_child(UiKit.label("Choose your mech and loadout", 22))
	_body.add_child(UiKit.mono("Mech", UiKit.DIM, 10))
	var mech_row := UiKit.hbox(_body, 8)
	for id in GameData.ids("mechs"):
		var text := UiKit.mech_name(id)
		var button := UiKit.primary_button(text, _pick_mech.bind(id)) if id == _mech else UiKit.outline_button(text, _pick_mech.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mech_row.add_child(button)
	_body.add_child(UiKit.mono("Loadout", UiKit.DIM, 10))
	var load_row := UiKit.hbox(_body, 8)
	var mech_def: Dictionary = GameData.get_entry("mechs", _mech)
	var capacity := Points.carry_capacity(mech_def)
	var slots := LoadoutStore.slots(_mech)
	for i in slots.size():
		var load: Dictionary = slots[i]["loadout"]
		var weight := Loadout.weight(mech_def, load)
		var fits := weight <= capacity
		var summary := "%s  /  %s" % [_weapon_name(load["primary"]), _weapon_name(load["secondary"])]
		if load["primary"] == load["secondary"]:
			summary = _weapon_name(load["primary"])
		var gear := "%s  /  %s" % [_item_name("equipment", load["equipment"]), _item_name("perk", load["perk"])]
		var text := "%s\n%s\n%s\n%d / %d%s" % [slots[i]["name"], summary, gear, roundi(weight), roundi(capacity), "" if fits else "  too heavy"]
		var button := UiKit.primary_button(text, _pick_slot.bind(i)) if i == _slot else UiKit.outline_button(text, _pick_slot.bind(i))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not fits
		load_row.add_child(button)
	_body.add_child(UiKit.label("Loadouts are made in Manage loadouts on the main menu.", 12, UiKit.DIM))
	var ready := UiKit.primary_button("Waiting for the others" if _ready_sent else "Ready", _on_ready)
	ready.disabled = _ready_sent
	_body.add_child(ready)


func _item_name(slot: String, id: String) -> String:
	return str(Loadout.item(slot, id).get("name", id.capitalize()))


func _weapon_name(id: String) -> String:
	return str(GameData.get_entry("weapons", id).get("display_name", id.capitalize()))


func _pick_mech(id: String) -> void:
	if id == _mech:
		return
	_mech = id
	_slot = LoadoutStore.active_index(id)
	_send()
	_build()


func _pick_slot(index: int) -> void:
	_slot = index
	_send()
	_build()


func _send() -> void:
	var load: Dictionary = LoadoutStore.slots(_mech)[_slot]["loadout"]
	chosen.emit(_mech, load.duplicate())


func _on_ready() -> void:
	_ready_sent = true
	_send()
	ready_pressed.emit()
	_build()
