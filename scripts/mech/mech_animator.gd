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
const CRIPPLED_FACTOR := 0.35
const FACTOR_RATE := 4.0
const DROOP_RATE := 2.5

## Vertical body bob in metres this frame. The cockpit camera follows a share of it.
var bob_y: float = 0.0
var stride_phase: float = 0.0
var flap_phase: float = 0.0

var _mech: Mech
var _cfg: Dictionary
var _entries: Array[Dictionary] = []
var _parent_of: Dictionary = {}
var _leg_ids: Array[String] = []
var _factor: Dictionary = {}
var _droop: Dictionary = {}
var _walk_amp: float = 0.0
var _flap_amp: float = 0.45
var _flap_hz: float = 0.0
var _bank: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _idle_time: float = 0.0
var _death: float = 0.0
var _limp: float = 0.0


func _init(mech: Mech) -> void:
	_mech = mech
	_cfg = mech.def.get("animation", {})
	_flap_hz = float(_cfg.get("flap_hz", 0.0))
	for part in mech.def["parts"]:
		var id: String = part["id"]
		if part.has("parent"):
			_parent_of[id] = part["parent"]
		var anim: Dictionary = part.get("anim", {})
		if anim.has("walk") or anim.has("flap"):
			_entries.append({
				"id": id,
				"pivot": mech.pivots[id],
				"walk": anim.get("walk", {}),
				"flap": anim.get("flap", {}),
			})
			_factor[id] = 1.0
			_droop[id] = 0.0
		if anim.has("walk") and part.get("kind", "") == "leg":
			_leg_ids.append(id)


func update(delta: float) -> void:
	_idle_time += delta
	if _mech.is_dead():
		_death = minf(1.0, _death + delta / DEATH_TIME)
	_update_factors(delta)
	if _mech.is_flying():
		_update_flight(delta)
	else:
		_update_walk(delta)
	_apply_parts(delta)
	_apply_rig()


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
	var moving := _mech.is_on_floor() and not _mech.is_dead()
	var target := clampf(flat / base_speed, 0.0, 1.0) if moving else 0.0
	_walk_amp = move_toward(_walk_amp, target, 5.0 * delta)

	# Walking backwards runs the gait in reverse.
	var forward := -_mech.global_transform.basis.z
	var direction := -1.0 if velocity.dot(forward) < -0.25 * flat else 1.0
	stride_phase = fposmod(stride_phase + direction * flat / float(_cfg["stride_length"]) * delta, 1.0)

	# The body rises and falls with each footfall (twice per full stride).
	bob_y = float(_cfg.get("bob_m", 0.0)) * _walk_amp * sin(stride_phase * TAU * 2.0)
	bob_y += float(_cfg.get("idle_bob_m", 0.0)) * sin(_idle_time * 1.5)
	# A crippled leg makes the whole body rock from side to side.
	_roll = deg_to_rad(float(_cfg.get("limp_roll_deg", 0.0))) * _limp * _walk_amp * sin(stride_phase * TAU)
	_pitch = 0.0


func _update_flight(delta: float) -> void:
	var climb_speed := float(_mech.def["base"]["climb_speed"])
	var climb := clampf(_mech.velocity.y / climb_speed, -1.0, 1.0)
	var climbing := maxf(climb, 0.0)
	var descending := maxf(-climb, 0.0)

	var hz_target := lerpf(float(_cfg["flap_hz"]), float(_cfg["flap_hz_climb"]), climbing)
	_flap_hz = move_toward(_flap_hz, hz_target, 3.0 * delta)
	flap_phase = fposmod(flap_phase + _flap_hz * delta, 1.0)
	# Flap hard to climb, ease off to glide down.
	var amp_target := lerpf(0.45, 1.0, climbing) - 0.25 * descending
	_flap_amp = move_toward(_flap_amp, amp_target, 3.0 * delta)

	bob_y = float(_cfg["hover_bob_m"]) * _flap_amp * sin(flap_phase * TAU)
	# Turning right banks right (right side down, a negative roll).
	var bank_target := -_mech.controls.turn * deg_to_rad(float(_cfg["bank_deg"]))
	_bank = lerpf(_bank, bank_target, clampf(4.0 * delta, 0.0, 1.0))
	_pitch = lerpf(_pitch, climb * deg_to_rad(float(_cfg["pitch_deg"])), clampf(3.0 * delta, 0.0, 1.0))
	_roll = _bank


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
			var droop_target := 1.0 if (_death > 0.0 or _limb_factor(id) <= 0.0) else 0.0
			_droop[id] = move_toward(_droop[id], droop_target, DROOP_RATE * delta)
			var live := _motion_angle(flap, flap_phase, _flap_amp, factor)
			var drooped := deg_to_rad(float(flap.get("droop_deg", 0.0)))
			rotation[_axis_index(flap)] += lerpf(live, drooped, _droop[id])

		entry["pivot"].rotation = rotation


func _apply_rig() -> void:
	var collapse := _death * _death * (3.0 - 2.0 * _death)
	bob_y *= 1.0 - collapse
	_mech.rig.position.y = bob_y - float(_cfg.get("collapse_m", 0.0)) * collapse
	_mech.rig.rotation = Vector3(
		_pitch + deg_to_rad(float(_cfg.get("death_pitch_deg", 0.0))) * collapse,
		0.0,
		_roll + deg_to_rad(float(_cfg.get("death_roll_deg", 0.0))) * collapse
	)


## Angle in radians of one motion at a point in the cycle.
static func _motion_angle(motion: Dictionary, cycle: float, amplitude: float, factor: float) -> float:
	var swing := float(motion["deg"]) * amplitude * sin(TAU * (cycle + float(motion.get("phase", 0.0))))
	return deg_to_rad((float(motion.get("offset_deg", 0.0)) + swing) * factor)


static func _axis_index(motion: Dictionary) -> int:
	return ["x", "y", "z"].find(motion["axis"])
