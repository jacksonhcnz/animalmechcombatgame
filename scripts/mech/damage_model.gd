class_name DamageModel
extends RefCounted
## Tracks the health of each part of one mech and what its damage does.
##
## Reads the active Ruleset, so each system can be switched off by a game mode:
## - location_damage off: all damage goes to one shared pool, no parts are lost.
## - joint_criticals off: hits on a joint count as ordinary damage to its parent part.
## - equipment_knockout off: weapons stay online whatever happens to their part.

signal part_disabled(part_id: String)
signal destroyed

var health: Dictionary = {}
var max_health: Dictionary = {}

var _parts: Dictionary = {}
var _mounts: Dictionary = {}
var _disabled: Dictionary = {}
var _rules: Ruleset
var _armor: float = 1.0
var _pool: float = 0.0
var _pool_max: float = 0.0
var _destroyed: bool = false


func _init(mech_def: Dictionary, rules: Ruleset) -> void:
	_rules = rules
	_armor = maxf(0.01, float(mech_def.get("base", {}).get("armor", 1.0)))
	for part in mech_def.get("parts", []):
		var hp := float(part["health"]) * rules.durability_mult
		_parts[part["id"]] = part
		health[part["id"]] = hp
		max_health[part["id"]] = hp
		_pool_max += hp
	_pool = _pool_max
	for mount in mech_def.get("mounts", []):
		_mounts[mount["id"]] = mount["part"]


## Applies damage to a part. Returns what happened:
## { part, applied, disabled, destroyed }. "part" is the part that really took the damage.
func apply_damage(part_id: String, amount: float) -> Dictionary:
	var result := {"part": part_id, "applied": 0.0, "disabled": false, "destroyed": false}
	if _destroyed or amount <= 0.0 or not _parts.has(part_id):
		return result

	var dmg := amount / _armor

	if not _rules.location_damage:
		var before_pool := _pool
		_pool = maxf(0.0, _pool - dmg)
		result["applied"] = before_pool - _pool
		if _pool <= 0.0:
			_destroy()
			result["destroyed"] = true
		return result

	var target := part_id
	if _parts[target].get("joint", false) and not _rules.joint_criticals:
		target = _parts[target].get("parent", "torso")
	result["part"] = target

	var before: float = health[target]
	health[target] = maxf(0.0, before - dmg)
	result["applied"] = before - health[target]
	if before > 0.0 and health[target] <= 0.0:
		_disabled[target] = true
		result["disabled"] = true
		part_disabled.emit(target)
		if _parts[target].get("fatal", false):
			_destroy()
			result["destroyed"] = true
	return result


func is_destroyed() -> bool:
	return _destroyed


## True if the part has no health left.
func is_part_disabled(part_id: String) -> bool:
	return _disabled.has(part_id)


## True if the part is disabled, one of its joints is, or a part it hangs from is. A crippled limb cannot
## use anything mounted on it.
func is_crippled(part_id: String) -> bool:
	if _disabled.has(part_id):
		return true
	# A part hanging from a destroyed part (guns on a gimbal bar on a mast) goes down with it.
	var ancestor: String = _parts.get(part_id, {}).get("parent", "")
	var steps := 0
	while ancestor != "" and steps < _parts.size():
		if _disabled.has(ancestor):
			return true
		ancestor = _parts.get(ancestor, {}).get("parent", "")
		steps += 1
	for other_id in _parts:
		var other: Dictionary = _parts[other_id]
		if other.get("joint", false) and other.get("parent", "") == part_id and _disabled.has(other_id):
			return true
	return false


## Remaining health of a part from 0 to 1. With location damage off this is the shared pool.
func part_ratio(part_id: String) -> float:
	if not _rules.location_damage:
		return total_ratio()
	if not health.has(part_id):
		return 0.0
	return float(health[part_id]) / float(max_health[part_id])


## Overall remaining health from 0 to 1.
func total_ratio() -> float:
	if not _rules.location_damage:
		return _pool / _pool_max if _pool_max > 0.0 else 0.0
	var now := 0.0
	var full := 0.0
	for part_id in health:
		now += health[part_id]
		full += max_health[part_id]
	return now / full if full > 0.0 else 0.0


## True if the weapon on this mount can be used.
func mount_online(mount_id: String) -> bool:
	if _destroyed or not _mounts.has(mount_id):
		return false
	if not _rules.equipment_knockout:
		return true
	return not is_crippled(_mounts[mount_id])


func speed_mult() -> float:
	return _effect_product("speed_mult")


func turn_mult() -> float:
	return _effect_product("turn_mult")


## Below 0.5 a flying mech cannot hold its altitude.
func lift_mult() -> float:
	return _effect_product("lift_mult")


func _effect_product(key: String) -> float:
	var product := 1.0
	for part_id in _disabled:
		product *= float(_parts[part_id].get("on_disabled", {}).get(key, 1.0))
	return product


func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit()
