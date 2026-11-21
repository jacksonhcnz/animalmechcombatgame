class_name Terrain
extends RefCounted
## Builds a terrain map from its data file (a map with "terrain": true): rolling ground with
## mesas of different heights, each with steep cliffs and one or more ramps up, dry washes cut
## into the ground, a wall rising round the edge and fields of blocky boulders for cover.
##
## Everything comes from the numbers in the data file, so the server and every client build
## the same ground. Heights are worked out at the corners of a grid of square cells (`cell`
## metres) and drawn as flat-coloured triangles: green where the ground is gentle, tan rock in
## layers where it is steep. A cell too steep to walk up, or holding a boulder, is marked as
## raised in the grid so computer pilots plan routes round it.

## Ground steeper than this (rise over run) is a cliff: drawn as rock and blocked for routes.
const CLIFF_SLOPE := 0.8
## Ground above this height counts as high ground and gets the lighter top greens.
const HIGH_GROUND := 14.0
const BOULDER_TANS: Array[String] = ["#9c7a4a", "#8b6c40", "#a8865a"]


## Works out the heights and the blocked cells.
static func rasterize(map_def: Dictionary) -> Canyon.Grid:
	var grid := Canyon.Grid.new()
	grid.cell = float(map_def.get("cell", 8.0))
	var size: Array = map_def["size"]
	var half_x := ceilf(float(size[0]) * 0.5 / grid.cell) * grid.cell
	var half_z := ceilf(float(size[1]) * 0.5 / grid.cell) * grid.cell
	grid.x0 = -half_x
	grid.z0 = -half_z
	grid.nx = int(half_x * 2.0 / grid.cell)
	grid.nz = int(half_z * 2.0 / grid.cell)
	var shape := _Shape.new(map_def, half_x, half_z)
	grid.heights.resize((grid.nx + 1) * (grid.nz + 1))
	for j in grid.nz + 1:
		for i in grid.nx + 1:
			grid.heights[j * (grid.nx + 1) + i] = shape.height(grid.x0 + float(i) * grid.cell, grid.z0 + float(j) * grid.cell)
	# The flyers' floor: clear of the tallest mesa.
	grid.depth = shape.tallest
	grid.raised.resize(grid.nx * grid.nz)
	grid.raised.fill(0)
	for j in grid.nz:
		for i in grid.nx:
			if _cell_slope(grid, i, j) > CLIFF_SLOPE:
				grid.raised[j * grid.nx + i] = 1
	_place_boulders(grid, map_def)
	return grid


## The steepest rise over run across one cell.
static func _cell_slope(grid: Canyon.Grid, i: int, j: int) -> float:
	var a := grid.corner(i, j)
	var b := grid.corner(i + 1, j)
	var c := grid.corner(i, j + 1)
	var d := grid.corner(i + 1, j + 1)
	var rise := maxf(maxf(absf(a - b), absf(c - d)), maxf(maxf(absf(a - c), absf(b - d)), maxf(absf(a - d), absf(b - c)) / sqrt(2.0)))
	return rise / grid.cell


