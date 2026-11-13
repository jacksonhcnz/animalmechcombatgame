extends SceneTree
## Loads the test range and plays a few seconds of it headlessly: aims at a dummy, fires,
## and checks damage, ammo, knockout, camera rules and HUD rules. Run with:
##   godot --headless --path . --script tests/smoke_test.gd
## Exits with a non-zero code if any check fails.

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	# If something stalls, fail instead of hanging forever.
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: smoke test timed out")
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


## Puts the player 25 m in front of a dummy, facing it, so shots land on it.
func _line_up(target: Mech, extra_height: float = 0.0) -> void:
	var player: Mech = _range.player
	player.global_position = target.global_position + Vector3(0.0, extra_height + 0.3, 25.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.aim_yaw = 0.0
	player.aim_pitch = 0.0
	await _frames(3)


func _fire_for(frames: int, primary: bool = false, secondary: bool = false, melee: bool = false) -> void:
	var c: MechControls = _range.player.controls
	for i in frames:
		c.fire_primary = primary
		c.fire_secondary = secondary
		c.fire_melee = melee
		await physics_frame
	c.fire_primary = false
	c.fire_secondary = false
	c.fire_melee = false


func _run() -> void:
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)
	# The tests drive the mech's controls directly, so stop the controller overwriting them.
	_range.controller.set_physics_process(false)

	print("-- _test_ground_movement")
	await _test_ground_movement()
	print("-- _test_shooting_and_ammo")
	await _test_shooting_and_ammo()
	print("-- _test_knockout")
	await _test_knockout()
	print("-- _test_destroy_and_respawn")
	await _test_destroy_and_respawn()
	print("-- _test_hardcore")
	await _test_hardcore()
	print("-- _test_arcade")
	await _test_arcade()
	print("-- _test_flying")
	await _test_flying()
	print("-- _test_timer")
	await _test_timer()

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_ground_movement() -> void:
	var player: Mech = _range.player
	_check(player != null and player.def["name"] == "Lion", "range starts the player as the Lion")
	_check(_range.targets.size() == 6, "range spawns six dummy targets")
	_check(player.is_on_floor(), "the lion stands on the ground")
	var start := player.global_position
	player.controls.throttle = 1.0
	await _frames(60)
	player.controls.throttle = 0.0
	_check(player.global_position.z < start.z - 3.0, "holding forward moves the lion forward (-Z)")
	var heading_before := player.rotation.y
	player.controls.turn = 1.0
	await _frames(30)
	player.controls.turn = 0.0
	_check(player.rotation.y < heading_before, "turning right rotates clockwise")
	player.controls.aim_yaw_delta = 10.0
	await _frames(2)
	_check(is_equal_approx(player.aim_yaw, deg_to_rad(100.0)), "aim yaw stops at the twist limit")
	player.controls.center_aim = true
	await _frames(2)
	_check(player.aim_yaw == 0.0, "centre aim resets the head")


func _test_shooting_and_ammo() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var player: Mech = _range.player
	var target: Mech = _range.targets[0]
	await _line_up(target)

	var hp_before: float = target.damage.total_ratio()
	var ammo_before: int = player.weapons[0].ammo
	await _fire_for(30, true)
	_check(player.weapons[0].ammo < ammo_before, "firing the autocannon spends ammo under standard rules")
	_check(target.damage.total_ratio() < hp_before, "autocannon fire damages the dummy")

	var shots_taken := ammo_before - player.weapons[0].ammo
	_check(shots_taken > 0 and shots_taken <= 30, "fire rate limits shots (%d shots in 30 frames)" % shots_taken)

	# A rocket pod shot should be limited by its cooldown, not fired every frame.
	var rockets_before: int = player.weapons[1].ammo
	await _fire_for(10, false, true)
	_check(rockets_before - player.weapons[1].ammo == 1, "the rocket pod fires once and then cools down")

	# Practice rules: no ammo limit.
	_range.start("lion", "practice")
	await _frames(10)
	player = _range.player
	var practice_ammo: int = player.weapons[0].ammo
	await _fire_for(20, true)
	_check(player.weapons[0].ammo == practice_ammo, "practice rules spend no ammo")

	# Empty weapon stops firing.
	_range.start("lion", "standard")
	await _frames(10)
	player = _range.player
	target = _range.targets[0]
	await _line_up(target)
	player.weapons[0].ammo = 0
	var ratio := target.damage.total_ratio()
	await _fire_for(20, true)
	_check(target.damage.total_ratio() == ratio, "an empty autocannon does no damage")


func _test_knockout() -> void:
	_range.start("velociraptor", "practice")
	await _frames(10)
	var player: Mech = _range.player
	var target: Mech = _range.targets[0]
	await _line_up(target)

	# Cripple the dummy's own weapon arm and confirm that mount goes offline.
	var dummy: Mech = _range.targets[1]
	_check(dummy.damage.mount_online("gun_l"), "a fresh dummy has its left gun online")
	dummy.take_hit("shoulder_l", 500.0)
	_check(not dummy.damage.mount_online("gun_l"), "hitting the shoulder joint knocks the arm gun offline")

	# The player's own offline weapon must not fire.
	player.take_hit("shoulder_l", 500.0)
	var ratio := target.damage.total_ratio()
	await _fire_for(20, true)
	_check(target.damage.total_ratio() == ratio, "an offline weapon does not fire")
	_check(player.weapons[1].ammo > 0, "the other weapon is unaffected")


