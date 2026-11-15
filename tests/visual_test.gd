extends SceneTree
## Checks the shaped visual pieces of a part: pieces exist, hitboxes stay plain boxes, damage
## colours reach the pieces, and all three mechs are drawn from pieces.
## Run with: godot --headless --path . --script tests/visual_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _run() -> void:
	var rules := Ruleset.load_id("standard")
	var lion := Mech.create("lion", rules)
	var raptor := Mech.create("velociraptor", rules)
	root.add_child(lion)
	root.add_child(raptor)
	await physics_frame

	var meshes: Dictionary = lion.get("_part_meshes")
	var pieces := 0
	for part_id in meshes:
		pieces += (meshes[part_id] as Node).get_child_count()
	_check(pieces > 100, "the lion is built from many shaped pieces (%d)" % pieces)
	_check((meshes["torso"] as MeshInstance3D).mesh == null, "a visual part has no plain box")
	var hitbox: Area3D = lion.get("_hitboxes")["torso"]
	_check((hitbox.get_child(0) as CollisionShape3D).shape is BoxShape3D, "its hitbox is still a box")
	_check(((hitbox.get_child(0) as CollisionShape3D).shape as BoxShape3D).size == Vector3(3.6, 2.6, 3.2), "hitbox keeps the data size")
	_check((raptor.get("_part_meshes")["torso"] as MeshInstance3D).mesh == null, "the velociraptor is drawn from pieces too")
	var hawk := Mech.create("hawk", rules)
	root.add_child(hawk)
	_check((hawk.get("_part_meshes")["wing_l"] as MeshInstance3D).get_child_count() > 5, "the hawk wing is a built truss")
	hawk.queue_free()

	var piece := (meshes["torso"] as Node).get_child(0) as MeshInstance3D
	var before := (piece.material_override as StandardMaterial3D).albedo_color
	lion.take_hit("torso", 60.0)
	var after := (piece.material_override as StandardMaterial3D).albedo_color
	_check(before != after, "damage darkens the pieces of a part")

	lion.queue_free()
	raptor.queue_free()
	await process_frame
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
