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
	_sprint()
	await _store_and_menus()
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


func _store_and_menus() -> void:
	LoadoutStore.path = "user://loadouts_test.json"
	DirAccess.remove_absolute(LoadoutStore.path)
	LoadoutStore.reset()
	check(LoadoutStore.slots("lion").size() == 4, "four boxes per mech")
	check(LoadoutStore.active_name("lion") == "Loadout 1", "default box name")
	LoadoutStore.save_slot("lion", 2, "  Sniper nest  ", {"primary": "sniper_cannon", "perk": "hardened"})
	LoadoutStore.set_active("lion", 2)
	LoadoutStore.reset()
	check(LoadoutStore.active_index("lion") == 2, "active box is remembered")
	check(LoadoutStore.active_name("lion") == "Sniper nest", "box name is saved and trimmed")
	check(LoadoutStore.active_loadout("lion")["primary"] == "sniper_cannon", "active loadout is the saved one")
	check(LoadoutStore.active_loadout("hawk")["primary"] == "autocannon", "other mechs are untouched")
	LoadoutStore.save_slot("hawk", 0, "", {"primary": "sniper_cannon", "equipment": "armor_plating"})
	check(LoadoutStore.active_loadout("hawk") == Loadout.default_loadout(), "a loadout too heavy for the mech is not used")
	DirAccess.remove_absolute(LoadoutStore.path)
	LoadoutStore.reset()
	for scene in ["res://scenes/main_menu.tscn", "res://scenes/loadout_menu.tscn"]:
		var menu: Node = load(scene).instantiate()
		root.add_child(menu)
		await process_frame
		check(menu.get_child_count() > 0, "%s builds" % scene)
		menu.free()
	var pause := PauseMenu.new()
	root.add_child(pause)
	await process_frame
	check(not pause.is_open(), "pause menu starts closed")
	pause.open()
	check(pause.is_open(), "pause menu opens")
	pause.free()


func _sprint() -> void:
	var mech := Mech.create("lion", Ruleset.new())
	check(is_equal_approx(mech.sprint_mult(), 1.0), "no sprint without the key")
	mech.controls.sprint = true
	mech.controls.throttle = 1.0
	check(mech.sprint_mult() > 1.0, "sprint speeds the mech up")
	mech.controls.throttle = -1.0
	check(is_equal_approx(mech.sprint_mult(), 1.0), "no sprint when moving backwards")
	mech.controls.throttle = 1.0
	mech.rules.sprinting = false
	check(is_equal_approx(mech.sprint_mult(), 1.0), "a ruleset can switch sprint off")
	mech.free()
	var a := MechControls.new()
	a.sprint = true
	var b := MechControls.new()
	check(NetProtocol.apply_input(b, NetProtocol.pack_input(a, 0.0, 0.0)) and b.sprint, "sprint travels over the network")
