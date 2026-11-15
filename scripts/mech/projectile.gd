class_name Projectile
extends Node3D
## A shot in flight. The server (or the offline test range) runs the real one: it flies,
## falls under gravity if the weapon has any (grenades arc), hits the first thing in its path
## and deals damage. Network clients run a visual copy that does no damage and is ended by
## a message from the server.

signal finished(id: int, pos: Vector3, exploded: bool)

const LIFT := Vector3.UP

static var _next_id: int = 1

var id: int = 0
var model: String = "bullet"
var velocity: Vector3 = Vector3.ZERO
var gravity: float = 0.0
var life: float = 2.0
var color: Color = Color.WHITE
var damage_amount: float = 0.0
var splash_radius: float = 0.0
var splash_damage: float = 0.0
var shooter: Mech
var authoritative: bool = false

var _done: bool = false


## A real projectile for a weapon, fired from `muzzle` towards `aim_point`.
static func fire(weapon_def: Dictionary, muzzle: Vector3, aim_point: Vector3, shooter_mech: Mech, damage_mult: float) -> Projectile:
	var cfg: Dictionary = weapon_def["projectile"]
	var p := Projectile.new()
	p.id = _next_id
	_next_id += 1
	p.model = str(cfg.get("model", "bullet"))
	p.gravity = float(cfg.get("gravity", 0.0))
	var speed := float(cfg["speed"])
	p.velocity = launch_velocity(muzzle, aim_point, speed, p.gravity, float(cfg.get("min_arc_deg", 0.0)))
	var reach := float(weapon_def["range"])
	p.life = reach / speed + 0.3 if p.gravity <= 0.0 else 9.0
	p.color = Color.html(str(weapon_def.get("tracer_color", "#ffffff")))
	p.damage_amount = float(weapon_def["damage"]) * damage_mult
	p.splash_radius = float(cfg.get("splash_radius", 0.0))
	p.splash_damage = float(cfg.get("splash_damage", 0.0)) * damage_mult
	p.shooter = shooter_mech
	p.authoritative = true
	return p


## The velocity to launch with so a shot reaches `to`. With no gravity it is straight at the
## target. With gravity it is a lob: the low arc at full speed, or, when that would be flatter
## than `min_arc_deg`, a slower throw at that steeper angle so the arc stays clearly visible.
## Out of reach it is the 45 degree angle at full speed, which goes furthest.
static func launch_velocity(from: Vector3, to: Vector3, speed: float, g: float, min_arc_deg: float = 0.0) -> Vector3:
	var delta := to - from
	if g <= 0.0:
		return (delta.normalized() if delta.length() > 0.01 else Vector3.FORWARD) * speed
	var flat := Vector3(delta.x, 0.0, delta.z)
	var x := flat.length()
	if x < 0.01:
		return (Vector3.UP if delta.y > 0.0 else Vector3.DOWN) * speed
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * delta.y * v2)
	if disc < 0.0:
		return (flat.normalized() * cos(PI / 4.0) + Vector3.UP * sin(PI / 4.0)) * speed
	var angle := atan((v2 - sqrt(disc)) / (g * x))
	var chosen_speed := speed
	var floor_angle := deg_to_rad(min_arc_deg)
	if angle < floor_angle:
		var denominator := 2.0 * cos(floor_angle) * cos(floor_angle) * (x * tan(floor_angle) - delta.y)
		if denominator > 0.0:
			var needed := sqrt(g * x * x / denominator)
			if needed <= speed:
				angle = floor_angle
				chosen_speed = needed
	return (flat.normalized() * cos(angle) + Vector3.UP * sin(angle)) * chosen_speed


func to_info() -> Dictionary:
	return {"id": id, "model": model, "pos": global_position if is_inside_tree() else position, "vel": velocity, "g": gravity, "life": life, "color": color.to_html(false), "r": splash_radius}


## A display-only copy built from `to_info` (what a network client does).
static func from_info(info: Dictionary) -> Projectile:
	var p := Projectile.new()
	p.id = int(info["id"])
	p.model = str(info["model"])
	p.velocity = info["vel"]
	p.gravity = float(info["g"])
	p.life = float(info["life"])
	p.color = Color.html(str(info["color"]))
	p.splash_radius = float(info.get("r", 0.0))
	return p


func _ready() -> void:
	_build_model()
	_face_velocity()


func _physics_process(delta: float) -> void:
	if _done:
		return
	var from := global_position
	velocity.y -= gravity * delta
	var to := from + velocity * delta
	life -= delta
	if authoritative:
		var query := PhysicsRayQueryParameters3D.create(from, to, Mech.LAYER_WORLD | Mech.LAYER_HITBOX)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		if shooter != null and is_instance_valid(shooter):
			query.exclude = shooter.own_rids()
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit["position"]
			_impact(hit["collider"])
			return
		if life <= 0.0:
			# A lob that never reached anything still bursts where it stopped.
			_end(gravity > 0.0 and splash_radius > 0.0)
			return
	elif life <= 0.0:
		_end(false)
		return
	global_position = to
	_face_velocity()


func _face_velocity() -> void:
	if velocity.length() > 0.1:
		var dir := velocity.normalized()
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		global_basis = Basis.looking_at(dir, up)


