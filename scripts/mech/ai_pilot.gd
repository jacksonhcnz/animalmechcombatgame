class_name AiPilot
extends RefCounted
## A computer pilot. Each physics frame it looks at the enemies, picks the nearest, and fills in the
## same MechControls a player's keyboard would: where to steer, where to aim and which triggers to
## hold. It runs only on the machine that owns the mech (the server), so it is as fair as a player
## sending input. How sharp it is comes from data/ai.json.

const TARGET_HEIGHT := 3.0
const FACING_DEADZONE := deg_to_rad(8.0)
const HEAD_TOLERANCE := deg_to_rad(5.0)
const MELEE_REACH := 11.0
## A flying pilot stays above this height (metres) so a turn or a stall does not put it in the ground.
const FLY_FLOOR := 32.0
## Path finding on a canyon map works on blocks this many ground cells wide.
const NAV_BLOCK := 4
## How often a walking pilot works its route out again (seconds), and how far ahead it looks along it.
const REPLAN_TIME := 1.0
const LOOKAHEAD_NODES := 5

## The map's ground, when the match is on a canyon: walkers route round the raised rock and flyers
## stay above it. Null on the open field.
var grid: Canyon.Grid
var _path: Array[Vector3] = []
var _replan_left: float = 0.0
var _coarse: PackedByteArray
var _cnx: int = 0
var _cnz: int = 0

var level: Dictionary
var _rng := RandomNumberGenerator.new()
var _target: Mech
var _retarget_left: float = 0.0
var _strafe: float = 1.0
var _strafe_left: float = 0.0
var _seen_for: float = 0.0
var _stuck_for: float = 0.0
var _unstick_left: float = 0.0
var _unstick_turn: float = 1.0
var _noise := Vector2.ZERO
var _noise_left: float = 0.0
## Charged weapons are held for a while and then let go, so each trigger has its own rhythm.
var _hold: Dictionary = {"primary": 0.0, "secondary": 0.0}


func _init(level_id: String = "") -> void:
	_rng.randomize()
	var table: Dictionary = GameData.ai_table()
	var wanted := level_id if table["levels"].has(level_id) else str(table["default_level"])
	level = table["levels"][wanted]
	_strafe = 1.0 if _rng.randf() < 0.5 else -1.0


## Decides what `mech` does this frame. `enemies` are the mechs it may fight.
func think(mech: Mech, enemies: Array[Mech], delta: float) -> void:
	var c := mech.controls
	c.clear()
	c.aim_yaw_target = mech.aim_yaw
	c.aim_pitch_target = mech.aim_pitch
	if mech.is_dead():
		return
	_retarget_left -= delta
	if _target == null or not is_instance_valid(_target) or _target.is_dead() or _retarget_left <= 0.0:
		_target = _nearest(mech, enemies)
		_retarget_left = 0.7
		_seen_for = 0.0
	if _target == null:
		return
	_noise_left -= delta
	if _noise_left <= 0.0:
		var wobble := deg_to_rad(float(level["aim_error_deg"]))
		_noise = Vector2(_rng.randfn(0.0, wobble), _rng.randfn(0.0, wobble))
		_noise_left = 0.4
	if mech.is_flying() and mech.landed:
		# Down on its feet: take off again at once.
		c.jump = true
	elif mech.is_flying():
		_fly(mech, c, delta)
	else:
		_walk(mech, c, delta)


## The height a flyer keeps above: the open-field floor, or clear of the canyon rim.
func _fly_floor() -> float:
	return FLY_FLOOR if grid == null else maxf(FLY_FLOOR, grid.depth + 24.0)


# ---------------------------------------------------------------- finding a way round the rock

