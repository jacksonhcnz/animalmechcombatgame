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

const LAYER_WORLD := 1
const LAYER_HITBOX := 2
const LAYER_MECH := 4

const GRAVITY := 22.0
const GROUND_ACCEL := 5.0
const AIR_ACCEL := 3.0
const SINK_SPEED := 14.0
const AIR_CONTROL := 1.5
const DEAD_COLOR := Color("#2b2b2b")

var def: Dictionary
var rules: Ruleset
var damage: DamageModel
var controls := MechControls.new()
var weapons: Array[WeaponState] = []
var team: int = 1
## Network mode: the mech is a display copy. It does no physics or shooting of its own;
## a client moves it from server snapshots and mirrors damage from server events.
var remote_mode: bool = false
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
var _own_rids: Array[RID] = []
var _aim_pivot: Node3D
var _aim_base_y: float = 0.0
var _third_pivot: Node3D
var _dead: bool = false
var _jump_cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


static func create(mech_id: String, ruleset: Ruleset) -> Mech:
	var mech := Mech.new()
	mech.setup(mech_id, ruleset)
	return mech


## A display copy for a network client: it does no physics or shooting of its own.
static func create_remote(mech_id: String, ruleset: Ruleset) -> Mech:
	var mech := Mech.new()
	mech.remote_mode = true
	mech.setup(mech_id, ruleset)
	return mech


func setup(mech_id: String, ruleset: Ruleset) -> void:
	def = GameData.get_entry("mechs", mech_id)
	rules = ruleset
	name = def.get("name", mech_id)
	damage = DamageModel.new(def, ruleset)
	damage.part_disabled.connect(_on_part_disabled)
	damage.destroyed.connect(_on_destroyed)
	for mount in def.get("mounts", []):
		weapons.append(WeaponState.new(mount["id"], GameData.get_entry("weapons", mount["weapon"])))
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


## World position of the weapon mount, used as the muzzle for tracers.
func mount_position(mount_id: String) -> Vector3:
	for mount in def.get("mounts", []):
		if mount["id"] == mount_id and _part_meshes.has(mount["part"]):
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
	_move(delta)
	_animate(delta)
	_handle_fire()


func _animate(delta: float) -> void:
	animator.update(delta)
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
	if twist >= PI:
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


func _move(delta: float) -> void:
	var base: Dictionary = def["base"]
	var c := controls
	# Turning right is a clockwise (negative) rotation about Y.
	rotation.y -= c.turn * float(base["turn_rate"]) * damage.turn_mult() * delta

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var wish := forward * c.throttle + right * c.strafe
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target := wish * float(base["speed"]) * damage.speed_mult()

	if is_flying():
		var lift := damage.lift_mult()
		var climb := c.vertical * float(base.get("climb_speed", 10.0)) * lift
		if is_zero_approx(c.vertical) and lift < 0.5:
			climb = -SINK_SPEED * (1.0 - lift)
		target.y = climb
		velocity = velocity.lerp(target, clampf(AIR_ACCEL * delta, 0.0, 1.0))
	else:
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

	if is_flying() and global_position.y > altitude_limit:
		global_position.y = altitude_limit
		velocity.y = minf(velocity.y, 0.0)


func _fall(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, clampf(2.0 * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, 0.0, clampf(2.0 * delta, 0.0, 1.0))
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()


func _handle_fire() -> void:
	for weapon in weapons:
		var wanted := false
		match weapon.slot():
			"primary":
				wanted = controls.fire_primary
			"secondary":
				wanted = controls.fire_secondary
			"melee":
				wanted = controls.fire_melee
		if not wanted or not weapon.ready_to_fire() or not weapon.has_ammo(rules):
			continue
		if not damage.mount_online(weapon.mount_id):
			continue
		weapon.consume(rules)
		_fire(weapon)


func _fire(weapon: WeaponState) -> void:
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
				target.take_hit(collider.get_meta("part_id"), float(weapon.def["damage"]), self)

	if not weapon.is_melee():
		var tracer_color := Color.html(weapon.def.get("tracer_color", "#ffffff"))
		var muzzle := mount_position(weapon.mount_id)
		fired.emit(muzzle, end, tracer_color)
		spawn_tracer(get_parent(), muzzle, end, tracer_color)


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


func _on_part_disabled(part_id: String) -> void:
	part_disabled.emit(part_id)


func _on_destroyed() -> void:
	_dead = true
	controls.clear()
	_refresh_colors()
	destroyed.emit(self)


static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
