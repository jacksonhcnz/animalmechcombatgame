class_name GameData
extends RefCounted
## Loads gameplay data (mechs, weapons, rulesets, balance version) from res://data.
## All gameplay numbers live in those JSON files, so balance changes are data edits.

const DATA_DIR := "res://data"
const VISUAL_SHAPES: Array[String] = ["box", "sphere", "cylinder", "hex", "plate"]
const MOVEMENT_TYPES: Array[String] = ["ground", "flying"]
const WEAPON_KINDS: Array[String] = ["ranged", "melee"]
const WEAPON_SLOTS: Array[String] = ["primary", "secondary", "melee", "bomb", "equipment"]
const PROJECTILE_MODELS: Array[String] = ["bullet", "pellet", "rocket", "grenade", "bomb"]
const TONES: Array[String] = ["primary", "accent", "dark"]

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func balance_version() -> int:
	return int(read_json(DATA_DIR + "/balance.json").get("version", 0))


## IDs of every data file of a kind ("mechs", "weapons", "rulesets"), sorted.
static func ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open("%s/%s" % [DATA_DIR, kind])
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".json"):
			result.append(file.get_basename())
	result.sort()
	return result


## One data entry. Returns an empty dictionary if it does not exist.
static func get_entry(kind: String, id: String) -> Dictionary:
	var key := "%s/%s" % [kind, id]
	if not _cache.has(key):
		var entry := read_json("%s/%s/%s.json" % [DATA_DIR, kind, id])
		_cache[key] = Points.resolve(entry) if kind == "mechs" else entry
	return _cache[key]


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Invalid JSON object in %s" % path)
	return {}


## Checks every data file. Returns a list of problems, empty if everything is fine.
static func validate_all() -> Array[String]:
	var problems: Array[String] = []
	if balance_version() <= 0:
		problems.append("balance.json: version must be a positive integer")
	problems.append_array(Points.validate())
	problems.append_array(Loadout.validate())
	for kind in ["mechs", "weapons", "rulesets"]:
		if ids(kind).is_empty():
			problems.append("%s: no data files found" % kind)
	for id in ids("weapons"):
		problems.append_array(_validate_weapon(id))
	for id in ids("rulesets"):
		problems.append_array(_validate_ruleset(id))
	for id in ids("maps"):
		problems.append_array(Canyon.validate(id))
	for id in ids("mechs"):
		problems.append_array(_validate_mech(id))
	return problems


## A sound entry names a clip in assets/audio (without the .ogg).
static func _validate_clip(tag: String, key: String, value: Variant) -> Array[String]:
	var p: Array[String] = []
	if not (value is String) or not ResourceLoader.exists("res://assets/audio/%s.ogg" % value):
		p.append("%s: %s must name a clip in assets/audio" % [tag, key])
	return p


