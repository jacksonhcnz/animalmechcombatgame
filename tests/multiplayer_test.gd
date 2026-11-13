extends SceneTree
## Checks the multiplayer core with real processes: a dedicated server, a bot client and this
## script as a client. Run with:
##   godot --headless --path . --script tests/multiplayer_test.gd

const PORT := 17777

var _checks := 0
var _failures := 0
var _pids: Array[int] = []
var _loose: Array[Node] = []


func _initialize() -> void:
	create_timer(100.0).timeout.connect(func() -> void:
		printerr("FAIL: multiplayer test timed out")
		_cleanup()
		quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _finish() -> void:
	_cleanup()
	for child in root.get_children():
		child.free()
	for node in _loose:
		node.free()
	await process_frame
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _cleanup() -> void:
	for pid in _pids:
		OS.kill(pid)


func _launch(extra: Array[String]) -> void:
	var args: Array[String] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	args.append_array(extra)
	_pids.append(OS.create_process(OS.get_executable_path(), PackedStringArray(args)))


func _wait_until(condition: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if condition.call():
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return condition.call()


func _make_client(balance: int = -1) -> Array:
	var scene := Node3D.new()
	scene.name = "MatchScene"
	root.add_child(scene)
	var mechs := Node3D.new()
	scene.add_child(mechs)
	var hud := Hud.new()
	scene.add_child(hud)
	var session := NetSession.new()
	session.name = "NetSession"
	session.mechs_root = mechs
	session.hud = hud
	session.controller = PlayerController.new()  # not in the tree, so it never overrides the controls
	_loose.append(session.controller)
	session.test_balance = balance
	scene.add_child(session)
	return [scene, session]


func _run() -> void:
	InputSetup.ensure_actions()
	_check_units()

	_launch(["--server", "--port=%d" % PORT, "--ruleset=standard", "--max-players=3", "--server-name=Test"])
	await create_timer(3.0).timeout

	# LAN discovery straight to the server.
	var scanner := LanDiscovery.Scanner.new()
	root.add_child(scanner)
	scanner.scan(["127.0.0.1"])
	await _wait_until(func() -> bool: return not scanner.results.is_empty(), 3.0)
	_check(scanner.results.has("127.0.0.1"), "LAN probe finds the server")
	if scanner.results.has("127.0.0.1"):
		var info: Dictionary = scanner.results["127.0.0.1"]
		_check(info["name"] == "Test" and int(info["max_players"]) == 3, "discovery reports the server details")
		_check(int(info["balance_version"]) == GameData.balance_version(), "discovery reports the balance version")

	# A client with the wrong balance version is turned away.
	var bad := _make_client(GameData.balance_version() + 1)
	var bad_session: NetSession = bad[1]
	var reason := [""]
	bad_session.rejected.connect(func(text: String) -> void: reason[0] = text)
	bad_session.start_client("127.0.0.1", PORT, "Bad", "lion")
	await _wait_until(func() -> bool: return reason[0] != "", 5.0)
	_check(reason[0].contains("Balance"), "wrong balance version is rejected (%s)" % reason[0])
	bad_session.stop()
	bad[0].queue_free()
	await create_timer(0.5).timeout

	# A proper client joins and spawns.
	var good := _make_client()
	var session: NetSession = good[1]
	var joined := [false]
	session.joined.connect(func() -> void: joined[0] = true)
	session.start_client("127.0.0.1", PORT, "Tester", "lion")
	await _wait_until(func() -> bool: return joined[0], 5.0)
	_check(joined[0], "client joins")
	await _wait_until(func() -> bool: return session.local_mech != null, 3.0)
	_check(session.local_mech != null, "client gets its own mech")
	_check(session.rules != null and session.rules.id == "standard", "client receives the server's ruleset")
	_check(session.phase == NetSession.Phase.WAITING, "match waits for an opponent")

	# A second client starts the match.
	_launch(["--join=127.0.0.1:%d" % PORT, "--name=Bot", "--mech=velociraptor"])
	await _wait_until(func() -> bool: return session.phase == NetSession.Phase.ACTIVE, 15.0)
	_check(session.phase == NetSession.Phase.ACTIVE, "match goes active with two pilots")
	_check(session.scores.size() == 2, "scoreboard lists both pilots")
	_check(session.get("_display_mechs").size() == 2, "client sees both mechs")

	# Driving forward moves the mech on the server and back to us.
	var mech: Mech = session.local_mech
	var start := mech.global_position
	mech.controls.throttle = 1.0
	await create_timer(2.0).timeout
	var moved := mech.global_position.distance_to(start)
	_check(moved > 3.0, "driving moves the mech (moved %.1f m)" % moved)
	mech.controls.throttle = 0.0

	# Firing uses ammunition on the server and reports it back.
	var ammo_before := 0
	for weapon in mech.weapons:
		ammo_before += weapon.ammo
	mech.controls.fire_primary = true
	await create_timer(1.0).timeout
	mech.controls.fire_primary = false
	await create_timer(0.5).timeout
	var ammo_after := 0
	for weapon in mech.weapons:
		ammo_after += weapon.ammo
	_check(ammo_after < ammo_before or not session.rules.ammo_limits, "firing is decided by the server (ammo %d -> %d)" % [ammo_before, ammo_after])

	# Leaving ends the session cleanly.
	session.stop()
	_check(not session.connected, "client can leave")
	await _finish()


func _check_units() -> void:
	var controls := MechControls.new()
	_check(NetProtocol.apply_input(controls, [1.0, -1.0, 0.5, 0.0, NetProtocol.FLAG_JUMP, 0.3, 0.1]), "valid input is accepted")
	_check(controls.jump and controls.throttle == 1.0, "input is applied")
	_check(not NetProtocol.apply_input(controls, [1.0]), "short input is rejected")
	_check(not NetProtocol.apply_input(controls, ["x", 0, 0, 0, 0, 0, 0]), "non-numeric input is rejected")
	_check(not NetProtocol.apply_input(controls, [INF, 0, 0, 0, 0, 0, 0]), "infinite input is rejected")
	NetProtocol.apply_input(controls, [9.0, 0.0, 0.0, 0.0, 0, 0.0, 0.0])
	_check(controls.throttle <= 1.0, "axes are clamped")

	var rules := Ruleset.load_id("hardcore")
	var copy := Ruleset.from_dict(rules.to_dict(), "hardcore")
	_check(copy.to_dict() == rules.to_dict(), "ruleset survives a round trip")

	var a := Mech.create("lion", rules)
	var b := Mech.create_remote("lion", rules)
	root.add_child(a)
	root.add_child(b)
	a.take_hit("torso", 40.0)
	b.mirror_state(a.damage.export_state())
	_check(b.damage.export_state() == a.damage.export_state(), "damage state survives export and import")
	a.queue_free()
	b.queue_free()
