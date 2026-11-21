extends SceneTree
## The Mesa Basin terrain map: its shape follows the sketch, the ramps can be walked up, the
## cliffs cannot, and computer pilots find their way across.

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("FAIL: mesa basin test timed out")
		quit(1))
	_go()


## The steepest rise over run along a straight line, sampled every 2 m.
func _steepest(grid: Canyon.Grid, from: Vector2, to: Vector2) -> float:
	var steps := int(from.distance_to(to) / 2.0)
	var worst := 0.0
	for k in steps:
		var a := from.lerp(to, float(k) / steps)
		var b := from.lerp(to, float(k + 1) / steps)
		worst = maxf(worst, absf(grid.height_at(b.x, b.y) - grid.height_at(a.x, a.y)) / a.distance_to(b))
	return worst


func _go() -> void:
	var map := Canyon.load_map("mesa_basin")
	_check(not map.is_empty() and Canyon.validate("mesa_basin").is_empty(), "the mesa basin map data is valid: %s" % [Canyon.validate("mesa_basin")])
	var start := Time.get_ticks_msec()
	var fresh := Canyon.rasterize(map)
	var took := Time.get_ticks_msec() - start
	_check(took < 5000, "the terrain is quick to work out (%d ms)" % took)
	var grid := Canyon.grid_for(map)
	_check(fresh.heights == grid.heights and fresh.raised == grid.raised, "working it out twice gives the same ground")
	_check(grid.heights.size() == (grid.nx + 1) * (grid.nz + 1), "the terrain has a height at every cell corner")
	_check(grid.boulders.size() > 60, "boulder fields give low cover (%d boulders)" % grid.boulders.size())

	# The sketch, north to south: wall, mesa, ramp down to the low middle, ramp up, mesa, wall.
	_check(grid.height_at(0.0, -670.0) > 50.0 and grid.height_at(0.0, 670.0) > 50.0, "a wall rises at each end")
	_check(grid.height_at(-32.0, -384.0) > 55.0, "the north mesa stands high (%.0f m)" % grid.height_at(-32.0, -384.0))
	_check(grid.height_at(32.0, 378.0) > 55.0, "the south mesa stands high (%.0f m)" % grid.height_at(32.0, 378.0))
	_check(absf(grid.height_at(0.0, 0.0)) < 10.0, "the middle is low ground (%.0f m)" % grid.height_at(0.0, 0.0))
	_check(grid.height_at(-32.0, -520.0) < 10.0, "low ground lies behind the north mesa")

	# The ground rolls: heights across open low ground are not all the same.
	var lowest := 1.0e9
	var highest := -1.0e9
	for x in range(-400, 401, 20):
		var h := grid.height_at(float(x), -20.0)
		if not grid.blocked_at(float(x), -20.0):
			lowest = minf(lowest, h)
			highest = maxf(highest, h)
	_check(highest - lowest > 4.0, "the ground undulates (%.1f m between low and high points)" % (highest - lowest))

	# Ramps are gentle enough to walk; outer cliffs are not.
	var north_ramp := _steepest(grid, Vector2(-32.0, -70.0), Vector2(-32.0, -360.0))
	var south_ramp := _steepest(grid, Vector2(32.0, 70.0), Vector2(32.0, 360.0))
	_check(north_ramp < 0.65, "the north ramp can be walked (steepest %.2f)" % north_ramp)
	_check(south_ramp < 0.65, "the south ramp can be walked (steepest %.2f)" % south_ramp)
	var cliff := _steepest(grid, Vector2(-110.0, -530.0), Vector2(-110.0, -420.0))
	_check(cliff > 1.2, "the north mesa's outer face is a cliff (steepest %.2f)" % cliff)
	_check(grid.height_at(-32.0, -360.0) > 55.0, "the north ramp reaches the top")

	# Computer pilots: a route from one end to the other, and up onto a mesa.
	var pilot := AiPilot.new("hard")
	pilot.grid = grid
	var north: Vector3 = Arena.map_spawn("mesa_basin", "north", 0).origin
	var south: Vector3 = Arena.map_spawn("mesa_basin", "south", 0).origin
	_check(absf(north.y - grid.height_at(north.x, north.z)) < 0.01, "spawns start at the height of the ground there")
	var route := pilot.plan(north, south)
	_check(route.size() > 10, "a route exists from the north spawn to the south spawn (%d points)" % route.size())
	var open := true
	for p in route:
		if grid.blocked_at(p.x, p.z):
			open = false
	_check(open, "every point of the route is on open ground")
	var up := pilot.plan(north, Vector3(-32.0, 0.0, -400.0))
	_check(up.size() > 3, "a route leads up onto the north mesa (%d points)" % up.size())

	# A mech walks up the ramp, and not up the cliff.
	LaunchConfig.mode = LaunchConfig.PRACTICE
	LaunchConfig.ruleset_id = "practice_match"
	LaunchConfig.team_size = 1
	LaunchConfig.bot_level = "easy"
	LaunchConfig.map = "mesa_basin"
	LaunchConfig.mech_id = "lion"
	var scene := MatchScene.new()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var session: NetSession = scene.session
	_check(session.rules.map == "mesa_basin", "a match runs on the mesa basin")
	scene.controller.set_physics_process(false)
	var me: NetSession.Slot = session._slots[1]
	_check(me.mech != null, "the player's mech is in the world")
	if me.mech == null:
		_finish()
		return
	var mech := me.mech
	for i in 30:
		await physics_frame
	_check(absf(mech.global_position.y - grid.height_at(mech.global_position.x, mech.global_position.z)) < 3.0, "the mech stands on the ground at its spawn (y %.1f)" % mech.global_position.y)

	await _place(mech, Vector3(-32.0, 0.0, -80.0), 0.0, grid)
	mech.controls.clear()
	mech.controls.throttle = 1.0
	var top := 0.0
	for i in 60 * 30:
		await physics_frame
		top = maxf(top, mech.global_position.y)
		if mech.global_position.z < -380.0:
			break
	_check(top > 50.0, "a lion walks up the north ramp to the top (reached %.0f m)" % top)

	await _place(mech, Vector3(-110.0, 0.0, -540.0), PI, grid)
	mech.controls.clear()
	mech.controls.throttle = 1.0
	var cliff_top := 0.0
	for i in 60 * 8:
		await physics_frame
		cliff_top = maxf(cliff_top, mech.global_position.y)
	_check(cliff_top < 35.0, "it cannot walk up the outer cliff (got to %.0f m)" % cliff_top)
	mech.controls.clear()
	for slot: NetSession.Slot in session._slots.values():
		if slot.pilot != null and slot.mech != null:
			var p := slot.mech.global_position
			_check(p.y > grid.height_at(p.x, p.z) - 5.0, "the computer pilot's %s stays on top of the ground" % slot.mech_id)
	_finish()


func _place(mech: Mech, at: Vector3, yaw: float, grid: Canyon.Grid) -> void:
	mech.velocity = Vector3.ZERO
	mech.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, grid.height_at(at.x, at.z) + mech.spawn_height(), at.z))
	for i in 3:
		await physics_frame


func _finish() -> void:
	print("mesa_basin_test: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)