static func _validate_weapon(id: String) -> Array[String]:
	var p: Array[String] = []
	var w := get_entry("weapons", id)
	var tag := "weapons/%s" % id
	for key in ["sound", "sound_charge", "sound_aim", "sound_burst"]:
		if w.has(key):
			p.append_array(_validate_clip(tag, key, w[key]))
	if w.get("id", "") != id:
		p.append("%s: id must equal the file name" % tag)
	if not str(w.get("name", "")).length() > 0:
		p.append("%s: name is required" % tag)
	if not WEAPON_KINDS.has(w.get("kind", "")):
		p.append("%s: kind must be one of %s" % [tag, WEAPON_KINDS])
	if not WEAPON_SLOTS.has(w.get("slot", "")):
		p.append("%s: slot must be one of %s" % [tag, WEAPON_SLOTS])
	for key in ["damage", "range", "fire_interval"]:
		if float(w.get(key, 0.0)) <= 0.0:
			p.append("%s: %s must be greater than 0" % [tag, key])
	if w.has("projectile"):
		var shot: Variant = w["projectile"]
		if not shot is Dictionary or float(shot.get("speed", 0.0)) <= 0.0:
			p.append("%s: projectile needs a speed above 0" % tag)
		elif not PROJECTILE_MODELS.has(str(shot.get("model", ""))):
			p.append("%s: projectile model must be one of %s" % [tag, PROJECTILE_MODELS])
		elif float(shot.get("gravity", 0.0)) < 0.0 or float(shot.get("splash_radius", 0.0)) < 0.0 or float(shot.get("splash_damage", 0.0)) < 0.0:
			p.append("%s: projectile gravity, splash_radius and splash_damage cannot be negative" % tag)
		if w.get("kind", "") == "melee":
			p.append("%s: melee weapons cannot fire projectiles" % tag)
		if w.has("charge"):
			var charge: Variant = w["charge"]
			var full_only: bool = charge is Dictionary and bool(charge.get("full_only", false))
			if not (charge is Dictionary and float(charge.get("max_time", 0.0)) > 0.0 and (full_only or float(charge.get("max_height", 0.0)) > 0.0)):
				p.append("%s: charge needs max_time above 0, and max_height above 0 unless full_only" % tag)
			elif not full_only and not (shot is Dictionary and float(shot.get("splash_radius", 0.0)) > 0.0):
				p.append("%s: a charged weapon bursts, so its projectile needs a splash_radius" % tag)
	if w.has("beam"):
		var beam: Variant = w["beam"]
		if not (beam is Dictionary and float(beam.get("width", 0.0)) > 0.0 and float(beam.get("fade", 0.0)) > 0.0):
			p.append("%s: beam needs a width and a fade time above 0" % tag)
		if w.has("projectile"):
			p.append("%s: a weapon is a beam or fires projectiles, not both" % tag)
	if w.has("visual"):
		p.append_array(_validate_visual(tag, w["visual"]))
		if float(w.get("muzzle", 0.0)) <= 0.0:
			p.append("%s: a weapon with a visual needs muzzle (how far in front of its mount the shots start)" % tag)
	if w.get("kind", "") == "ranged":
		if int(w.get("ammo", 0)) <= 0:
			p.append("%s: ranged weapons need ammo greater than 0" % tag)
		if not Color.html_is_valid(str(w.get("tracer_color", ""))):
			p.append("%s: tracer_color must be a colour such as #ffe066" % tag)
	return p


static func _validate_ruleset(id: String) -> Array[String]:
	var p: Array[String] = []
	var r := get_entry("rulesets", id)
	var tag := "rulesets/%s" % id
	if r.is_empty():
		p.append("%s: file is empty or invalid" % tag)
	for key in r:
		if not Ruleset.DEFAULTS.has(key):
			p.append("%s: unknown setting '%s'" % [tag, key])
			continue
		var expected: Variant = Ruleset.DEFAULTS[key]
		var actual: Variant = r[key]
		var numbers := (expected is float or expected is int) and (actual is float or actual is int)
		if not numbers and typeof(expected) != typeof(actual):
			p.append("%s: '%s' has the wrong type" % [tag, key])
	var map_id := str(r.get("map", "field"))
	if map_id != "field" and get_entry("maps", map_id).is_empty():
		p.append("%s: map '%s' does not exist (use field or a file in data/maps)" % [tag, map_id])
	var best_of := int(r.get("best_of", 0))
	if best_of < 0 or (best_of > 0 and best_of % 2 == 0):
		p.append("%s: best_of must be 0 (no rounds) or an odd number such as 7" % tag)
	if best_of > 0 and float(r.get("match_time", 0.0)) <= 0.0:
		p.append("%s: a round match needs match_time (the length of a round) above 0" % tag)
	return p


