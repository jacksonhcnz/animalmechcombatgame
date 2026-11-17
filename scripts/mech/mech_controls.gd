class_name MechControls
extends RefCounted
## What a pilot (a player, or later an AI) wants the mech to do this frame.
## Axes run from -1 to 1. Aim deltas are in radians and are consumed by the mech.

var throttle: float = 0.0
var strafe: float = 0.0
var turn: float = 0.0
var vertical: float = 0.0
var jump: bool = false
var sprint: bool = false
## Where the pilot is aiming, as absolute angles. NAN means "use the aim deltas instead".
## A server uses these, because a lost packet must not lose a turn.
var aim_yaw_target: float = NAN
var aim_pitch_target: float = 0.0
var aim_yaw_delta: float = 0.0
var aim_pitch_delta: float = 0.0
var center_aim: bool = false
var fire_primary: bool = false
var fire_secondary: bool = false
var fire_melee: bool = false
var fire_bomb: bool = false
## The "use equipment" key (F): switches the raptor's sniper scope on and off.
var use_equipment: bool = false
## The aim sent with the controls is a world heading, not one relative to the body (set while the
## pilot is turning round for the sniper, so the aim stays put while the body swings).
var aim_world: bool = false


## True when the pilot is asking to move or turn the legs.
func is_idle_movement() -> bool:
	return throttle == 0.0 and strafe == 0.0 and turn == 0.0


func clear() -> void:
	throttle = 0.0
	strafe = 0.0
	turn = 0.0
	vertical = 0.0
	jump = false
	sprint = false
	aim_yaw_delta = 0.0
	aim_pitch_delta = 0.0
	center_aim = false
	fire_primary = false
	fire_secondary = false
	fire_melee = false
	fire_bomb = false
	use_equipment = false
	aim_world = false
