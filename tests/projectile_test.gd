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
	await _test_sniper_knockout()
	await _test_flak_airburst()
	await _test_flak_hold_and_release()
	await _test_bomb()
	await _test_ion_cannon()
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


func _test_sniper_knockout() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var sniper := GameData.get_entry("weapons", "sniper_cannon")
	_check(bool(sniper.get("knockout", false)), "the sniper cannon is a knockout weapon")
	var limb := "front_left_leg" if target.damage.health.has("front_left_leg") else ""
	for id in target.damage.health:
		if id != "head" and id != "torso" and id != "hips" and not target.damage.is_part_disabled(id):
			limb = id
			break
	var head_hits := target.damage.knockout_amount("head")
	_check(head_hits > target.damage.health["head"], "a head hit is enough to knock the pilot out")
	_check(target.damage.knockout_amount("torso") < 0.0, "the torso is too big for a one shot knockout")
	target.take_knockout(limb, 38.0, player)
	_check(target.damage.is_part_disabled(limb), "one sniper hit puts out the limb it hits (%s)" % limb)
	target.take_knockout("head", 38.0, player)
	_check(target.damage.is_destroyed(), "a head shot knocks the mech out")


func _test_flak_airburst() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var flak := GameData.get_entry("weapons", "flak_burst")
	var weapon := WeaponState.new("test", flak)
	_check(weapon.is_charged() and is_zero_approx(weapon.burst_height(0.0)), "uncocked flak bursts at the aim point")
	_check(is_equal_approx(weapon.burst_height(99.0), float(flak["charge"]["max_height"])), "fully cocked flak bursts at its top height")
	var held := weapon.burst_height(0.6)
	_check(held > 0.0 and held < weapon.burst_height(1.2), "the longer it is held, the higher it bursts")
	var aim := target.global_position + Vector3(0.0, 1.0, 0.0)
	var shot := Projectile.fire(flak, player.global_position + Vector3(0.0, 6.0, 0.0), aim, player, 1.0, 10.0)
	_range.add_child(shot)
	shot.global_position = player.global_position + Vector3(0.0, 6.0, 0.0)
	var burst: Array[Vector3] = []
	shot.finished.connect(func(_id: int, pos: Vector3, _exploded: bool) -> void: burst.append(pos))
	for i in 200:
		await physics_frame
		if not is_instance_valid(shot):
			break
	var burst_at: Vector3 = burst[0] if not burst.is_empty() else Vector3.ZERO
	_check(burst_at.y > aim.y + 8.0, "cocked flak bursts in the air above the target (%.1f m up)" % (burst_at.y - aim.y))
	_check(burst_at.distance_to(aim + Vector3.UP * 10.0) < 1.5, "it bursts at the height it was cocked to")


func _test_flak_hold_and_release() -> void:
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var weapon: WeaponState
	for w in player.weapons:
		if w.slot() == "secondary":
			weapon = w
	weapon.def = GameData.get_entry("weapons", "flak_burst")
	weapon.ammo = 50
	var seen: Array[Dictionary] = []
	player.projectile_launched.connect(func(info: Dictionary) -> void: seen.append(info))
	player.controls.fire_secondary = true
	await _frames(30)
	_check(seen.is_empty(), "holding the button cocks the flak without firing it")
	_check(weapon.charge_ratio() > 0.1, "the flak charge builds while held")
	player.controls.fire_secondary = false
	await _frames(2)
	_check(seen.size() == 1, "letting go fires the flak shell")
	_check(weapon.charge_time == 0.0, "the charge resets after firing")


func _test_bomb() -> void:
	_range.start("hawk", "standard")
	await _frames(10)
	var hawk: Mech = _range.player
	var target: Mech = _range.targets[0]
	var bomb: WeaponState
	for w in hawk.weapons:
		if w.slot() == "bomb":
			bomb = w
	_check(bomb != null and bomb.def["id"] == "air_bomb", "the hawk carries an air bomb on its own slot")
	_check(not Loadout.options("primary").has("air_bomb") and not Loadout.options("secondary").has("air_bomb"), "the bomb is not a loadout choice")
	hawk.global_position = Vector3(target.global_position.x, 45.0, target.global_position.z + 140.0)
	hawk.rotation = Vector3.ZERO
	hawk.air_speed = 40.0
	hawk.velocity = Vector3(0.0, 0.0, -40.0)
	var spot: Variant = hawk.predict_drop(bomb)
	_check(spot != null and (spot as Vector3).z < hawk.global_position.z - 30.0, "the sight shows the bomb landing ahead of the plane, not straight below")
	var seen: Array[Dictionary] = []
	hawk.projectile_launched.connect(func(info: Dictionary) -> void: seen.append(info))
	target.global_position = Vector3(spot.x, 0.5, spot.z)
	var before: float = target.damage.total_ratio()
	hawk.controls.fire_bomb = true
	await physics_frame
	hawk.controls.fire_bomb = false
	_check(seen.size() == 1 and seen[0]["model"] == "bomb", "firing drops a bomb")
	_check(absf((seen[0]["vel"] as Vector3).z + 40.0) < 3.0 and (seen[0]["vel"] as Vector3).y < 0.0, "the bomb carries the plane's speed and starts to fall")
	await _frames(200)
	_check(target.damage.total_ratio() < before, "the bomb lands where the sight showed and its blast hurts the mech there")
	_check(bomb.ammo == int(bomb.def["ammo"]) - 1 or bomb.ammo < int(bomb.def["ammo"]), "the bomb uses up ammunition")