## Picks boulder spots: a fixed scatter (the same every time for the same seed) on low, gentle
## ground, gathered into fields. Each boulder blocks the cells under it.
static func _place_boulders(grid: Canyon.Grid, map_def: Dictionary) -> void:
	var spec: Dictionary = map_def.get("boulders", {})
	var count := int(spec.get("count", 0))
	if count <= 0:
		return
	var sizes: Array = spec.get("size", [4, 10])
	var max_height := float(spec.get("max_height", 12.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var keep_clear: Array[Vector2] = []
	for end in ["north", "south"]:
		for point: Array in map_def.get("spawns", {}).get(end, {}).get("points", []):
			keep_clear.append(Vector2(float(point[0]), float(point[1])))
	var field_seed := float(int(spec.get("seed", 1)) % 1000)
	var tries := 0
	while grid.boulders.size() < count and tries < count * 200:
		tries += 1
		var x := rng.randf_range(grid.x0 + 60.0, -grid.x0 - 60.0)
		var z := rng.randf_range(grid.z0 + 60.0, -grid.z0 - 60.0)
		var size := rng.randf_range(float(sizes[0]), float(sizes[1]))
		var tall := size * rng.randf_range(0.6, 1.2)
		var turn := rng.randi() % 4
		# Boulders gather in fields rather than spreading evenly.
		if _Shape.value_noise(x / 110.0 + field_seed, z / 110.0) < 0.5:
			continue
		var ground := grid.height_at(x, z)
		if ground > max_height or grid.blocked_at(x, z):
			continue
		var near_spawn := false
		for spot in keep_clear:
			if spot.distance_to(Vector2(x, z)) < 40.0:
				near_spawn = true
		if near_spawn:
			continue
		var footprint := Vector2(size, size * (0.7 if turn % 2 == 0 else 1.3))
		# Sit the boulder on the lowest corner of its footprint, so no edge floats.
		var low := ground
		for dx in [-0.5, 0.5]:
			for dz in [-0.5, 0.5]:
				low = minf(low, grid.height_at(x + dx * footprint.x, z + dz * footprint.y))
		grid.boulders.append(AABB(Vector3(x - footprint.x * 0.5, low - 1.0, z - footprint.y * 0.5), Vector3(footprint.x, tall + (ground - low) + 1.0, footprint.y)))
		# A smaller block leaning on some boulders, so a field reads as rubble, not a grid of crates.
		if rng.randf() < 0.45:
			var small := size * 0.5
			var side := Vector3(footprint.x * 0.5, 0.0, 0.0) if rng.randf() < 0.5 else Vector3(0.0, 0.0, footprint.y * 0.5)
			var at := Vector3(x, low - 1.0, z) + side
			grid.boulders.append(AABB(at - Vector3(small * 0.5, 0.0, small * 0.5), Vector3(small, small * 0.8 + (ground - low) + 1.0, small)))
	for box in grid.boulders:
		var i0 := int(floor((box.position.x - grid.x0) / grid.cell))
		var i1 := int(floor((box.end.x - grid.x0) / grid.cell))
		var j0 := int(floor((box.position.z - grid.z0) / grid.cell))
		var j1 := int(floor((box.end.z - grid.z0) / grid.cell))
		for j in range(maxi(0, j0), mini(grid.nz - 1, j1) + 1):
			for i in range(maxi(0, i0), mini(grid.nx - 1, i1) + 1):
				grid.raised[j * grid.nx + i] = 1


## Builds the drawn ground, the boulders and a static body to stand on.
static func build(parent: Node3D, map_def: Dictionary) -> Canyon.Grid:
	var grid := Canyon.grid_for(map_def)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var faces := PackedVector3Array()
	for j in grid.nz:
		for i in grid.nx:
			var p00 := _point(grid, i, j)
			var p10 := _point(grid, i + 1, j)
			var p01 := _point(grid, i, j + 1)
			var p11 := _point(grid, i + 1, j + 1)
			# Alternate the diagonal so long slopes do not show stripes.
			if (i + j) % 2 == 0:
				_triangle(positions, normals, colors, faces, p00, p11, p10, i, j)
				_triangle(positions, normals, colors, faces, p00, p01, p11, i, j)
			else:
				_triangle(positions, normals, colors, faces, p00, p01, p10, i, j)
				_triangle(positions, normals, colors, faces, p10, p01, p11, i, j)
	for k in grid.boulders.size():
		_box(positions, normals, colors, faces, grid.boulders[k], Color(BOULDER_TANS[k % BOULDER_TANS.size()]))

	var body := StaticBody3D.new()
	body.name = "Canyon"
	body.collision_layer = Mech.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh_data := ArrayMesh.new()
	mesh_data.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh := MeshInstance3D.new()
	mesh.mesh = mesh_data
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.material_override = material
	body.add_child(mesh)
	parent.add_child(body)
	return grid


static func _point(grid: Canyon.Grid, i: int, j: int) -> Vector3:
	return Vector3(grid.x0 + float(i) * grid.cell, grid.corner(i, j), grid.z0 + float(j) * grid.cell)


## One flat-coloured ground triangle.
static func _triangle(positions: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, i: int, j: int) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal
	var height := (a.y + b.y + c.y) / 3.0
	var color: Color
	if normal.y < 1.0 / sqrt(1.0 + CLIFF_SLOPE * CLIFF_SLOPE) + 0.08:
		# Rock face, in layers of tan.
		color = Color(Canyon.ROCK_TANS[(int(floor(height / Canyon.LAYER_HEIGHT)) + floori(Canyon._hash(floori(i / 6.0), floori(j / 6.0)) / 300.0)) % Canyon.ROCK_TANS.size()])
	else:
		var tones: Array[String] = Canyon.TOP_GREENS if height > HIGH_GROUND else Canyon.FLOOR_GREENS
		color = Color(tones[Canyon._hash(floori(i / float(Canyon.PATCH)), floori(j / float(Canyon.PATCH))) % tones.size()])
		# A little shading on slopes so the roll of the ground reads.
		color = color.darkened((1.0 - normal.y) * 0.9)
	_emit(positions, normals, colors, a, b, c, normal, color)
	faces.append_array(PackedVector3Array([a, b, c]))


## A triangle drawn facing along `normal` (Godot draws triangles that go clockwise as seen from the front).
static func _emit(positions: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var corners := [a, b, c] if (b - a).cross(c - a).dot(normal) < 0.0 else [a, c, b]
	for corner: Vector3 in corners:
		positions.append(corner)
		normals.append(normal)
		colors.append(color)


## A flat-coloured box (a boulder).
static func _box(positions: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, faces: PackedVector3Array, box: AABB, color: Color) -> void:
	var lo := box.position
	var hi := box.end
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	# Each side as corner indices going clockwise from outside, with its normal and a shade.
	var sides := [
		[[4, 5, 6, 7], Vector3.UP, 0.0],
		[[0, 4, 7, 3], Vector3.LEFT, 0.12],
		[[1, 2, 6, 5], Vector3.RIGHT, 0.12],
		[[0, 1, 5, 4], Vector3.FORWARD, 0.2],
		[[3, 7, 6, 2], Vector3.BACK, 0.06],
	]
	for side: Array in sides:
		var k: Array = side[0]
		var normal: Vector3 = side[1]
		var shade := color.darkened(float(side[2]))
		_emit(positions, normals, colors, c[k[0]], c[k[1]], c[k[2]], normal, shade)
		_emit(positions, normals, colors, c[k[0]], c[k[2]], c[k[3]], normal, shade)
		faces.append_array(PackedVector3Array([c[k[0]], c[k[1]], c[k[2]], c[k[0]], c[k[2]], c[k[3]]]))


## Problems in a terrain map's data, empty if it is fine (spawns are checked by Canyon.validate).
static func validate(def: Dictionary, tag: String) -> Array[String]:
	var p: Array[String] = []
	var size: Variant = def.get("size")
	if not (size is Array and size.size() == 2 and float(size[0]) > 0.0 and float(size[1]) > 0.0):
		p.append("%s: size needs [width, length] in metres" % tag)
	if float(def.get("cell", 0.0)) <= 0.0:
		p.append("%s: cell must be above 0" % tag)
	for mesa: Variant in def.get("mesas", []):
		if not (mesa is Dictionary and mesa.has_all(["x", "z", "rx", "rz", "height", "cliff"])):
			p.append("%s: every mesa needs x, z, rx, rz, height and cliff" % tag)
			return p
		if float(mesa["rx"]) <= 0.0 or float(mesa["rz"]) <= 0.0 or float(mesa["cliff"]) <= 0.0:
			p.append("%s: mesa sizes and cliff must be above 0" % tag)
		for ramp: Variant in mesa.get("ramps", []):
			if not (ramp is Dictionary and ramp.has_all(["dir", "length", "width"])):
				p.append("%s: every ramp needs dir, length and width" % tag)
			elif float(ramp["length"]) * 0.7 < float(mesa["height"]):
				p.append("%s: a ramp up a %s m mesa is too short to walk up" % [tag, mesa["height"]])
	for wash: Variant in def.get("washes", []):
		if not (wash is Dictionary and wash.get("points") is Array and wash["points"].size() >= 2):
			p.append("%s: every wash needs at least 2 points" % tag)
	return p


## The ground's shape as a height at any point.
class _Shape extends RefCounted:
	var mesas: Array = []
	var washes: Array = []
	var roll := 0.0
	var wave := 75.0
	var ground_seed := 0.0
	var edge_width := 80.0
	var edge_height := 70.0
	var half_x := 0.0
	var half_z := 0.0
	var tallest := 0.0

	func _init(def: Dictionary, hx: float, hz: float) -> void:
		half_x = hx
		half_z = hz
		var ground: Dictionary = def.get("ground", {})
		roll = float(ground.get("roll", 0.0))
		wave = float(ground.get("wavelength", 75.0))
		ground_seed = float(int(ground.get("seed", 0)) % 1000) * 7.31
		var edge: Dictionary = def.get("edge", {})
		edge_width = float(edge.get("width", 80.0))
		edge_height = float(edge.get("height", 70.0))
		for m: Dictionary in def.get("mesas", []):
			var ramps: Array = []
			for r: Dictionary in m.get("ramps", []):
				var bearing := deg_to_rad(float(r["dir"]))
				# Compass bearing: 0 is north (-z), 90 is east (+x).
				ramps.append([Vector2(sin(bearing), -cos(bearing)), float(r["length"]), cos(deg_to_rad(float(r["width"])))])
			mesas.append({
				"c": Vector2(float(m["x"]), float(m["z"])), "rx": float(m["rx"]), "rz": float(m["rz"]),
				"h": float(m["height"]), "cliff": float(m["cliff"]), "ledge": bool(m.get("ledge", false)), "ramps": ramps,
			})
			tallest = maxf(tallest, float(m["height"]))
		for w: Dictionary in def.get("washes", []):
			var points: Array[Vector2] = []
			for point: Array in w["points"]:
				points.append(Vector2(float(point[0]), float(point[1])))
			washes.append({"points": points, "width": float(w.get("width", 16.0)), "depth": float(w.get("depth", 4.0))})

	func height(x: float, z: float) -> float:
		var p := Vector2(x, z)
		var s := ground_seed
		var base := roll * (0.36 * sin(x / (wave * 0.98) + s) * cos(z / (wave * 1.32)) \
			+ 0.25 * sin((x + z) / (wave * 0.72) + s * 0.5) \
			+ 0.42 * (value_noise(x / (wave * 0.6) + s, z / (wave * 0.6)) - 0.5) * 2.0 \
			+ 0.15 * (value_noise(x / (wave * 0.22), z / (wave * 0.22) + s) - 0.5) * 2.0)
		var mesa := 0.0
		for m: Dictionary in mesas:
			mesa = maxf(mesa, _mesa_height(m, p))
		var wash := 0.0
		for w: Dictionary in washes:
			var d := _distance_to_line(p, w["points"])
			wash = maxf(wash, float(w["depth"]) * exp(-pow(d / (float(w["width"]) * 0.5), 2.0)))
		var h := base + mesa - wash * (1.0 - smoothstep(2.0, 10.0, mesa))
		# The wall round the edge rises over `edge_width` metres.
		var inside := minf(half_x - absf(x), half_z - absf(z))
		if inside >= edge_width:
			return h
		var wall := edge_height * smoothstep(edge_width, 0.0, inside) + 5.0 * value_noise(x / 18.0, z / 18.0) * smoothstep(edge_width * 0.5, 0.0, inside)
		return maxf(h, wall)

	func _mesa_height(m: Dictionary, p: Vector2) -> float:
		var d: Vector2 = p - m["c"]
		var rx: float = m["rx"]
		var rz: float = m["rz"]
		var angle := atan2(d.y, d.x)
		var c: Vector2 = m["c"]
		# A rough edge rather than a perfect ellipse.
		var n := sqrt(pow(d.x / rx, 2.0) + pow(d.y / rz, 2.0)) + 0.05 * sin(5.0 * angle + c.x) + 0.035 * sin(9.0 * angle + c.y)
		# How far outside the edge, in metres: scaled by the mesa's radius in this direction.
		var radius := 1.0 / sqrt(pow(cos(angle) / rx, 2.0) + pow(sin(angle) / rz, 2.0))
		var out := (n - 1.0) * radius
		var h: float = m["h"]
		if out <= 0.0:
			return h
		# Steep cliffs all round, except where a ramp runs out.
		var reach: float = m["cliff"]
		var dir := d.normalized() if d.length() > 0.001 else Vector2.ZERO
		for ramp: Array in m["ramps"]:
			var k := smoothstep(float(ramp[2]), 1.0, dir.dot(ramp[0]))
			reach = maxf(reach, lerpf(float(m["cliff"]), float(ramp[1]), k))
		if out >= reach:
			return 0.0
		var t := 1.0 - out / reach
		if m["ledge"]:
			# Two climbs with a flat ledge halfway up.
			return h * (0.48 * smoothstep(0.0, 0.42, t) + 0.52 * smoothstep(0.56, 0.96, t))
		return h * smoothstep(0.0, 1.0, t)

	static func _distance_to_line(p: Vector2, points: Array[Vector2]) -> float:
		var best := 1.0e9
		for k in points.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[k], points[k + 1])))
		return best

	## Smooth noise between 0 and 1, the same everywhere for the same point.
	static func value_noise(x: float, z: float) -> float:
		var xi := floorf(x)
		var zi := floorf(z)
		var xf := x - xi
		var zf := z - zi
		var u := xf * xf * (3.0 - 2.0 * xf)
		var v := zf * zf * (3.0 - 2.0 * zf)
		var a := _hash01(xi, zi)
		var b := _hash01(xi + 1.0, zi)
		var c := _hash01(xi, zi + 1.0)
		var d := _hash01(xi + 1.0, zi + 1.0)
		return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

	static func _hash01(x: float, z: float) -> float:
		var s := sin(x * 127.1 + z * 311.7) * 43758.5453
		return s - floorf(s)
