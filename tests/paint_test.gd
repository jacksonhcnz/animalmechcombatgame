extends SceneTree
## Team matches paint mechs red and blue; elsewhere a mech wears its pilot's chosen colour.

var _failed := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_go()


func _go() -> void:
	var rules := Ruleset.load_id("standard")
	var plain := Mech.create("lion", rules)
	var green := Mech.create("lion", rules, {}, "#3fae6a")
	var junk := Mech.create("lion", rules, {}, "not a colour")
	_check(plain.def["palette"]["primary"] == GameData.get_entry("mechs", "lion")["palette"]["primary"], "no paint keeps the mech's own colour")
	_check(green.def["palette"]["primary"] == "#3fae6a", "paint replaces the body colour")
	_check(Color.html(green.def["palette"]["dark"]).v < Color.html("#3fae6a").v, "shaded tone is darker")
	_check(junk.def["palette"]["primary"] == plain.def["palette"]["primary"], "an invalid colour is ignored")
	_check(GameData.get_entry("mechs", "lion")["palette"]["primary"] == "#e8962a", "shared mech data is not changed")

	var round_rules := Ruleset.load_id("practice_match")
	var session := NetSession.new()
	root.add_child(session)
	session.rules = round_rules
	var slot := NetSession.Slot.new()
	slot.team = 1
	slot.paint = "#3fae6a"
	_check(session._paint_for(slot) == LoadoutStore.TEAM_PAINT[1], "team 1 is blue in a round match")
	slot.team = 2
	_check(session._paint_for(slot) == LoadoutStore.TEAM_PAINT[2], "team 2 is red in a round match")
	session.rules = rules
	_check(session._paint_for(slot) == "#3fae6a", "individual match uses the pilot's colour")
	slot.paint = "junk"
	_check(session._paint_for(slot) == "", "bad pilot colour falls back to default")

	LoadoutStore.paint_path = "user://paint_test.txt"
	LoadoutStore.reset()
	LoadoutStore.set_paint("#8e5bd6")
	LoadoutStore.reset()
	_check(LoadoutStore.paint() == "#8e5bd6", "colour is saved")
	LoadoutStore.set_paint("")
	print("paint_test: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)