func _test_ion_cannon() -> void:
	var picked := Loadout.complete({"primary": "autocannon", "secondary": "ion_cannon"})
	_check(picked["primary"] == "ion_cannon" and picked["secondary"] == "ion_cannon", "an ion cannon takes both weapon slots")
	var lion := GameData.get_entry("mechs", "lion")
	var built := Loadout.apply(lion, picked)
	var secondary_mounts := 0
	var ion_mounts := 0
	for mount in built["mounts"]:
		if mount.get("slot", "") == "secondary":
			secondary_mounts += 1
		if mount["weapon"] == "ion_cannon":
			ion_mounts += 1
	_check(secondary_mounts == 0 and ion_mounts == 1, "the ion cannon is one weapon on one mount")
	_check(Loadout.fits(lion, picked), "the lion can carry an ion cannon")
	var hawk := GameData.get_entry("mechs", "hawk")
	_check(Loadout.weight(hawk, picked) == float(GameData.get_entry("weapons", "ion_cannon")["weight"]) + Loadout.weight(hawk, Loadout.default_loadout()) - 35.0, "its weight is counted once")
	_range.start("lion", "standard")
	await _frames(10)
	var target: Mech = _range.targets[0]
	var player := await _stand_back(target)
	var weapon: WeaponState
	for w in player.weapons:
		if w.slot() == "primary":
			weapon = w
	weapon.def = GameData.get_entry("weapons", "ion_cannon")
	weapon.ammo = 6
	for w in player.weapons:
		if w != weapon:
			w.ammo = 0  # the real loadout has no other weapon mounts
	var seen: Array[Dictionary] = []
	var beams: Array[Dictionary] = []
	player.projectile_launched.connect(func(info: Dictionary) -> void: seen.append(info))
	player.beam_fired.connect(func(from: Vector3, to: Vector3, _c: Color, _w: float, fade: float) -> void: beams.append({"from": from, "to": to, "fade": fade}))
	_check(not weapon.def.has("projectile") and weapon.def.has("beam"), "the ion cannon is an instant beam, not a projectile")
	_check(is_equal_approx(float(weapon.def["beam"]["fade"]), 3.0), "the beam fades over 3 seconds")
	_check(weapon.is_two_slot() and weapon.needs_full_charge(), "the ion cannon is a two slot weapon that needs a full charge")
	player.controls.fire_secondary = true
	await _frames(60)
	player.controls.fire_secondary = false
	await _frames(3)
	_check(beams.is_empty() and weapon.ammo == 6, "letting go before 3 seconds loses the shot and costs no ammo")
	_check(target.damage.total_ratio() == 1.0, "a cancelled shot hurts nothing")
	player.controls.fire_primary = true
	await _frames(int(3.3 * Engine.physics_ticks_per_second))
	_check(beams.is_empty(), "it does not fire while it is still held")
	_check(weapon.charge_ratio() >= 1.0, "the charge is full after 3 seconds")
	player.controls.fire_primary = false
	await _frames(3)
	_check(beams.size() == 1 and weapon.ammo == 5 and seen.is_empty(), "letting go with a full charge fires one beam at once")
	_check(target.damage.is_destroyed(), "the beam destroys the mech it hits outright, the moment it fires")


func _test_info_round_trip() -> void:
	var player: Mech = _range.player
	var shot := Projectile.fire(GameData.get_entry("weapons", "rocket_pod"), Vector3.ZERO, Vector3(0, 0, -50), player, 1.0)
	var copy := Projectile.from_info(shot.to_info())
	_check(copy.id == shot.id and copy.model == "rocket", "a client copy has the same id and model")
	_check(copy.velocity.is_equal_approx(shot.velocity) and not copy.authoritative, "the copy flies the same way but deals no damage")
	shot.free()
	copy.free()
