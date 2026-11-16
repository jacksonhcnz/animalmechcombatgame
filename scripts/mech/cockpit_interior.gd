class_name CockpitInterior
extends RefCounted
## Builds the inside of a mech's cockpit, seen from the pilot's seat. The canopy is a box of
## glass (not drawn) held up by grey structure: a header beam across the top of the
## windscreen, two slanted pillars up its sides, and roof struts running out to the corners of
## the screen. At the bottom a console slopes up from the screen's lower corners to the base of
## the windscreen, and the HUD readouts sit on it (see Hud).
##
## The numbers come from the mech's "cockpit_frame" data, all as fractions of the screen
## (1 is the screen edge, measured from the centre): "top" is [half width, height] of the
## windscreen's top corners, "bottom" is [half width, height] of its bottom corners (height
## below the centre, so negative), "distance" is how far ahead the windscreen sits, and "beam"
## is the thickness of the structure.

## How far in front of the eyes the near ends of the roof struts and console start.
const NEAR := 0.3
## The reference screen shape. The frame is laid out for this and the sides fall off-screen on
## narrower windows.
const ASPECT := 16.0 / 9.0
const CAMERA_FOV_DEG := 80.0


## Where a screen position (x and y in -1..1 from the centre) lands at a depth, in cockpit space.
static func screen_point(nx: float, ny: float, depth: float) -> Vector3:
	var half_height := tan(deg_to_rad(CAMERA_FOV_DEG) * 0.5) * depth
	return Vector3(nx * half_height * ASPECT, ny * half_height, -depth)


## Where the console's far edge sits on the screen, as a fraction of the screen height from
## the top. The HUD uses it to place readouts on the console.
static func console_top(frame: Dictionary) -> float:
	return (1.0 - float(frame["bottom"][1])) * 0.5


static func build(frame: Dictionary, palette: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "CockpitInterior"
	var depth := float(frame["distance"])
	var top: Array = frame["top"]
	var bottom: Array = frame["bottom"]
	var beam := float(frame.get("beam", 0.06))
	var dark := Color.html(palette["dark"])
	var accent := Color.html(palette["accent"])
	var structure := Color(0.5, 0.52, 0.56).lerp(dark, 0.12)
	var bolt := Color("#d3d6da")

	var far_tl := screen_point(-float(top[0]), float(top[1]), depth)
	var far_tr := screen_point(float(top[0]), float(top[1]), depth)
	var far_bl := screen_point(-float(bottom[0]), float(bottom[1]), depth)
	var far_br := screen_point(float(bottom[0]), float(bottom[1]), depth)
	var near_tl := screen_point(-1.0, 1.0, NEAR)
	var near_tr := screen_point(1.0, 1.0, NEAR)
	var near_bl := screen_point(-1.0, -1.0, NEAR)
	var near_br := screen_point(1.0, -1.0, NEAR)

	# The console: a flat slope from the bottom of the screen up to the windscreen's base.
	var console := _quad(root, "Console", [near_bl, near_br, far_br, far_bl], accent.darkened(0.55))
	console.set_meta("far_edge_y", far_bl.y)
	# Two darker bays on the console, where the readouts sit.
	_bay(root, "BayLeft", near_bl, near_br, far_bl, far_br, 0.04, 0.47, accent.darkened(0.75))
	_bay(root, "BayRight", near_bl, near_br, far_bl, far_br, 0.53, 0.96, accent.darkened(0.75))

	# Structure: header, pillars, roof struts and the lip along the console.
	_beam(root, "Header", far_tl, far_tr, beam, structure)
	_beam(root, "PillarLeft", far_bl, far_tl, beam * 1.1, structure)
	_beam(root, "PillarRight", far_br, far_tr, beam * 1.1, structure)
	_beam(root, "StrutLeft", near_tl, far_tl, beam * 1.3, structure)
	_beam(root, "StrutRight", near_tr, far_tr, beam * 1.3, structure)
	_beam(root, "Lip", far_bl, far_br, beam * 0.8, structure)
	# Bolts at the joints, like a built frame.
	for corner in [far_tl, far_tr, far_bl, far_br]:
		_bolt(root, corner + Vector3(0.0, 0.0, 0.03), beam * 1.7, bolt)
	return root


## A flat four-cornered surface (corners in order around the edge).
static func _quad(parent: Node3D, quad_name: String, corners: Array, color: Color) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 2, 0, 2, 3]:
		tool.add_vertex(corners[index])
	tool.generate_normals()
	var node := MeshInstance3D.new()
	node.name = quad_name
	node.mesh = tool.commit()
	node.material_override = _flat(color, 1 if quad_name.begins_with("Bay") else 0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## A rectangle on the console between two fractions across it, just above its surface.
static func _bay(parent: Node3D, bay_name: String, near_l: Vector3, near_r: Vector3, far_l: Vector3, far_r: Vector3, from: float, to: float, color: Color) -> void:
	var lift := Vector3(0.0, 0.004, 0.0)
	var nearest_a := near_l.lerp(near_r, from).lerp(far_l.lerp(far_r, from), 0.05) + lift
	var nearest_b := near_l.lerp(near_r, to).lerp(far_l.lerp(far_r, to), 0.05) + lift
	var farthest_a := near_l.lerp(near_r, from).lerp(far_l.lerp(far_r, from), 0.8) + lift
	var farthest_b := near_l.lerp(near_r, to).lerp(far_l.lerp(far_r, to), 0.8) + lift
	_quad(parent, bay_name, [nearest_a, nearest_b, farthest_b, farthest_a], color)


## A flat-coloured box stretched between two points.
static func _beam(parent: Node3D, beam_name: String, from: Vector3, to: Vector3, thickness: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = beam_name
	var mesh := BoxMesh.new()
	var along := to - from
	mesh.size = Vector3(thickness, thickness, along.length())
	node.mesh = mesh
	node.material_override = _flat(color, 2)
	var dir := along.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	node.transform = Transform3D(Basis.looking_at(dir, up), (from + to) * 0.5)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func _bolt(parent: Node3D, pos: Vector3, diameter: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = "Bolt"
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = diameter * 0.35
	mesh.radial_segments = 6
	mesh.rings = 1
	node.mesh = mesh
	node.material_override = _flat(color, 3)
	node.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _flat(color: Color, priority: int = 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	# Unshaded, so the frame reads the same whatever the sun does: it is the pilot's own cockpit.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Always drawn over the mech's own body, which would otherwise poke through the console.
	material.no_depth_test = true
	material.render_priority = priority
	return material
