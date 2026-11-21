class_name Canyon
extends RefCounted
## Builds a canyon map from its data file (data/maps/<id>.json): flat ground in the canyon,
## and rock standing `depth` metres above it everywhere else (the canyon walls, the mesas in
## the middle and the high ground around the rim). Ground and tops are green, the rock faces
## tan in layers.
##
## The map is worked out on a grid of square cells (`cell` metres), one cell either canyon
## floor or raised, then drawn as flat-coloured rectangles with the runs of matching cells
## merged. The server and every client build it from the same numbers, so they agree.
##
## A map with "terrain": true is built by Terrain instead (rolling ground, mesas of different
## heights with ramps); it fills the same Grid, with heights at the cell corners.

const TOP_GREENS: Array[String] = ["#74a554", "#6b9a4d", "#7dae5c"]
const FLOOR_GREENS: Array[String] = ["#5d8a44", "#56803f", "#65944b"]
const ROCK_TANS: Array[String] = ["#c19a62", "#b0894f", "#caa46e", "#a3804a"]
## A rock face is drawn in layers this tall, each a slightly different tan.
const LAYER_HEIGHT := 7.5
## Patches of ground tone are this many cells across.
const PATCH := 10

## The grid: 0 is canyon floor (open to walk), 1 is raised (rock, a cliff or a boulder).
class Grid extends RefCounted:
	var cell: float = 4.0
	var depth: float = 20.0
	var x0: float = 0.0
	var z0: float = 0.0
	var nx: int = 0
	var nz: int = 0
	var raised: PackedByteArray = PackedByteArray()
	## Terrain maps only: ground height at each cell corner, (nx + 1) by (nz + 1). Empty on canyon maps.
	var heights: PackedFloat32Array = PackedFloat32Array()
	## Terrain maps only: the boulders, as boxes.
	var boulders: Array[AABB] = []

	func at(i: int, j: int) -> int:
		if i < 0 or j < 0 or i >= nx or j >= nz:
			return 1
		return raised[j * nx + i]

	## Height of the ground at a world position (0 in the canyon, `depth` on the rock; on a
	## terrain map, the height of the drawn ground).
	func height_at(x: float, z: float) -> float:
		if heights.is_empty():
			return depth * at(int(floor((x - x0) / cell)), int(floor((z - z0) / cell)))
		var fx := clampf((x - x0) / cell, 0.0, float(nx) - 0.001)
		var fz := clampf((z - z0) / cell, 0.0, float(nz) - 0.001)
		var i := int(fx)
		var j := int(fz)
		var u := fx - float(i)
		var v := fz - float(j)
		var h00 := corner(i, j)
		var h10 := corner(i + 1, j)
		var h01 := corner(i, j + 1)
		var h11 := corner(i + 1, j + 1)
		# The same split into triangles as the drawn ground.
		if (i + j) % 2 == 0:
			return h00 + (h11 - h01) * u + (h01 - h00) * v if v > u else h00 + (h10 - h00) * u + (h11 - h10) * v
		return h00 + (h10 - h00) * u + (h01 - h00) * v if u + v < 1.0 else h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)

	## Ground height at a cell corner (terrain maps).
	func corner(i: int, j: int) -> float:
		return heights[clampi(j, 0, nz) * (nx + 1) + clampi(i, 0, nx)]

	## True where a walker cannot go: rock, a cliff, a boulder or off the map.
	func blocked_at(x: float, z: float) -> bool:
		return at(int(floor((x - x0) / cell)), int(floor((z - z0) / cell))) != 0

	func half_x() -> float:
		return -x0

	func half_z() -> float:
		return -z0


static func load_map(map_id: String) -> Dictionary:
	return GameData.get_entry("maps", map_id)


static var _grids: Dictionary = {}


## The grid for a map, worked out once and kept (terrain maps take a moment to work out).
static func grid_for(map_def: Dictionary) -> Grid:
	var key := map_def.hash()
	if not _grids.has(key):
		_grids[key] = rasterize(map_def)
	return _grids[key]


