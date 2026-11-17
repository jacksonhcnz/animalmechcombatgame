extends SceneTree
## The raptor's tail sniper: only the raptor can carry it, the first click engages the scope and
## turns the mech tail first to the aim, the wheel zooms, and moving turns it back round.
## Run with:  godot --headless --path . --script tests/sniper_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		printerr("FAIL: sniper test timed out")
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
	_check(not Loadout.options("equipment", "lion").has("sniper_rifle"), "the lion cannot carry the sniper rifle")
	_check(not Loadout.options("equipment", "hawk").has("sniper_rifle"), "the hawk cannot carry the sniper rifle")
	_check(Loadout.options("equipment", "velociraptor").has("sniper_rifle"), "the raptor can carry the sniper rifle")
	_check(not Loadout.options("primary", "velociraptor").has("sniper_cannon") and not Loadout.options("secondary", "velociraptor").has("sniper_cannon"), "the sniper is equipment, not a weapon slot choice")
	var wrong := Loadout.complete({"equipment": "sniper_rifle"}, "lion")
	_check(wrong["equipment"] == "none", "a sniper rifle picked for the lion falls back to no equipment")
	var raptor_def := GameData.get_entry("mechs", "velociraptor")
	_check(Loadout.fits(raptor_def, {"primary": "autocannon", "secondary": "rocket_pod", "equipment": "sniper_rifle", "perk": "none"}), "the raptor can carry the sniper rifle with its normal weapons")

	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Mech.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	world.add_child(floor_body)

	var rules := Ruleset.load_id("standard")
	var raptor := Mech.create("velociraptor", rules, {"primary": "autocannon", "secondary": "rocket_pod", "equipment": "sniper_rifle", "perk": "none"})
	world.add_child(raptor)
	raptor.global_position = Vector3(0.0, 0.2, 0.0)
	await _frames(20)
	var sniper: WeaponState
	for w in raptor.weapons:
		if w.is_scoped():
			sniper = w
	_check(sniper != null, "the raptor has a scoped weapon")
	if sniper == null:
		quit(1)
		return
	var mount: Dictionary = {}
	for m in raptor.def["mounts"]:
		if m["id"] == sniper.mount_id:
			mount = m
	_check(mount.get("part", "") == "tail_tip", "the sniper sits on the tail")
	var seen: Array[Dictionary] = []
	raptor.projectile_launched.connect(func(info: Dictionary) -> void: seen.append(info))

	raptor.aim_yaw = 0.4
	var world_aim := raptor.rotation.y + raptor.aim_yaw
	var ammo := sniper.ammo
	raptor.controls.use_equipment = true
	await _frames(2)
	raptor.controls.use_equipment = false
	_check(raptor.sniping, "F engages the scope")
	_check(sniper.ammo == ammo and seen.is_empty(), "engaging the scope does not fire")
	_check(raptor.scope_zoom == float(sniper.def["scope"]["start_zoom"]), "the scope starts at its start zoom")
	var start_position := raptor.global_position
	raptor.controls.fire_primary = true
	await _frames(3)
	raptor.controls.fire_primary = false
	await _frames(3)
	_check(seen.is_empty(), "it will not fire until the tail points at the aim, and the hand guns are put away")
	await _frames(300)
	_check(raptor.sniper_aligned(), "the mech turns until its tail points at the aim")
	_check(raptor.global_position.distance_to(start_position) < 0.5, "it stands still while it turns")
	var held := wrapf(raptor.rotation.y + raptor.aim_yaw - world_aim, -PI, PI)
	_check(absf(held) < 0.05, "the aim stays fixed in the world while the body swings (off by %.3f)" % held)
	raptor.controls.fire_primary = true
	await _frames(20)
	_check(seen.is_empty(), "the sniper does not fire while the button is held")
	raptor.controls.fire_primary = false
	await _frames(2)
	_check(seen.size() == 1 and sniper.ammo == ammo - 1, "once aligned the sniper fires when the button is let go")

	raptor.zoom_scope(2.0)
	_check(raptor.scope_zoom > float(sniper.def["scope"]["start_zoom"]), "the wheel zooms in")
	raptor.zoom_scope(100.0)
	_check(is_equal_approx(raptor.scope_zoom, float(sniper.def["scope"]["max_zoom"])), "zoom stops at the maximum")
	raptor.zoom_scope(-100.0)
	_check(is_equal_approx(raptor.scope_zoom, float(sniper.def["scope"]["min_zoom"])), "zoom stops at the minimum")

	raptor.controls.use_equipment = true
	await _frames(2)
	raptor.controls.use_equipment = false
	_check(not raptor.sniping, "F again puts the scope away")
	await _frames(2)
	raptor.controls.use_equipment = true
	await _frames(2)
	raptor.controls.use_equipment = false
	_check(raptor.sniping, "F brings it back")
	raptor.controls.throttle = 1.0
	await _frames(2)
	raptor.controls.throttle = 0.0
	_check(not raptor.sniping and raptor.scope_zoom == 1.0, "moving leaves the scope")
	_check(raptor.realigning, "the mech turns back round afterwards")
	await _frames(300)
	_check(not raptor.realigning, "it finishes turning back")
	_check(absf(raptor.aim_yaw) <= deg_to_rad(float(raptor.def["base"]["twist_limit_deg"])) + 0.01, "the aim is back inside the normal twist")
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
