class_name MechAnimator
extends RefCounted
## Procedural animation for one mech: walking, flapping, banking, limping and collapsing.
##
## It needs no animation files. Each limb has a pivot and a motion described in the mech's
## data file ("anim"), and the mech has an "animation" block with the tuning numbers.
## The result is applied by rotating the pivot nodes, so hitboxes move with the visible parts.
##
## Walking is driven by distance travelled, so the legs match the speed. Damage changes the
## motion: a crippled limb moves weakly (a limp), a destroyed leg hangs, a destroyed wing droops,
## and a destroyed mech collapses.

const DEATH_TIME := 0.9
const STAND_TIME := 1.2
const CRIPPLED_FACTOR := 0.35
const FACTOR_RATE := 4.0
const DROOP_RATE := 2.5
const LOOK_RATE := 7.0

## Vertical body bob in metres this frame. The cockpit camera follows a share of it.
var bob_y: float = 0.0
var stride_phase: float = 0.0
var flap_phase: float = 0.0

var _step_index: int = -1
var _last_stride: float = -1.0
var _flap_index: int = -1

var _mech: Mech
var _cfg: Dictionary
var _entries: Array[Dictionary] = []
var _parent_of: Dictionary = {}
var _leg_ids: Array[String] = []
var _factor: Dictionary = {}
var _droop: Dictionary = {}
var _walk_amp: float = 0.0
var _flap_amp: float = 0.45
var _perch: float = 0.0
## Melee strikes under way: mount id -> how far through the strike it is (0 to 1).
var _strikes: Dictionary = {}
var _flap_hz: float = 0.0
var _bank: float = 0.0
var _pitch: float = 0.0
## How far the body has risen into its standing posture, 0 (walking) to 1 (standing still).
var _stand: float = 0.0
var _roll: float = 0.0
var _yaw: float = 0.0
var _crouch: float = 0.0
var _idle_time: float = 0.0
var _death: float = 0.0
var _limp: float = 0.0
var _look_yaw: Dictionary = {}
var _look_pitch: Dictionary = {}
var _fall_peak: float = 0.0
var _land: float = 0.0


func _init(mech: Mech) -> void:
	_mech = mech
	_cfg = mech.def.get("animation", {})
	_flap_hz = float(_cfg.get("flap_hz", 0.0))
	for part in mech.def["parts"]:
		var id: String = part["id"]
		if part.has("parent"):
			_parent_of[id] = part["parent"]
		var anim: Dictionary = part.get("anim", {})
		if anim.has("walk") or anim.has("flap") or anim.has("aim") or anim.has("stabilize") or anim.has("look") or anim.has("strike"):
			_entries.append({
				"id": id,
				"pivot": mech.pivots[id],
				"walk": anim.get("walk", {}),
				"flap": anim.get("flap", {}),
				"aim": anim.get("aim", ""),
				"stabilize": float(anim.get("stabilize", 0.0)),
				"look": anim.get("look", {}),
				"strike": anim.get("strike", {}),
				"base_pos": mech.pivots[id].position,
				"last_pos": mech.pivots[id].position,
				"last": Vector3(INF, INF, INF),
			})
			_look_yaw[id] = 0.0
			_look_pitch[id] = 0.0
			_factor[id] = 1.0
			_droop[id] = 0.0
		if anim.has("walk") and part.get("kind", "") == "leg":
			_leg_ids.append(id)


## Starts the strike animation of a melee mount (a claw swipe, a bite, a talon strike).
func start_strike(mount_id: String) -> void:
	_strikes[mount_id] = 0.0


## The pose of a strike `t` (0 to 1) of the way through: [rotation in degrees, how far forward it lunges 0..1].
## The limb draws back, snaps forward and eases home.
static func strike_pose(strike: Dictionary, t: float) -> Vector2:
	var windup := float(strike.get("windup_deg", 0.0))
	var hit := float(strike.get("deg", 0.0))
	if t < 0.3:
		return Vector2(lerpf(0.0, windup, _ease(t / 0.3)), 0.0)
	if t < 0.5:
		var u := _ease((t - 0.3) / 0.2)
		return Vector2(lerpf(windup, hit, u), u)
	var back := _ease((t - 0.5) / 0.5)
	return Vector2(lerpf(hit, 0.0, back), 1.0 - back)


