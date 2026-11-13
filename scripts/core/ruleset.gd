class_name Ruleset
extends RefCounted
## A game mode, expressed as data: which systems are on and how they are tuned.
## Loaded from res://data/rulesets/<id>.json. Systems read these flags instead of
## being hard-wired, so a mode can switch any of them off.

## Every setting with its default. Unknown keys in a data file are rejected by validation.
const DEFAULTS := {
	"display_name": "Standard",
	"hud": true,
	"crosshair": true,
	"allow_third_person": true,
	"force_cockpit": false,
	"location_damage": true,
	"joint_criticals": true,
	"equipment_knockout": true,
	"ammo_limits": true,
	"friendly_fire": false,
	"durability_mult": 1.0,
	"match_time": 0.0,
}

var id: String = ""
var display_name: String
## Show the on-screen HUD.
var hud: bool
## Show the crosshair.
var crosshair: bool
## Allow switching to the third-person camera.
var allow_third_person: bool
## Cockpit view only. Overrides allow_third_person.
var force_cockpit: bool
## Damage is tracked per part. If off, all damage goes to one shared health pool.
var location_damage: bool
## Hits on joints cripple limbs. If off, joint hits count as ordinary damage to the parent part.
var joint_criticals: bool
## Weapons and equipment go offline when their part is crippled.
var equipment_knockout: bool
## Ranged weapons use limited ammo.
var ammo_limits: bool
## Team members can damage each other.
var friendly_fire: bool
## Multiplies every part's health.
var durability_mult: float
## Match length in seconds. 0 means untimed.
var match_time: float


func _init() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])


static func from_dict(data: Dictionary, ruleset_id: String = "") -> Ruleset:
	var ruleset := Ruleset.new()
	ruleset.id = ruleset_id
	for key in data:
		if DEFAULTS.has(key):
			ruleset.set(key, data[key])
	return ruleset


static func load_id(ruleset_id: String) -> Ruleset:
	return from_dict(GameData.get_entry("rulesets", ruleset_id), ruleset_id)


## True if the player may use the third-person camera under this ruleset.
func third_person_allowed() -> bool:
	return allow_third_person and not force_cockpit
