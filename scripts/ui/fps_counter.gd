class_name FpsCounter
extends CanvasLayer
## A small frames-per-second readout in the top-left corner, shown when the Visuals option is on.
## One lives on the root of the scene tree so it stays across menus and matches.

var _label: Label
var _elapsed := 0.0


func _init() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(10, 8)
	_label.add_theme_font_override("font", UiKit.mono_font())
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", UiKit.LIME)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())
