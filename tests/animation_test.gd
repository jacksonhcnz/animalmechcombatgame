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
		var z: float = hawk.pivots["wing_l"].rotation.z
		min_z = minf(min_z, z)
		max_z = maxf(max_z, z)
	_check(max_z - min_z > deg_to_rad(20.0), "hawk wings flap (range %.2f rad)" % (max_z - min_z))
	hawk.take_hit("wing_l", 9999.0)
	await _frames(120)
	var drooped: float = hawk.pivots["wing_l"].rotation.z
	_check(is_equal_approx(drooped, deg_to_rad(55.0)), "a destroyed wing droops (%.2f rad)" % drooped)
	hawk.controls.turn = 1.0
	await _frames(60)
	hawk.controls.turn = 0.0
	_check(hawk.rig.rotation.z < -0.1, "hawk banks into a right turn")

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

	# Gimbal gun mount: the mast turns and the bar tilts with the aim; losing the mast knocks out both guns.
	lion.aim_yaw = 0.5
	lion.aim_pitch = 0.2
	await _frames(3)
	_check(is_equal_approx(lion.pivots["mast"].rotation.y, 0.5), "gun mast turns with the aim")
	_check(is_equal_approx(lion.pivots["crossbar"].rotation.x, 0.2), "gimbal bar tilts with the aim")
	_check(lion.damage.mount_online("gun_l") and lion.damage.mount_online("gun_r"), "both guns work while the mast is intact")
	lion.take_hit("mast", 9999.0)
	_check(not lion.damage.mount_online("gun_l") and not lion.damage.mount_online("gun_r"), "destroying the mast knocks out both guns")
	_check(lion.damage.mount_online("jaw"), "the jaw still works without the mast")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
