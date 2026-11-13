extends SceneTree
## Unit tests for data, rulesets, damage and weapons. Run headlessly:
##   godot --headless --path . --script tests/run_tests.gd
## Exits with a non-zero code if any check fails.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_data_files()
	_test_rulesets()
	_test_damage_basics()
	_test_joint_criticals()
	_test_equipment_knockout()
	_test_location_damage_off()
	_test_fatal_parts()
	_test_durability_and_armor()
	_test_effects()
	_test_weapon_state()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _model(mech_id: String, ruleset_id: String) -> DamageModel:
	return DamageModel.new(GameData.get_entry("mechs", mech_id), Ruleset.load_id(ruleset_id))


func _rules(overrides: Dictionary) -> Ruleset:
	return Ruleset.from_dict(overrides, "test")


func _test_data_files() -> void:
	var problems := GameData.validate_all()
	for problem in problems:
		printerr("data problem: " + problem)
	_check(problems.is_empty(), "all data files validate")
	_check(GameData.balance_version() >= 1, "balance version is set")
	_check(GameData.ids("mechs") == ["hawk", "lion", "velociraptor"], "the three starting mechs exist")
	_check(GameData.get_entry("mechs", "hawk").get("movement") == "flying", "hawk flies")
	_check(GameData.get_entry("mechs", "lion").get("movement") == "ground", "lion is a ground mech")
	_check(GameData.get_entry("mechs", "does_not_exist").is_empty(), "missing entry is empty")


func _test_rulesets() -> void:
	var hardcore := Ruleset.load_id("hardcore")
	_check(not hardcore.hud, "hardcore removes the HUD")
	_check(not hardcore.crosshair, "hardcore removes the crosshair")
	_check(hardcore.force_cockpit, "hardcore forces cockpit view")
	_check(not hardcore.third_person_allowed(), "hardcore blocks third person")
	_check(hardcore.friendly_fire, "hardcore has friendly fire")
	var standard := Ruleset.load_id("standard")
	_check(standard.hud and standard.third_person_allowed(), "standard keeps HUD and third person")
	_check(standard.ammo_limits, "standard limits ammo")
	_check(standard.match_time > 0.0, "standard matches are timed")
	var defaults := Ruleset.from_dict({})
	_check(defaults.location_damage and defaults.hud, "empty ruleset uses defaults")
	var partial := Ruleset.from_dict({"hud": false})
	_check(not partial.hud and partial.crosshair, "ruleset overrides only what it names")


func _test_damage_basics() -> void:
	var m := _model("lion", "practice")
	var before: float = m.health["tail"]
	var result := m.apply_damage("tail", 10.0)
	var expected := 10.0 / 1.2
	_check(is_equal_approx(result["applied"], expected), "lion armour divides damage")
	_check(is_equal_approx(m.health["tail"], before - expected), "tail health drops")
	_check(not m.is_destroyed(), "lion survives a small tail hit")
	_check(m.total_ratio() < 1.0 and m.total_ratio() > 0.9, "total health drops slightly")
	var none := m.apply_damage("nonexistent", 50.0)
	_check(none["applied"] == 0.0, "unknown part takes no damage")
	var zero := m.apply_damage("tail", 0.0)
	_check(zero["applied"] == 0.0, "zero damage does nothing")


func _test_joint_criticals() -> void:
	var on := _model("lion", "practice")
	var result := on.apply_damage("knee_fl", 200.0)
	_check(result["part"] == "knee_fl" and result["disabled"], "knee is disabled when joint criticals are on")
	_check(on.is_part_disabled("knee_fl"), "knee reports disabled")
	_check(on.is_crippled("leg_fl"), "leg is crippled by its disabled knee")
	_check(not on.is_part_disabled("leg_fl"), "leg itself still has health")
	_check(on.speed_mult() < 1.0, "a disabled knee slows the lion")

	var off := Ruleset.from_dict({"joint_criticals": false}, "test")
	var m := DamageModel.new(GameData.get_entry("mechs", "lion"), off)
	var redirected := m.apply_damage("knee_fl", 20.0)
	_check(redirected["part"] == "leg_fl", "with joint criticals off a knee hit goes to the leg")
	_check(not m.is_part_disabled("knee_fl"), "knee is untouched when joint criticals are off")