func _impact(collider: Object) -> void:
	var direct: Mech = null
	if collider is Node and collider.has_meta("part_id"):
		direct = collider.get_meta("mech")
		if is_instance_valid(direct) and shooter != null:
			direct.take_hit(collider.get_meta("part_id"), damage_amount, shooter)
		else:
			direct = null
	if splash_radius > 0.0 and splash_damage > 0.0:
		for node in get_tree().get_nodes_in_group("mechs"):
			var other := node as Mech
			if other == null or other == direct or other == shooter or other.is_dead() or other.remote_mode:
				continue
			var near := other.nearest_part(global_position)
			var distance := float(near[1])
			if distance < splash_radius:
				other.take_hit(str(near[0]), splash_damage * (1.0 - distance / splash_radius), shooter)
	_end(splash_radius > 0.0)


func _end(exploded: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(id, global_position, exploded)
	if exploded:
		spawn_explosion(get_parent(), global_position, splash_radius, color)
	queue_free()


## A quick expanding burst, used where a rocket or grenade lands.
static func spawn_explosion(parent: Node, pos: Vector3, radius: float, tint: Color) -> void:
	if parent == null or not parent.is_inside_tree() or radius <= 0.0:
		return
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.6, 0.2, 0.85).lerp(tint, 0.25)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = material
	ball.scale = Vector3.ONE * radius * 0.2
	parent.add_child(ball)
	ball.global_position = pos
	var tween := ball.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * radius * 0.6, 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(ball.queue_free)


# ---- models

func _build_model() -> void:
	match model:
		"rocket":
			_build_rocket()
		"grenade":
			_build_grenade()
		"pellet":
			_add_mesh(_sphere(0.34), Vector3.ZERO, Vector3.ZERO, color, true)
		_:
			var length := 1.4
			_add_mesh(_box(Vector3(0.16, 0.16, length)), Vector3.ZERO, Vector3.ZERO, color, true)
			_add_mesh(_box(Vector3(0.07, 0.07, length * 1.5)), Vector3.ZERO, Vector3.ZERO, Color.WHITE, true)


func _build_rocket() -> void:
	var metal := Color("#d3d6da")
	var red := Color("#c0392b")
	_add_mesh(_cylinder(0.36, 0.36, 1.7), Vector3.ZERO, Vector3(90, 0, 0), metal, false)
	_add_mesh(_cylinder(0.0, 0.36, 0.7), Vector3(0, 0, -1.2), Vector3(-90, 0, 0), red, false)
	_add_mesh(_cylinder(0.38, 0.38, 0.12), Vector3(0, 0, -0.5), Vector3(90, 0, 0), red, false)
	_add_mesh(_box(Vector3(0.9, 0.05, 0.45)), Vector3(0, 0, 0.7), Vector3.ZERO, red, false)
	_add_mesh(_box(Vector3(0.05, 0.9, 0.45)), Vector3(0, 0, 0.7), Vector3.ZERO, red, false)
	_add_mesh(_cylinder(0.3, 0.3, 0.2), Vector3(0, 0, 0.9), Vector3(90, 0, 0), Color("#555a60"), false)
	_add_mesh(_cylinder(0.0, 0.26, 1.1), Vector3(0, 0, 1.5), Vector3(90, 0, 0), Color(1.0, 0.7, 0.2), true)
	var trail := CPUParticles3D.new()
	trail.amount = 28
	trail.lifetime = 0.7
	trail.local_coords = false
	trail.position = Vector3(0, 0, 1.2)
	trail.direction = Vector3.ZERO
	trail.spread = 180.0
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.6
	trail.gravity = Vector3.ZERO
	var puff := SphereMesh.new()
	puff.radius = 0.22
	puff.height = 0.44
	puff.radial_segments = 8
	puff.rings = 4
	var puff_material := StandardMaterial3D.new()
	puff_material.vertex_color_use_as_albedo = true
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = puff_material
	trail.mesh = puff
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
	ramp.set_color(1, Color(0.6, 0.6, 0.62, 0.0))
	trail.color_ramp = ramp
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.4
	add_child(trail)


func _build_grenade() -> void:
	_add_mesh(_sphere(0.8), Vector3.ZERO, Vector3.ZERO, Color("#556b2f"), false)
	_add_mesh(_cylinder(0.86, 0.86, 0.14), Vector3.ZERO, Vector3(90, 0, 0), Color("#d3d6da"), false)
	_add_mesh(_cylinder(0.3, 0.3, 0.22), Vector3(0, 0, -0.42), Vector3(90, 0, 0), Color("#d3d6da"), false)
	_add_mesh(_box(Vector3(0.1, 0.1, 0.34)), Vector3(0, 0.42, 0.1), Vector3.ZERO, Color("#c0392b"), false)


func _add_mesh(mesh: Mesh, pos: Vector3, rot_deg: Vector3, tint: Color, unshaded: bool) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 1.0
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	node.position = pos
	node.rotation_degrees = rot_deg
	add_child(node)


static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _sphere(diameter: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = diameter * 0.5
	sphere.height = diameter
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere


## Cylinder along the up axis, with separate top and bottom diameters (a top of 0 makes a cone).
static func _cylinder(top: float, bottom: float, length: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top * 0.5
	cylinder.bottom_radius = bottom * 0.5
	cylinder.height = length
	cylinder.radial_segments = 12
	cylinder.rings = 1
	return cylinder