func _build_coarse() -> void:
	_cnx = int(ceil(float(grid.nx) / NAV_BLOCK))
	_cnz = int(ceil(float(grid.nz) / NAV_BLOCK))
	_coarse = PackedByteArray()
	_coarse.resize(_cnx * _cnz)
	for j in _cnz:
		for i in _cnx:
			var blocked := 0
			for dj in NAV_BLOCK:
				for di in NAV_BLOCK:
					if grid.at(i * NAV_BLOCK + di, j * NAV_BLOCK + dj) != 0:
						blocked = 1
			_coarse[j * _cnx + i] = blocked


func _coarse_of(p: Vector3) -> Vector2i:
	var size := grid.cell * NAV_BLOCK
	return Vector2i(clampi(int(floor((p.x - grid.x0) / size)), 0, _cnx - 1), clampi(int(floor((p.z - grid.z0) / size)), 0, _cnz - 1))


func _coarse_centre(c: Vector2i) -> Vector3:
	var size := grid.cell * NAV_BLOCK
	return Vector3(grid.x0 + (c.x + 0.5) * size, 0.0, grid.z0 + (c.y + 0.5) * size)


func _open(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cnx and c.y < _cnz and _coarse[c.y * _cnx + c.x] == 0


## The nearest open block to `c` (itself if it is open), for a start or goal that stands on rock.
func _nearest_open(c: Vector2i) -> Vector2i:
	if _open(c):
		return c
	for radius in range(1, 40):
		for dj in range(-radius, radius + 1):
			for di in range(-radius, radius + 1):
				if maxi(absi(di), absi(dj)) != radius:
					continue
				var n := c + Vector2i(di, dj)
				if _open(n):
					return n
	return c


## True when walking straight from a to b stays on the canyon floor.
func walkable_line(a: Vector3, b: Vector3) -> bool:
	if grid == null:
		return true
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(1, int(length / 6.0))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / steps)
		if grid.height_at(p.x, p.z) > 0.0:
			return false
		# Keep a body's width clear of the rock on either side.
		var side := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized() * 7.0 if length > 0.1 else Vector3.ZERO
		if grid.height_at(p.x + side.x, p.z + side.z) > 0.0 or grid.height_at(p.x - side.x, p.z - side.z) > 0.0:
			return false
	return true


## A route over the canyon floor from `from` to `to` as a list of points, found with A* over the
## blocks. Empty when there is none.
func plan(from: Vector3, to: Vector3) -> Array[Vector3]:
	var route: Array[Vector3] = []
	if grid == null:
		return route
	if _coarse.is_empty():
		_build_coarse()
	var start := _nearest_open(_coarse_of(from))
	var goal := _nearest_open(_coarse_of(to))
	var came: Dictionary = {}
	var cost: Dictionary = {start: 0.0}
	# A small binary heap of [priority, x, y].
	var heap: Array = [[0.0, start.x, start.y]]
	var found := false
	while not heap.is_empty():
		var top: Array = heap[0]
		var last: Array = heap.pop_back()
		if not heap.is_empty():
			heap[0] = last
			var at := 0
			while true:
				var l := at * 2 + 1
				var r := l + 1
				var m := at
				if l < heap.size() and heap[l][0] < heap[m][0]:
					m = l
				if r < heap.size() and heap[r][0] < heap[m][0]:
					m = r
				if m == at:
					break
				var tmp: Array = heap[at]
				heap[at] = heap[m]
				heap[m] = tmp
				at = m
		var here := Vector2i(int(top[1]), int(top[2]))
		if here == goal:
			found = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = here + d
			if not _open(n):
				continue
			# A diagonal step must not squeeze between two blocks of rock.
			if d.x != 0 and d.y != 0 and (not _open(here + Vector2i(d.x, 0)) or not _open(here + Vector2i(0, d.y))):
				continue
			var step := 1.414 if d.x != 0 and d.y != 0 else 1.0
			var new_cost: float = float(cost[here]) + step
			if not cost.has(n) or new_cost < float(cost[n]):
				cost[n] = new_cost
				came[n] = here
				var priority := new_cost + Vector2(n - goal).length()
				heap.append([priority, n.x, n.y])
				var at := heap.size() - 1
				while at > 0:
					var parent := (at - 1) / 2
					if heap[parent][0] <= heap[at][0]:
						break
					var swap: Array = heap[parent]
					heap[parent] = heap[at]
					heap[at] = swap
					at = parent
	if not found:
		return route
	var cell := goal
	while cell != start:
		route.push_front(_coarse_centre(cell))
		cell = came[cell]
	route.push_front(_coarse_centre(start))
	return route


