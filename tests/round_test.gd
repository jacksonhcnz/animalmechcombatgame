extends SceneTree
## The Standard Match mode: two teams, best of 7, ends swap every round, one life per round,
## and the canyon map. Run with:
##   godot --headless --path . --script tests/round_test.gd

var _checks := 0
var _failures := 0
var _session: NetSession
var _world: Node3D


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("FAIL: round test timed out")
		quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _run() -> void:
	_test_canyon_map()
	await _test_match_flow()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_canyon_map() -> void:
	var map := Canyon.load_map("canyon")
	_check(not map.is_empty() and Canyon.validate("canyon").is_empty(), "the canyon map data is valid")
	var grid := Canyon.rasterize(map)
	_check(is_equal_approx(grid.depth, 60.0), "the canyon is 60 m deep")
	var zs: Array[float] = []
	for point: Array in map["outer"]:
		zs.append(float(point[1]))
	var length: float = zs.max() - zs.min()
	_check(absf(length - 1368.0) < 5.0, "the canyon is 1368 m long (1520 m less 10%%): %.0f m" % length)
	_check(grid.height_at(-54.0, -621.0) == 0.0, "the north spawn area is canyon floor")
	_check(grid.height_at(0.0, 621.0) == 0.0, "the south spawn area is canyon floor")
	_check(grid.height_at(-400.0, -620.0) == 60.0, "beyond the canyon wall is high ground")
	var island: Array = map["islands"][0]
	var inside := Vector2.ZERO
	for point: Array in island:
		inside += Vector2(float(point[0]), float(point[1]))
	inside /= island.size()
	_check(grid.height_at(inside.x, inside.y) == 60.0, "the mesas in the middle stand 60 m high")
	_check(Ruleset.load_id("standard_match").best_of == 7 and Ruleset.load_id("standard_match").rounds_to_win() == 4, "standard match is best of 7: first to 4")


func _start_session() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	Arena.build_canyon(_world, "canyon")
	var mechs := Node3D.new()
	_world.add_child(mechs)
	_session = NetSession.new()
	_session.mechs_root = mechs
	_world.add_child(_session)
	await process_frame
	var error := _session.start_server(17999, "standard_match", "round test", 8)
	_check(error == OK, "the test server starts")


func _slot(peer: int) -> NetSession.Slot:
	return _session._slots[peer]


func _kill_team(team: int) -> void:
	for slot: NetSession.Slot in _session._slots.values():
		if slot.team == team and slot.mech != null and not slot.mech.is_dead():
			slot.mech.take_hit("torso", 100000.0)
			slot.mech.take_hit("head", 100000.0)


func _test_match_flow() -> void:
	await _start_session()
	var a := _session._add_slot(2, "Ann", "lion")
	var b := _session._add_slot(3, "Bob", "hawk")
	var c := _session._add_slot(4, "Cy", "lion")
	_check(a.team == 1 and b.team == 2 and c.team == 1, "pilots are dealt to the smaller team: %d %d %d" % [a.team, b.team, c.team])
	_check(_session.phase == NetSession.Phase.WAITING, "the match waits for pilots")
	_session._server_tick(0.1)
	_check(_session.phase == NetSession.Phase.COUNTDOWN and _session.round_number == 1, "round 1 counts down once both teams have a pilot")
	_check(_slot(2).mech.global_position.z < -550.0 and _slot(4).mech.global_position.z < -550.0, "team 1 starts at the north end in round 1")
	_check(_slot(3).mech.global_position.z > 550.0, "team 2 starts at the south end")
	_check(absf(_slot(2).mech.global_position.x - _slot(4).mech.global_position.x) > 10.0, "teammates start in different places")
	_session._server_tick(4.0)
	_check(_session.phase == NetSession.Phase.ACTIVE, "the round begins after the countdown")

	_kill_team(2)
	_check(_slot(3).respawn_left < 0.0, "a destroyed mech does not respawn within the round (one life)")
	_session._server_tick(0.1)
	_check(_session.phase == NetSession.Phase.ROUND_OVER and _session.team_wins == [1, 0], "team 1 wins round 1 (wins %s)" % [_session.team_wins])
	_session._server_tick(0.1)
	_check(_slot(3).respawn_left < 0.0 and _slot(3).mech.is_dead(), "still out after the round ended")
	_session._server_tick(NetProtocol.ROUND_OVER_TIME + 0.1)
	_check(_session.phase == NetSession.Phase.COUNTDOWN and _session.round_number == 2, "round 2 counts down")
	_check(_slot(2).mech.global_position.z > 550.0 and _slot(3).mech.global_position.z < -550.0, "the teams swap ends for round 2")
	_check(not _slot(3).mech.is_dead(), "everyone starts the new round alive")
	# Round 2: Cy leaves, so it is one against one, and nobody fires: a draw on time.
	_session._remove_mech(c)
	_session._slots.erase(4)
	_session._server_tick(4.0)
	_session._server_tick(_session.time_left + 1.0)
	_check(_session.phase == NetSession.Phase.ROUND_OVER and _session.team_wins == [1, 0] and _session.result_text.contains("draw"), "a round level on time is a draw and scores nothing")
	_session._server_tick(NetProtocol.ROUND_OVER_TIME + 0.1)
	_check(_session.round_number == 3 and _slot(2).mech.global_position.z < -550.0, "round 3 swaps back")
	_session._server_tick(4.0)

	# Round 3 and 4 to team 1, who now need 4 wins in total.
	_kill_team(2)
	_session._server_tick(0.1)
	_check(_session.team_wins == [2, 0], "team 1 leads 2-0")
	_session._server_tick(NetProtocol.ROUND_OVER_TIME + 0.1)
	_session._server_tick(4.0)
	_kill_team(1)
	_session._server_tick(0.1)
	_check(_session.team_wins == [2, 1] and _session.phase == NetSession.Phase.ROUND_OVER, "team 2 pulls one back: 2-1")
	_session._server_tick(NetProtocol.ROUND_OVER_TIME + 0.1)
	_session._server_tick(4.0)
	_kill_team(2)
	_session._server_tick(0.1)
	_session._server_tick(NetProtocol.ROUND_OVER_TIME + 0.1)
	_session._server_tick(4.0)
	_check(_session.team_wins == [3, 1] and _session.phase == NetSession.Phase.ACTIVE, "3-1 is not yet a win")
	_kill_team(2)
	_session._server_tick(0.1)
	_check(_session.phase == NetSession.Phase.FINISHED and _session.team_wins == [4, 1], "the first team to 4 wins the match")
	_check(_session.result_text.begins_with("Team 1 wins the match"), "the result names the winner")
	_session._server_tick(NetProtocol.RESULT_TIME + 0.1)
	_check(_session.phase == NetSession.Phase.COUNTDOWN and _session.round_number == 1 and _session.team_wins == [0, 0], "a new match starts from round 1, 0-0")

	# A pilot arriving mid-round waits for the next one.
	_session._server_tick(4.0)
	_check(_session.phase == NetSession.Phase.ACTIVE, "round 1 of the new match is under way")
	var late := _session._add_slot(5, "Late", "lion")
	_check(late.mech == null and not _session._joins_now(), "a late pilot gets no mech mid-round")
	_session._server_tick(0.1)
	_check(_session.phase == NetSession.Phase.ACTIVE, "a pilot with no mech yet does not end the round")
	_session.stop()
	_world.queue_free()
	await process_frame
