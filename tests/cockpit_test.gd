extends SceneTree
## Checks the cockpit interior: it surrounds the camera, shows only in cockpit view, never
## blocks the crosshair, and is forced on in hardcore. Run with:
##   godot --headless --path . --script tests/cockpit_test.gd

var _checks := 0
var _failures := 0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: cockpit test timed out")
		quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var range_scene: Node3D = load("res://scenes/test_range.tscn").instantiate()
	root.add_child(range_scene)
	await _frames(40)
	range_scene.controller.set_physics_process(false)

	for mech_id in GameData.ids("mechs"):
		range_scene.start(mech_id, "practice")
		await _frames(40)
		var player: Mech = range_scene.player
		range_scene.controller.set_physics_process(false)
		_check(player.cockpit_interior != null, "%s has a cockpit interior" % mech_id)
		_check(player.cockpit_interior.get_parent() == player.get_node("AimPivot"), "%s interior is attached to the cockpit camera pivot" % mech_id)
		_check(player.cockpit_interior.visible, "%s interior shows in cockpit view" % mech_id)

		# The opening around the crosshair stays clear: the centre of the view is empty.
		var camera: Camera3D = player.cockpit_camera
		var clear := true
		for child in player.cockpit_interior.get_children():
			var node := child as MeshInstance3D
			var local: Vector3 = camera.global_transform.affine_inverse() * node.global_position
			var half: Vector3 = (node.mesh as BoxMesh).size * 0.5
			var rotated := node.global_transform.basis.inverse() * (camera.global_position - node.global_position)
			if absf(rotated.x) < half.x and absf(rotated.y) < half.y and absf(rotated.z) < half.z:
				clear = false
			if node.name != "Console" and node.name != "Display":
				# A ray straight ahead of the camera must pass the frame without touching it.
				var ahead := node.global_transform.basis.inverse() * (camera.global_position - camera.global_transform.basis.z * local.length() - node.global_position)
				if absf(ahead.x) < half.x and absf(ahead.y) < half.y and absf(ahead.z) < half.z:
					clear = false
		_check(clear, "%s cockpit frame leaves the centre of the view clear" % mech_id)

		player.toggle_view()
		_check(not player.cockpit_interior.visible, "%s interior hides in third-person view" % mech_id)
		player.toggle_view()

	# Hardcore forces the cockpit view, so the interior is on.
	range_scene.start("lion", "hardcore")
	await _frames(40)
	var hardcore_player: Mech = range_scene.player
	hardcore_player.toggle_view()
	_check(hardcore_player.cockpit_interior.visible, "hardcore keeps the cockpit view and its interior")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
