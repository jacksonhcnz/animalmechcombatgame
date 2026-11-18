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
	if mech.is_flying():
		_fly(mech, c, delta)
	else:
		_walk(mech, c, delta)


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

	# Steer the body round to face the enemy, and keep a sensible distance from it.
	if absf(yaw_to) > FACING_DEADZONE:
		c.turn = -clampf(yaw_to * 2.5, -1.0, 1.0)
	var ideal := clampf(_longest_range(mech) * 0.4, 18.0, 80.0)
	var melee := _has_melee(mech)
	if melee and distance < 45.0:
		ideal = 6.0
	if absf(yaw_to) < deg_to_rad(70.0):
		if distance > ideal * 1.25:
			c.throttle = 1.0
			c.sprint = distance > ideal * 2.5
		elif distance < ideal * 0.55:
			c.throttle = -0.7
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe = -_strafe if _rng.randf() < float(level["dodge"]) else _strafe
		_strafe_left = _rng.randf_range(1.2, 3.2)
	if distance < ideal * 2.0 and distance > MELEE_REACH:
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
	c.turn = -clampf(yaw_to * 2.0, -1.0, 1.0)
	pitch_goal = clampf(pitch_goal, deg_to_rad(-20.0), deg_to_rad(25.0))
	if origin.y < FLY_FLOOR:
		pitch_goal = maxf(pitch_goal, deg_to_rad(10.0))
	c.vertical = clampf((pitch_goal - mech.flight_pitch) * 3.0, -1.0, 1.0)
	if origin.y < FLY_FLOOR * 0.6:
		c.vertical = 1.0
	elif origin.y > mech.altitude_limit - 12.0:
		c.vertical = minf(c.vertical, -0.6)
	if mech.stalled and origin.y > FLY_FLOOR * 0.6:
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
