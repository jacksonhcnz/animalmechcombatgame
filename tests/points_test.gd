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
	var problems := GameData.validate_all()
	check(problems.is_empty(), "data validates: %s" % str(problems))
	if failures > 0:
		quit(1)
	else:
		print("points_test passed")
		quit(0)
