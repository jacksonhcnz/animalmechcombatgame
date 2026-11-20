extends SceneTree
## A flyer that gets close to the ground settles onto its feet and walks slowly; Space takes off.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		printerr("FAIL: landing test timed out")
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


func _run() -> void:
	var range_scene: Node3D = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(range_scene)
	await _frames(40)
	range_scene.controller.set_physics_process(false)
	range_scene.start("hawk", "standard")
	await _frames(10)
	var hawk: Mech = range_scene.player
	var cruise := hawk.top_air_speed() * Points.flight("cruise_fraction")
	var walk_speed := float(hawk.def["landing"]["walk_speed"])

	# High up it just flies.
	hawk.controls.clear()
	await _frames(30)
	_check(not hawk.landed, "high above the ground it stays in the air")

	# Slowed down and low over open ground, it settles onto its feet.
	hawk.global_position = Vector3(0.0, 2.2, 150.0)
	hawk.rotation = Vector3.ZERO
	hawk.air_speed = cruise * 0.5
	hawk.flight_pitch = 0.0
	hawk.velocity = Vector3.ZERO
	await _frames(90)
	_check(hawk.landed, "close to the ground and slow, it lands")
	_check(hawk.is_on_floor(), "and stands on the ground")
	_check(absf(hawk.rotation.x) < 0.01 and absf(hawk.rotation.z) < 0.01, "level on its feet")

	# It walks, but slowly.
	var before := hawk.global_position
	hawk.controls.throttle = 1.0
	await _frames(120)
	var walked := hawk.global_position.distance_to(before)
	var speed := Vector2(hawk.velocity.x, hawk.velocity.z).length()
	_check(walked > 3.0, "it walks forward (%.1f m in two seconds)" % walked)
	_check(speed <= walk_speed * 1.05, "and only slowly (%.1f m/s, the limit is %.1f)" % [speed, walk_speed])
	_check(hawk.landed, "walking does not take off")
	hawk.controls.clear()

	# Space takes off again, and it does not just settle straight back down.
	hawk.controls.jump = true
	await _frames(3)
	hawk.controls.jump = false
	_check(not hawk.landed, "Space takes off")
	var start_y := hawk.global_position.y
	await _frames(90)
	_check(not hawk.landed, "it stays in the air after taking off")
	_check(hawk.global_position.y > start_y + 3.0, "and climbs (%.1f m up)" % (hawk.global_position.y - start_y))
	_check(not hawk.stalled, "without stalling")

	# Cruising fast just above the ground does not land: it must slow down first.
	hawk.global_position = Vector3(0.0, 2.2, 100.0)
	hawk.air_speed = cruise
	hawk.flight_pitch = 0.0
	await _frames(5)
	_check(not hawk.landed, "at cruise speed it skims instead of landing")

	print("landing_test: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
