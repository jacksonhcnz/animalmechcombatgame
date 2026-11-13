class_name NetProtocol
extends RefCounted
## Numbers that both ends of a connection must agree on, and helpers for the input message.
##
## The protocol version changes whenever the messages change. The balance version
## (data/balance.json) must match too, so every server plays by the same numbers.

const VERSION := 1
const DEFAULT_PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 8

## How often the server sends the state of every mech.
const SNAPSHOT_RATE := 20.0
## Clients show other mechs this far in the past, so they can blend between two snapshots.
const INTERP_DELAY := 0.1

const COUNTDOWN_TIME := 3.0
const RESPAWN_TIME := 4.0
const RESULT_TIME := 12.0
## Used when the ruleset has no match time of its own.
const DEFAULT_MATCH_TIME := 300.0

const FLAG_JUMP := 1
const FLAG_FIRE_PRIMARY := 2
const FLAG_FIRE_SECONDARY := 4
const FLAG_FIRE_MELEE := 8


## Packs one frame of a pilot's controls into a small array for the network.
static func pack_input(controls: MechControls, aim_yaw: float, aim_pitch: float) -> Array:
	var flags := 0
	if controls.jump:
		flags |= FLAG_JUMP
	if controls.fire_primary:
		flags |= FLAG_FIRE_PRIMARY
	if controls.fire_secondary:
		flags |= FLAG_FIRE_SECONDARY
	if controls.fire_melee:
		flags |= FLAG_FIRE_MELEE
	return [controls.throttle, controls.strafe, controls.turn, controls.vertical, flags, aim_yaw, aim_pitch]


## Applies a packed input to a mech's controls. Returns false if the message is malformed.
## Values are clamped, so a modified client cannot ask for more than full stick.
static func apply_input(controls: MechControls, data: Variant) -> bool:
	if not data is Array or data.size() != 7:
		return false
	for value in data:
		if not (value is float or value is int):
			return false
		if is_nan(float(value)) or is_inf(float(value)):
			return false
	controls.throttle = clampf(float(data[0]), -1.0, 1.0)
	controls.strafe = clampf(float(data[1]), -1.0, 1.0)
	controls.turn = clampf(float(data[2]), -1.0, 1.0)
	controls.vertical = clampf(float(data[3]), -1.0, 1.0)
	var flags := int(data[4])
	controls.jump = flags & FLAG_JUMP != 0
	controls.fire_primary = flags & FLAG_FIRE_PRIMARY != 0
	controls.fire_secondary = flags & FLAG_FIRE_SECONDARY != 0
	controls.fire_melee = flags & FLAG_FIRE_MELEE != 0
	controls.aim_yaw_target = float(data[5])
	controls.aim_pitch_target = float(data[6])
	return true
