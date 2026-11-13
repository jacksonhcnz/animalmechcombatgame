class_name WeaponState
extends RefCounted
## One weapon on one mount: its data, remaining ammo and cooldown.

var mount_id: String
var def: Dictionary
var ammo: int = 0
var cooldown: float = 0.0


func _init(mount: String, weapon_def: Dictionary) -> void:
	mount_id = mount
	def = weapon_def
	ammo = int(weapon_def.get("ammo", 0))


func slot() -> String:
	return def.get("slot", "primary")


func is_melee() -> bool:
	return def.get("kind", "ranged") == "melee"


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)


func ready_to_fire() -> bool:
	return cooldown <= 0.0


## Melee never needs ammo. Ranged weapons do unless the ruleset removes ammo limits.
func has_ammo(rules: Ruleset) -> bool:
	return is_melee() or not rules.ammo_limits or ammo > 0


## Uses one shot: starts the cooldown and spends ammo if limits are on.
func consume(rules: Ruleset) -> void:
	cooldown = float(def.get("fire_interval", 0.5))
	if rules.ammo_limits and not is_melee():
		ammo = maxi(0, ammo - 1)
