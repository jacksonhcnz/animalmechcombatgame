class_name MainMenu
extends Control
## The start screen: the offline test range, hosting a match, joining by address, and
## scanning the local network. The same command-line options as LaunchConfig skip the menu,
## which is how a dedicated server starts.

## A message to show when the menu opens (for example why a connection ended).
static var pending_message: String = ""

var _name_edit: LineEdit
var _address_edit: LineEdit
var _ruleset_pick: OptionButton
var _status: Label
var _list: VBoxContainer
var _scanner: LanDiscovery.Scanner


func _ready() -> void:
	Settings.apply_all()
	if LaunchConfig.from_args(OS.get_cmdline_user_args()):
		_start_match.call_deferred()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_set_status(pending_message)
	pending_message = ""


func _set_status(text: String) -> void:
	_status.text = "System status   /   %s" % (text.to_upper() if text != "" else "Standby")


func _build() -> void:
	var column := UiKit.page(self)
	_name_edit = UiKit.header(column)

	column.add_child(UiKit.mono("Operations / Main menu"))
	var title_row := UiKit.hbox(column, 0)
	var titles := UiKit.vbox(title_row, 6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.heading("Ready for deployment?", 52))
	titles.add_child(UiKit.label("Configure your mech. Test your build. Enter the fight.", 15, UiKit.DIM))
	_status = UiKit.mono("", UiKit.DIM, 11)
	_status.size_flags_vertical = Control.SIZE_SHRINK_END
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(220, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(_status)

	var cards := UiKit.hbox(column, 22)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_loadout_card(cards)
	_build_range_card(cards)
	_build_multiplayer_card(cards)

	var footer := UiKit.hbox(column, 0)
	var mech_id := LaunchConfig.mech_id
	var active := UiKit.mono("Active: %s / %s" % [UiKit.mech_name(mech_id), LoadoutStore.active_name(mech_id)], UiKit.DIM, 10)
	active.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(active)
	footer.add_child(UiKit.link_button("Options", UiKit.LIME, func() -> void: get_tree().change_scene_to_file("res://scenes/options_menu.tscn")))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(24, 0)
	footer.add_child(gap)
	footer.add_child(UiKit.link_button("Quit game", UiKit.DIM, func() -> void: get_tree().quit()))


func _card(parent: Control, stretch: float, step: String, title: String, subtitle: String) -> VBoxContainer:
	var panel := UiKit.panel(UiKit.PANEL, UiKit.BORDER, 20)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch
	parent.add_child(panel)
	var box := UiKit.vbox(panel, 10)
	box.add_child(UiKit.mono(step))
	box.add_child(UiKit.heading(title, 38))
	box.add_child(UiKit.label(subtitle, 14, UiKit.DIM))
	return box


func _build_loadout_card(parent: Control) -> void:
	var box := _card(parent, 1.25, "01 / Prepare", "Loadout", "Your mech. Your playstyle.")
	var mech_id := LaunchConfig.mech_id
	var mech_def := GameData.get_entry("mechs", mech_id)
	var choice := LoadoutStore.active_loadout(mech_id)
	var inner := UiKit.panel(UiKit.INNER, UiKit.BORDER, 16)
	box.add_child(inner)
	var details := UiKit.vbox(inner, 6)
	details.add_child(UiKit.mono("Active mech", UiKit.DIM, 10))
	details.add_child(UiKit.heading(UiKit.mech_name(mech_id), 40))
	details.add_child(UiKit.label(LoadoutStore.active_name(mech_id), 15, UiKit.LIME))
	var weapons := UiKit.label("%s  /  %s" % [Loadout.item("primary", choice["primary"]).get("name", ""), Loadout.item("secondary", choice["secondary"]).get("name", "")], 13, UiKit.DIM)
	weapons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(weapons)
	UiKit.spacer(details, 8)
	var used := Loadout.weight(mech_def, choice)
	var capacity := Points.carry_capacity(mech_def)
	var carry := UiKit.hbox(details, 0)
	var carrying := UiKit.mono("Carrying", UiKit.DIM, 10)
	carrying.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carry.add_child(carrying)
	carry.add_child(UiKit.mono("%.0f / %.0f" % [used, capacity], UiKit.TEXT, 12))
	details.add_child(UiKit.progress(used, capacity))
	UiKit.spacer(box)
	box.add_child(UiKit.primary_button("Manage loadouts", func() -> void: get_tree().change_scene_to_file("res://scenes/loadout_menu.tscn")))
	box.add_child(UiKit.mono("Select mech  →  choose 1 of %d loadouts" % LoadoutStore.SLOT_COUNT, UiKit.DIM, 9))


func _build_range_card(parent: Control) -> void:
	var box := _card(parent, 1.0, "02 / Practice", "Test range", "Fine-tune before the fight.")
	var picture := UiKit.panel(UiKit.INNER, UiKit.BORDER, 0)
	box.add_child(picture)
	var target := TargetGraphic.new()
	target.custom_minimum_size = Vector2(0, 150)
	picture.add_child(target)
	box.add_child(UiKit.mono("Offline / No match required"))
	var note := UiKit.label("Take your active loadout into a safe testing environment.", 14, UiKit.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	UiKit.spacer(box)
	box.add_child(UiKit.outline_button("Enter test range", _on_test_range))


func _build_multiplayer_card(parent: Control) -> void:
	var box := _card(parent, 1.8, "03 / Engage", "Multiplayer", "Create a match or find your next opponent.")
	UiKit.rule(box)
	box.add_child(UiKit.label("Host a match", 18))
	box.add_child(UiKit.mono("Ruleset", UiKit.DIM, 10))
	var host_row := UiKit.hbox(box, 10)
	_ruleset_pick = OptionButton.new()
	_ruleset_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in GameData.ids("rulesets"):
		_ruleset_pick.add_item(str(GameData.get_entry("rulesets", id).get("display_name", id.capitalize())))
		_ruleset_pick.set_item_metadata(_ruleset_pick.item_count - 1, id)
	_ruleset_pick.select(maxi(0, GameData.ids("rulesets").find("standard_match")))
	UiKit.style_input(_ruleset_pick)
	host_row.add_child(_ruleset_pick)
	var host := UiKit.primary_button("Host", _on_host)
	host.custom_minimum_size = Vector2(150, 44)
	host_row.add_child(host)
	UiKit.rule(box)
	box.add_child(UiKit.label("Join by address", 18))
	var join_row := UiKit.hbox(box, 10)
	_address_edit = LineEdit.new()
	_address_edit.text = "127.0.0.1"
	_address_edit.placeholder_text = "address or address:port"
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_edit.add_theme_font_override("font", UiKit.mono_font())
	UiKit.style_input(_address_edit)
	join_row.add_child(_address_edit)
	var join := UiKit.outline_button("Join", _on_join)
	join.custom_minimum_size = Vector2(150, 44)
	join_row.add_child(join)
	UiKit.rule(box)
	var lan_row := UiKit.hbox(box, 10)
	var lan_text := UiKit.vbox(lan_row, 2)
	lan_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_text.add_child(UiKit.label("Local network", 16))
	lan_text.add_child(UiKit.label("Find nearby matches on your LAN.", 13, UiKit.DIM))
	var scan := UiKit.outline_button("Scan", _on_scan)
	scan.custom_minimum_size = Vector2(150, 44)
	lan_row.add_child(scan)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	box.add_child(_list)


class TargetGraphic:
	extends Control
	## The bull's-eye picture on the test range card.

	func _draw() -> void:
		var centre := size * 0.5
		var ring := Color(0.55, 0.6, 0.62, 0.55)
		draw_line(Vector2(centre.x - 110, centre.y), Vector2(centre.x + 110, centre.y), ring, 1.0)
		draw_line(Vector2(centre.x, 8), Vector2(centre.x, size.y - 8), ring, 1.0)
		for radius in [64.0, 38.0]:
			draw_arc(centre, minf(radius, size.y * 0.5 - 6.0), 0.0, TAU, 64, ring, 1.0, true)
		draw_arc(centre, 12.0, 0.0, TAU, 32, UiKit.LIME, 2.0, true)


func _read_choices() -> void:
	var cleaned := _name_edit.text.strip_edges()
	LaunchConfig.player_name = cleaned if cleaned != "" else "Pilot"
	LaunchConfig.loadout = LoadoutStore.active_loadout(LaunchConfig.mech_id)
	LaunchConfig.ruleset_id = _ruleset_pick.get_item_metadata(_ruleset_pick.selected)
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
	_set_status("Scanning...")
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_status) and _scanner.results.is_empty():
		_set_status("No servers found on this network")


func _on_found(info: Dictionary) -> void:
	_set_status("")
	var text := "%s  (%s, %d/%d)" % [info.get("name", "?"), info.get("mode", "?"), int(info.get("players", 0)), int(info.get("max_players", 0))]
	var address := str(info["address"])
	var port := int(info.get("port", NetProtocol.DEFAULT_PORT))
	_list.add_child(UiKit.outline_button(text, func() -> void:
		_address_edit.text = "%s:%d" % [address, port]
		_on_join()))


func _start_match() -> void:
	get_tree().change_scene_to_file("res://scenes/match.tscn")