static func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func update(delta: float) -> void:
	for mount_id in _strikes.keys():
		var length := _strike_time(mount_id)
		_strikes[mount_id] = float(_strikes[mount_id]) + delta / length
		if float(_strikes[mount_id]) >= 1.0:
			_strikes.erase(mount_id)
	_idle_time += delta
	if _mech.is_dead():
		_death = minf(1.0, _death + delta / DEATH_TIME)
	_update_factors(delta)
	if _mech.is_flying() and not _mech.landed:
		_update_flight(delta)
	else:
		_update_walk(delta)
	# A landed flyer stands up on its feet, a little higher than it flew.
	_perch = move_toward(_perch, 1.0 if _mech.landed else 0.0, 2.5 * delta)
	_update_stand(delta)
	_apply_parts(delta)
	_apply_rig()


## One footfall clip each time the gait passes a step point (`steps_per_stride` of them a stride).
func _footstep_sound() -> void:
	var sounds: Dictionary = _mech.def.get("sounds", {})
	if not sounds.has("step") or _mech.get_parent() == null:
		return
	var count := maxi(1, int(sounds.get("steps_per_stride", 1)))
	var index := int(stride_phase * float(count))
	# The phase wraps from 1 back to 0 (or the other way when walking backwards), which counts as a
	# step point too: with one step a stride the index never changes by itself.
	var wrapped := absf(stride_phase - _last_stride) > 0.5
	var first := _last_stride < 0.0
	var stepped := index != _step_index or wrapped
	_step_index = index
	_last_stride = stride_phase
	if first or not stepped or _walk_amp < 0.2 or _mech.is_dead():
		return
	var pitch := 0.96 + 0.08 * float((index + 1) % 2)
	# A quiet perk (noise_mult below 1) lowers the footfall and the distance it carries.
	var quiet := float(_mech.def.get("noise_mult", 1.0))
	var loudness := lerpf(0.5, 1.0, _walk_amp) * quiet
	Sfx.play_at(_mech.get_parent(), str(sounds["step"]), _mech.global_position,
			float(sounds.get("step_db", 0.0)) - 6.0 + 6.0 * _walk_amp + linear_to_db(quiet), pitch, _mech.team, loudness)


## How strongly each limb moves, from 0 (disabled) to 1 (healthy), eased over time.
func _update_factors(delta: float) -> void:
	var limp_total := 0.0
	for entry in _entries:
		var id: String = entry["id"]
		var target := _limb_factor(id)
		_factor[id] = move_toward(_factor[id], target, FACTOR_RATE * delta)
		if _leg_ids.has(id):
			limp_total += 1.0 - target
	_limp = limp_total / float(_leg_ids.size()) if not _leg_ids.is_empty() else 0.0


## A limb is as weak as the weakest of itself and the limbs it hangs from.
func _limb_factor(part_id: String) -> float:
	var factor := 1.0
	var id := part_id
	while id != "":
		if _mech.damage.is_part_disabled(id):
			return 0.0
		if _mech.damage.is_crippled(id):
			factor = minf(factor, CRIPPLED_FACTOR)
		id = _parent_of.get(id, "")
	return factor


func _update_walk(delta: float) -> void:
	var velocity := _mech.velocity
	var flat := Vector2(velocity.x, velocity.z).length()
	var base_speed := float(_mech.def["base"]["speed"])
	if _mech.landed:
		base_speed = float(_mech.def.get("landing", {}).get("walk_speed", base_speed))
		_flap_amp = move_toward(_flap_amp, 0.0, 3.0 * delta)
	var moving := _mech.grounded() and not _mech.is_dead()
	var target := clampf(flat / base_speed, 0.0, 1.0) if moving else 0.0
	_walk_amp = move_toward(_walk_amp, target, 5.0 * delta)

	# Walking backwards runs the gait in reverse.
	var forward := -_mech.global_transform.basis.z
	var direction := -1.0 if velocity.dot(forward) < -0.25 * flat else 1.0
	stride_phase = fposmod(stride_phase + direction * flat / float(_cfg["stride_length"]) * delta, 1.0)
	_footstep_sound()

	# The body rises and falls with each footfall (twice per full stride).
	bob_y = float(_cfg.get("bob_m", 0.0)) * _walk_amp * sin(stride_phase * TAU * 2.0)
	bob_y += float(_cfg.get("idle_bob_m", 0.0)) * sin(_idle_time * 1.5)
	# A crippled leg makes the whole body rock from side to side.
	_roll = deg_to_rad(float(_cfg.get("limp_roll_deg", 0.0))) * _limp * _walk_amp * sin(stride_phase * TAU)
	# Prowling body motion (optional, used by the lion): the spine sways side to side, the
	# weight shifts over the planted feet, the shoulders rise and fall, and the body sinks low.
	_yaw = deg_to_rad(float(_cfg.get("sway_yaw_deg", 0.0))) * _walk_amp * sin(stride_phase * TAU + 0.6)
	_roll += deg_to_rad(float(_cfg.get("sway_roll_deg", 0.0))) * _walk_amp * sin(stride_phase * TAU + 1.6)
	_pitch = deg_to_rad(float(_cfg.get("sway_pitch_deg", 0.0))) * _walk_amp * sin(stride_phase * TAU * 2.0 + 0.8)
	_crouch = float(_cfg.get("stalk_drop_m", 0.0)) * _walk_amp
	# Landing from a jump or fall: the body dips, more the harder the landing, then recovers.
	if not _mech.grounded():
		_fall_peak = maxf(_fall_peak, -_mech.velocity.y)
	elif _fall_peak > 0.0:
		_land = clampf(_fall_peak / 15.0, 0.0, 1.0)
		_fall_peak = 0.0
	_land = move_toward(_land, 0.0, 3.0 * delta)
	_crouch += float(_cfg.get("land_dip_m", 0.0)) * _land