## Works out which cells are canyon floor and which are raised.
static func rasterize(map_def: Dictionary) -> Grid:
	if map_def.get("terrain", false):
		return Terrain.rasterize(map_def)
	var grid := Grid.new()
	grid.cell = float(map_def.get("cell", 4.0))
	grid.depth = float(map_def.get("depth", 20.0))
	var outer: Array = map_def["outer"]
	var lowest := Vector2(1.0e9, 1.0e9)
	var highest := Vector2(-1.0e9, -1.0e9)
	for point: Array in outer:
		lowest = Vector2(minf(lowest.x, float(point[0])), minf(lowest.y, float(point[1])))
		highest = Vector2(maxf(highest.x, float(point[0])), maxf(highest.y, float(point[1])))
	var rim := float(map_def.get("rim", 90.0))
	# A grid centred on the middle of the map, a whole number of cells each way.
	var half_x := ceilf((maxf(absf(lowest.x), absf(highest.x)) + rim) / grid.cell) * grid.cell
	var half_z := ceilf((maxf(absf(lowest.y), absf(highest.y)) + rim) / grid.cell) * grid.cell
	grid.x0 = -half_x
	grid.z0 = -half_z
	grid.nx = int(half_x * 2.0 / grid.cell)
	grid.nz = int(half_z * 2.0 / grid.cell)
	grid.raised.resize(grid.nx * grid.nz)
	grid.raised.fill(1)
	_fill(grid, outer, 0)
	for island: Array in map_def.get("islands", []):
		_fill(grid, island, 1)
	return grid


## Sets every cell whose centre is inside the polygon to `value` (a scan line across each row).
static func _fill(grid: Grid, polygon: Array, value: int) -> void:
	for j in grid.nz:
		var z := grid.z0 + (float(j) + 0.5) * grid.cell
		var crossings: Array[float] = []
		for k in polygon.size():
			var a: Array = polygon[k]
			var b: Array = polygon[(k + 1) % polygon.size()]
			if (float(a[1]) <= z) != (float(b[1]) <= z):
				crossings.append(float(a[0]) + (z - float(a[1])) / (float(b[1]) - float(a[1])) * (float(b[0]) - float(a[0])))
		crossings.sort()
		for c in range(0, crossings.size() - 1, 2):
			var first := maxi(0, int(ceil((crossings[c] - grid.x0) / grid.cell - 0.5)))
			var last := mini(grid.nx - 1, int(ceil((crossings[c + 1] - grid.x0) / grid.cell - 0.5)) - 1)
			for i in range(first, last + 1):
				grid.raised[j * grid.nx + i] = value


## Problems in a map's data file, empty if it is fine.
static func validate(map_id: String) -> Array[String]:
	var p: Array[String] = []
	var def := load_map(map_id)
	var tag := "maps/%s" % map_id
	if def.get("id", "") != map_id:
		p.append("%s: id must equal the file name" % tag)
	if def.get("terrain", false):
		p.append_array(Terrain.validate(def, tag))
		if not p.is_empty():
			return p
	elif float(def.get("cell", 0.0)) <= 0.0 or float(def.get("depth", 0.0)) <= 0.0:
		p.append("%s: cell and depth must be above 0" % tag)
		return p
	if not def.get("terrain", false):
		var outer: Variant = def.get("outer")
		if not (outer is Array and outer.size() >= 3):
			p.append("%s: outer needs at least 3 points" % tag)
			return p
		for island: Variant in def.get("islands", []):
			if not (island is Array and island.size() >= 3):
				p.append("%s: every island needs at least 3 points" % tag)
				return p
	var grid := grid_for(def)
	for end in ["north", "south"]:
		var spawns: Variant = def.get("spawns", {}).get(end)
		if not (spawns is Dictionary and ["north", "south"].has(str(spawns.get("facing", ""))) and spawns.get("points") is Array):
			p.append("%s: spawns.%s needs facing (north or south) and points" % [tag, end])
			continue
		if spawns["points"].size() < 4:
			p.append("%s: spawns.%s needs at least 4 points, one for each pilot of a team" % [tag, end])
		for point: Array in spawns["points"]:
			# The spot and the ground around it must all be open floor.
			for dx in [-8.0, 0.0, 8.0]:
				for dz in [-8.0, 0.0, 8.0]:
					if grid.blocked_at(float(point[0]) + dx, float(point[1]) + dz):
						p.append("%s: spawn %s is not clear canyon floor" % [tag, point])
						break
	return p


## Builds the terrain under `parent`: the drawn mesh and a static body to stand on.
## Returns the grid, so callers can ask how high the ground is.
static func build(parent: Node3D, map_def: Dictionary) -> Grid:
	if map_def.get("terrain", false):
		return Terrain.build(parent, map_def)
	var grid := grid_for(map_def)
	var drawn := _Mesh.new()
	var faces := PackedVector3Array()
	_tops(grid, drawn, faces)
	_walls_across(grid, drawn, faces)
	_walls_along(grid, drawn, faces)

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
	var mesh := MeshInstance3D.new()
	mesh.mesh = drawn.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.material_override = material
	body.add_child(mesh)
	parent.add_child(body)
	return grid


