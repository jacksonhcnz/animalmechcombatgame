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


## Puts the hawk high up at cruise speed, holds the controls for `frames`, and returns it.
func _fly(hawk: Mech, throttle: float, vertical: float, turn: float, sprint: bool, frames: int) -> Mech:
	hawk.global_position = Vector3(0.0, 300.0, 0.0)
	hawk.rotation = Vector3.ZERO
	hawk.air_speed = -1.0
	hawk.flight_pitch = 0.0
	hawk.flight_roll = 0.0
	hawk._sink = 0.0
	hawk.velocity = Vector3.ZERO
	hawk.controls.throttle = throttle
	hawk.controls.vertical = vertical
	hawk.controls.turn = turn
	hawk.controls.sprint = sprint
	await _frames(frames)
	hawk.controls.clear()
	return hawk


func _run() -> void:
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)
	_range.controller.set_physics_process(false)
	_range.start("hawk", "standard")
	await _frames(10)
	var hawk: Mech = _range.player
	hawk.altitude_limit = 900.0
	var top := hawk.top_air_speed()
	var cruise := top * Points.flight("cruise_fraction")

	# It never hovers: with no input it flies straight ahead at cruise speed.
	var start := Vector3(0.0, 300.0, 0.0)
	await _fly(hawk, 0.0, 0.0, 0.0, false, 60)
	_check(absf(hawk.air_speed - cruise) < 2.0, "with no input it flies at cruise speed (%.0f of %.0f)" % [hawk.air_speed, cruise])
	_check(hawk.global_position.distance_to(start) > cruise * 0.8, "and it keeps moving forward")
	_check(absf(hawk.global_position.y - 300.0) < 1.0 and not hawk.stalled, "level flight holds its altitude")

	await _fly(hawk, 1.0, 0.0, 0.0, false, 240)
	_check(hawk.air_speed > cruise * 1.15, "pushing the throttle speeds it up (%.0f)" % hawk.air_speed)
	await _fly(hawk, -1.0, 0.0, 0.0, false, 240)
	_check(hawk.air_speed < cruise * 0.85 and not hawk.stalled, "pulling the throttle back slows it but does not stall it (%.0f)" % hawk.air_speed)

	# Pitch trades speed for height: a dive builds speed, a climb bleeds it.
	await _fly(hawk, 0.0, -1.0, 0.0, false, 90)
	var dive_speed := hawk.air_speed
	var dive_y := hawk.global_position.y
	_check(hawk.flight_pitch < -0.3 and dive_y < 290.0, "pushing the nose down loses height")
	await _fly(hawk, 0.0, 1.0, 0.0, false, 90)
	_check(hawk.flight_pitch > 0.3 and hawk.global_position.y > 310.0, "pulling the nose up gains height")
	_check(dive_speed > hawk.air_speed + 8.0, "a dive is faster than a climb (%.0f against %.0f)" % [dive_speed, hawk.air_speed])

	# Banking turns it.
	await _fly(hawk, 0.0, 0.0, 1.0, false, 90)
	_check(hawk.rotation.z < -0.5 and hawk.rotation.y < -0.5, "holding right banks right and turns right (roll %.2f, heading %.2f)" % [hawk.rotation.z, hawk.rotation.y])

	# Stall: slow and nose high, the wings stop lifting, the nose drops and it falls; diving recovers.
	hawk.global_position = Vector3(0.0, 600.0, 0.0)
	hawk.air_speed = hawk.stall_air_speed() * 0.6
	hawk.flight_pitch = 0.9
	hawk.controls.clear()
	await _frames(20)
	_check(hawk.stalled, "too slow and the wings stall")
	_check(hawk.flight_pitch < 0.9 - 0.1, "the nose drops in a stall (%.2f)" % hawk.flight_pitch)
	var fastest_fall := 0.0
	for i in 300:
		await physics_frame
		fastest_fall = maxf(fastest_fall, hawk._sink)
	_check(fastest_fall > 3.0, "it drops while stalled (%.1f m/s)" % fastest_fall)
	_check(not hawk.stalled, "the dive builds speed and the stall ends (%.0f m/s)" % hawk.air_speed)
	# A mech with both wings gone cannot hold the air.
	var broken := await _fly(hawk, 0.0, 0.0, 0.0, false, 5)
	broken.take_hit("wing_l", 9999.0)
	broken.take_hit("wing_r", 9999.0)
	await _frames(40)
	_check(broken.stalled and broken.global_position.y < 295.0, "with both wings gone it falls")
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
