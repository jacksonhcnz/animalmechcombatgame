extends SceneTree
## Flying mechs dive faster and have a boost with a tank and a cooldown. Run with:
##   godot --headless --path . --script tests/flight_test.gd

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		printerr("FAIL: flight test timed out")
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


func _fly(hawk: Mech, throttle: float, vertical: float, sprint: bool) -> Vector3:
	hawk.global_position = Vector3(0.0, 60.0, 0.0)
	hawk.velocity = Vector3.ZERO
	hawk.controls.throttle = throttle
	hawk.controls.vertical = vertical
	hawk.controls.sprint = sprint
	await _frames(90)
	var seen := hawk.velocity
	hawk.controls.clear()
	return seen


func _run() -> void:
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)
	_range.controller.set_physics_process(false)
	_range.start("hawk", "standard")
	await _frames(10)
	var hawk: Mech = _range.player
	hawk.altitude_limit = 500.0

	var climbing := await _fly(hawk, 0.0, 1.0, false)
	var diving := await _fly(hawk, 0.0, -1.0, false)
	_check(-diving.y > climbing.y * 1.7, "diving is much faster than climbing (%.1f down, %.1f up)" % [-diving.y, climbing.y])
	var cruise := await _fly(hawk, 1.0, 0.0, false)
	var dive_run := await _fly(hawk, 1.0, -1.0, false)
	_check(Vector2(dive_run.x, dive_run.z).length() > Vector2(cruise.x, cruise.z).length() * 1.2, "going forward in a dive is faster along the ground")
	var boosted := await _fly(hawk, 1.0, 0.0, true)
	_check(Vector2(boosted.x, boosted.z).length() > Vector2(cruise.x, cruise.z).length() * 1.4, "boosting is faster")
	_check(hawk.boost_left < 10.0, "boosting uses up the tank")
	hawk.set_boost(1.0, false)

	# The tank: 10 seconds, then locked until refilled.
	hawk.controls.throttle = 1.0
	hawk.controls.sprint = true
	var seconds := 0.0
	while hawk.boost_left > 0.0 and seconds < 20.0:
		hawk._update_boost(0.1)
		seconds += 0.1
	_check(absf(seconds - 10.0) < 0.3, "a full tank lasts about 10 seconds (%.1f)" % seconds)
	_check(hawk.boost_locked and not hawk.boosting, "an empty tank locks the boost")
	hawk._update_boost(0.1)
	_check(not hawk.boosting, "holding Shift does nothing while it is locked")
	var wait := 0.0
	while hawk.boost_locked and wait < 30.0:
		hawk._update_boost(0.1)
		wait += 0.1
	_check(absf(wait - 8.0) < 0.5, "it unlocks after the cooldown, about 8 seconds (%.1f)" % wait)
	_check(hawk.boost_ratio() > 0.99, "and the tank is full again")
	hawk._update_boost(0.1)
	_check(hawk.boosting, "boost works again once refilled")
	hawk.controls.clear()

	# Ground mechs sprint as before and do not use the tank.
	_range.start("lion", "standard")
	await _frames(10)
	var lion: Mech = _range.player
	lion.controls.throttle = 1.0
	lion.controls.sprint = true
	_check(is_equal_approx(lion.sprint_mult(), 1.5) and not lion.boosting, "a ground mech sprints with no tank")
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
