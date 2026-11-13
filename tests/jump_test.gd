extends SceneTree
## Checks jumping for ground mechs. Run with:
##   godot --headless --path . --script tests/jump_test.gd

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: jump test timed out")
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


## Holds jump until the mech has landed again. Returns the highest point reached above the start.
func _jump_and_land(mech: Mech) -> float:
	var start_y := mech.global_position.y
	var peak := 0.0
	mech.controls.jump = true
	await physics_frame
	mech.controls.jump = false
	for i in 240:
		await physics_frame
		peak = maxf(peak, mech.global_position.y - start_y)
		if mech.is_on_floor() and i > 5:
			break
	return peak


func _start(mech_id: String, ruleset_id: String = "practice") -> Mech:
	_range.start(mech_id, ruleset_id)
	await _frames(40)
	_range.controller.set_physics_process(false)
	return _range.player


func _run() -> void:
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)

	var lion := await _start("lion")
	_check(lion.can_jump(), "a lion standing on the ground can jump")
	var expected := pow(float(lion.def["base"]["jump_speed"]), 2.0) / (2.0 * Mech.GRAVITY)
	var peak := await _jump_and_land(lion)
	_check(absf(peak - expected) < 0.5, "the lion jumps about %.1f m (reached %.2f m)" % [expected, peak])
	_check(lion.is_on_floor(), "the lion lands")

	# Cooldown: holding jump does not bounce at once, but it recovers.
	lion.controls.jump = true
	await _frames(3)
	_check(not lion.can_jump() or lion.velocity.y > 0.0, "jump has a cooldown after landing")
	lion.controls.jump = false
	await _frames(70)
	_check(lion.can_jump(), "the lion can jump again after the cooldown")

	# No second jump in mid-air.
	lion.controls.jump = true
	await _frames(10)
	var rising_speed := lion.velocity.y
	await _frames(10)
	_check(lion.velocity.y < rising_speed, "no extra jump in mid-air")
	lion.controls.jump = false
	await _frames(120)

	# A damaged mech jumps lower.
	var raptor := await _start("velociraptor")
	var healthy_peak := await _jump_and_land(raptor)
	await _frames(60)
	raptor.take_hit("knee_l", 9999.0)
	await _frames(60)
	var hurt_peak := await _jump_and_land(raptor)
	_check(hurt_peak < healthy_peak - 0.2, "a crippled raptor jumps lower (%.2f vs %.2f m)" % [hurt_peak, healthy_peak])
	_check(healthy_peak > expected, "the raptor out-jumps the lion (%.2f vs %.2f m)" % [healthy_peak, expected])

	# A ruleset can turn jumping off.
	var no_jump := await _start("lion")
	no_jump.rules.jumping = false
	_check(not no_jump.can_jump(), "a ruleset can switch jumping off")

	# Flying mechs do not jump.
	var hawk := await _start("hawk")
	_check(not hawk.can_jump(), "flying mechs do not jump")

	# The landing dip pushes the body down, then it recovers.
	var dip_lion := await _start("lion")
	dip_lion.controls.jump = true
	await physics_frame
	dip_lion.controls.jump = false
	var lowest := 0.0
	for i in 120:
		await physics_frame
		lowest = minf(lowest, dip_lion.rig.position.y)
	_check(lowest < -0.1, "the body dips on landing (%.2f m)" % lowest)
	await _frames(90)
	_check(absf(dip_lion.rig.position.y) < 0.1, "the body recovers after the dip")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