static func _validate_mech(id: String) -> Array[String]:
	var p: Array[String] = []
	var m := get_entry("mechs", id)
	var tag := "mechs/%s" % id
	if m.get("id", "") != id:
		p.append("%s: id must equal the file name" % tag)
	if not str(m.get("name", "")).length() > 0:
		p.append("%s: name is required" % tag)
	if not MOVEMENT_TYPES.has(m.get("movement", "")):
		p.append("%s: movement must be one of %s" % [tag, MOVEMENT_TYPES])

	var palette: Dictionary = m.get("palette", {})
	for tone in TONES:
		if not Color.html_is_valid(str(palette.get(tone, ""))):
			p.append("%s: palette.%s must be a colour such as #d9a441" % [tag, tone])

	var pts: Dictionary = m.get("points", {})
	for stat in Points.STATS:
		if not (pts.get(stat) is float or pts.get(stat) is int) or int(pts[stat]) < 1:
			p.append("%s: points.%s must be a whole number of 1 or more" % [tag, stat])
	if Points.total(m) != int(Points.table().get("budget", 0)):
		p.append("%s: points must add up to the budget of %d (is %d)" % [tag, int(Points.table().get("budget", 0)), Points.total(m)])
	var weight := Points.weapons_weight(m)
	if weight > Points.carry_capacity(m):
		p.append("%s: weapons weigh %.0f but the mech can only carry %.0f" % [tag, weight, Points.carry_capacity(m)])
	var base: Dictionary = m.get("base", {})
	for key in ["speed", "turn_rate", "armor", "twist_limit_deg"]:
		if float(base.get(key, 0.0)) <= 0.0:
			p.append("%s: base.%s must be greater than 0" % [tag, key])
	if m.get("movement", "") == "ground":
		var jump: Variant = base.get("jump_speed")
		if not ((jump is float or jump is int) and float(jump) >= 0.0):
			p.append("%s: ground mechs need base.jump_speed of 0 or more (0 disables jumping)" % tag)
	if m.get("movement", "") == "flying":
		for key in ["climb_speed", "spawn_height"]:
			if float(base.get(key, 0.0)) <= 0.0:
				p.append("%s: flying mechs need base.%s greater than 0" % [tag, key])

	if not _is_vec3(m.get("collider", {}).get("size")) or not _is_vec3(m.get("collider", {}).get("center")):
		p.append("%s: collider needs size and center as [x, y, z]" % tag)
	if not _is_vec3(m.get("cockpit")):
		p.append("%s: cockpit must be [x, y, z]" % tag)
	var frame: Dictionary = m.get("cockpit_frame", {})
	var top: Variant = frame.get("top")
	var bottom: Variant = frame.get("bottom")
	if not (top is Array and top.size() == 2 and float(top[0]) > 0.0 and float(top[1]) > 0.0 and float(top[0]) <= 1.0 and float(top[1]) <= 1.0):
		p.append("%s: cockpit_frame.top must be [half width, height] as fractions of the screen, above 0 and at most 1" % tag)
	if not (bottom is Array and bottom.size() == 2 and float(bottom[0]) > 0.0 and float(bottom[0]) <= 1.0 and float(bottom[1]) < 0.0 and float(bottom[1]) >= -0.9):
		p.append("%s: cockpit_frame.bottom must be [half width above 0, height below the centre from -0.9 to just under 0]" % tag)
	if float(frame.get("distance", 0.0)) < 0.4:
		p.append("%s: cockpit_frame.distance must be at least 0.4 (the camera's near plane is 0.2)" % tag)
	if float(frame.get("beam", 0.0)) <= 0.0:
		p.append("%s: cockpit_frame.beam (structure thickness) must be greater than 0" % tag)
	if float(m.get("third_person", {}).get("distance", 0.0)) <= 0.0:
		p.append("%s: third_person.distance must be greater than 0" % tag)

	var parts: Array = m.get("parts", [])
	var part_ids: Dictionary = {}
	var has_fatal := false
	for part in parts:
		part_ids[part.get("id", "")] = part
	if parts.is_empty():
		p.append("%s: needs at least one part" % tag)
	if not part_ids.has("head"):
		p.append("%s: needs a part with id 'head' (the cockpit)" % tag)
	if part_ids.size() != parts.size():
		p.append("%s: part ids must be unique" % tag)
	for part in parts:
		var ptag := "%s part '%s'" % [tag, part.get("id", "?")]
		if not str(part.get("name", "")).length() > 0:
			p.append("%s: name is required" % ptag)
		if part.has("damage_to"):
			var owner_part: Variant = part_ids.get(part["damage_to"])
			if owner_part == null or owner_part.has("damage_to"):
				p.append("%s: damage_to must name a part that has its own health" % ptag)
			if part.get("fatal", false):
				p.append("%s: a part with damage_to cannot be fatal" % ptag)
		elif float(part.get("health", 0.0)) <= 0.0:
			p.append("%s: health must be greater than 0" % ptag)
		if not TONES.has(part.get("tone", "")):
			p.append("%s: tone must be one of %s" % [ptag, TONES])
		if part.has("visual"):
			p.append_array(_validate_visual(ptag, part["visual"]))
		if not _is_vec3(part.get("size")) or not _is_vec3(part.get("pos")):
			p.append("%s: size and pos must be [x, y, z]" % ptag)
		if part.get("fatal", false):
			has_fatal = true
		if part.get("joint", false):
			var parent: String = part.get("parent", "")
			if not part_ids.has(parent):
				p.append("%s: a joint needs a parent that exists" % ptag)
		elif part.has("parent") and not part_ids.has(part["parent"]):
			p.append("%s: parent '%s' does not exist" % [ptag, part["parent"]])
		var effects: Dictionary = part.get("on_disabled", {})
		for key in effects:
			if not ["speed_mult", "turn_mult", "lift_mult"].has(key):
				p.append("%s: unknown on_disabled effect '%s'" % [ptag, key])
	if not has_fatal:
		p.append("%s: needs at least one fatal part" % tag)
	p.append_array(_validate_animation(tag, m, parts, part_ids))

	var mount_ids: Dictionary = {}
	for mount in m.get("mounts", []):
		var mtag := "%s mount '%s'" % [tag, mount.get("id", "?")]
		if mount_ids.has(mount.get("id", "")):
			p.append("%s: mount ids must be unique" % mtag)
		mount_ids[mount.get("id", "")] = true
		if not part_ids.has(mount.get("part", "")):
			p.append("%s: part '%s' does not exist" % [mtag, mount.get("part", "")])
		if get_entry("weapons", str(mount.get("weapon", ""))).is_empty():
			p.append("%s: weapon '%s' does not exist" % [mtag, mount.get("weapon", "")])
	return p