func _test_equipment_knockout() -> void:
	var m := _model("velociraptor", "standard")
	_check(m.mount_online("gun_l"), "left gun starts online")
	m.apply_damage("shoulder_l", 500.0)
	_check(not m.mount_online("gun_l"), "a crippled shoulder knocks the left gun offline")
	_check(m.mount_online("gun_r"), "the right gun is unaffected")

	var off := Ruleset.from_dict({"equipment_knockout": false}, "test")
	var m2 := DamageModel.new(GameData.get_entry("mechs", "velociraptor"), off)
	m2.apply_damage("arm_l", 500.0)
	_check(m2.is_part_disabled("arm_l"), "arm is still destroyed")
	_check(m2.mount_online("gun_l"), "with knockout off the gun stays online")


func _test_location_damage_off() -> void:
	var rules := Ruleset.from_dict({"location_damage": false}, "test")
	var m := DamageModel.new(GameData.get_entry("mechs", "lion"), rules)
	var result := m.apply_damage("leg_fl", 50.0)
	_check(result["applied"] > 0.0 and not result["disabled"], "damage goes to the pool")
	_check(not m.is_part_disabled("leg_fl"), "no part is disabled with location damage off")
	_check(m.speed_mult() == 1.0, "no speed penalty with location damage off")
	_check(m.part_ratio("leg_fl") == m.total_ratio(), "every part shows the shared pool")
	for i in 100:
		m.apply_damage("tail", 100.0)
	_check(m.is_destroyed(), "the shared pool can still destroy the mech")


func _test_fatal_parts() -> void:
	var m := _model("hawk", "practice")
	var seen := []
	m.destroyed.connect(func(): seen.append("destroyed"))
	var result := m.apply_damage("head", 1000.0)
	_check(result["destroyed"] and m.is_destroyed(), "destroying the head destroys the mech")
	_check(seen == ["destroyed"], "destroyed signal fires once")
	m.apply_damage("torso", 1000.0)
	_check(seen == ["destroyed"], "no second destroyed signal")
	_check(m.apply_damage("tail", 10.0)["applied"] == 0.0, "a destroyed mech takes no more damage")
	_check(not m.mount_online("gun_l"), "a destroyed mech has no weapons online")

	var tail_only := _model("hawk", "practice")
	tail_only.apply_damage("tail", 1000.0)
	_check(not tail_only.is_destroyed(), "losing the tail alone is not fatal")


func _test_durability_and_armor() -> void:
	var normal := _model("lion", "standard")
	var hardcore := _model("lion", "hardcore")
	_check(is_equal_approx(hardcore.max_health["torso"], normal.max_health["torso"] * 0.6), "hardcore scales health by 0.6")
	var arcade := _model("lion", "arcade")
	_check(is_equal_approx(arcade.max_health["head"], normal.max_health["head"] * 1.5), "arcade scales health by 1.5")


func _test_effects() -> void:
	var m := _model("hawk", "practice")
	_check(m.lift_mult() == 1.0, "fresh hawk has full lift")
	m.apply_damage("wing_l", 500.0)
	_check(is_equal_approx(m.lift_mult(), 0.5), "one lost wing halves lift")
	_check(m.turn_mult() < 1.0, "a lost wing hurts turning")
	m.apply_damage("wing_r", 500.0)
	_check(m.lift_mult() < 0.5, "two lost wings cannot hold altitude")

	var joint := _model("hawk", "practice")
	joint.apply_damage("wing_joint_l", 500.0)
	_check(is_equal_approx(joint.lift_mult(), 0.7), "a wing joint loses some lift")
	_check(joint.is_crippled("wing_l"), "wing is crippled by its joint")


func _test_weapon_state() -> void:
	var limited := Ruleset.load_id("standard")
	var unlimited := Ruleset.load_id("practice")
	var cannon := WeaponState.new("gun_l", GameData.get_entry("weapons", "autocannon"))
	_check(cannon.ammo == 400, "autocannon starts with 400 rounds")
	_check(cannon.ready_to_fire() and cannon.has_ammo(limited), "autocannon is ready")
	cannon.consume(limited)
	_check(cannon.ammo == 399, "a shot spends one round")
	_check(not cannon.ready_to_fire(), "autocannon is on cooldown after firing")
	cannon.tick(1.0)
	_check(cannon.ready_to_fire(), "cooldown ends")
	cannon.consume(unlimited)
	_check(cannon.ammo == 399, "no ammo is spent when limits are off")

	var pod := WeaponState.new("gun_r", GameData.get_entry("weapons", "rocket_pod"))
	pod.ammo = 1
	pod.consume(limited)
	_check(pod.ammo == 0 and not pod.has_ammo(limited), "an empty weapon cannot fire")
	_check(pod.has_ammo(unlimited), "ammo limits off means it can always fire")

	var bite := WeaponState.new("jaw", GameData.get_entry("weapons", "jaw_bite"))
	_check(bite.is_melee() and bite.has_ammo(limited), "melee weapons never need ammo")
