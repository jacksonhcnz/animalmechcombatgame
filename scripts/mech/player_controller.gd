class_name PlayerController
extends Node
## Turns keyboard, mouse and gamepad input into MechControls for one mech.
## The mouse (and the gamepad's right stick) aims the head and weapons.
## A, D and the left stick's sideways axis turn the legs.

@export var mouse_sensitivity: float = 0.0025
@export var stick_aim_rate: float = 2.2
## When false the pilot gives no input (for example after the match ends).
var enabled: bool = true
var mech: Mech

var _mouse_yaw: float = 0.0
var _mouse_pitch: float = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Moving the mouse right looks right (a negative yaw); moving it up looks up.
		_mouse_yaw -= event.relative.x * mouse_sensitivity
		_mouse_pitch -= event.relative.y * mouse_sensitivity
	elif event.is_action_pressed("toggle_view") and mech != null and enabled:
		mech.toggle_view()


func _physics_process(delta: float) -> void:
	if mech == null or not is_instance_valid(mech):
		return
	var c := mech.controls
	if not enabled or mech.is_dead():
		c.clear()
		_mouse_yaw = 0.0
		_mouse_pitch = 0.0
		return
	c.throttle = Input.get_axis("move_back", "move_forward")
	c.turn = Input.get_axis("turn_left", "turn_right")
	c.strafe = Input.get_axis("strafe_left", "strafe_right")
	c.vertical = Input.get_axis("descend", "ascend")
	c.aim_yaw_delta += _mouse_yaw - Input.get_axis("aim_left", "aim_right") * stick_aim_rate * delta
	c.aim_pitch_delta += _mouse_pitch + Input.get_axis("aim_down", "aim_up") * stick_aim_rate * delta
	_mouse_yaw = 0.0
	_mouse_pitch = 0.0
	if Input.is_action_just_pressed("center_aim"):
		c.center_aim = true
	c.fire_primary = Input.is_action_pressed("fire_primary")
	c.fire_secondary = Input.is_action_pressed("fire_secondary")
	c.fire_melee = Input.is_action_pressed("fire_melee")
