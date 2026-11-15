class_name PauseMenu
extends CanvasLayer
## Esc opens this panel in a match or the test range: resume, or go back to the main menu.
## The game keeps running behind it (a networked match cannot pause).

signal leave_requested

var _panel: Control


func _ready() -> void:
	layer = 20
	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_button(box, "Resume", close)
	_button(box, "Main menu", func() -> void: leave_requested.emit())
	var help := Label.new()
	help.text = "Melee: F (gamepad X)   Jump: Space   View: C"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_panel.visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if is_open():
		close()
	else:
		open()