func _update_flight(delta: float) -> void:
	# The whole body pitches and banks as a plane now, so the wings only flap: hard in a climb, easy in a dive.
	var climb := clampf(sin(_mech.flight_pitch) / sin(deg_to_rad(Points.flight("max_pitch_deg"))), -1.0, 1.0)
	var climbing := maxf(climb, 0.0)
	var descending := maxf(-climb, 0.0)

	var hz_target := lerpf(float(_cfg["flap_hz"]), float(_cfg["flap_hz_climb"]), climbing)
	_flap_hz = move_toward(_flap_hz, hz_target, 3.0 * delta)
	flap_phase = fposmod(flap_phase + _flap_hz * delta, 1.0)
	var wrapped := _flap_hz > 0.0 and flap_phase < _flap_hz * delta
	if wrapped and _mech.get_parent() != null:
		Sfx.play_at(_mech.get_parent(), str(_mech.def.get("sounds", {}).get("flap", "")), _mech.global_position, -4.0 + 4.0 * _flap_amp, 1.0, _mech.team)
	# Flap hard to climb, ease off to glide down.
	var amp_target := lerpf(0.45, 1.0, climbing) - 0.25 * descending
	_flap_amp = move_toward(_flap_amp, amp_target, 3.0 * delta)

	_walk_amp = move_toward(_walk_amp, 0.0, 5.0 * delta)
	bob_y = float(_cfg["hover_bob_m"]) * _flap_amp * sin(flap_phase * TAU)
	# Turning right banks right (right side down, a negative roll).
	_bank = 0.0
	_pitch = 0.0
	_roll = 0.0
	_yaw = 0.0
	_crouch = 0.0


## How long a strike on this mount lasts, from the first part that animates it.
func _strike_time(mount_id: String) -> float:
	for entry in _entries:
		var strike: Dictionary = entry["strike"]
		if not strike.is_empty() and strike["mount"] == mount_id:
			return maxf(0.1, float(strike.get("time", 0.45)))
	return 0.45


