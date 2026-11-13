class_name InputSetup
extends RefCounted
## Registers the game's input actions with default bindings for keyboard and mouse
## and for a gamepad. Gameplay code only ever asks about actions, never about keys,
## so bindings can be remapped later (and other devices added) without touching it.
##
## Mouse movement is handled by PlayerController (it is not an action).

const DEADZONE := 0.2


static func ensure_actions() -> void:
	for action in _defaults():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for event in _defaults()[action]:
			InputMap.action_add_event(action, event)


static func _defaults() -> Dictionary:
	return {
		"move_forward": [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"turn_left": [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"turn_right": [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"strafe_left": [_key(KEY_Q), _button(JOY_BUTTON_LEFT_SHOULDER)],
		"strafe_right": [_key(KEY_E), _button(JOY_BUTTON_RIGHT_SHOULDER)],
		"ascend": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
		"jump": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
		"descend": [_key(KEY_CTRL), _button(JOY_BUTTON_B)],
		"aim_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"aim_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"aim_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"aim_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"center_aim": [_key(KEY_Z), _button(JOY_BUTTON_RIGHT_STICK)],
		"fire_primary": [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"fire_secondary": [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"fire_melee": [_key(KEY_F), _button(JOY_BUTTON_X)],
		"toggle_view": [_key(KEY_C), _button(JOY_BUTTON_Y)],
	}


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