func _test_destroy_and_respawn() -> void:
	_range.start("lion", "practice")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var destroyed_seen := [false]
	target.destroyed.connect(func(_m: Mech) -> void: destroyed_seen[0] = true)
	await _line_up(target, 0.6)
	await _fire_for(150, true)
	_check(destroyed_seen[0], "sustained fire destroys a dummy")
	_check(target.is_dead(), "a destroyed dummy is dead")
	await create_timer(_range.RESPAWN_DELAY + 0.5).timeout
	await _frames(5)
	_check(_range.targets.size() == 6, "a destroyed dummy is replaced")
	var alive := 0
	for t in _range.targets:
		if not t.is_dead():
			alive += 1
	_check(alive == 6, "all six dummies are alive again")


func _test_hardcore() -> void:
	_range.start("lion", "hardcore")
	await _frames(10)
	var player: Mech = _range.player
	_check(not _range.hud.panels_visible(), "hardcore hides the HUD")
	_check(not _range.hud.crosshair_visible(), "hardcore hides the crosshair")
	_check(not player.view_third_person, "hardcore starts in cockpit view")
	player.toggle_view()
	_check(not player.view_third_person, "hardcore refuses to switch to third person")
	_check(player.cockpit_camera.current, "the cockpit camera is the active one")
	_check(not player.third_person_camera.current, "the third-person camera is not active")
	_check(player.damage.max_health["torso"] < 180.0, "hardcore lowers durability")

	_range.start("lion", "standard")
	await _frames(10)
	player = _range.player
	_check(_range.hud.panels_visible() and _range.hud.crosshair_visible(), "standard shows HUD and crosshair")
	player.toggle_view()
	_check(player.view_third_person and player.third_person_camera.current, "standard allows third person")
	player.toggle_view()
	_check(not player.view_third_person and player.cockpit_camera.current, "toggling again returns to the cockpit")

	# Friendly fire: same-team damage is ignored unless the ruleset allows it.
	var ally := Mech.create("lion", Ruleset.load_id("standard"))
	_range.add_child(ally)
	ally.team = 1
	var result := ally.take_hit("torso", 50.0, player)
	_check(result["applied"] == 0.0, "no friendly fire under standard rules")
	var hard_rules := Ruleset.load_id("hardcore")
	var ally2 := Mech.create("lion", hard_rules)
	_range.add_child(ally2)
	ally2.team = 1
	var attacker := Mech.create("lion", hard_rules)
	_range.add_child(attacker)
	attacker.team = 1
	var hard := ally2.take_hit("torso", 50.0, attacker)
	_check(hard["applied"] > 0.0, "friendly fire works under hardcore rules")
	ally.queue_free()
	ally2.queue_free()
	attacker.queue_free()


func _test_arcade() -> void:
	_range.start("lion", "arcade")
	await _frames(10)
	var player: Mech = _range.player
	var target: Mech = _range.targets[0]
	await _line_up(target, 0.6)
	await _fire_for(30, true)
	_check(target.damage.total_ratio() < 1.0, "arcade damage still lands")
	_check(not target.damage.is_part_disabled("head"), "arcade has no per-part knockout")
	_check(_range.hud.panels_visible(), "arcade shows the HUD")
	player.take_hit("pod_l", 5000.0)
	_check(player.is_dead(), "the shared pool can still kill the player")


func _test_flying() -> void:
	_range.start("hawk", "practice")
	await _frames(10)
	var player: Mech = _range.player
	_check(player.is_flying(), "the hawk flies")
	var start_y := player.global_position.y
	await _frames(30)
	_check(absf(player.global_position.y - start_y) < 1.0, "a healthy hawk holds its altitude")
	player.controls.vertical = 1.0
	await _frames(60)
	player.controls.vertical = 0.0
	_check(player.global_position.y > start_y + 3.0, "the hawk climbs when asked")
	player.global_position.y = _range.ALTITUDE_LIMIT - 1.0
	player.controls.vertical = 1.0
	await _frames(90)
	player.controls.vertical = 0.0
	_check(player.global_position.y <= _range.ALTITUDE_LIMIT + 0.01, "the hawk cannot pass the altitude limit")

	player.global_position.y = 40.0
	player.velocity = Vector3.ZERO
	player.take_hit("wing_l", 1000.0)
	player.take_hit("wing_r", 1000.0)
	var height := player.global_position.y
	await _frames(60)
	_check(player.global_position.y < height - 3.0, "a hawk with both wings gone loses altitude")


func _test_timer() -> void:
	_range.start("lion", "standard")
	await _frames(5)
	var before: float = _range._time_left
	_check(before > 590.0 and before <= 600.0, "a standard match starts at ten minutes")
	await _frames(60)
	_check(_range._time_left < before, "the match clock counts down")
	_range._time_left = 0.05
	await _frames(20)
	_check(_range._match_over, "the match ends when time runs out")
	_check(not _range.controller.enabled, "the player cannot act after time is up")
	_range.start("lion", "practice")
	await _frames(5)
	_check(_range._time_left == 0.0 and not _range._match_over, "practice is untimed")
