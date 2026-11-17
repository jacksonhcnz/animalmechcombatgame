class_name Mech
extends CharacterBody3D
## An animal-shaped mech. The body is built from the boxes in its data file, in flat
## colours, and every box is also a hitbox. The pilot sits in the head: the cockpit
## camera is placed there, and the third-person camera orbits behind it.
##
## Forward is -Z. Aim (head and weapons) is separate from the direction the legs face.

signal hit_taken(result: Dictionary)
signal part_disabled(part_id: String)
signal destroyed(mech: Mech)
## A shot was fired. Servers broadcast it so every client can draw the tracer.
signal fired(from: Vector3, to: Vector3, color: Color)
## A beam weapon fired: the beam stays where it is and fades over `fade` seconds.
signal beam_fired(from: Vector3, to: Vector3, color: Color, width: float, fade: float)
## A real projectile left the muzzle: its start data, so a server can tell its clients.
signal projectile_launched(info: Dictionary)
## A projectile ended (hit something or ran out of life) at a position.
signal projectile_ended(id: int, pos: Vector3, exploded: bool)

const LAYER_WORLD := 1
const LAYER_HITBOX := 2
const LAYER_MECH := 4

const GRAVITY := 22.0
const GROUND_ACCEL := 5.0
const AIR_ACCEL := 3.0
const SINK_SPEED := 14.0
const AIR_CONTROL := 1.5
const DEAD_COLOR := Color("#2b2b2b")
## The colour of the tone "metal" in a part's visual pieces (silver bolts, nuts and joints).
const METAL_COLOR := Color("#d3d6da")

var def: Dictionary
var rules: Ruleset
var damage: DamageModel
var controls := MechControls.new()
var weapons: Array[WeaponState] = []
var team: int = 1
## Network mode: the mech is a display copy. It does no physics or shooting of its own;
## a client moves it from server snapshots and mirrors damage from server events.
var remote_mode: bool = false
## Flying mechs: seconds of boost left, whether it is locked while refilling, and whether it is on now.
var boost_left: float = 10.0
var boost_locked: bool = false
var boosting: bool = false
## Flying mechs: speed along the nose (m/s, negative until the first frame sets it), the nose pitch
## and bank in radians, whether the wings have stalled, and how fast it is falling in a stall.
var air_speed: float = -1.0
var flight_pitch: float = 0.0
var flight_roll: float = 0.0
var stalled: bool = false
var _sink: float = 0.0
## Sniper mode (the raptor's tail sniper): the mech has stopped and turned tail first to the aim,
## and the scope is up. `realigning` is the turn back round afterwards.
var sniping: bool = false
var _equip_was_down: bool = false
var realigning: bool = false
## How far the scope is zoomed in (1 is the plain view). Only the local pilot's copy uses it.
var scope_zoom: float = 1.0
var remote_grounded: bool = true
## Whoever last damaged this mech, so a server can credit the kill.
var last_attacker: Mech
var is_player: bool = false
var altitude_limit: float = 150.0
var aim_yaw: float = 0.0
var aim_pitch: float = 0.0
var view_third_person: bool = false
var cockpit_camera: Camera3D
var third_person_camera: Camera3D
## The cockpit frame around the camera. Only the local pilot has one, and only the cockpit view shows it.
var cockpit_interior: Node3D
## Holds every visible part and hitbox, so the animator can bob and tilt the whole body.
var rig: Node3D
## One pivot node per part. A part hangs from its parent part's pivot, so joints follow limbs.
var pivots: Dictionary = {}
var animator: MechAnimator

var _part_defs: Dictionary = {}
var _part_meshes: Dictionary = {}
var _hitboxes: Dictionary = {}
var _base_colors: Dictionary = {}
## Extra visual pieces of a part: part id -> [[material, base colour], ...]
var _piece_materials: Dictionary = {}
## The visible gun model of each ranged mount, by mount id.
var _guns: Dictionary = {}
var _own_rids: Array[RID] = []
var _aim_pivot: Node3D
var _aim_base_y: float = 0.0
var _third_pivot: Node3D
var _dead: bool = false
var _jump_cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


static func create(mech_id: String, ruleset: Ruleset, loadout: Dictionary = {}) -> Mech:
	var mech := Mech.new()
	mech.setup(mech_id, ruleset, loadout)
	return mech


## A display copy for a network client: it does no physics or shooting of its own.
static func create_remote(mech_id: String, ruleset: Ruleset) -> Mech:
	var mech := Mech.new()
	mech.remote_mode = true
	mech.setup(mech_id, ruleset)
	return mech


func setup(mech_id: String, ruleset: Ruleset, loadout: Dictionary = {}) -> void:
	def = Loadout.apply(GameData.get_entry("mechs", mech_id), loadout)
	rules = ruleset
	add_to_group("mechs")
	name = def.get("name", mech_id)
	damage = DamageModel.new(def, ruleset)
	damage.part_disabled.connect(_on_part_disabled)
	damage.destroyed.connect(_on_destroyed)
	var ammo_load := Points.ammo_for(def)
	for mount in def.get("mounts", []):
		var weapon := WeaponState.new(mount["id"], GameData.get_entry("weapons", mount["weapon"]), str(mount.get("slot", "")))
		weapon.ammo = int(ammo_load.get(mount["id"], weapon.ammo))
		weapons.append(weapon)
	_build_body()
	animator = MechAnimator.new(self)


