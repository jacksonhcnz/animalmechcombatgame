extends Node3D
## The test range: an open field of low-poly flat-colour blocks with dummy mechs to shoot at.
## Used to try every mech, weapon and ruleset offline.
##
## Keys: 1/2/3 pick Lion/Velociraptor/Hawk, F1/F2/F4/F5 pick Practice/Standard/Hardcore/Arcade,
## F3 developer overlay, R restart, Esc releases the mouse, click to capture it.

const MECH_KEYS := {KEY_1: "lion", KEY_2: "velociraptor", KEY_3: "hawk"}
const RULESET_KEYS := {KEY_F1: "practice", KEY_F2: "standard", KEY_F4: "hardcore", KEY_F5: "arcade"}
const ALTITUDE_LIMIT := 120.0
const FIELD_HALF := 380.0
const RESPAWN_DELAY := 4.0
const BLOCK_COLORS: Array[String] = ["#7d8f69", "#a39171", "#6f7f94", "#9c6f5a", "#85a07a"]

## Dummy mechs: [mech id, x, z, height above ground (0 = default)].
const TARGETS := [
	["lion", -40.0, -60.0, 0.0],
	["velociraptor", 0.0, -45.0, 0.0],
	["lion", 40.0, -60.0, 0.0],
	["velociraptor", -25.0, -95.0, 0.0],
	["hawk", -20.0, -120.0, 18.0],
	["hawk", 30.0, -110.0, 26.0],
]

var player: Mech
var targets: Array[Mech] = []
var rules: Ruleset
var hud: Hud
var controller: PlayerController
var player_mech_id: String = "lion"
var ruleset_id: String = "practice"

var _time_left: float = 0.0
var _match_over: bool = false
var _generation: int = 0
var _mechs_root: Node3D


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_environment()
	_mechs_root = Node3D.new()
	_mechs_root.name = "Mechs"
	add_child(_mechs_root)
	hud = Hud.new()
	add_child(hud)
	controller = PlayerController.new()
	add_child(controller)
	start(player_mech_id, ruleset_id)


## (Re)starts the range with a mech and a ruleset.
func start(mech_id: String, new_ruleset_id: String) -> void:
	_generation += 1
	player_mech_id = mech_id
	ruleset_id = new_ruleset_id
	rules = Ruleset.load_id(ruleset_id)
	for child in _mechs_root.get_children():
		child.queue_free()
	targets.clear()
	_match_over = false
	_time_left = rules.match_time

	player = Mech.create(player_mech_id, rules)
	player.team = 1
	player.altitude_limit = ALTITUDE_LIMIT
	_mechs_root.add_child(player)
	player.global_position = Vector3(0.0, player.spawn_height(), 40.0)
	player.make_player()
	player.destroyed.connect(_on_player_destroyed)
	controller.mech = player
	controller.enabled = true

	for spec in TARGETS:
		_spawn_target(spec)

	hud.bind(player, rules)
	hud.set_timer(_time_left if rules.match_time > 0.0 else -1.0)


func _process(delta: float) -> void:
	if rules != null and rules.match_time > 0.0 and not _match_over:
		_time_left = maxf(0.0, _time_left - delta)
		hud.set_timer(_time_left)
		if _time_left <= 0.0:
			_match_over = true
			controller.enabled = false
			hud.show_message("TIME UP\nPress R to restart")
	if hud.debug_visible:
		var alive := 0
		for target in targets:
			if is_instance_valid(target) and not target.is_dead():
				alive += 1
		hud.set_debug_extra("Targets alive %d / %d\nPosition %s" % [alive, targets.size(), player.global_position.round()])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F3:
			hud.toggle_debug()
		elif event.keycode == KEY_R:
			start(player_mech_id, ruleset_id)
		elif MECH_KEYS.has(event.keycode):
			start(MECH_KEYS[event.keycode], ruleset_id)
		elif RULESET_KEYS.has(event.keycode):
			start(player_mech_id, RULESET_KEYS[event.keycode])


func _spawn_target(spec: Array) -> void:
	var target := Mech.create(spec[0], rules)
	target.team = 2
	target.altitude_limit = ALTITUDE_LIMIT
	_mechs_root.add_child(target)
	var height: float = spec[3] if spec[3] > 0.0 else target.spawn_height()
	target.global_position = Vector3(spec[1], height, spec[2])
	target.rotation.y = PI
	targets.append(target)
	var generation := _generation
	target.destroyed.connect(func(dead: Mech) -> void: _respawn_later(spec, dead, generation))


func _respawn_later(spec: Array, dead: Mech, generation: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if generation != _generation:
		return
	targets.erase(dead)
	if is_instance_valid(dead):
		dead.queue_free()
	_spawn_target(spec)


func _on_player_destroyed(_mech: Mech) -> void:
	controller.enabled = false
	hud.show_message("DESTROYED\nPress R to restart")


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8fc4e8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#dce6f0")
	environment.ambient_light_energy = 0.45
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)

	_add_block(Vector3(0.0, -0.5, 0.0), Vector3(FIELD_HALF * 2.0, 1.0, FIELD_HALF * 2.0), Color("#7c9a68"))

	# Walls around the field, so nothing wanders off the edge.
	var wall_color := Color("#5d6b5a")
	_add_block(Vector3(0.0, 20.0, -FIELD_HALF), Vector3(FIELD_HALF * 2.0, 40.0, 8.0), wall_color)
	_add_block(Vector3(0.0, 20.0, FIELD_HALF), Vector3(FIELD_HALF * 2.0, 40.0, 8.0), wall_color)
	_add_block(Vector3(-FIELD_HALF, 20.0, 0.0), Vector3(8.0, 40.0, FIELD_HALF * 2.0), wall_color)
	_add_block(Vector3(FIELD_HALF, 20.0, 0.0), Vector3(8.0, 40.0, FIELD_HALF * 2.0), wall_color)

	# A fixed scatter of blocks (the same every time), kept clear of the spawn and targets.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	var placed := 0
	while placed < 70:
		var x := rng.randf_range(-FIELD_HALF + 30.0, FIELD_HALF - 30.0)
		var z := rng.randf_range(-FIELD_HALF + 30.0, FIELD_HALF - 30.0)
		var w := rng.randf_range(5.0, 20.0)
		var d := rng.randf_range(5.0, 20.0)
		var h := rng.randf_range(2.0, 16.0)
		var color := Color(BLOCK_COLORS[rng.randi() % BLOCK_COLORS.size()])
		if absf(x) < 80.0 and z > -150.0 and z < 70.0:
			continue
		_add_block(Vector3(x, h * 0.5, z), Vector3(w, h, d), color)
		placed += 1


func _add_block(center: Vector3, size: Vector3, color: Color) -> void:
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
	add_child(body)
