extends SceneTree
## Checks the sound minimap and the Silent Stride perk. Run with:
##   godot --headless --path . --script tests/minimap_test.gd

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: minimap test timed out")
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


func _longest_step_range(loadout: Dictionary) -> float:
	_range.start("lion", "practice")
	await _frames(30)
	_range.controller.set_physics_process(false)
	var walker: Mech = _range.player
	walker.def["noise_mult"] = Loadout.apply(GameData.get_entry("mechs", "lion"), loadout)["noise_mult"]
	Sfx.events.clear()
	walker.controls.throttle = 1.0
	await _frames(300)
	walker.controls.throttle = 0.0
	var best := 0.0
	for event in Sfx.events:
		if event["clip"] == "lion_step" and int(event["team"]) == walker.team:
			best = maxf(best, float(event["range"]))
	return best


func _run() -> void:
	# Projection: ahead is up the screen, to the right is right.
	var ahead := Minimap.project(Vector3.ZERO, 0.0, Vector3(0, 0, -75))
	_check(ahead["offset"].y < -40.0 and absf(ahead["offset"].x) < 0.01, "a sound ahead shows above the middle")
	var right := Minimap.project(Vector3.ZERO, 0.0, Vector3(75, 0, 0))
	_check(right["offset"].x > 40.0 and absf(right["offset"].y) < 0.01, "a sound to the right shows to the right")
	var turned := Minimap.project(Vector3.ZERO, PI * 0.5, Vector3(0, 0, -75))
	_check(turned["offset"].x > 40.0, "turning left puts what was ahead on the right")
	var far := Minimap.project(Vector3.ZERO, 0.0, Vector3(0, 0, -400))
	_check(far["pinned"] and is_equal_approx(far["offset"].length(), Minimap.RADIUS), "a distant sound pins to the rim")

	# Audibility.
	var shot := {"pos": Vector3(0, 0, -100), "range": 130.0, "team": 2}
	_check(Minimap.audible(shot, Vector3.ZERO, 1), "an enemy shot within range is heard")
	_check(not Minimap.audible({"pos": Vector3(0, 0, -200), "range": 130.0, "team": 2}, Vector3.ZERO, 1), "a shot beyond its range is not")
	_check(not Minimap.audible({"pos": Vector3(0, 0, -3), "range": 130.0, "team": 1}, Vector3.ZERO, 1), "your own sounds are not drawn")
	_check(Minimap.audible({"pos": Vector3(0, 0, -3), "range": 130.0, "team": 2}, Vector3.ZERO, 1), "an enemy right next to you is heard")

	# The perk.
	var perk := GameData.get_entry("perks", "silent_stride")
	_check(not perk.is_empty() and float(perk["mods"]["noise_mult"]) < 0.5, "Silent Stride makes footsteps much quieter")
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(30)
	var normal := await _longest_step_range({})
	var quiet := await _longest_step_range({"perk": "silent_stride"})
	_check(normal > 20.0, "normal footsteps carry (%.0f m)" % normal)
	_check(quiet > 0.0 and quiet < normal * 0.5, "Silent Stride footsteps carry far less (%.0f m against %.0f m)" % [quiet, normal])

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
