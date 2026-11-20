extends SceneTree
## Plays a practice match against computer pilots and checks they really fight. Run with:
##   godot --headless --path . --script tests/practice_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		printerr("FAIL: practice test timed out")
		quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _play(size: int, level: String) -> MatchScene:
	LaunchConfig.mode = LaunchConfig.PRACTICE
	LaunchConfig.ruleset_id = "practice_match"
	LaunchConfig.team_size = size
	LaunchConfig.bot_level = level
	LaunchConfig.mech_id = "lion"
	LaunchConfig.player_name = "Tester"
	LaunchConfig.loadout = {}
	var scene := MatchScene.new()
	root.add_child(scene)
	return scene


func _teams(scene: MatchScene) -> Array:
	var counts := [0, 0]
	for slot: NetSession.Slot in scene.session._slots.values():
		counts[slot.team - 1] += 1
	return counts


func _run() -> void:
	for size in [1, 2, 3]:
		var scene := _play(size, "normal")
		await _frames(10)
		_check(_teams(scene) == [size, size], "%dv%d has %d pilots a side (%s)" % [size, size, size, str(_teams(scene))])
		var bots := 0
		for slot: NetSession.Slot in scene.session._slots.values():
			if slot.pilot != null:
				bots += 1
		_check(bots == size * 2 - 1, "%dv%d fills the rest with %d computer pilots" % [size, size, size * 2 - 1])
		_check(scene.session.multiplayer.get_peers().is_empty(), "a practice match opens no network port")
		scene.queue_free()
		await _frames(5)

	# A full 2v2: the player stands still, so the bots must find and shoot them or each other.
	var scene := _play(2, "hard")
	await _frames(30)
	var session: NetSession = scene.session
	_check(session.phase == NetSession.Phase.COUNTDOWN or session.phase == NetSession.Phase.ACTIVE, "the match starts by itself")
	_check(session.choice_window(), "round 1 starts with a pick period")
	session.press_ready()
	for i in 60 * 6:
		await physics_frame
		if session.phase == NetSession.Phase.ACTIVE:
			break
	_check(session.phase == NetSession.Phase.ACTIVE, "the countdown ends and the round begins")
	var start := {}
	var mechs: Array[Mech] = []
	for slot: NetSession.Slot in session._slots.values():
		start[slot.peer] = slot.mech.global_position
		mechs.append(slot.mech)
	var tally := [0]
	for mech in mechs:
		mech.fired.connect(func(_a: Vector3, _b: Vector3, _c: Color) -> void: tally[0] += 1)
		mech.projectile_launched.connect(func(_info: Dictionary) -> void: tally[0] += 1)
		mech.beam_fired.connect(func(_a: Vector3, _b: Vector3, _c: Color, _d: float, _e: float) -> void: tally[0] += 1)
	var damaged := false
	for i in 60 * 45:
		await physics_frame
		if session.phase != NetSession.Phase.ACTIVE:
			break
		for mech in mechs:
			if is_instance_valid(mech) and mech.damage.total_ratio() < 0.99:
				damaged = true
		if damaged and tally[0] > 20:
			break
	var moved := 0
	for slot: NetSession.Slot in session._slots.values():
		if slot.pilot != null and slot.mech != null and is_instance_valid(slot.mech) and slot.mech.global_position.distance_to(start[slot.peer]) > 8.0:
			moved += 1
	_check(moved >= 2, "the computer pilots move to engage (%d of 3 moved)" % moved)
	_check(tally[0] > 5, "the computer pilots fire their weapons (%d shots)" % tally[0])
	_check(damaged, "the computer pilots hurt someone")
	scene.queue_free()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