## Flat ground and tops, as rectangles: runs of equal cells along each row, in patches.
static func _tops(grid: Grid, drawn: _Mesh, faces: PackedVector3Array) -> void:
	for j in grid.nz:
		var i := 0
		while i < grid.nx:
			var value := grid.at(i, j)
			var end := i + 1
			while end < grid.nx and grid.at(end, j) == value and end % PATCH != 0:
				end += 1
			var y := grid.depth * value
			var x_from := grid.x0 + float(i) * grid.cell
			var x_to := grid.x0 + float(end) * grid.cell
			var z_from := grid.z0 + float(j) * grid.cell
			var z_to := z_from + grid.cell
			var tones: Array[String] = TOP_GREENS if value == 1 else FLOOR_GREENS
			var color := Color(tones[_hash(floori(i / float(PATCH)), floori(j / float(PATCH))) % tones.size()])
			drawn.quad(Vector3(x_from, y, z_from), Vector3(x_to, y, z_from), Vector3(x_to, y, z_to), Vector3(x_from, y, z_to), Vector3.UP, color)
			_face(faces, Vector3(x_from, y, z_from), Vector3(x_to, y, z_from), Vector3(x_to, y, z_to), Vector3(x_from, y, z_to))
			i = end


## Rock faces that run along x, where a row of cells meets the next row and one is raised.
static func _walls_across(grid: Grid, drawn: _Mesh, faces: PackedVector3Array) -> void:
	for j in grid.nz - 1:
		var z := grid.z0 + float(j + 1) * grid.cell
		var i := 0
		while i < grid.nx:
			var here := grid.at(i, j)
			var there := grid.at(i, j + 1)
			if here == there:
				i += 1
				continue
			var end := i + 1
			while end < grid.nx and grid.at(end, j) == here and grid.at(end, j + 1) == there:
				end += 1
			# The face looks towards the lower side.
			var facing := Vector3(0.0, 0.0, 1.0) if here == 1 else Vector3(0.0, 0.0, -1.0)
			var x_from := grid.x0 + float(i) * grid.cell
			var x_to := grid.x0 + float(end) * grid.cell
			_rock(drawn, faces, Vector3(x_from, 0.0, z), Vector3(x_to, 0.0, z), grid.depth, facing, _hash(i, j))
			i = end


## Rock faces that run along z, where a column of cells meets the next column.
static func _walls_along(grid: Grid, drawn: _Mesh, faces: PackedVector3Array) -> void:
	for i in grid.nx - 1:
		var x := grid.x0 + float(i + 1) * grid.cell
		var j := 0
		while j < grid.nz:
			var here := grid.at(i, j)
			var there := grid.at(i + 1, j)
			if here == there:
				j += 1
				continue
			var end := j + 1
			while end < grid.nz and grid.at(i, end) == here and grid.at(i + 1, end) == there:
				end += 1
			var facing := Vector3(1.0, 0.0, 0.0) if here == 1 else Vector3(-1.0, 0.0, 0.0)
			var z_from := grid.z0 + float(j) * grid.cell
			var z_to := grid.z0 + float(end) * grid.cell
			_rock(drawn, faces, Vector3(x, 0.0, z_from), Vector3(x, 0.0, z_to), grid.depth, facing, _hash(i, j))
			j = end


## One rock face from `a` to `b` along the ground and `height` up, drawn in layers.
static func _rock(drawn: _Mesh, faces: PackedVector3Array, a: Vector3, b: Vector3, height: float, facing: Vector3, seed_value: int) -> void:
	var layers := maxi(1, int(round(height / LAYER_HEIGHT)))
	for layer in layers:
		var low := height * float(layer) / float(layers)
		var high := height * float(layer + 1) / float(layers)
		var color := Color(ROCK_TANS[(layer + floori(seed_value / 7.0)) % ROCK_TANS.size()])
		drawn.quad(a + Vector3(0.0, low, 0.0), b + Vector3(0.0, low, 0.0), b + Vector3(0.0, high, 0.0), a + Vector3(0.0, high, 0.0), facing, color)
	_face(faces, a, b, b + Vector3(0.0, height, 0.0), a + Vector3(0.0, height, 0.0))


## A quad as two triangles for the collision shape.
static func _face(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append_array(PackedVector3Array([a, b, c, a, c, d]))


static func _hash(i: int, j: int) -> int:
	return absi((i * 73856093) ^ (j * 19349663)) % 1000


## The drawn mesh, gathered one flat-coloured quad at a time.
class _Mesh extends RefCounted:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## A quad whose corners go round the edge; drawn facing along `normal`.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
		var start := positions.size()
		# Godot draws triangles that go clockwise as seen from the front.
		var clockwise := (b - a).cross(c - a).dot(normal) < 0.0
		var corners: Array[Vector3] = []
		corners.assign([a, b, c, d] if clockwise else [a, d, c, b])
		for corner in corners:
			positions.append(corner)
			normals.append(normal)
			colors.append(color)
		indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
