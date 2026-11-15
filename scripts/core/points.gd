class_name Points
extends RefCounted
## The hidden, fixed point budget of each mech. Players never change it.
## A mech's data file gives points for speed (which also covers mobility: turning,
## jumping, flight climb), armor and carry weight. data/points.json turns points into
## stats, so balance stays a data edit.

const STATS: Array[String] = ["speed", "armor", "carry"]


static func table() -> Dictionary:
	return GameData.read_json(GameData.DATA_DIR + "/points.json")


## Returns the mech definition with the stats its points buy written into `base`.
static func resolve(mech_def: Dictionary) -> Dictionary:
	if mech_def.is_empty() or not mech_def.has("points"):
		return mech_def
	var t := table()
	var pts: Dictionary = mech_def["points"]
	var base: Dictionary = mech_def.get("base", {}).duplicate()
	var wanted: Array[String] = ["speed", "turn_rate"]
	wanted.append_array(["jump_speed", "jump_cooldown"] if mech_def.get("movement", "") == "ground" else ["climb_speed"])
	for key in wanted:
		base[key] = _value(t.get("speed", {}), key, float(pts.get("speed", 0)))
	base["armor"] = _value(t.get("armor", {}), "armor", float(pts.get("armor", 0)))
	var result := mech_def.duplicate()
	result["base"] = base
	return result


static func _value(group: Dictionary, key: String, points: float) -> float:
	var rule: Dictionary = group.get(key, {})
	return float(rule.get("base", 0.0)) + float(rule.get("per_point", 0.0)) * points


static func total(mech_def: Dictionary) -> int:
	var sum := 0
	for stat in STATS:
		sum += int(mech_def.get("points", {}).get(stat, 0))
	return sum


static func carry_capacity(mech_def: Dictionary) -> float:
	var rule: Dictionary = table().get("carry", {}).get("capacity", {})
	var pts := float(mech_def.get("points", {}).get("carry", 0))
	return float(rule.get("base", 0.0)) + float(rule.get("per_point", 0.0)) * pts


static func _weapon(mount: Dictionary) -> Dictionary:
	return GameData.get_entry("weapons", mount["weapon"])


## Weight of the weapons themselves (ammo not counted).
static func weapons_weight(mech_def: Dictionary) -> float:
	var sum := 0.0
	for mount in mech_def.get("mounts", []):
		sum += float(_weapon(mount).get("weight", 0.0))
	return sum + float(mech_def.get("gear_weight", 0.0))


## Ammo each mount can carry: its full load, cut back evenly when the mech's carry
## capacity cannot hold every full load. Returns {mount id: rounds}.
static func ammo_for(mech_def: Dictionary) -> Dictionary:
	var full_weight := 0.0
	for mount in mech_def.get("mounts", []):
		var w := _weapon(mount)
		full_weight += _full_ammo(mech_def, w) * float(w.get("ammo_weight", 0.0))
	var room := maxf(0.0, carry_capacity(mech_def) - weapons_weight(mech_def))
	var share := 1.0 if full_weight <= 0.0 else minf(1.0, room / full_weight)
	var result := {}
	for mount in mech_def.get("mounts", []):
		result[mount["id"]] = int(floor(_full_ammo(mech_def, _weapon(mount)) * share))
	return result


static func _full_ammo(mech_def: Dictionary, weapon: Dictionary) -> float:
	return float(weapon.get("ammo", 0)) * float(mech_def.get("ammo_mult", 1.0))


static func validate() -> Array[String]:
	var p: Array[String] = []
	var t := table()
	if int(t.get("budget", 0)) <= 0:
		p.append("points.json: budget must be a positive integer")
	for group in ["speed", "armor", "carry"]:
		if not t.get(group) is Dictionary:
			p.append("points.json: missing group %s" % group)
	for key in ["speed", "turn_rate", "jump_speed", "jump_cooldown", "climb_speed"]:
		if not t.get("speed", {}).has(key):
			p.append("points.json: speed.%s is required" % key)
	if not t.get("armor", {}).has("armor"):
		p.append("points.json: armor.armor is required")
	if not t.get("carry", {}).has("capacity"):
		p.append("points.json: carry.capacity is required")
	return p
