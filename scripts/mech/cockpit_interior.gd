class_name CockpitInterior
extends RefCounted
## Builds the inside of a mech's cockpit from flat-coloured boxes: a canopy frame with a
## window opening, tilted side pillars, and a dashboard with a raised console. It is placed
## around the cockpit camera and only the local pilot sees it.
##
## The numbers come from the mech's "cockpit_frame" data: "window" is the half-width and
## half-height of the opening, "distance" is how far in front of the eyes the frame sits,
## "pillar_tilt_deg" leans the side pillars inwards and "console_height" raises the dashboard.

const BIG := 6.0


static func build(frame: Dictionary, palette: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "CockpitInterior"
	var window: Array = frame["window"]
	var hw := float(window[0])
	var hh := float(window[1])
	var d := float(frame["distance"])
	var tilt := deg_to_rad(float(frame.get("pillar_tilt_deg", 0.0)))
	var console := float(frame.get("console_height", 0.2))
	var dark := Color.html(palette["dark"])
	var trim := Color.html(palette["accent"])

	# Canopy beam above the window and dashboard panel below it.
	_box(root, "Canopy", Vector3(hw * 2.0 + BIG * 2.0, BIG, 0.8), Vector3(0.0, hh + BIG * 0.5, -d), dark.darkened(0.3))
	_box(root, "Dashboard", Vector3(hw * 2.0 + BIG * 2.0, BIG, 0.8), Vector3(0.0, -hh - BIG * 0.5, -d), dark.lightened(0.12))
	# Side pillars, leaning inwards towards the top.
	for side in [-1.0, 1.0]:
		var pillar := _box(root, "Pillar", Vector3(BIG, BIG * 2.0 + hh * 2.0, 0.8), Vector3(side * (hw + BIG * 0.5), 0.0, -d), dark)
		pillar.rotation.z = -side * tilt
	# Raised console on the dashboard, in the mech's accent colour, with a small dark display.
	_box(root, "Console", Vector3(hw * 1.3, console, 0.7), Vector3(0.0, -hh + console * 0.5, -d + 0.45), trim)
	_box(root, "Display", Vector3(hw * 0.5, console * 0.3, 0.05), Vector3(0.0, -hh + console + 0.01, -d + 0.45), dark.darkened(0.4))
	return root


static func _box(parent: Node3D, box_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	# Unshaded, so the frame reads the same whatever the sun does: it is the pilot's own cockpit.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
