extends SceneTree
## Checks that a pilot can swap mech and loadout between rounds. Run with:
##   godot --headless --path . --script tests/choice_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	create_timer(200.0).timeout.connect(func() -> void:
		printerr("FAIL: choice test timed out")
		quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _until(phase: NetSession.Phase, session: NetSession, seconds: float) -> bool:
	for i in int(seconds * 60.0):
		await physics_frame
		if session.phase == phase:
			return true
	return false


func _run() -> void:
	LaunchConfig.mode = LaunchConfig.PRACTICE
	LaunchConfig.ruleset_id = "practice_match"
	LaunchConfig.team_size = 1
	LaunchConfig.bot_level = "easy"
	LaunchConfig.mech_id = "lion"
	LaunchConfig.player_name = "Tester"
	LaunchConfig.loadout = {}
	var scene := MatchScene.new()
	root.add_child(scene)
	await process_frame
	var session: NetSession = scene.session
	_check(await _until(NetSession.Phase.ACTIVE, session, 10.0), "the round begins")

	# During a round a swap is refused.
	session.choose("velociraptor", {})
	_check(session.chosen_mech() == "lion", "a swap in the middle of a round is refused")
	_check(not scene._choice.is_open(), "the choice panel is hidden during a round")

	# End the round by destroying the other mech.
	for slot: NetSession.Slot in session._slots.values():
		if slot.pilot != null:
			slot.mech.take_kill()
	_check(await _until(NetSession.Phase.ROUND_OVER, session, 5.0), "the round ends")
	await process_frame
	await process_frame
	_check(session.can_choose(), "a swap is allowed between rounds")
	_check(scene._choice.is_open(), "the choice panel opens between rounds")

	# Pick the raptor with its second loadout (a sniper-style or whatever is stored there).
	var wanted: Dictionary = LoadoutStore.slots("velociraptor")[1]["loadout"]
	session.choose("velociraptor", wanted)
	_check(session.chosen_mech() == "velociraptor", "the chosen mech is remembered")
	session.choose("not_a_mech", {})
	_check(session.chosen_mech() == "velociraptor", "an unknown mech is refused")
	var me: NetSession.Slot = session._slots[session.my_id]
	_check(me.loadout["primary"] == wanted["primary"], "the chosen loadout is kept")
	var started := Time.get_ticks_msec()
	session.press_ready()
	_check(await _until(NetSession.Phase.COUNTDOWN, session, 6.0), "Ready ends the break early")
	_check(Time.get_ticks_msec() - started < 8000, "Ready does not wait out the full break")
	await process_frame
	_check(not scene._choice.is_open(), "the panel closes when the next round starts")
	_check(me.mech != null and str(me.mech.def["id"]) == "velociraptor", "the next round starts in the chosen mech")
	var has_primary := false
	for weapon: WeaponState in me.mech.weapons:
		if weapon.def.get("id", "") == wanted["primary"] or weapon.mount_id != "":
			has_primary = true
	_check(has_primary, "the new mech carries weapons")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
