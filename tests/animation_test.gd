extends SceneTree
## Checks procedural animation: legs swing while walking, flap while flying, limp and droop
## when damaged, collapse on death, hitboxes follow limbs, and head bob is adjustable. Run with:
##   godot --headless --path . --script tests/animation_test.gd

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: animation test timed out")
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


func _walk(mech: Mech, frames: int) -> float:
	## Walks forward and returns the largest leg swing (radians) seen.
	var peak := 0.0
	mech.controls.throttle = 1.0
	for i in frames:
		await physics_frame
		peak = maxf(peak, absf(mech.pivots["leg_l"].rotation.x) if mech.pivots.has("leg_l") else absf(mech.pivots["leg_fl"].rotation.x))
	mech.controls.throttle = 0.0
	return peak


func _part_index(mech: Mech, id: String) -> int:
	for i in mech.def["parts"].size():
		if mech.def["parts"][i]["id"] == id:
			return i
	return -1


func _run() -> void:
	GameSettings.set_head_bob(0.4)
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)
	_range.controller.set_physics_process(false)

	# Head bob setting.
	GameSettings.set_head_bob(2.0)
	_check(is_equal_approx(GameSettings.head_bob, 1.0), "head bob is clamped to 1")
	GameSettings.set_head_bob(-1.0)
	_check(is_equal_approx(GameSettings.head_bob, 0.0), "head bob is clamped to 0")
	GameSettings.set_head_bob(0.4)

	# Ground mech: still, then walking.
	_range.start("velociraptor", "practice")
	await _frames(40)
	var player: Mech = _range.player
	_range.controller.set_physics_process(false)
	_check(absf(player.pivots["leg_l"].rotation.x) < 0.01, "legs are still when standing")
	player.controls.aim_yaw_delta = 10.0
	await _frames(2)
	_check(is_equal_approx(player.aim_yaw, deg_to_rad(110.0)), "the raptor's aim stops at its twist limit")
	# The head turns to face where the pilot looks, but only as far as its neck allows.
	player.aim_yaw = 0.8
	player.aim_pitch = 0.2
	await _frames(40)
	_check(absf(player.pivots["head"].rotation.y - 0.8) < 0.02, "the raptor's head turns to face the aim (%.2f rad)" % player.pivots["head"].rotation.y)
	player.aim_yaw = deg_to_rad(108.0)
	await _frames(60)
	_check(is_equal_approx(player.pivots["head"].rotation.y, deg_to_rad(100.0)), "the raptor's head stops at its own limit while the aim goes on (%.2f rad)" % player.pivots["head"].rotation.y)
	player.aim_yaw = 0.0
	player.aim_pitch = 0.0
	await _frames(60)
	_check(absf(player.pivots["head"].rotation.y) < 0.02, "the head comes back to centre")
	# Skeleton: thigh, knee, shin, ankle, foot, sickle claw hang from one another.
	_check(player.pivots["shin_l"].get_parent() == player.pivots["knee_l"], "the shin hangs from the knee")
	_check(player.pivots["metatarsus_l"].get_parent() == player.pivots["shin_l"], "the ankle bone hangs from the shin")
	_check(player.pivots["foot_l"].get_parent() == player.pivots["metatarsus_l"], "the foot hangs from the ankle bone")
	_check(player.pivots["sickle_l"].get_parent() == player.pivots["foot_l"], "the sickle claw is on the foot")
	_check(player.pivots["forearm_l"].get_parent() == player.pivots["arm_l"], "the forearm hangs from the upper arm")
	_check(player.damage.mount_online("gun_l") and player.damage.mount_online("kick"), "raptor guns and kick start online")
	var shin_fold := 0.0
	var shin_stretch := 0.0
	player.controls.throttle = 1.0
	for i in 90:
		await physics_frame
		shin_fold = minf(shin_fold, player.pivots["shin_l"].rotation.x)
		shin_stretch = maxf(shin_stretch, player.pivots["shin_l"].rotation.x)
	player.controls.throttle = 0.0
	_check(shin_fold < deg_to_rad(-15.0), "the shin folds to lift the foot (%.2f rad)" % shin_fold)
	_check(shin_stretch < 0.001, "the shin never bends the wrong way")
	_check(absf(player.pivots["tail_tip"].rotation.y) <= deg_to_rad(10.0) + 0.001, "the raptor's tail stays stiff")
	var before_leg: float = player.damage.health["leg_r"]
	player.take_hit("sickle_r", 10.0)
	_check(player.damage.health["leg_r"] < before_leg, "a hit on the sickle claw counts against the leg")
	var peak := await _walk(player, 90)
	_check(peak > deg_to_rad(10.0), "legs swing while walking (peak %.2f rad)" % peak)
	_check(is_equal_approx(player.pivots["leg_l"].rotation.x + player.pivots["leg_r"].rotation.x, 0.0) or absf(player.pivots["leg_l"].rotation.x + player.pivots["leg_r"].rotation.x) < 0.05, "legs swing in opposite directions")

	# Hitbox follows the leg.
	player.controls.throttle = 1.0
	var moved := false
	var leg_hitbox: Node3D = player.get_node("Rig").find_child("Hitbox_leg_l", true, false)
	var first := leg_hitbox.global_position - player.global_position
	for i in 30:
		await physics_frame
		if (leg_hitbox.global_position - player.global_position).distance_to(first) > 0.2:
			moved = true
	player.controls.throttle = 0.0
	_check(moved, "leg hitbox moves with the animated leg")

	# Head bob only moves the camera by its share.
	GameSettings.set_head_bob(0.0)
	await _frames(5)
	var steady_y := player._aim_pivot.position.y
	_check(is_equal_approx(steady_y, player._aim_base_y), "head bob 0 keeps the camera steady")
	GameSettings.set_head_bob(0.4)

	# Crippled leg: weaker swing than a healthy one.
	player.take_hit("knee_l", 9999.0)
	await _frames(40)
	player.controls.throttle = 1.0
	var healthy := 0.0
	var hurt := 0.0
	for i in 90:
		await physics_frame
		hurt = maxf(hurt, absf(player.pivots["leg_l"].rotation.x))
		healthy = maxf(healthy, absf(player.pivots["leg_r"].rotation.x))
	player.controls.throttle = 0.0
	_check(hurt < healthy * 0.7, "a crippled leg swings less (%.2f vs %.2f)" % [hurt, healthy])

	# Death: the body collapses.
	var rest_y: float = player.rig.position.y
	player.take_hit("torso", 99999.0)
	await _frames(80)
	_check(player.is_dead(), "player died")
	_check(player.rig.position.y < rest_y - 0.5, "a dead mech collapses")

	# Flying mech: wings flap, then droop when destroyed.
	_range.start("hawk", "practice")
	await _frames(40)
	var hawk: Mech = _range.player
	_range.controller.set_physics_process(false)
	var min_z := 99.0
	var max_z := -99.0
	for i in 120:
		await physics_frame
		# The wing is a chain, so the tip's real angle is the sum of the three joints.
		var z: float = hawk.pivots["wing_l"].rotation.z + hawk.pivots["wing_mid_l"].rotation.z + hawk.pivots["wing_tip_l"].rotation.z
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	_check(max_z - min_z > deg_to_rad(20.0), "hawk wings flap (range %.2f rad)" % (max_z - min_z))
	hawk.take_hit("wing_l", 9999.0)
	await _frames(120)
	var drooped: float = hawk.pivots["wing_l"].rotation.z + hawk.pivots["wing_mid_l"].rotation.z + hawk.pivots["wing_tip_l"].rotation.z
	_check(is_equal_approx(drooped, deg_to_rad(35.0 + 20.0 + 12.0)), "a destroyed wing droops all the way along (%.2f rad)" % drooped)
	hawk.controls.turn = 1.0
	await _frames(60)
	hawk.controls.turn = 0.0
	_check(hawk.rig.rotation.z < -0.1, "hawk banks into a right turn")

	# The hawk's neck and head share the turn between them, up to the hawk's limit.
	hawk.aim_yaw = 1.0
	await _frames(60)
	var turned: float = hawk.pivots["neck_a"].rotation.y + hawk.pivots["neck_b"].rotation.y + hawk.pivots["head"].rotation.y
	_check(absf(turned - 1.0) < 0.03, "the hawk's neck and head together turn to face the aim (%.2f rad)" % turned)
	_check(hawk.pivots["neck_a"].rotation.y > 0.2 and hawk.pivots["head"].rotation.y > 0.2, "both the neck and the head take part in the turn")
	hawk.aim_yaw = 0.0
	await _frames(60)
	# Bird skeleton: the wing is a wave that travels outwards, and the neck keeps the head level.
	_check(hawk.pivots["wing_tip_r"].get_parent() == hawk.pivots["wing_mid_r"], "the primaries hang from the forearm")
	_check(hawk.pivots["wing_mid_r"].get_parent() == hawk.pivots["wing_r"], "the forearm hangs from the upper wing")
	_check(hawk.pivots["head"].get_parent() == hawk.pivots["neck_b"], "the head sits on the neck")
	hawk.take_hit("wing_tip_r", 10.0)
	_check(hawk.damage.health["wing_r"] < hawk.damage.max_health["wing_r"], "a hit on the primaries counts against the wing")
	hawk.controls.vertical = 1.0
	await _frames(100)
	_check(hawk.rig.rotation.x > 0.05, "the hawk pitches up as it climbs")
	_check(hawk.pivots["neck_a"].rotation.x < -0.02, "the neck turns against the pitch to keep the head level")
	hawk.controls.vertical = 0.0
	# Without a lag the tip would just be a scaled copy of the root; with one it falls out of step.
	var out_of_step := 0.0
	for i in 120:
		await physics_frame
		var inner: float = hawk.pivots["wing_r"].rotation.z - deg_to_rad(4.0)
		var tip: float = hawk.pivots["wing_tip_r"].rotation.z
		out_of_step = maxf(out_of_step, absf(tip - inner * 16.0 / 14.0))
	_check(out_of_step > deg_to_rad(4.0), "the wingtip lags behind the wing root (the flap travels outwards)")

	# Belly gimbal: it turns and tilts with the aim, carries both guns, and is the guns' weak point.
	hawk.aim_yaw = 0.7
	hawk.aim_pitch = -0.3
	await _frames(5)
	_check(is_equal_approx(hawk.pivots["mast"].rotation.y, 0.7), "the belly gimbal turns with the aim")
	_check(is_equal_approx(hawk.pivots["crossbar"].rotation.x, -0.3), "the gimbal bar tilts down with the aim")
	_check(hawk.pivots["pod_l"].get_parent() == hawk.pivots["crossbar"], "the guns hang from the gimbal bar")
	_check(hawk.pivots["mast"].position.y < -0.5, "the gimbal sits below the body")
	_check(hawk.damage.mount_online("gun_l") and hawk.damage.mount_online("gun_r"), "both guns work although the left wing is gone")
	hawk.take_hit("mast", 9999.0)
	_check(not hawk.damage.mount_online("gun_l") and not hawk.damage.mount_online("gun_r"), "losing the belly gimbal knocks out both guns")
	_check(hawk.damage.mount_online("talon"), "the talons still work without the gimbal")
	hawk.aim_yaw = 0.0
	hawk.aim_pitch = 0.0

	# Lion: all four legs animate.
	_range.start("lion", "practice")
	await _frames(40)
	var lion: Mech = _range.player
	_range.controller.set_physics_process(false)
	var lion_peak := await _walk(lion, 90)
	_check(lion_peak > deg_to_rad(10.0), "lion legs swing while walking")
	# Feline gait: four evenly spaced footfalls, and the body sinks low while prowling.
	var phases: Array[float] = []
	for id in ["leg_rl", "leg_fl", "leg_rr", "leg_fr"]:
		phases.append(float(lion.def["parts"][_part_index(lion, id)]["anim"]["walk"]["phase"]))
	_check(phases == [0.0, 0.25, 0.5, 0.75], "lion walks in a lateral-sequence gait")
	lion.controls.throttle = 1.0
	await _frames(60)
	_check(lion.rig.position.y < -0.1, "lion crouches while prowling (%.2f m)" % lion.rig.position.y)
	lion.controls.throttle = 0.0

	# Skeleton: each leg is a chain of segments that fold at the joints to lift the foot.
	_check(lion.pivots["forearm_fl"].get_parent() == lion.pivots["knee_fl"], "the forearm hangs from the elbow")
	_check(lion.pivots["knee_fl"].get_parent() == lion.pivots["leg_fl"], "the elbow hangs from the upper arm")
	_check(lion.pivots["leg_fl"].get_parent() == lion.pivots["scapula_fl"], "the upper arm hangs from the shoulder blade")
	_check(lion.pivots["foot_rl"].get_parent() == lion.pivots["shin_rl"], "the foot hangs from the shin")
	lion.controls.throttle = 1.0
	var most_fold := 0.0
	var most_stretch := 0.0
	var spine := 0.0
	var blade := 0.0
	for i in 120:
		await physics_frame
		most_fold = minf(most_fold, lion.pivots["forearm_fl"].rotation.x)
		most_stretch = maxf(most_stretch, lion.pivots["forearm_fl"].rotation.x)
		spine = maxf(spine, absf(lion.pivots["hips"].rotation.y))
		blade = maxf(blade, absf(lion.pivots["scapula_fl"].rotation.x))
	lion.controls.throttle = 0.0
	_check(most_fold < deg_to_rad(-20.0), "the forearm folds to lift the paw (%.2f rad)" % most_fold)
	_check(most_stretch < 0.001, "the forearm never bends the wrong way")
	_check(spine > deg_to_rad(1.0), "the spine twists while walking (%.2f rad)" % spine)
	_check(blade > deg_to_rad(3.0), "the shoulder blade swings with the stride (%.2f rad)" % blade)
	var leg_before: float = lion.damage.health["leg_fl"]
	lion.take_hit("paw_fl", 10.0)
	_check(lion.damage.health["leg_fl"] < leg_before, "a hit on the paw counts against the leg it belongs to")
	_check(lion.damage.is_cosmetic("paw_fl") and not lion.damage.health.has("paw_fl"), "the paw has no health of its own")

	# The lion's head follows the aim up to 110 degrees, though its gimbal and view keep turning.
	lion.aim_yaw = 1.0
	await _frames(40)
	_check(absf(lion.pivots["head"].rotation.y - 1.0) < 0.02, "the lion's head turns to face the aim")
	lion.aim_yaw = 3.0
	await _frames(80)
	_check(is_equal_approx(lion.pivots["head"].rotation.y, deg_to_rad(110.0)), "the lion's head stops at 110 degrees")
	_check(is_equal_approx(lion.pivots["mast"].rotation.y, 3.0), "while the gimbal keeps turning with the aim")
	lion.aim_yaw = 0.5
	await _frames(60)
	# Gimbal gun mount: the mast turns and the bar tilts with the aim; losing the mast knocks out both guns.
	lion.aim_yaw = 0.5
	lion.aim_pitch = 0.2
	await _frames(3)
	_check(is_equal_approx(lion.pivots["mast"].rotation.y, 0.5), "gun mast turns with the aim")
	# The gimbal spins a full circle: turning past straight behind carries on round, never stops.
	lion.controls.aim_yaw_delta = 2.6
	await _frames(2)
	lion.controls.aim_yaw_delta = 2.6
	await _frames(2)
	_check(is_equal_approx(lion.aim_yaw, wrapf(0.5 + 5.2, -PI, PI)), "the lion's aim spins past straight behind (%.2f rad)" % lion.aim_yaw)
	_check(is_equal_approx(lion.pivots["mast"].rotation.y, lion.aim_yaw), "the gun mast follows the aim all the way round")
	lion.aim_yaw = 0.5
	_check(is_equal_approx(lion.pivots["crossbar"].rotation.x, 0.2), "gimbal bar tilts with the aim")
	_check(lion.damage.mount_online("gun_l") and lion.damage.mount_online("gun_r"), "both guns work while the mast is intact")
	lion.take_hit("mast", 9999.0)
	_check(not lion.damage.mount_online("gun_l") and not lion.damage.mount_online("gun_r"), "destroying the mast knocks out both guns")
	_check(lion.damage.mount_online("jaw"), "the jaw still works without the mast")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