func _apply_parts(delta: float) -> void:
	var alive := 1.0 - _death
	for entry in _entries:
		var id: String = entry["id"]
		var factor: float = _factor[id]
		var rotation := Vector3.ZERO

		var walk: Dictionary = entry["walk"]
		if not walk.is_empty():
			rotation[_axis_index(walk)] += _motion_angle(walk, stride_phase, _walk_amp, factor) * alive

		var flap: Dictionary = entry["flap"]
		if not flap.is_empty():
			# A destroyed (or dead) wing droops instead of flapping.
			var droop_target := 1.0 if (_death > 0.0 or _limb_factor(id) <= 0.0 or _mech.landed) else 0.0
			_droop[id] = move_toward(_droop[id], droop_target, DROOP_RATE * delta)
			var live := _motion_angle(flap, flap_phase, _flap_amp, factor)
			var drooped := deg_to_rad(float(flap.get("droop_deg", 0.0)))
			rotation[_axis_index(flap)] += lerpf(live, drooped, _droop[id])

		# A melee strike: the limb draws back, snaps forward and settles, lunging a little as it hits.
		var strike: Dictionary = entry["strike"]
		var lunge := Vector3.ZERO
		if not strike.is_empty() and _strikes.has(strike["mount"]):
			var pose := strike_pose(strike, float(_strikes[strike["mount"]]))
			rotation[_axis_index(strike)] += deg_to_rad(pose.x) * alive * factor
			if strike.has("lunge"):
				var v: Array = strike["lunge"]
				lunge = Vector3(float(v[0]), float(v[1]), float(v[2])) * pose.y * alive * factor
		if entry["base_pos"] + lunge != entry["last_pos"]:
			entry["last_pos"] = entry["base_pos"] + lunge
			entry["pivot"].position = entry["last_pos"]

		# Looking: the head (and neck) turn towards where the pilot is aiming, but only as far
		# as the anatomy allows. Past that limit the aim carries on and the head stays put.
		var look: Dictionary = entry["look"]
		if not look.is_empty():
			var limit := deg_to_rad(float(look["turn_deg"]))
			var share := float(look.get("share", 1.0))
			var rate := float(look.get("speed", LOOK_RATE)) * delta
			_look_yaw[id] = move_toward(_look_yaw[id], clampf(_mech.aim_yaw, -limit, limit) * share, rate)
			_look_pitch[id] = move_toward(_look_pitch[id], _mech.aim_pitch * share, rate)
			rotation.y += _look_yaw[id] * alive
			rotation.x += _look_pitch[id] * alive

		# A stabilised part (a bird's neck) turns against the body's pitch, so the head stays level.
		# The neck keeps the head level against the body pitching, whether that is the rig or a plane's whole body.
		var body_pitch := _mech.flight_pitch if _mech.is_flying() else 0.0
		rotation.x -= (_pitch + body_pitch + stand_pitch()) * float(entry["stabilize"]) * alive

		# Gimbal parts follow where the pilot is aiming, and freeze when destroyed.
		match entry["aim"]:
			"yaw":
				rotation.y += _mech.aim_yaw * factor
			"pitch":
				rotation.x += _mech.aim_pitch * factor

		# Setting a transform wakes up the hitboxes riding on it, so only touch parts that moved.
		if rotation != entry["last"]:
			entry["last"] = rotation
			entry["pivot"].rotation = rotation


## Upright mechs straighten up when they stop and lean forward again to move.
func _update_stand(delta: float) -> void:
	var standing := not _mech.is_dead() and not _mech.is_flying() and _mech.grounded() \
		and Vector2(_mech.velocity.x, _mech.velocity.z).length() < 0.5
	_stand = move_toward(_stand, 1.0 if standing else 0.0, delta / STAND_TIME)
	if _mech.body_rig != null:
		_mech.body_rig.rotation.x = stand_pitch()


## The body's nose-up tilt, in radians, from the standing posture.
func stand_pitch() -> float:
	var eased := _stand * _stand * (3.0 - 2.0 * _stand)
	return deg_to_rad(float(_cfg.get("stand_pitch_deg", 0.0))) * eased


func _apply_rig() -> void:
	var collapse := _death * _death * (3.0 - 2.0 * _death)
	bob_y *= 1.0 - collapse
	var rig_y := bob_y - _crouch * (1.0 - collapse) - float(_cfg.get("collapse_m", 0.0)) * collapse + float(_cfg.get("perch_lift_m", 0.0)) * _perch
	var rig_rotation := Vector3(
		_pitch + deg_to_rad(float(_cfg.get("death_pitch_deg", 0.0))) * collapse,
		_yaw * (1.0 - collapse),
		_roll + deg_to_rad(float(_cfg.get("death_roll_deg", 0.0))) * collapse
	)
	if rig_y != _mech.rig.position.y:
		_mech.rig.position.y = rig_y
	if rig_rotation != _mech.rig.rotation:
		_mech.rig.rotation = rig_rotation


## Angle in radians of one motion at a point in the cycle.
static func _motion_angle(motion: Dictionary, cycle: float, amplitude: float, factor: float) -> float:
	var wave := sin(TAU * (cycle + float(motion.get("phase", 0.0))))
	# "rectify" keeps only the positive half of the wave: a limb that folds and then straightens,
	# like a knee bending to lift the foot during the swing, and never bends the other way.
	if motion.get("rectify", false):
		wave = maxf(wave, 0.0)
	var swing := float(motion["deg"]) * amplitude * wave
	return deg_to_rad((float(motion.get("offset_deg", 0.0)) + swing) * factor)


static func _axis_index(motion: Dictionary) -> int:
	return ["x", "y", "z"].find(motion["axis"])