func is_flying() -> bool:
	return def.get("movement", "ground") == "flying"


func is_dead() -> bool:
	return _dead


## On the ground. A display copy cannot ask the physics engine, so it uses what the server said.
func grounded() -> bool:
	return remote_grounded if remote_mode else is_on_floor()


## True if this mech can jump right now: a ground mech, standing on the floor, with the
## ruleset allowing it and the jump recovered.
func can_jump() -> bool:
	return not is_flying() and not _dead and rules.jumping and is_on_floor() \
		and _jump_cooldown <= 0.0 and float(def["base"].get("jump_speed", 0.0)) > 0.0


## Height above the ground to spawn at, so the body starts just above the floor.
func spawn_height() -> float:
	if is_flying():
		return float(def["base"].get("spawn_height", 15.0))
	return 0.3


## Turns this mech into the local player: creates the cameras and makes one current.
func make_player() -> void:
	is_player = true
	cockpit_camera = Camera3D.new()
	cockpit_camera.name = "CockpitCamera"
	cockpit_camera.fov = 80.0
	cockpit_camera.near = 0.2
	cockpit_camera.far = 3000.0
	_aim_pivot.add_child(cockpit_camera)
	cockpit_interior = CockpitInterior.build(def["cockpit_frame"], def["palette"])
	_aim_pivot.add_child(cockpit_interior)

	third_person_camera = Camera3D.new()
	third_person_camera.name = "ThirdPersonCamera"
	third_person_camera.fov = 70.0
	third_person_camera.near = 0.3
	third_person_camera.far = 3000.0
	var tp: Dictionary = def["third_person"]
	third_person_camera.position = Vector3(0.0, float(tp.get("height", 4.0)), float(tp["distance"]))
	_third_pivot.add_child(third_person_camera)

	apply_view_rules()


## Re-checks the camera against the ruleset, e.g. after a rule change.
func apply_view_rules() -> void:
	if not rules.third_person_allowed():
		view_third_person = false
	_update_cameras()


func toggle_view() -> void:
	if not is_player or not rules.third_person_allowed():
		return
	view_third_person = not view_third_person
	_update_cameras()


## Applies damage to a part. Returns the result of DamageModel.apply_damage.
func take_hit(part_id: String, amount: float, attacker: Mech = null) -> Dictionary:
	if attacker != null and attacker != self and attacker.team == team and not rules.friendly_fire:
		return {"part": part_id, "applied": 0.0, "disabled": false, "destroyed": false}
	var result := damage.apply_damage(part_id, amount)
	if result["applied"] > 0.0:
		if attacker != null and attacker != self:
			last_attacker = attacker
		_refresh_colors()
		result["raw"] = amount
		hit_taken.emit(result)
	return result


## A knockout shot: puts the part it hit out of action in one hit (a head hit knocks the
## pilot out). Falls back to `fallback` damage where a knockout does not apply.
func take_knockout(part_id: String, fallback: float, attacker: Mech = null) -> Dictionary:
	var amount := damage.knockout_amount(part_id)
	return take_hit(part_id, amount if amount > 0.0 else fallback, attacker)


## A shot that destroys the whole mech outright (the ion cannon), wherever it lands.
func take_kill(attacker: Mech = null) -> Dictionary:
	if attacker != null and attacker != self and attacker.team == team and not rules.friendly_fire:
		return {"part": "", "applied": 0.0, "disabled": false, "destroyed": false}
	var result := damage.kill()
	if attacker != null and attacker != self:
		last_attacker = attacker
	_refresh_colors()
	result["raw"] = 0.0
	hit_taken.emit(result)
	return result


## World position of the weapon mount, used as the muzzle for tracers.
func mount_position(mount_id: String) -> Vector3:
	for mount in def.get("mounts", []):
		if mount["id"] == mount_id and _part_meshes.has(mount["part"]):
			if _guns.has(mount_id):
				var gun: Node3D = _guns[mount_id]
				var muzzle := float(GameData.get_entry("weapons", str(mount["weapon"])).get("muzzle", 0.0))
				return gun.global_transform * Vector3(0.0, 0.0, -muzzle)
			return _part_meshes[mount["part"]].global_position
	return global_position


func aim_origin() -> Vector3:
	return _aim_pivot.global_position


func aim_direction() -> Vector3:
	return -_aim_pivot.global_transform.basis.z


## Copies a damage state from the server (used when a mech first appears on a client).
func mirror_state(state: Dictionary) -> void:
	damage.import_state(state)
	if damage.is_destroyed():
		_dead = true
		controls.clear()
	_refresh_colors()


func _physics_process(delta: float) -> void:
	if remote_mode:
		# A display copy only animates. The local player's copy still turns its own head at once.
		if is_player and not _dead:
			_update_aim()
			for weapon in weapons:
				if weapon.is_charged():
					weapon.show_charge((controls.fire_primary or controls.fire_secondary) if weapon.is_two_slot() else (controls.fire_primary if weapon.slot() == "primary" else controls.fire_secondary), delta)
		else:
			_apply_aim_pivots()
		_animate(delta)
		return
	for weapon in weapons:
		weapon.tick(delta)
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	if _dead:
		_fall(delta)
		_animate(delta)
		return
	_update_aim()
	if sniping and (not controls.is_idle_movement() or _dead or not _sniper_online()):
		set_sniping(false)
	_move(delta)
	_animate(delta)
	_handle_fire(delta)