## Where a walking pilot should steer: straight at `point` when the way is clear, otherwise along a
## route round the rock.
func _steer_point(mech: Mech, point: Vector3, delta: float) -> Vector3:
	if grid == null:
		return point
	var origin := mech.global_position
	if walkable_line(origin, point):
		_path.clear()
		return point
	_replan_left -= delta
	if _replan_left <= 0.0 or _path.is_empty():
		_replan_left = REPLAN_TIME
		_path = plan(origin, point)
	if _path.is_empty():
		return point
	# Drop the points already passed, then head for the furthest of the next few that is in a straight line.
	while _path.size() > 1 and Vector2(_path[0].x - origin.x, _path[0].z - origin.z).length() < grid.cell * NAV_BLOCK * 1.2:
		_path.pop_front()
	var best := _path[0]
	for i in mini(LOOKAHEAD_NODES, _path.size()):
		if walkable_line(origin, _path[i]):
			best = _path[i]
	return best


func _nearest(mech: Mech, enemies: Array[Mech]) -> Mech:
	var best: Mech
	var best_distance := INF
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
			continue
		var distance := mech.global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## The spot to aim at on the target, led a little for how fast it is moving and how long the shot takes.
func _aim_point(mech: Mech, weapon: WeaponState) -> Vector3:
	var point := _target.global_position + (Vector3.ZERO if _target.is_flying() else Vector3.UP * TARGET_HEIGHT)
	if weapon == null:
		return point
	var projectile: Dictionary = weapon.def.get("projectile", {})
	var speed := float(projectile.get("speed", 0.0))
	if speed > 0.0:
		var time := mech.aim_origin().distance_to(point) / speed
		point += _target.velocity * time * float(level["lead"])
		point.y += 0.5 * float(projectile.get("gravity", 0.0)) * time * time
	return point


## The weapon that decides how it aims: the first ranged one that is not the sniper rifle.
func _main_weapon(mech: Mech) -> WeaponState:
	for weapon in mech.weapons:
		if not weapon.is_melee() and not weapon.is_scoped() and weapon.slot() != "bomb":
			return weapon
	return null


func _longest_range(mech: Mech) -> float:
	var best := 0.0
	for weapon in mech.weapons:
		if not weapon.is_melee() and weapon.slot() != "bomb":
			best = maxf(best, float(weapon.def.get("range", 0.0)))
	return best


