class_name Arena
extends RefCounted
## Builds a field of low-poly flat-colour blocks: sky, sun, ground, boundary walls and a
## deterministic scatter of obstacles. The test range and the multiplayer arena both use it,
## so a server and its clients build exactly the same world from the same numbers.

const BLOCK_COLORS: Array[String] = ["#7d8f69", "#a39171", "#6f7f94", "#9c6f5a", "#85a07a"]

## Multiplayer arena: a smaller field with spawn points ringed round the edge, facing the centre.
const MATCH_HALF := 170.0
const MATCH_ALTITUDE_LIMIT := 120.0
const MATCH_SPAWN_RADIUS := 130.0
const MATCH_SPAWNS := 8


## Builds the world under `parent`. `keep_clear` lists rectangles (x, z, width, depth) that get no blocks.
static func build(parent: Node3D, half: float, block_count: int, keep_clear: Array[Rect2], seed_value: int) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8fc4e8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#dce6f0")
	environment.ambient_light_energy = 0.45
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	parent.add_child(sun)

	add_block(parent, Vector3(0.0, -0.5, 0.0), Vector3(half * 2.0, 1.0, half * 2.0), Color("#7c9a68"))

	# Walls around the field, so nothing wanders off the edge.
	var wall_color := Color("#5d6b5a")
	add_block(parent, Vector3(0.0, 20.0, -half), Vector3(half * 2.0, 40.0, 8.0), wall_color)
	add_block(parent, Vector3(0.0, 20.0, half), Vector3(half * 2.0, 40.0, 8.0), wall_color)
	add_block(parent, Vector3(-half, 20.0, 0.0), Vector3(8.0, 40.0, half * 2.0), wall_color)
	add_block(parent, Vector3(half, 20.0, 0.0), Vector3(8.0, 40.0, half * 2.0), wall_color)

	# A fixed scatter of blocks: the same every time for the same seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed := 0
	while placed < block_count:
		var x := rng.randf_range(-half + 30.0, half - 30.0)
		var z := rng.randf_range(-half + 30.0, half - 30.0)
		var w := rng.randf_range(5.0, 20.0)
		var d := rng.randf_range(5.0, 20.0)
		var h := rng.randf_range(2.0, 16.0)
		var color := Color(BLOCK_COLORS[rng.randi() % BLOCK_COLORS.size()])
		var blocked := false
		for zone in keep_clear:
			if zone.intersects(Rect2(x - w * 0.5, z - d * 0.5, w, d)):
				blocked = true
		if blocked:
			continue
		add_block(parent, Vector3(x, h * 0.5, z), Vector3(w, h, d), color)
		placed += 1


## The multiplayer arena. Spawn areas are kept clear of blocks.
static func build_match_arena(parent: Node3D) -> void:
	var clear: Array[Rect2] = []
	for i in MATCH_SPAWNS:
		var spot := spawn_transform(i).origin
		clear.append(Rect2(spot.x - 22.0, spot.z - 22.0, 44.0, 44.0))
	build(parent, MATCH_HALF, 36, clear, 20261114)


## Where spawn number `index` is: on a ring round the field, facing the middle.
## Slots 0 and 1 are opposite each other, so a 1v1 match starts with the players facing off.
static func spawn_transform(index: int) -> Transform3D:
	var order: Array[int] = [0, 4, 2, 6, 1, 5, 3, 7]
	var slot := order[index % MATCH_SPAWNS]
	var angle := TAU * float(slot) / float(MATCH_SPAWNS)
	var position := Vector3(sin(angle) * MATCH_SPAWN_RADIUS, 0.0, cos(angle) * MATCH_SPAWN_RADIUS)
	# Forward is -Z, so face the centre: yaw so that -Z points from the spawn to the origin.
	var yaw := atan2(position.x, position.z)
	return Transform3D(Basis(Vector3.UP, yaw), position)


static func add_block(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Mech.LAYER_WORLD
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	body.add_child(mesh)
	parent.add_child(body)
