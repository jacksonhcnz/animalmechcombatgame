extends SceneTree
## Points turn into stats, budgets are fixed, and carry capacity limits ammo.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", what)


func _init() -> void:
	var budget := int(Points.table().get("budget", 0))
	for id in GameData.ids("mechs"):
		var d := GameData.get_entry("mechs", id)
		check(Points.total(d) == budget, "%s spends the whole budget" % id)
		check(float(d["base"]["speed"]) > 0.0 and float(d["base"]["armor"]) > 0.0 and float(d["base"]["turn_rate"]) > 0.0, "%s has stats from points" % id)
		check(Points.weapons_weight(d) <= Points.carry_capacity(d), "%s can carry its weapons" % id)
	var lion := GameData.get_entry("mechs", "lion")
	var hawk := GameData.get_entry("mechs", "hawk")
	check(is_equal_approx(float(lion["base"]["speed"]), 14.0), "lion speed from 10 points is 14")
	check(is_equal_approx(float(lion["base"]["armor"]), 1.2), "lion armor from 7 points is 1.2")
	check(float(hawk["base"]["speed"]) > float(lion["base"]["speed"]), "more speed points, faster mech")
	check(hawk["base"].has("climb_speed") and not hawk["base"].has("jump_speed"), "flyers get climb, not jump")
	check(lion["base"].has("jump_speed") and not lion["base"].has("climb_speed"), "walkers get jump, not climb")
	var lion_ammo := Points.ammo_for(lion)
	check(int(lion_ammo["gun_l"]) == 400 and int(lion_ammo["gun_r"]) == 24, "lion carries full ammo")
	var hawk_ammo := Points.ammo_for(hawk)
	check(int(hawk_ammo["gun_l"]) < 400 and int(hawk_ammo["gun_l"]) > 0, "hawk carries less ammo")
	var m := Mech.new()
	m.setup("hawk", Ruleset.new())
	check(m.weapons[0].ammo == int(hawk_ammo["gun_l"]), "mech spawns with the carried ammo")
	m.free()
	_loadouts(lion, hawk)
	var problems := GameData.validate_all()
	check(problems.is_empty(), "data validates: %s" % str(problems))
	if failures > 0:
		quit(1)
	else:
		print("points_test passed")
		quit(0)


func _loadouts(lion: Dictionary, hawk: Dictionary) -> void:
	var heavy := {"primary": "sniper_cannon", "secondary": "rocket_pod", "equipment": "armor_plating", "perk": "none"}
	check(Loadout.fits(lion, heavy), "lion carries the heavy loadout")
	check(not Loadout.fits(hawk, heavy), "hawk is too weak to carry it")
	check(Loadout.sanitize(hawk, heavy) == Loadout.default_loadout(), "a too heavy loadout falls back to the default")
	check(Loadout.complete({"primary": "rocket_pod", "perk": "nonsense", "equipment": 5}) == Loadout.default_loadout(), "wrong-slot and unknown items are ignored")
	var plated := Loadout.apply(lion, {"equipment": "armor_plating"})
	check(float(plated["base"]["armor"]) > float(lion["base"]["armor"]), "armor plating raises armor")
	check(is_equal_approx(float(lion["base"]["armor"]), 1.2), "applying a loadout leaves the shared data alone")
	var sprint := Loadout.apply(lion, {"perk": "sprinter"})
	check(float(sprint["base"]["speed"]) > float(lion["base"]["speed"]), "sprinter is faster")
	var gun := Loadout.apply(lion, {"primary": "machine_gun"})
	var mech := Mech.create("lion", Ruleset.new(), {"primary": "machine_gun", "perk": "sharpshooter"})
	check(mech.weapons[0].def["id"] == "machine_gun", "chosen primary is mounted")
	check(mech.weapons[1].def["id"] == "rocket_pod", "default secondary stays")
	check(float(mech.def["damage_mult"]) > 1.0, "perk raises damage")
	mech.free()
	var crate := Points.ammo_for(Loadout.apply(lion, {"equipment": "ammo_crate"}))
	check(int(crate["gun_l"]) > 400, "ammo crate carries more rounds when there is room")
	check(gun["mounts"][0]["weapon"] == "machine_gun", "mount weapon swapped")
