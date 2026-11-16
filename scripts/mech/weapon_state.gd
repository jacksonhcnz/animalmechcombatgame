class_name WeaponState
extends RefCounted
## One weapon on one mount: its data, remaining ammo and cooldown.

var mount_id: String
var def: Dictionary
var ammo: int = 0
var cooldown: float = 0.0
## Seconds the fire button has been held on a weapon that is cocked before it fires.
var charge_time: float = 0.0


## Which fire button works the weapon. It belongs to the mount, not the weapon, so any ranged
## weapon can go in either weapon slot; with no mount slot given, the weapon's own is used.
var mount_slot: String = ""


func _init(mount: String, weapon_def: Dictionary, slot_override: String = "") -> void:
	mount_id = mount
	mount_slot = slot_override
	def = weapon_def
	ammo = int(weapon_def.get("ammo", 0))


func slot() -> String:
	return mount_slot if mount_slot != "" else def.get("slot", "primary")


## True for a weapon that takes both weapon slots (the ion cannon); either fire button works it.
func is_two_slot() -> bool:
	return bool(def.get("two_slot", false))


## True for a weapon that only fires after a full charge; letting go early cancels the shot.
func needs_full_charge() -> bool:
	return bool(def.get("charge", {}).get("full_only", false))


func is_melee() -> bool:
	return def.get("kind", "ranged") == "melee"


## True for a weapon fired on release, after being cocked ("charge" in its data).
func is_charged() -> bool:
	return def.has("charge")


func charge_max() -> float:
	return float(def.get("charge", {}).get("max_time", 1.0))


## 0 to 1: how far the weapon is cocked.
func charge_ratio() -> float:
	return clampf(charge_time / maxf(0.01, charge_max()), 0.0, 1.0)


## How high above the aim point a shell cocked for `held` seconds bursts.
func burst_height(held: float) -> float:
	var charge: Dictionary = def.get("charge", {})
	return clampf(held / maxf(0.01, charge_max()), 0.0, 1.0) * float(charge.get("max_height", 0.0))


## Mirrors the cocking on a client's own mech so the HUD can show it (the server does the firing).
func show_charge(held: bool, delta: float) -> void:
	charge_time = minf(charge_time + delta, charge_max()) if held else 0.0


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