func _animate(delta: float) -> void:
	animator.update(delta)
	_update_charge_glow()
	if is_player and cockpit_camera != null:
		# Looking back through the scope, the mech's own tail would fill the view: hide it.
		var hide_tail := sniping and not view_third_person
		for part in def["parts"]:
			if part.get("kind", "") == "tail" and _part_meshes.has(part["id"]):
				_part_meshes[part["id"]].visible = not hide_tail
		# The scope narrows the view: a zoom of 4 shows a quarter of the width.
		var narrow := 1.0 / maxf(scope_zoom, 1.0)
		cockpit_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(80.0) * 0.5) * narrow))
		third_person_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(70.0) * 0.5) * narrow))
	# The cockpit camera follows only a share of the body bob, set by the player's head bob setting.
	_aim_pivot.position.y = _aim_base_y + animator.bob_y * GameSettings.head_bob


func _update_aim() -> void:
	var base: Dictionary = def["base"]
	var twist := deg_to_rad(float(base["twist_limit_deg"]))
	var pitch_min := deg_to_rad(float(base["pitch_min_deg"]))
	var pitch_max := deg_to_rad(float(base["pitch_max_deg"]))
	if controls.center_aim:
		aim_yaw = 0.0
		aim_pitch = 0.0
		controls.center_aim = false
	var wanted_yaw := aim_yaw + controls.aim_yaw_delta
	var wanted_pitch := aim_pitch + controls.aim_pitch_delta
	if not is_nan(controls.aim_yaw_target):
		# A server is told where the pilot is aiming, not how far they turned.
		wanted_yaw = controls.aim_yaw_target
		wanted_pitch = controls.aim_pitch_target
		if controls.aim_world:
			wanted_yaw = wrapf(wanted_yaw - rotation.y, -PI, PI)
	if sniping or realigning:
		# While turning round the aim may point anywhere; the body swings under it.
		aim_yaw = wrapf(wanted_yaw, -PI, PI)
	elif twist >= PI:
		# A twist limit of 180 degrees or more means the aim can spin freely all the way round.
		aim_yaw = wrapf(wanted_yaw, -PI, PI)
	else:
		aim_yaw = clampf(wanted_yaw, -twist, twist)
	aim_pitch = clampf(wanted_pitch, pitch_min, pitch_max)
	controls.aim_yaw_delta = 0.0
	controls.aim_pitch_delta = 0.0
	_apply_aim_pivots()


func _apply_aim_pivots() -> void:
	_aim_pivot.rotation = Vector3(aim_pitch, aim_yaw, 0.0)
	_third_pivot.rotation = Vector3(aim_pitch, aim_yaw, 0.0)


## Seconds of boost in a full tank (flying mechs).
func boost_capacity() -> float:
	return Points.flight("boost_time")


## 0 to 1: how much boost is left.
func boost_ratio() -> float:
	return clampf(boost_left / boost_capacity(), 0.0, 1.0)


## Sets the boost from what the server reports (a display copy does not work it out itself).
func set_boost(ratio: float, locked: bool) -> void:
	boost_left = clampf(ratio, 0.0, 1.0) * boost_capacity()
	boost_locked = locked


## A flying mech holds Space to boost: faster in every direction, for a tank of 10 seconds. When the
## tank runs empty the boost is locked until it has refilled, which takes the cooldown.
func _update_boost(delta: float) -> void:
	var capacity := boost_capacity()
	var moving := true  # a flyer is always moving
	boosting = is_flying() and rules.sprinting and controls.sprint and moving and not boost_locked and boost_left > 0.0
	if boosting:
		boost_left = maxf(0.0, boost_left - delta)
		if boost_left <= 0.0:
			boost_locked = true
			boosting = false
	else:
		boost_left = minf(capacity, boost_left + capacity / Points.flight("boost_cooldown") * delta)
		if boost_locked and boost_left >= capacity:
			boost_locked = false


func _sniper_online() -> bool:
	for weapon in weapons:
		if weapon.is_scoped() and damage.mount_online(weapon.mount_id):
			return true
	return false


## Engages or leaves sniper mode. Leaving it turns the mech back round until the aim is inside its
## normal twist again (see _sniper_turn).
func set_sniping(on: bool) -> void:
	if on == sniping:
		return
	sniping = on
	if on:
		realigning = false
		scope_zoom = float(sniper_scope().get("start_zoom", 4.0))
	else:
		scope_zoom = 1.0
		var twist := deg_to_rad(float(def["base"]["twist_limit_deg"]))
		realigning = twist < PI and absf(aim_yaw) > twist


## The scope settings of the first scoped weapon this mech carries, or an empty dictionary.
func sniper_scope() -> Dictionary:
	for weapon in weapons:
		if weapon.is_scoped():
			return weapon.def["scope"]
	return {}


## Zooms the scope in (positive) or out (negative) by notches.
func zoom_scope(notches: float) -> void:
	if not sniping:
		return
	var scope := sniper_scope()
	scope_zoom = clampf(scope_zoom * pow(1.25, notches), float(scope.get("min_zoom", 2.0)), float(scope.get("max_zoom", 16.0)))


