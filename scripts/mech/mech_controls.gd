class_name MechControls
extends RefCounted
## What a pilot (a player, or later an AI) wants the mech to do this frame.
## Axes run from -1 to 1. Aim deltas are in radians and are consumed by the mech.

var throttle: float = 0.0
var strafe: float = 0.0
var turn: float = 0.0
var vertical: float = 0.0
var jump: bool = false
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


func clear() -> void:
	throttle = 0.0
	strafe = 0.0
	turn = 0.0
	vertical = 0.0
	jump = false
	aim_yaw_delta = 0.0
	aim_pitch_delta = 0.0
	center_aim = false
	fire_primary = false
	fire_secondary = false
	fire_melee = false
