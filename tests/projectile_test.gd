extends SceneTree
## Shots are projectiles: they take time to arrive, grenades fly an arc, rockets burst, and
## the data a server sends lets a client draw the same shot. Run with:
##   godot --headless --path . --script tests/projectile_test.gd

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		printerr("FAIL: projectile test timed out")
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
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)
	_range.controller.set_physics_process(false)
	_test_arc_math()
	await _test_bullet_takes_time()
	await _test_grenade_arc()
	await _test_rocket_splash()
	_test_info_round_trip()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_arc_math() -> void:
	var from := Vector3.ZERO
	var to := Vector3(0.0, 0.0, -100.0)
	var launch := Projectile.launch_velocity(from, to, 75.0, 22.0)
	_check(launch.y > 1.0, "a grenade is launched upwards to arc onto a level target")
	_check(is_equal_approx(launch.length(), 75.0), "a long lob uses full speed")
	var flat := Vector2(launch.x, launch.z).length()
	var angle := atan2(launch.y, flat)
	var landing := 75.0 * 75.0 * sin(2.0 * angle) / 22.0
	_check(absf(landing - 100.0) < 0.5, "the launch angle lands on the target (%.1f m)" % landing)
	var straight := Projectile.launch_velocity(from, to, 260.0, 0.0)
	_check(is_zero_approx(straight.y), "a bullet with no gravity flies straight at the aim point")
	var far := Projectile.launch_velocity(from, Vector3(0.0, 0.0, -900.0), 75.0, 22.0)
	_check(absf(far.normalized().y - sin(PI / 4.0)) < 0.01, "out of reach, a lob uses the 45 degree angle")
	var near := Projectile.launch_velocity(from, Vector3(0.0, -3.0, -25.0), 75.0, 22.0, 20.0)
	_check(atan2(near.y, Vector2(near.x, near.z).length()) > deg_to_rad(19.0) and near.length() < 75.0, "a close lob is thrown slower on a visible arc")


func _stand_back(target: Mech) -> Mech:
	var player: Mech = _range.player
	player.global_position = target.global_position + Vector3(0.0, 0.3, 25.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.aim_yaw = 0.0
	player.aim_pitch = 0.0
	await _frames(3)
	return player


func _shot(weapon_id: String, player: Mech, aim_point: Vector3) -> Projectile:
	var weapon_def := GameData.get_entry("weapons", weapon_id)
	var shot := Projectile.fire(weapon_def, player.global_position + Vector3(0.0, 6.0, 0.0), aim_point, player, 1.0)
	_range.add_child(shot)
	shot.global_position = player.global_position + Vector3(0.0, 6.0, 0.0)
	return shot


func _test_bullet_takes_time() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var before: float = target.damage.total_ratio()
	player.controls.fire_primary = true
	await physics_frame
	player.controls.fire_primary = false
	_check(target.damage.total_ratio() == before, "a bullet does not hit the instant it is fired")
	await _frames(40)
	_check(target.damage.total_ratio() < before, "the bullet arrives and damages the dummy")


func _test_grenade_arc() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var before: float = target.damage.total_ratio()
	var aim := target.global_position + Vector3(0.0, 3.0, 0.0)
	var shot := _shot("grenade_launcher", player, aim)
	var start_y := shot.global_position.y
	var peak := start_y
	for i in 240:
		await physics_frame
		if not is_instance_valid(shot) or not shot.is_inside_tree():
			break
		peak = maxf(peak, shot.global_position.y)
	_check(peak > start_y + 1.0, "a grenade rises on an arc (peak %.1f above the muzzle)" % (peak - start_y))
	_check(target.damage.total_ratio() < before, "the grenade lands on the target and damages it")


func _test_rocket_splash() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var before: float = target.damage.total_ratio()
	var spot := Vector3(target.global_position.x + 4.0, 0.0, target.global_position.z)
	var shot := _shot("rocket_pod", player, spot)
	for i in 120:
		await physics_frame
		if not is_instance_valid(shot):
			break
	_check(not is_instance_valid(shot), "the rocket burst on the ground")
	_check(target.damage.total_ratio() < before, "the rocket's blast hurts a mech standing nearby")


func _test_info_round_trip() -> void:
	var player: Mech = _range.player
	var shot := Projectile.fire(GameData.get_entry("weapons", "rocket_pod"), Vector3.ZERO, Vector3(0, 0, -50), player, 1.0)
	var copy := Projectile.from_info(shot.to_info())
	_check(copy.id == shot.id and copy.model == "rocket", "a client copy has the same id and model")
	_check(copy.velocity.is_equal_approx(shot.velocity) and not copy.authoritative, "the copy flies the same way but deals no damage")
	shot.free()
	copy.free()