## True once the tail points at the aim (the aim is straight behind the body).
func sniper_aligned() -> bool:
	return PI - absf(wrapf(aim_yaw, -PI, PI)) < deg_to_rad(4.0)


## In sniper mode the mech stands still and swings round until its tail points along the aim,
## which stays fixed in the world. Afterwards it swings back until the aim is inside its normal
## twist limit. A server waits for the pilot to confirm the world aim before it turns.
func _sniper_turn(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if not is_nan(controls.aim_yaw_target) and not controls.aim_world:
		return
	var a := wrapf(aim_yaw, -PI, PI)
	var needed := 0.0
	if sniping:
		needed = a - (PI if a >= 0.0 else -PI)
	else:
		var limit := deg_to_rad(float(def["base"]["twist_limit_deg"]))
		if absf(a) <= limit:
			realigning = false
			return
		needed = a - signf(a) * limit * 0.9
	var step := clampf(needed, -1.0, 1.0) * minf(absf(needed), float(def["base"]["turn_rate"]) * 1.5 * damage.turn_mult() * delta)
	rotation.y += step
	aim_yaw = wrapf(aim_yaw - step, -PI, PI)
	_apply_aim_pivots()


## Speed multiplier while sprinting on the ground: Shift held, moving forward, ruleset allows it.
## Flying mechs boost instead (see _update_boost).
func sprint_mult() -> float:
	if controls.sprint and rules.sprinting and controls.throttle > 0.0:
		return float(Points.table().get("sprint", {}).get("speed_mult", 1.0))
	return 1.0


func _move(delta: float) -> void:
	if is_flying():
		_fly(delta)
		return
	if sniping or realigning:
		_sniper_turn(delta)
		return
	var base: Dictionary = def["base"]
	var c := controls
	# Turning right is a clockwise (negative) rotation about Y.
	rotation.y -= c.turn * float(base["turn_rate"]) * damage.turn_mult() * delta

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var wish := forward * c.throttle + right * c.strafe
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target := wish * float(base["speed"]) * damage.speed_mult() * sprint_mult()

	# In the air a mech can steer only a little, so a jump commits it to a direction.
	var accel := GROUND_ACCEL if is_on_floor() else AIR_CONTROL
	var flat := Vector2(velocity.x, velocity.z).lerp(Vector2(target.x, target.z), clampf(accel * delta, 0.0, 1.0))
	velocity.x = flat.x
	velocity.z = flat.y
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if c.jump and can_jump():
		velocity.y = float(base["jump_speed"]) * damage.speed_mult()
		_jump_cooldown = float(base.get("jump_cooldown", 0.8))
	move_and_slide()


## The most a flying mech can fly, in m/s along its nose: its speed stat times the flight multiplier,
## and faster again while boosting.
func top_air_speed() -> float:
	var top := float(def["base"]["speed"]) * damage.speed_mult() * Points.flight("max_speed_mult")
	return top * (Points.flight("boost_speed_mult") if boosting else 1.0)


## The speed below which a flying mech stalls. Damaged wings give less lift, so it stalls sooner.
func stall_air_speed() -> float:
	var top := float(def["base"]["speed"]) * damage.speed_mult() * Points.flight("max_speed_mult")
	return top * Points.flight("stall_fraction") / maxf(damage.lift_mult(), 0.2)


## Flying like a plane. A flyer is always moving along its nose. Shift and Ctrl set the
## throttle, A and D bank and turn, W and S pitch the nose down and up (Q and E nudge the
## rudder). Climbing and turning cost speed and diving gains it. Below the stall speed the
## wings stop lifting: the controls go soft, the nose drops and the mech falls until it picks
## speed up again.
func _fly(delta: float) -> void:
	var c := controls
	_update_boost(delta)
	var top := top_air_speed()
	var cruise := float(def["base"]["speed"]) * damage.speed_mult() * Points.flight("max_speed_mult") * Points.flight("cruise_fraction")
	var idle := top / maxf(1.0, Points.flight("boost_speed_mult") if boosting else 1.0) * Points.flight("idle_fraction")
	var stall := stall_air_speed()
	if air_speed < 0.0:
		air_speed = cruise
	# The throttle sets the speed it settles at: idle when pulled right back, the top when pushed.
	var target := cruise
	if c.throttle < 0.0:
		target = lerpf(cruise, idle, -c.throttle)
	elif c.throttle > 0.0:
		target = lerpf(cruise, top, c.throttle)
	if boosting:
		target = top
	air_speed += (target - air_speed) * clampf(Points.flight("throttle_response") * delta, 0.0, 1.0)
	# Gravity: climbing bleeds speed, diving builds it.
	air_speed -= sin(flight_pitch) * Points.flight("gravity_coupling") * delta
	air_speed = clampf(air_speed, 0.0, top * 1.4)

	var lift_factor := clampf(air_speed / stall, 0.0, 1.0)
	stalled = lift_factor < 1.0
	var max_pitch := deg_to_rad(Points.flight("max_pitch_deg"))
	flight_pitch += c.vertical * Points.flight("pitch_rate") * lift_factor * delta
	if stalled:
		flight_pitch = move_toward(flight_pitch, -1.0, (1.0 - lift_factor) * Points.flight("stall_nose_drop") * delta)
	flight_pitch = clampf(flight_pitch, -max_pitch, max_pitch)
	# Turning right banks right: a negative roll. The bank is what turns the nose.
	var roll_target := -c.turn * deg_to_rad(Points.flight("max_roll_deg")) * lift_factor
	flight_roll = move_toward(flight_roll, roll_target, Points.flight("roll_rate") * delta)
	var turn_scale := clampf(air_speed / maxf(cruise, 1.0), 0.6, 1.2)
	rotation.y += sin(flight_roll) * Points.flight("turn_rate") * damage.turn_mult() * turn_scale * delta
	rotation.y -= c.strafe * Points.flight("rudder_rate") * lift_factor * delta
	rotation.x = flight_pitch
	rotation.z = flight_roll

	if stalled:
		_sink = minf(_sink + GRAVITY * (1.0 - lift_factor) * delta, 55.0)
	else:
		_sink = maxf(0.0, _sink - 60.0 * delta)
	var forward := -global_transform.basis.z
	velocity = forward * air_speed + Vector3.DOWN * _sink
	move_and_slide()

	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		if hit.get_normal().y > 0.7:
			# Belly on the ground: the nose cannot point into it, and it skids to a stop.
			flight_pitch = maxf(flight_pitch, 0.0)
			air_speed = maxf(0.0, air_speed - 25.0 * delta)
			_sink = 0.0
		else:
			# Struck a wall or a cliff.
			air_speed *= 0.6

	if global_position.y > altitude_limit:
		global_position.y = altitude_limit
		velocity.y = minf(velocity.y, 0.0)
		flight_pitch = minf(flight_pitch, 0.0)


func _fall(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, clampf(2.0 * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, 0.0, clampf(2.0 * delta, 0.0, 1.0))
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


func _handle_fire(delta: float) -> void:
	# F switches the sniper scope on and off.
	var equip_pressed := controls.use_equipment and not _equip_was_down
	_equip_was_down = controls.use_equipment
	if equip_pressed and _sniper_online():
		set_sniping(not sniping)
	for weapon in weapons:
		if sniping and not weapon.is_scoped():
			continue  # the guns are put away while the mech is lined up for the sniper
		var wanted := false
		if weapon.is_two_slot():
			wanted = controls.fire_primary or controls.fire_secondary
		else:
			match weapon.slot():
				"primary":
					wanted = controls.fire_primary
				"secondary":
					wanted = controls.fire_secondary
				"melee":
					wanted = controls.fire_melee
				"bomb":
					wanted = controls.fire_bomb
		var usable := weapon.ready_to_fire() and weapon.has_ammo(rules) and damage.mount_online(weapon.mount_id)
		if weapon.is_scoped():
			# With the scope up, a press of either fire button takes aim and letting go fires
			# (if the tail is on the aim).
			wanted = controls.fire_primary or controls.fire_secondary
			var fresh_press := wanted and not weapon.button_was_down
			var released := weapon.button_was_down and not wanted
			weapon.button_was_down = wanted
			if not sniping:
				weapon.sniper_armed = false
			elif fresh_press:
				weapon.sniper_armed = true
			elif released and weapon.sniper_armed:
				weapon.sniper_armed = false
				if usable and sniper_aligned():
					weapon.consume(rules)
					_fire(weapon)
			continue
		if weapon.is_charged():
			# Hold to cock it, let go to fire. The longer the hold, the higher the burst.
			if wanted and usable:
				weapon.charge_time = minf(weapon.charge_time + delta, weapon.charge_max())
				continue
			if weapon.charge_time <= 0.0:
				continue
			var held := weapon.charge_time
			weapon.charge_time = 0.0
			if not usable:
				continue
			if weapon.needs_full_charge() and held < weapon.charge_max() - 0.001:
				continue  # let go too soon: the shot is lost
			weapon.consume(rules)
			if weapon.def.has("projectile"):
				_launch(weapon, weapon.burst_height(held))
			else:
				_fire(weapon)
			continue
		if not wanted or not usable:
			continue
		weapon.consume(rules)
		_fire(weapon)


func _fire(weapon: WeaponState) -> void:
	if weapon.def.has("projectile"):
		_launch(weapon)
		return
	var origin := aim_origin()
	var dir := aim_direction()
	var spread := deg_to_rad(float(weapon.def.get("spread_deg", 0.0)))
	if spread > 0.0:
		dir = _apply_spread(dir, spread)
	var reach := float(weapon.def["range"])
	var end := origin + dir * reach

	var query := PhysicsRayQueryParameters3D.create(origin, end, LAYER_WORLD | LAYER_HITBOX)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _own_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit["position"]
		var collider: Object = hit["collider"]
		if collider is Node and collider.has_meta("part_id"):
			var target: Mech = collider.get_meta("mech")
			if is_instance_valid(target):
				if bool(weapon.def.get("kill", false)):
					target.take_kill(self)
				else:
					target.take_hit(collider.get_meta("part_id"), float(weapon.def["damage"]) * float(def.get("damage_mult", 1.0)), self)

	if weapon.def.has("beam"):
		var beam: Dictionary = weapon.def["beam"]
		var beam_color := Color.html(weapon.def.get("tracer_color", "#ffffff"))
		var beam_from := mount_position(weapon.mount_id)
		beam_fired.emit(beam_from, end, beam_color, float(beam["width"]), float(beam["fade"]))
		spawn_beam(get_parent(), beam_from, end, beam_color, float(beam["width"]), float(beam["fade"]))
	elif not weapon.is_melee():
		var tracer_color := Color.html(weapon.def.get("tracer_color", "#ffffff"))
		var muzzle := mount_position(weapon.mount_id)
		fired.emit(muzzle, end, tracer_color)
		spawn_tracer(get_parent(), muzzle, end, tracer_color)


## Where a bomb dropped now would land: its arc is followed step by step until it meets the world
## or a mech. Returns the point, or null if it would not land within a few seconds.
func predict_drop(weapon: WeaponState) -> Variant:
	var cfg: Dictionary = weapon.def["projectile"]
	var gravity := float(cfg.get("gravity", 0.0))
	var position := mount_position(weapon.mount_id)
	var speed := velocity + Vector3.DOWN * float(cfg["speed"])
	var space := get_world_3d().direct_space_state
	for step in 160:
		var next := position + speed * 0.05
		var query := PhysicsRayQueryParameters3D.create(position, next, LAYER_WORLD | LAYER_HITBOX)
		query.collide_with_areas = true
		query.exclude = _own_rids
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit["position"]
		position = next
		speed.y -= gravity * 0.05
	return null


## Fires a projectile from the muzzle at the point the crosshair is on. Grenades are lobbed
## on an arc to land there.
func _launch(weapon: WeaponState, burst_height: float = 0.0) -> void:
	var origin := aim_origin()
	var dir := aim_direction()
	var spread := deg_to_rad(float(weapon.def.get("spread_deg", 0.0)))
	if spread > 0.0:
		dir = _apply_spread(dir, spread)
	var reach := float(weapon.def["range"])
	var aim_point := origin + dir * reach
	var query := PhysicsRayQueryParameters3D.create(origin, aim_point, LAYER_WORLD | LAYER_HITBOX)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _own_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit["position"]
	var muzzle := mount_position(weapon.mount_id)
	var shot := Projectile.fire(weapon.def, muzzle, aim_point, self, float(def.get("damage_mult", 1.0)), burst_height)
	var parent := get_parent()
	if parent == null:
		shot.free()
		return
	parent.add_child(shot)
	shot.global_position = muzzle
	shot.finished.connect(func(id: int, pos: Vector3, exploded: bool) -> void: projectile_ended.emit(id, pos, exploded))
	projectile_launched.emit(shot.to_info())


func own_rids() -> Array[RID]:
	return _own_rids


## The part whose hitbox is nearest a point, as [part id, distance]. Used for blast damage.
func nearest_part(point: Vector3) -> Array:
	var best_id := ""
	var best := INF
	for part_id in _hitboxes:
		var distance := (_hitboxes[part_id] as Node3D).global_position.distance_to(point)
		if distance < best:
			best = distance
			best_id = part_id
	return [best_id, best]


func _apply_spread(dir: Vector3, spread: float) -> Vector3:
	var helper := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var side := dir.cross(helper).normalized()
	var up := side.cross(dir).normalized()
	var angle := _rng.randf() * TAU
	var amount := _rng.randf() * spread
	return (dir + (side * cos(angle) + up * sin(angle)) * tan(amount)).normalized()


## Draws a short-lived line between two points. Clients use it for tracers the server reports.
static func spawn_tracer(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var tracer := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, length)
	tracer.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.material_override = material
	parent.add_child(tracer)
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	tracer.look_at_from_position((from + to) * 0.5, to, up)
	parent.get_tree().create_timer(0.08).timeout.connect(tracer.queue_free)


## Draws a beam that stays where it was fired and fades away over `fade` seconds: a white core
## inside a coloured sheath. Clients use it for the beams the server reports.
static func spawn_beam(parent: Node, from: Vector3, to: Vector3, color: Color, width: float, fade: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var holder := Node3D.new()
	parent.add_child(holder)
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	holder.look_at_from_position((from + to) * 0.5, to, up)
	var materials: Array[StandardMaterial3D] = []
	for layer in [[width, color], [width * 0.35, Color.WHITE]]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(layer[0], layer[0], length)
		piece.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = layer[1]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		piece.material_override = material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(piece)
		materials.append(material)
	var tween := holder.create_tween()
	tween.tween_method(func(alpha: float) -> void:
		for material in materials:
			material.albedo_color.a = alpha, 1.0, 0.0, fade)
	tween.tween_callback(holder.queue_free)


func _build_body() -> void:
	collision_layer = LAYER_MECH
	collision_mask = LAYER_WORLD | LAYER_MECH

	var collider: Dictionary = def["collider"]
	var body_shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = _vec3(collider["size"])
	body_shape.shape = body_box
	body_shape.position = _vec3(collider["center"])
	add_child(body_shape)

	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)

	var palette: Dictionary = def["palette"]
	var parts: Array = def["parts"]
	for part in parts:
		_part_defs[part["id"]] = part

	# Pivots first, parents before children, so each part can hang from its parent's pivot.
	var pivot_world: Dictionary = {}
	var pending: Array = parts.duplicate()
	while not pending.is_empty():
		var progressed := false
		for part in pending.duplicate():
			var part_id: String = part["id"]
			var parent_id: String = part.get("parent", "")
			if parent_id != "" and not pivots.has(parent_id):
				continue
			var world := _vec3(part.get("anim", {}).get("pivot", part["pos"]))
			var pivot := Node3D.new()
			pivot.name = "Pivot_" + part_id
			var parent_world: Vector3 = pivot_world[parent_id] if parent_id != "" else Vector3.ZERO
			pivot.position = world - parent_world
			(pivots[parent_id] if parent_id != "" else rig).add_child(pivot)
			pivots[part_id] = pivot
			pivot_world[part_id] = world
			pending.erase(part)
			progressed = true
		if not progressed:
			push_error("%s: parts have a parent loop" % name)
			break

	for part in parts:
		var part_id: String = part["id"]
		var size := _vec3(part["size"])
		var pivot_pos: Vector3 = pivot_world[part_id]
		var local: Vector3 = _vec3(part["pos"]) - pivot_pos
		var rot := _vec3(part.get("rot_deg", [0.0, 0.0, 0.0]))

		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Part_" + part_id
		var box := BoxMesh.new()
		box.size = size
		mesh_node.mesh = box
		var material := StandardMaterial3D.new()
		var color := Color.html(palette[part["tone"]])
		material.albedo_color = color
		material.roughness = 1.0
		mesh_node.material_override = material
		mesh_node.position = local
		mesh_node.rotation_degrees = rot
		if part.has("visual"):
			# The part is drawn as a set of shaped pieces instead of its plain box. Its hitbox
			# still uses `size`, so the look can change without changing gameplay.
			mesh_node.mesh = null
			_build_visual(part_id, mesh_node, part["visual"], palette)
		pivots[part_id].add_child(mesh_node)
		_part_meshes[part_id] = mesh_node
		_base_colors[part_id] = color

		var hitbox := Area3D.new()
		hitbox.name = "Hitbox_" + part_id
		hitbox.collision_layer = LAYER_HITBOX
		hitbox.collision_mask = 0
		hitbox.monitoring = false
		hitbox.position = local
		hitbox.rotation_degrees = rot
		var hit_shape := CollisionShape3D.new()
		var hit_box := BoxShape3D.new()
		hit_box.size = size
		hit_shape.shape = hit_box
		hitbox.add_child(hit_shape)
		hitbox.set_meta("part_id", part_id)
		hitbox.set_meta("mech", self)
		pivots[part_id].add_child(hitbox)
		_hitboxes[part_id] = hitbox
		_own_rids.append(hitbox.get_rid())

	_build_guns(palette)

	var head: Dictionary = _part_defs["head"]
	var cockpit_pos := _vec3(head["pos"]) + _vec3(def["cockpit"])
	_aim_pivot = Node3D.new()
	_aim_pivot.name = "AimPivot"
	_aim_pivot.position = cockpit_pos
	_aim_base_y = cockpit_pos.y
	add_child(_aim_pivot)
	_third_pivot = Node3D.new()
	_third_pivot.name = "ThirdPersonPivot"
	_third_pivot.position = cockpit_pos
	add_child(_third_pivot)


## A glowing ball at the muzzle of a weapon that needs a full charge, growing as it charges.
func _update_charge_glow() -> void:
	for weapon in weapons:
		if not weapon.needs_full_charge() or not _guns.has(weapon.mount_id):
			continue
		var glow: MeshInstance3D = _guns[weapon.mount_id].get_node_or_null("ChargeGlow")
		if glow == null:
			glow = MeshInstance3D.new()
			glow.name = "ChargeGlow"
			var ball := SphereMesh.new()
			ball.radius = 0.5
			ball.height = 1.0
			glow.mesh = ball
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.html(str(weapon.def.get("tracer_color", "#ffffff")))
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.material_override = material
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.position = Vector3(0.0, 0.0, -float(weapon.def.get("muzzle", 1.0)))
			_guns[weapon.mount_id].add_child(glow)
		var ratio := weapon.charge_ratio()
		glow.visible = ratio > 0.0
		glow.scale = Vector3.ONE * (0.3 + 1.7 * ratio)


## Draws each ranged mount's weapon (its `visual` in the weapon data) on the part that carries it,
## pointing forward. A mount can set `gun_scale` and `gun_offset` for a small or offset mount.
func _build_guns(palette: Dictionary) -> void:
	for mount in def.get("mounts", []):
		var weapon_def := GameData.get_entry("weapons", str(mount["weapon"]))
		if not weapon_def.has("visual") or not _part_meshes.has(mount["part"]):
			continue
		var gun := Node3D.new()
		gun.name = "Gun_" + str(mount["id"])
		gun.scale = Vector3.ONE * float(mount.get("gun_scale", 1.0))
		gun.position = _vec3(mount.get("gun_offset", [0.0, 0.0, 0.0]))
		if mount.has("gun_rot_deg"):
			gun.rotation_degrees = _vec3(mount["gun_rot_deg"])
		_part_meshes[mount["part"]].add_child(gun)
		_build_visual(mount["part"], gun, weapon_def["visual"], palette)
		_guns[mount["id"]] = gun


## Builds the shaped pieces of a part (see data/README.md, "visual").
func _build_visual(part_id: String, holder: Node3D, pieces: Array, palette: Dictionary) -> void:
	var materials: Array = _piece_materials.get(part_id, [])
	for piece in pieces:
		var mesh_piece := MeshInstance3D.new()
		var size := _vec3(piece["size"]) if piece.has("size") else Vector3.ONE
		match piece.get("shape", "box"):
			"plate":
				mesh_piece.mesh = _plate_mesh(piece["points"], float(piece["thickness"]), float(piece.get("round", 0.0)))
			"sphere":
				var sphere := SphereMesh.new()
				sphere.radius = size.x * 0.5
				sphere.height = size.x
				sphere.radial_segments = 16
				sphere.rings = 8
				mesh_piece.mesh = sphere
			"cylinder", "hex":
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = size.x * 0.5
				cylinder.bottom_radius = size.x * 0.5
				cylinder.height = size.y
				cylinder.radial_segments = 6 if piece["shape"] == "hex" else 16
				cylinder.rings = 1
				mesh_piece.mesh = cylinder
			_:
				var box := BoxMesh.new()
				box.size = size
				mesh_piece.mesh = box
		var tone: String = piece["tone"]
		var color := METAL_COLOR if tone == "metal" else Color.html(palette[tone])
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		mesh_piece.material_override = material
		mesh_piece.position = _vec3(piece.get("pos", [0.0, 0.0, 0.0]))
		mesh_piece.rotation_degrees = _vec3(piece.get("rot_deg", [0.0, 0.0, 0.0]))
		holder.add_child(mesh_piece)
		materials.append([material, color])
	_piece_materials[part_id] = materials


## A flat plate: the outline `points` ([x, y] pairs, drawn in the piece's own XY plane) pushed out
## to `thickness` along Z, with corners rounded by `round_radius`. Like a stamped metal plate.
static func _plate_mesh(points: Array, thickness: float, round_radius: float) -> ArrayMesh:
	var outline := PackedVector2Array()
	for point in points:
		outline.append(Vector2(float(point[0]), float(point[1])))
	if round_radius > 0.0:
		outline = _round_outline(outline, round_radius)
	if Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var half := thickness * 0.5
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := Geometry2D.triangulate_polygon(outline)
	for face in [1.0, -1.0]:
		var normal := Vector3(0.0, 0.0, face)
		for k in range(0, cap.size(), 3):
			_add_triangle(tool, normal,
				Vector3(outline[cap[k]].x, outline[cap[k]].y, half * face),
				Vector3(outline[cap[k + 1]].x, outline[cap[k + 1]].y, half * face),
				Vector3(outline[cap[k + 2]].x, outline[cap[k + 2]].y, half * face))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if a.is_equal_approx(b):
			continue
		var edge := b - a
		var side := Vector3(edge.y, -edge.x, 0.0).normalized()
		var a_top := Vector3(a.x, a.y, half)
		var b_top := Vector3(b.x, b.y, half)
		var a_bottom := Vector3(a.x, a.y, -half)
		var b_bottom := Vector3(b.x, b.y, -half)
		_add_triangle(tool, side, a_top, b_top, b_bottom)
		_add_triangle(tool, side, a_top, b_bottom, a_bottom)
	return tool.commit()


## Adds one triangle, ordered so that it faces along `normal` (Godot treats clockwise as the front).
static func _add_triangle(tool: SurfaceTool, normal: Vector3, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0:
		var swap := p1
		p1 = p2
		p2 = swap
	for point in [p0, p1, p2]:
		tool.set_normal(normal)
		tool.add_vertex(point)


## Rounds every corner of an outline with a small curve of the given radius.
static func _round_outline(outline: PackedVector2Array, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := outline.size()
	var steps := 4
	for i in count:
		var corner := outline[i]
		var to_prev := outline[(i - 1 + count) % count] - corner
		var to_next := outline[(i + 1) % count] - corner
		var reach := minf(radius, minf(to_prev.length(), to_next.length()) * 0.5)
		var start := corner + to_prev.normalized() * reach
		var end := corner + to_next.normalized() * reach
		for k in steps + 1:
			var f := float(k) / float(steps)
			result.append(start * (1.0 - f) * (1.0 - f) + corner * 2.0 * f * (1.0 - f) + end * f * f)
	return result


func _update_cameras() -> void:
	if cockpit_camera == null:
		return
	cockpit_camera.current = not view_third_person
	third_person_camera.current = view_third_person
	# From inside the cockpit the pilot should not see the inside of their own head.
	_part_meshes["head"].visible = view_third_person
	cockpit_interior.visible = not view_third_person


func _refresh_colors() -> void:
	for part_id in _part_meshes:
		var color: Color = _base_colors[part_id]
		var ratio := damage.part_ratio(part_id)
		if _dead or (rules.location_damage and damage.is_part_disabled(part_id)):
			color = DEAD_COLOR
		else:
			color = color.lerp(DEAD_COLOR, (1.0 - ratio) * 0.6)
		_part_meshes[part_id].material_override.albedo_color = color
		var tint := 1.0 if (_dead or (rules.location_damage and damage.is_part_disabled(part_id))) else (1.0 - ratio) * 0.6
		for piece in _piece_materials.get(part_id, []):
			var base: Color = piece[1]
			piece[0].albedo_color = base.lerp(DEAD_COLOR, tint)


func _on_part_disabled(part_id: String) -> void:
	part_disabled.emit(part_id)


func _on_destroyed() -> void:
	_dead = true
	controls.clear()
	_refresh_colors()
	destroyed.emit(self)


static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
