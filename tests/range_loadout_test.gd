extends SceneTree
## The test range can open the loadout screen, and comes back flying the loadout picked there.

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_go()


func _go() -> void:
	LoadoutStore.path = "user://range_loadout_test.json"
	LoadoutStore.paint_path = "user://range_loadout_test_paint.txt"
	LoadoutStore.reset()
	LaunchConfig.mech_id = "lion"
	var range_scene: Node3D = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(range_scene)
	await process_frame
	await process_frame
	var before: Mech = range_scene.player
	range_scene.open_loadouts()
	await process_frame
	await process_frame
	_check(range_scene._loadouts != null, "the loadout screen opens over the range")
	_check(range_scene._loadouts.get_child(0) is LoadoutMenu, "it is the real loadout screen")
	_check(not range_scene.controller.enabled, "the pilot is not steered while it is open")

	# Edit and save a loadout the way the screen does, then go back.
	var edited: Dictionary = LoadoutStore.slots("lion")[2]["loadout"].duplicate()
	edited["primary"] = "rocket_pod"
	edited["secondary"] = "machine_gun"
	LoadoutStore.save_slot("lion", 2, "Range test", edited)
	LoadoutStore.set_active("lion", 2)
	range_scene.close_loadouts()
	await process_frame
	_check(range_scene._loadouts == null, "the screen closes")
	_check(range_scene.player != before, "the range restarts with a fresh mech")
	_check(range_scene.controller.enabled, "the pilot can steer again")
	var weapons: Array[String] = []
	for mount in range_scene.player.def["mounts"]:
		weapons.append(str(mount["weapon"]))
	_check(weapons.has("rocket_pod") and weapons.has("machine_gun"), "the mech carries the edited loadout: %s" % [weapons])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://range_loadout_test.json"))
	print("range_loadout_test: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)
