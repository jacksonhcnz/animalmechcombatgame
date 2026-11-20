extends SceneTree
## Computer pilots on the canyon: routes round the rock, and a practice match that crosses it.

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
	var grid := Canyon.rasterize(Canyon.load_map("canyon"))
	var pilot := AiPilot.new("hard")
	pilot.grid = grid
	var north: Vector3 = Arena.map_spawn("canyon", "north", 0).origin
	var south: Vector3 = Arena.map_spawn("canyon", "south", 0).origin
	var start := Time.get_ticks_msec()
	var route := pilot.plan(north, south)
	var took := Time.get_ticks_msec() - start
	_check(route.size() > 10, "a route exists from the north spawn to the south spawn (%d points)" % route.size())
	_check(took < 400, "planning is quick (%d ms)" % took)
	var on_floor := true
	for p in route:
		if grid.height_at(p.x, p.z) > 0.0:
			on_floor = false
	_check(on_floor, "every point of the route is on the canyon floor")
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i].distance_to(route[i - 1])
	_check(length >= north.distance_to(south) - 1.0, "the route is no shorter than the straight line")

	# A whole practice match on the canyon: pilots cross to meet each other.
	LaunchConfig.mode = LaunchConfig.PRACTICE
	LaunchConfig.ruleset_id = "practice_match"
	LaunchConfig.team_size = 1
	LaunchConfig.bot_level = "hard"
	LaunchConfig.map = "canyon"
	LaunchConfig.mech_id = "lion"
	var scene := MatchScene.new()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var session: NetSession = scene.session
	_check(session.rules.map == "canyon", "the match is on the canyon")
	_check(scene.get_node_or_null("Canyon") != null or _has_canyon(scene), "the canyon is built in the world")
	session.press_ready()
	for i in 60 * 8:
		await physics_frame
		if session.phase == NetSession.Phase.ACTIVE:
			break
	_check(session.phase == NetSession.Phase.ACTIVE, "the round begins")
	var bot: NetSession.Slot
	var me: NetSession.Slot = session._slots[1]
	for slot: NetSession.Slot in session._slots.values():
		if slot.pilot != null:
			bot = slot
	_check(bot != null and bot.pilot.grid != null, "the computer pilot knows the map")
	var gap_start := bot.mech.global_position.distance_to(me.mech.global_position)
	for i in 60 * 30:
		await physics_frame
	var gap_end := bot.mech.global_position.distance_to(me.mech.global_position)
	var bx := bot.mech.global_position
	_check(bx.y > -5.0, "the pilot did not fall through the world (y %.0f)" % bx.y)
	_check(me.mech.global_position.y > -5.0, "nor did the player")
	_check(gap_end < gap_start - 150.0, "the %s pilot made its way toward the player: %.0f m to %.0f m" % [bot.mech_id, gap_start, gap_end])
	print("canyon_ai_test: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _has_canyon(node: Node) -> bool:
	for child in node.get_children():
		if child.name == "Canyon" or _has_canyon(child):
			return true
	return false
