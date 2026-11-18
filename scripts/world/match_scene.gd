class_name MatchScene
extends Node3D
## A networked match: the arena, the HUD, and a NetSession that is the server, the listen
## server or a client depending on LaunchConfig. The node must be named "MatchScene" so the
## session has the same path on every machine.

var session: NetSession
var hud: Hud
var controller: PlayerController
var status_text: String = ""

var _mechs_root: Node3D
var _pause: PauseMenu
var _world_built: bool = false


func _ready() -> void:
	name = "MatchScene"
	GameSettings.load_settings()
	InputSetup.ensure_actions()
	# The map comes from the ruleset: a server knows it now, a client is told when it joins.
	session = NetSession.new()
	session.world_ready.connect(_build_world)
	if LaunchConfig.mode != LaunchConfig.CLIENT:
		_build_world(Ruleset.load_id(LaunchConfig.ruleset_id))
	_mechs_root = Node3D.new()
	_mechs_root.name = "Mechs"
	add_child(_mechs_root)
	hud = Hud.new()
	add_child(hud)
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.leave_requested.connect(func() -> void: _leave(""))
	controller = PlayerController.new()
	controller.enabled = false
	add_child(controller)

	session.name = "NetSession"
	session.mechs_root = _mechs_root
	session.hud = hud
	session.controller = controller
	add_child(session)
	session.rejected.connect(func(reason: String) -> void: _leave("Rejected: " + reason))
	session.disconnected.connect(func(reason: String) -> void: _leave(reason))

	match LaunchConfig.mode:
		LaunchConfig.SERVER, LaunchConfig.HOST:
			var local := {}
			if LaunchConfig.mode == LaunchConfig.HOST:
				local = {"name": LaunchConfig.player_name, "mech": LaunchConfig.mech_id, "loadout": LaunchConfig.loadout}
			var error := session.start_server(LaunchConfig.port, LaunchConfig.ruleset_id, LaunchConfig.server_name, LaunchConfig.max_players, local)
			if error != OK:
				_leave("Could not start the server (error %d). Is the port in use?" % error)
			else:
				print("Server '%s' running on port %d, ruleset %s" % [LaunchConfig.server_name, LaunchConfig.port, LaunchConfig.ruleset_id])
		LaunchConfig.PRACTICE:
			var local := {"name": LaunchConfig.player_name, "mech": LaunchConfig.mech_id, "loadout": LaunchConfig.loadout}
			var error := session.start_offline(LaunchConfig.ruleset_id, local, LaunchConfig.team_size, LaunchConfig.bot_level)
			if error != OK:
				_leave("Could not start the practice match (error %d)" % error)
		LaunchConfig.CLIENT:
			var error := session.start_client(LaunchConfig.address, LaunchConfig.port, LaunchConfig.player_name, LaunchConfig.mech_id, LaunchConfig.loadout)
			if error != OK:
				_leave("Could not connect (error %d)" % error)
			else:
				hud.show_message("Connecting to %s ..." % LaunchConfig.address)


func _build_world(rules: Ruleset) -> void:
	if _world_built:
		return
	_world_built = true
	if rules.map == "field":
		Arena.build_match_arena(self)
	else:
		Arena.build_canyon(self, rules.map)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _headless() and not _pause.is_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_pause.toggle()
		elif event.keycode == KEY_F3:
			hud.toggle_debug()
		elif event.keycode == KEY_F10:
			_leave("")


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Leaves the match and returns to the menu, carrying a message to show there.
func _leave(message: String) -> void:
	MainMenu.pending_message = message
	session.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if LaunchConfig.mode == LaunchConfig.SERVER:
		# A dedicated server has no menu to return to.
		print(message if message != "" else "Server stopped")
		get_tree().quit(0 if message == "" else 1)
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
