class_name GameSettings
extends RefCounted
## Player preferences, saved to user://settings.cfg.
## These are personal comfort options, not game rules, so rulesets never change them.

const PATH := "user://settings.cfg"
const HEAD_BOB_STEP := 0.1

## How much of the mech's walking bob the cockpit camera follows, from 0 (perfectly
## steady) to 1 (the full body bob). Default is small.
static var head_bob: float = 0.4


## Sets the head bob, clamped to 0..1 and rounded to the nearest 5 per cent.
static func set_head_bob(value: float) -> void:
	head_bob = snappedf(clampf(value, 0.0, 1.0), 0.05)


static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	set_head_bob(float(config.get_value("view", "head_bob", head_bob)))
	# A name given on the command line wins over the saved one.
	var saved := str(config.get_value("pilot", "name", "")).strip_edges().left(20)
	if saved != "" and not LaunchConfig.name_from_args:
		LaunchConfig.player_name = saved


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("view", "head_bob", head_bob)
	config.set_value("pilot", "name", LaunchConfig.player_name)
	config.save(PATH)
