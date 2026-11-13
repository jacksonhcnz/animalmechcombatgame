class_name GameData
extends RefCounted
## Loads gameplay data (mechs, weapons, rulesets, balance version) from res://data.
## All gameplay numbers live in those JSON files, so balance changes are data edits.

const DATA_DIR := "res://data"
const MOVEMENT_TYPES: Array[String] = ["ground", "flying"]
const WEAPON_KINDS: Array[String] = ["ranged", "melee"]
const WEAPON_SLOTS: Array[String] = ["primary", "secondary", "melee"]
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
		_cache[key] = read_json("%s/%s/%s.json" % [DATA_DIR, kind, id])
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
	for kind in ["mechs", "weapons", "rulesets"]:
		if ids(kind).is_empty():
			problems.append("%s: no data files found" % kind)
	for id in ids("weapons"):
		problems.append_array(_validate_weapon(id))
	for id in ids("rulesets"):
		problems.append_array(_validate_ruleset(id))
	for id in ids("mechs"):
		problems.append_array(_validate_mech(id))
	return problems


static func _validate_weapon(id: String) -> Array[String]:
	var p: Array[String] = []
	var w := get_entry("weapons", id)
	var tag := "weapons/%s" % id
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
	var window: Variant = frame.get("window")
	if not (window is Array and window.size() == 2 and float(window[0]) > 0.0 and float(window[1]) > 0.0):
		p.append("%s: cockpit_frame.window must be [half width, half height] greater than 0" % tag)
	if float(frame.get("distance", 0.0)) < 0.4:
		p.append("%s: cockpit_frame.distance must be at least 0.4 (the camera's near plane is 0.2)" % tag)
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
		if not (cfg[key] is float or cfg[key] is int):
			p.append("%s: animation.%s must be a number" % [tag, key])

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


static func _is_vec3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for n in value:
		if not (n is float or n is int):
			return false
	return true