func _line_clear(mech: Mech, to: Vector3) -> bool:
	var space := mech.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(mech.aim_origin(), to)
	query.exclude = [mech.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == _target or hit["collider"] is Mech


func _walk(mech: Mech, c: MechControls, delta: float) -> void:
	var weapon := _main_weapon(mech)
	var origin := mech.global_position
	var point := _aim_point(mech, weapon)
	var flat := Vector2(point.x - origin.x, point.z - origin.z)
	var distance := flat.length()
	var yaw_to := wrapf(atan2(-(point.x - origin.x), -(point.z - origin.z)) - mech.rotation.y, -PI, PI)

	# Steer the body round to face the enemy (or the next point on the way round the rock), and keep a
	# sensible distance from it.
	var steer := _steer_point(mech, point, delta)
	var detour := steer != point
	var body_yaw := yaw_to if not detour else wrapf(atan2(-(steer.x - origin.x), -(steer.z - origin.z)) - mech.rotation.y, -PI, PI)
	if absf(body_yaw) > FACING_DEADZONE:
		c.turn = -clampf(body_yaw * 2.5, -1.0, 1.0)
	var ideal := clampf(_longest_range(mech) * 0.4, 18.0, 80.0)
	var melee := _has_melee(mech)
	if melee and distance < 45.0:
		ideal = 6.0
	if detour:
		# No way through yet: just get round the rock.
		if absf(body_yaw) < deg_to_rad(70.0):
			c.throttle = 1.0
			c.sprint = distance > ideal * 2.5
	elif absf(yaw_to) < deg_to_rad(70.0):
		if distance > ideal * 1.25:
			c.throttle = 1.0
			c.sprint = distance > ideal * 2.5
		elif distance < ideal * 0.55:
			c.throttle = -0.7
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe = -_strafe if _rng.randf() < float(level["dodge"]) else _strafe
		_strafe_left = _rng.randf_range(1.2, 3.2)
	if not detour and distance < ideal * 2.0 and distance > MELEE_REACH:
		c.strafe = _strafe * 0.8
	_unstick(mech, c, delta)

	# Aim the head.
	var twist := deg_to_rad(float(mech.def["base"]["twist_limit_deg"]))
	var wanted_yaw := clampf(yaw_to, -twist, twist) if twist < PI else yaw_to
	var wanted_pitch := _pitch_to(mech, point) + _noise.y
	wanted_yaw += _noise.x
	_swing_aim(mech, c, wanted_yaw, wanted_pitch, delta)

	# Pull the triggers.
	var aimed := absf(wrapf(mech.aim_yaw - wanted_yaw, -PI, PI)) < HEAD_TOLERANCE and absf(mech.aim_pitch - wanted_pitch) < HEAD_TOLERANCE
	var clear := _line_clear(mech, point)
	_seen_for = _seen_for + delta if clear else 0.0
	var ready := _seen_for >= float(level["reaction"])
	for weapon_state: WeaponState in mech.weapons:
		if weapon_state.is_scoped() or weapon_state.slot() == "bomb":
			continue
		var reach := float(weapon_state.def.get("range", 0.0)) * float(level["fire_range"])
		if weapon_state.is_melee():
			if distance < MELEE_REACH:
				c.fire_melee = true
			continue
		if ready and aimed and distance < reach:
			_pull(c, weapon_state, delta)


func _has_melee(mech: Mech) -> bool:
	for weapon in mech.weapons:
		if weapon.is_melee():
			return true
	return false


func _pitch_to(mech: Mech, point: Vector3) -> float:
	var from := mech.aim_origin()
	var rise := point.y - from.y
	var run := Vector2(point.x - from.x, point.z - from.z).length()
	return atan2(rise, maxf(run, 0.1))


## Turns the head toward where it wants to aim, no faster than the pilot's level allows.
func _swing_aim(mech: Mech, c: MechControls, wanted_yaw: float, wanted_pitch: float, delta: float) -> void:
	var step := deg_to_rad(float(level["aim_rate_deg"])) * delta
	c.aim_yaw_target = mech.aim_yaw + clampf(wrapf(wanted_yaw - mech.aim_yaw, -PI, PI), -step, step)
	c.aim_pitch_target = mech.aim_pitch + clampf(wanted_pitch - mech.aim_pitch, -step, step)


## Holds a weapon's trigger. A charged weapon is held to charge and then released, in turn.
func _pull(c: MechControls, weapon: WeaponState, delta: float) -> void:
	var key := "primary" if weapon.is_two_slot() or weapon.slot() == "primary" else "secondary"
	var down := true
	if weapon.is_charged():
		var cycle := weapon.charge_max() + 0.4
		_hold[key] = fmod(float(_hold[key]) + delta, cycle)
		down = float(_hold[key]) < weapon.charge_max() + 0.05
	if down:
		if key == "primary":
			c.fire_primary = true
		else:
			c.fire_secondary = true


## Gets a mech out of a corner: if it wants to move but is not getting anywhere, it jumps and turns away.
func _unstick(mech: Mech, c: MechControls, delta: float) -> void:
	if _unstick_left > 0.0:
		_unstick_left -= delta
		c.throttle = 1.0
		c.turn = _unstick_turn
		c.jump = true
		return
	var moving := Vector2(mech.velocity.x, mech.velocity.z).length()
	var top := float(mech.def["base"]["speed"])
	if c.throttle > 0.0 and moving < top * 0.25:
		_stuck_for += delta
	else:
		_stuck_for = 0.0
	if _stuck_for > 1.0:
		_stuck_for = 0.0
		_unstick_left = 1.3
		_unstick_turn = 1.0 if _rng.randf() < 0.5 else -1.0


func _fly(mech: Mech, c: MechControls, delta: float) -> void:
	var origin := mech.global_position
	var weapon := _main_weapon(mech)
	var point := _aim_point(mech, weapon)
	var to := point - origin
	var flat := Vector2(to.x, to.z)
	var distance := flat.length()
	var yaw_to := wrapf(atan2(-to.x, -to.z) - mech.rotation.y, -PI, PI)
	var pitch_goal := atan2(to.y, maxf(distance, 0.1))

	# Keep the speed up (a flyer that slows down stalls and falls), bank toward the enemy, point the
	# nose at it without climbing or diving too steeply, and stay well clear of the ground and the ceiling.
	c.throttle = 0.85
	# A flyer that strays far from the middle of the map turns back toward it.
	var steer_yaw := yaw_to
	var leash := (minf(grid.half_x(), grid.half_z()) * 0.8) if grid != null else 600.0
	if Vector2(origin.x, origin.z).length() > leash:
		steer_yaw = wrapf(atan2(origin.x, origin.z) - mech.rotation.y, -PI, PI)
	c.turn = -clampf(steer_yaw * 2.0, -1.0, 1.0)
	pitch_goal = clampf(pitch_goal, deg_to_rad(-20.0), deg_to_rad(25.0))
	if origin.y < _fly_floor():
		pitch_goal = maxf(pitch_goal, deg_to_rad(10.0))
	c.vertical = clampf((pitch_goal - mech.flight_pitch) * 3.0, -1.0, 1.0)
	if origin.y < _fly_floor() * 0.6:
		c.vertical = 1.0
	elif origin.y > mech.altitude_limit - 12.0:
		c.vertical = minf(c.vertical, -0.6)
	if mech.stalled and origin.y > _fly_floor() * 0.6:
		c.vertical = minf(c.vertical, -0.3)
		c.throttle = 1.0

	# The guns follow the head, which can look away from the nose.
	var twist := deg_to_rad(float(mech.def["base"]["twist_limit_deg"]))
	var wanted_yaw := clampf(yaw_to, -twist, twist) + _noise.x
	var wanted_pitch := pitch_goal - mech.rotation.x + _noise.y
	_swing_aim(mech, c, wanted_yaw, wanted_pitch, delta)
	var aimed := absf(wrapf(mech.aim_yaw - wanted_yaw, -PI, PI)) < HEAD_TOLERANCE and absf(mech.aim_pitch - wanted_pitch) < HEAD_TOLERANCE
	var clear := _line_clear(mech, point)
	_seen_for = _seen_for + delta if clear else 0.0
	var ready := _seen_for >= float(level["reaction"])
	for weapon_state: WeaponState in mech.weapons:
		if weapon_state.is_scoped():
			continue
		if weapon_state.slot() == "bomb":
			if not _target.is_flying() and distance < 22.0 and origin.y > 12.0:
				c.fire_bomb = true
			continue
		if weapon_state.is_melee():
			if distance < MELEE_REACH:
				c.fire_melee = true
			continue
		if ready and aimed and distance < float(weapon_state.def.get("range", 0.0)) * float(level["fire_range"]):
			_pull(c, weapon_state, delta)