## Checks the "animation" block of a mech and the "anim" block of each part.
static func _validate_animation(tag: String, mech: Dictionary, parts: Array, part_ids: Dictionary) -> Array[String]:
	var p: Array[String] = []
	var flying: bool = mech.get("movement", "") == "flying"
	var sounds: Dictionary = mech.get("sounds", {})
	for key in sounds:
		if key in ["step", "flap", "destroyed"]:
			p.append_array(_validate_clip(tag, "sounds." + key, sounds[key]))
		elif key != "steps_per_stride" and key != "step_db":
			p.append("%s: unknown sounds.%s" % [tag, key])
	var cfg: Dictionary = mech.get("animation", {})
	if cfg.is_empty():
		p.append("%s: needs an animation block" % tag)
	var required: Array[String] = ["stride_length", "bob_m"]
	if flying:
		required = ["flap_hz", "flap_hz_climb", "hover_bob_m", "bank_deg", "pitch_deg"]
	for key in required:
		if float(cfg.get(key, 0.0)) <= 0.0:
			p.append("%s: animation.%s must be greater than 0" % [tag, key])
	for key in cfg:
		if key == "stand_pivot":
			if not _is_vec3(cfg[key]):
				p.append("%s: animation.stand_pivot must be [x, y, z]" % tag)
		elif not (cfg[key] is float or cfg[key] is int):
			p.append("%s: animation.%s must be a number" % [tag, key])
	if cfg.has("stand_pivot") != cfg.has("stand_pitch_deg"):
		p.append("%s: animation needs both stand_pivot and stand_pitch_deg, or neither" % tag)

	for part in parts:
		var ptag := "%s part '%s'" % [tag, part.get("id", "?")]
		var anim: Dictionary = part.get("anim", {})
		for key in anim:
			if not ["pivot", "walk", "flap", "aim", "stabilize", "look"].has(key):
				p.append("%s: unknown anim entry '%s'" % [ptag, key])
		if anim.has("aim") and not ["yaw", "pitch"].has(anim["aim"]):
			p.append("%s: anim.aim must be 'yaw' or 'pitch'" % ptag)
		if anim.has("look"):
			var look: Dictionary = anim["look"]
			if not (look.get("turn_deg") is float or look.get("turn_deg") is int) or float(look.get("turn_deg", 0.0)) <= 0.0:
				p.append("%s: look.turn_deg must be a number greater than 0" % ptag)
			for key in look:
				if not ["turn_deg", "share", "speed"].has(key):
					p.append("%s: unknown look setting '%s'" % [ptag, key])
		if anim.has("stabilize") and not (anim["stabilize"] is float or anim["stabilize"] is int):
			p.append("%s: anim.stabilize must be a number" % ptag)
		if anim.has("pivot") and not _is_vec3(anim["pivot"]):
			p.append("%s: anim.pivot must be [x, y, z]" % ptag)
		for motion_name in ["walk", "flap"]:
			if not anim.has(motion_name):
				continue
			if (motion_name == "walk") == flying:
				p.append("%s: a %s mech cannot use a '%s' motion" % [ptag, "flying" if flying else "ground", motion_name])
			var motion: Dictionary = anim[motion_name]
			if not ["x", "y", "z"].has(motion.get("axis", "")):
				p.append("%s: %s.axis must be x, y or z" % [ptag, motion_name])
			if not (motion.get("deg") is float or motion.get("deg") is int):
				p.append("%s: %s.deg must be a number" % [ptag, motion_name])
			for key in motion:
				if not ["axis", "deg", "phase", "offset_deg", "droop_deg", "rectify"].has(key):
					p.append("%s: unknown %s setting '%s'" % [ptag, motion_name, key])

		# A chain of parents must end somewhere, not loop back on itself.
		var steps := 0
		var current: String = part.get("parent", "")
		while current != "" and steps <= parts.size():
			current = part_ids.get(current, {}).get("parent", "")
			steps += 1
		if steps > parts.size():
			p.append("%s: parent chain loops" % ptag)
	return p


