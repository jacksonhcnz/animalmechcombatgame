extends SceneTree
## Checks that footsteps, wing flaps and weapon shots make sound. Run with:
##   godot --headless --path . --script tests/sound_test.gd

var _checks := 0
var _failures := 0
var _range: Node3D


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: sound test timed out")
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


func _players() -> int:
	return _range.find_children("*", "AudioStreamPlayer3D", true, false).size()


func _start(mech_id: String) -> Mech:
	_range.start(mech_id, "practice")
	await _frames(40)
	_range.controller.set_physics_process(false)
	return _range.player


func _run() -> void:
	_range = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(_range)
	await _frames(40)

	for id in ["lion_step", "raptor_step", "elephant_step", "wing_flap", "machine_gun_shot", "ion_charge", "ion_blast", "sniper_breath", "sniper_shot"]:
		_check(Sfx.stream(id) != null, "clip %s loads" % id)

	for id in ["lion", "velociraptor"]:
		var walker := await _start(id)
		var quiet := _players()
		walker.controls.throttle = 1.0
		var seen := 0
		for i in 240:
			await physics_frame
			seen = maxi(seen, _players() - quiet)
		walker.controls.throttle = 0.0
		_check(seen > 0, "%s walking makes footsteps" % id)

	var idle := await _start("lion")
	await _frames(200)
	var before := _players()
	await _frames(60)
	_check(_players() <= before, "a standing lion is silent")

	var hawk := await _start("hawk")
	hawk.controls.throttle = 1.0
	hawk.controls.vertical = 1.0
	var flaps := 0
	for i in 300:
		await physics_frame
		flaps = maxi(flaps, _players())
	_check(flaps > 0 or not hawk.is_flying(), "a flying hawk flaps audibly")

	var gunner := await _start("lion")
	gunner.weapons[0] = WeaponState.new(gunner.weapons[0].mount_id, GameData.get_entry("weapons", "machine_gun"))
	var cues: Array[String] = []
	gunner.sound_cue.connect(func(clip: String, _pos: Vector3) -> void: cues.append(clip))
	gunner.controls.fire_primary = true
	await _frames(40)
	gunner.controls.fire_primary = false
	_check(not cues.is_empty(), "firing the machine gun cues a sound for network clients")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
