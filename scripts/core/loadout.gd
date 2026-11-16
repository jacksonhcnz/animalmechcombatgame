class_name Loadout
extends RefCounted
## A pilot's four loadout slots: primary weapon, secondary weapon, equipment and perk.
## The mech's hidden points decide how much it can carry; a loadout that is too heavy
## is not accepted and the mech's default loadout is used instead.

const SLOTS: Array[String] = ["primary", "secondary", "equipment", "perk"]
const MOD_KEYS: Array[String] = ["armor_mult", "speed_mult", "turn_mult", "damage_mult", "ammo_mult"]
const DEFAULT := {"primary": "autocannon", "secondary": "rocket_pod", "equipment": "none", "perk": "none"}


static func default_loadout() -> Dictionary:
	return DEFAULT.duplicate()


## Ids that can go in a slot, sorted.
static func options(slot: String) -> Array[String]:
	var result: Array[String] = []
	match slot:
		"primary", "secondary":
			# Either weapon slot takes any ranged weapon, so two of the same is fine.
			for id in GameData.ids("weapons"):
				var weapon := GameData.get_entry("weapons", id)
				# Melee weapons and the hawk's bomb (its own slot and button) are not for the loadout.
				if weapon.get("kind", "ranged") != "melee" and ["primary", "secondary"].has(weapon.get("slot", "")):
					result.append(id)
		"equipment":
			result.assign(GameData.ids("equipment"))
		"perk":
			result.assign(GameData.ids("perks"))
	return result


static func item(slot: String, id: String) -> Dictionary:
	match slot:
		"primary", "secondary":
			return GameData.get_entry("weapons", id)
		"equipment":
			return GameData.get_entry("equipment", id)
		"perk":
			return GameData.get_entry("perks", id)
	return {}


## Fills missing slots with the defaults and drops anything unknown or in the wrong slot.
static func complete(choice: Variant) -> Dictionary:
	var result := default_loadout()
	if choice is Dictionary:
		for slot in SLOTS:
			var id: Variant = choice.get(slot)
			if id is String and options(slot).has(id):
				result[slot] = id
	return result


## Weight of everything the loadout adds up to, ammo not counted.
static func weight(mech_def: Dictionary, choice: Dictionary) -> float:
	var sum := 0.0
	for slot in SLOTS:
		sum += float(item(slot, choice[slot]).get("weight", 0.0))
	return sum


static func ammo_mult(choice: Dictionary) -> float:
	var m := 1.0
	for slot in ["equipment", "perk"]:
		m *= float(item(slot, choice[slot]).get("mods", {}).get("ammo_mult", 1.0))
	return m


## Whether the weapons and gear fit within what the mech can carry.
static func fits(mech_def: Dictionary, choice: Dictionary) -> bool:
	return weight(mech_def, choice) <= Points.carry_capacity(mech_def)


## A usable loadout for a mech: completed, and the default if too heavy.
static func sanitize(mech_def: Dictionary, choice: Variant) -> Dictionary:
	var result := complete(choice)
	if not fits(mech_def, result):
		return default_loadout()
	return result


## The mech definition with the loadout applied: weapons swapped in by slot, gear weight
## and ammo scaling recorded for the carry rules, perk and equipment mods applied to stats.
static func apply(mech_def: Dictionary, choice: Variant) -> Dictionary:
	var load := sanitize(mech_def, choice)
	var result := mech_def.duplicate(true)
	var mounts: Array = result.get("mounts", [])
	for mount in mounts:
		var slot: String = GameData.get_entry("weapons", mount["weapon"]).get("slot", "")
		if slot == "primary" or slot == "secondary":
			mount["weapon"] = load[slot]
			mount["slot"] = slot
	var gear := 0.0
	for slot in ["equipment", "perk"]:
		gear += float(item(slot, load[slot]).get("weight", 0.0))
	result["gear_weight"] = gear
	result["ammo_mult"] = ammo_mult(load)
	var base: Dictionary = result["base"]
	var mods := {}
	for key in MOD_KEYS:
		mods[key] = 1.0
		for slot in ["equipment", "perk"]:
			mods[key] *= float(item(slot, load[slot]).get("mods", {}).get(key, 1.0))
	base["armor"] = float(base["armor"]) * mods["armor_mult"]
	base["turn_rate"] = float(base["turn_rate"]) * mods["turn_mult"]
	for key in ["speed", "jump_speed", "climb_speed"]:
		if base.has(key):
			base[key] = float(base[key]) * mods["speed_mult"]
	result["damage_mult"] = mods["damage_mult"]
	result["loadout"] = load
	return result


static func validate() -> Array[String]:
	var p: Array[String] = []
	for kind in ["equipment", "perks"]:
		var ids := GameData.ids(kind)
		if not ids.has("none"):
			p.append("%s: a 'none' entry is required" % kind)
		for id in ids:
			var e := GameData.get_entry(kind, id)
			var tag := "%s/%s" % [kind, id]
			if e.get("id", "") != id:
				p.append("%s: id must equal the file name" % tag)
			if str(e.get("name", "")) == "":
				p.append("%s: name is required" % tag)
			if float(e.get("weight", -1.0)) < 0.0:
				p.append("%s: weight must be 0 or more" % tag)
			for key in e.get("mods", {}):
				if not MOD_KEYS.has(key) or float(e["mods"][key]) <= 0.0:
					p.append("%s: mods.%s is not a known modifier above 0" % [tag, key])
	for slot in ["primary", "secondary"]:
		for id in options(slot):
			var w := GameData.get_entry("weapons", id)
			if float(w.get("weight", -1.0)) < 0.0 or float(w.get("ammo_weight", -1.0)) < 0.0:
				p.append("weapons/%s: loadout weapons need weight and ammo_weight of 0 or more" % id)
	for slot in SLOTS:
		if not options(slot).has(DEFAULT[slot]):
			p.append("loadout default %s '%s' does not exist" % [slot, DEFAULT[slot]])
	for id in GameData.ids("mechs"):
		var d := GameData.get_entry("mechs", id)
		if not fits(d, default_loadout()):
			p.append("mechs/%s: cannot carry the default loadout" % id)
	return p
