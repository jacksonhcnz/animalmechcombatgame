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
	if m.get("movement", "") == "flying":
		for key in ["climb_speed", "spawn_height"]:
			if float(base.get(key, 0.0)) <= 0.0:
				p.append("%s: flying mechs need base.%s greater than 0" % [tag, key])

	if not _is_vec3(m.get("collider", {}).get("size")) or not _is_vec3(m.get("collider", {}).get("center")):
		p.append("%s: collider needs size and center as [x, y, z]" % tag)
	if not _is_vec3(m.get("cockpit")):
		p.append("%s: cockpit must be [x, y, z]" % tag)
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
		if float(part.get("health", 0.0)) <= 0.0:
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


static func _is_vec3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for n in value:
		if not (n is float or n is int):
			return false
	return true