## Checks a part's "visual" pieces.
static func _validate_visual(ptag: String, pieces: Variant) -> Array[String]:
	var p: Array[String] = []
	if not pieces is Array or (pieces as Array).is_empty():
		p.append("%s: visual must be a list of at least one piece" % ptag)
		return p
	for piece in pieces:
		if not piece is Dictionary:
			p.append("%s: every visual piece must be an object" % ptag)
			continue
		if piece.get("shape", "box") == "plate":
			var outline: Variant = piece.get("points")
			if not outline is Array or (outline as Array).size() < 3:
				p.append("%s: a plate piece needs points, at least three [x, y] pairs" % ptag)
			elif (outline as Array).any(func(point: Variant) -> bool: return not (point is Array and (point as Array).size() == 2)):
				p.append("%s: every plate point must be [x, y]" % ptag)
			if float(piece.get("thickness", 0.0)) <= 0.0:
				p.append("%s: a plate piece needs a thickness above 0" % ptag)
			if piece.has("holes"):
				if not piece["holes"] is Array:
					p.append("%s: plate holes must be a list" % ptag)
				else:
					for hole in piece["holes"]:
						var circle: bool = hole is Array and (hole as Array).size() == 3 and not hole[0] is Array
						var polygon: bool = hole is Array and (hole as Array).size() >= 3 and hole[0] is Array
						if not (circle or polygon):
							p.append("%s: a plate hole is [x, y, radius] or a list of [x, y] points" % ptag)
		elif not _is_vec3(piece.get("size")):
			p.append("%s: visual piece needs a size [x, y, z]" % ptag)
		if piece.has("pos") and not _is_vec3(piece["pos"]):
			p.append("%s: visual piece pos must be [x, y, z]" % ptag)
		if piece.has("rot_deg") and not _is_vec3(piece["rot_deg"]):
			p.append("%s: visual piece rot_deg must be [x, y, z]" % ptag)
		if not VISUAL_SHAPES.has(piece.get("shape", "box")):
			p.append("%s: visual piece shape must be one of %s" % [ptag, VISUAL_SHAPES])
		if not TONES.has(piece.get("tone", "")) and not ["metal", "black", "eye"].has(piece.get("tone", "")):
			p.append("%s: visual piece tone must be one of %s, metal, black or eye" % [ptag, TONES])
	return p


static func _is_vec3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for n in value:
		if not (n is float or n is int):
			return false
	return true
