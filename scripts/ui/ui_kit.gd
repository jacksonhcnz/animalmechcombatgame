class_name UiKit
extends RefCounted
## The look shared by the menus: a dark console with lime accents, condensed headings and small
## monospaced labels. Fonts come from the player's system (Barlow Condensed if installed, else a
## condensed face the system has), so no font files ship with the game.

const BG := Color("0a0e10")
const PANEL := Color("131a1c")
const INNER := Color("0d1315")
const BORDER := Color("273134")
const LIME := Color("dcf26b")
const LIME_SOFT := Color("232c13")
const TEXT := Color("f2f2e8")
const DIM := Color("8c979a")

static var _heading_font: SystemFont
static var _mono_font: SystemFont


static func heading_font() -> Font:
	if _heading_font == null:
		_heading_font = SystemFont.new()
		_heading_font.font_names = PackedStringArray(["Barlow Condensed", "Bahnschrift SemiCondensed", "Bahnschrift", "Arial Narrow", "Roboto Condensed", "Oswald", "DejaVu Sans Condensed", "sans-serif"])
		_heading_font.font_weight = 600
	return _heading_font


static func mono_font() -> Font:
	if _mono_font == null:
		_mono_font = SystemFont.new()
		_mono_font.font_names = PackedStringArray(["JetBrains Mono", "IBM Plex Mono", "Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	return _mono_font


## Plain body text.
static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A small upper-case monospaced caption.
static func mono(text: String, color: Color = LIME, size: int = 11) -> Label:
	var l := label(text.to_upper(), size, color)
	l.add_theme_font_override("font", mono_font())
	return l


## A big condensed upper-case title.
static func heading(text: String, size: int = 34, color: Color = TEXT) -> Label:
	var l := FitLabel.new()
	l.text = text.to_upper()
	l.base_size = size
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", heading_font())
	l.clip_text = true  # never pushes the layout wider than the window; the font shrinks to fit
	return l


static func box(fill: Color, border: Color = BORDER, pad: int = 0, radius: int = 4, border_width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func panel(fill: Color = PANEL, border: Color = BORDER, pad: int = 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, border, pad))
	return p


static func vbox(parent: Node, gap: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	parent.add_child(v)
	return v


static func hbox(parent: Node, gap: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	parent.add_child(h)
	return h


static func spacer(parent: Node, height: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	if height == 0:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


static func rule(parent: Node) -> HSeparator:
	var h := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	h.add_theme_stylebox_override("separator", line)
	parent.add_child(h)
	return h


static func _button_styles(b: Button, fill: Color, hover: Color, border: Color, text_color: Color) -> void:
	b.add_theme_stylebox_override("normal", box(fill, border, 12))
	b.add_theme_stylebox_override("hover", box(hover, border, 12))
	b.add_theme_stylebox_override("pressed", box(hover, border, 12))
	b.add_theme_stylebox_override("focus", box(fill, LIME, 12))
	b.add_theme_stylebox_override("disabled", box(fill.darkened(0.3), border, 12))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, text_color)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_font_size_override("font_size", 15)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 44)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func _arrow(b: Button, color: Color) -> void:
	var a := label("→", 18, color)
	a.set_anchors_preset(Control.PRESET_FULL_RECT)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	a.offset_right = -14
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(a)


## The bright lime call to action, with an arrow at the right.
static func primary_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_button_styles(b, LIME, LIME.lightened(0.18), LIME, Color("10150a"))
	_arrow(b, Color("10150a"))
	b.pressed.connect(action)
	return b


## The quieter outlined button, with an arrow at the right.
static func outline_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_button_styles(b, INNER, PANEL.lightened(0.08), BORDER.lightened(0.25), TEXT)
	_arrow(b, LIME)
	b.pressed.connect(action)
	return b


## A flat text button (Edit, back links).
static func link_button(text: String, color: Color, action: Callable, mono_style: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_font_size_override("font_size", 12 if mono_style else 14)
	if mono_style:
		b.add_theme_font_override("font", mono_font())
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(action)
	return b


## Dark fields: text boxes and drop-downs.
static func style_input(c: Control) -> void:
	for key in ["normal", "hover", "pressed", "focus", "read_only"]:
		if c is LineEdit and key == "pressed":
			continue
		c.add_theme_stylebox_override(key, box(INNER, LIME if key == "focus" else BORDER.lightened(0.15), 12))
	c.add_theme_color_override("font_color", TEXT)
	c.custom_minimum_size = Vector2(0, 44)
	if c is OptionButton:
		(c as OptionButton).alignment = HORIZONTAL_ALIGNMENT_LEFT
		c.add_theme_color_override("font_hover_color", TEXT)
		c.add_theme_color_override("font_pressed_color", TEXT)
		c.add_theme_color_override("font_focus_color", TEXT)
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func progress(value: float, maximum: float) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = maxf(maximum, 1.0)
	p.value = minf(value, maximum)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 6)
	p.add_theme_stylebox_override("background", box(Color("232c2f"), Color("232c2f"), 0, 3, 0))
	p.add_theme_stylebox_override("fill", box(LIME if value <= maximum else Color("ff7a5c"), LIME, 0, 3, 0))
	return p


static func background(parent: Control) -> void:
	var back := ColorRect.new()
	back.color = BG
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(back)


## Full-screen page: dark background and a scrolling column with the shared margins. Returns the
## column to add content to.
const PAGE_SIZE := Vector2(1280, 820)


static func page(parent: Control) -> VBoxContainer:
	background(parent)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.clip_contents = true
	parent.add_child(holder)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	holder.add_child(margin)
	# The layout is drawn for a window of at least PAGE_SIZE: smaller windows shrink it to fit.
	var fit := func() -> void:
		var factor := minf(1.0, minf(holder.size.x / PAGE_SIZE.x, holder.size.y / PAGE_SIZE.y))
		factor = maxf(factor, 0.1)
		margin.scale = Vector2(factor, factor)
		margin.size = holder.size / factor
	holder.resized.connect(fit)
	fit.call_deferred()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	return column


## The top bar: game name at the left, the pilot's name at the right. Returns the name field.
static func header(column: VBoxContainer) -> LineEdit:
	var top := hbox(column, 0)
	var title := vbox(top, 4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(mono("A M C   /   Combat Systems"))
	title.add_child(heading("Animal Mech Combat", 22))
	var pilot := panel(PANEL, BORDER, 12)
	pilot.custom_minimum_size = Vector2(220, 0)
	top.add_child(pilot)
	var inner := vbox(pilot, 2)
	inner.add_child(mono("Pilot name", DIM, 10))
	var row := hbox(inner, 4)
	var edit := LineEdit.new()
	edit.text = LaunchConfig.player_name
	edit.max_length = 20
	edit.flat = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_color_override("font_color", TEXT)
	edit.add_theme_color_override("caret_color", LIME)
	edit.add_theme_font_size_override("font_size", 16)
	edit.text_changed.connect(func(t: String) -> void:
		LaunchConfig.player_name = t.strip_edges() if t.strip_edges() != "" else "Pilot")
	row.add_child(edit)
	row.add_child(link_button("Edit", LIME, func() -> void:
		edit.grab_focus()
		edit.select_all()))
	rule(column)
	return edit


## A mech id as the name shown to the player.
static func mech_name(id: String) -> String:
	return id.capitalize()


## A title whose font shrinks until the text fits the width it is given.
class FitLabel:
	extends Label

	var base_size: int = 34


	func _init() -> void:
		resized.connect(_fit)


	func _fit() -> void:
		var font := get_theme_font("font")
		var fitted := base_size
		while fitted > 14 and size.x > 1.0 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > size.x:
			fitted -= 2
		if get_theme_font_size("font_size") != fitted:
			add_theme_font_size_override("font_size", fitted)


## An on/off switch: a pill with a knob, and "On" / "Off" beside it.
class Toggle:
	extends HBoxContainer

	signal toggled(on: bool)
	var on: bool = false
	var _caption: Label
	var _pill: Control


	func _init(start_on: bool = false) -> void:
		on = start_on
		add_theme_constant_override("separation", 12)
		_caption = UiKit.mono("", UiKit.DIM, 11)
		_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_caption)
		_pill = Control.new()
		_pill.custom_minimum_size = Vector2(48, 26)
		_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_pill.draw.connect(_draw_pill)
		_pill.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				set_on(not on, true))
		add_child(_pill)
		_refresh()


	func set_on(value: bool, emit: bool = false) -> void:
		on = value
		_refresh()
		if emit:
			toggled.emit(on)


	func _refresh() -> void:
		_caption.text = "ON" if on else "OFF"
		_pill.queue_redraw()


	func _draw_pill() -> void:
		var h := _pill.size.y
		var track := StyleBoxFlat.new()
		track.bg_color = UiKit.LIME if on else Color("39454a")
		track.set_corner_radius_all(int(h / 2.0))
		_pill.draw_style_box(track, Rect2(Vector2.ZERO, _pill.size))
		var radius := (h - 6.0) / 2.0
		var centre_x := _pill.size.x - h / 2.0 if on else h / 2.0
		_pill.draw_circle(Vector2(centre_x, h / 2.0), radius, Color("10150a") if on else Color("c9d1d3"))


## A slider with the lime fill from the left and a small bar for a handle, plus a value label.
static func slider(value: float, low: float, high: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", box(Color("2b3639"), Color("2b3639"), 0, 2, 0))
	s.add_theme_stylebox_override("grabber_area", box(LIME, LIME, 0, 2, 0))
	s.add_theme_stylebox_override("grabber_area_highlight", box(LIME, LIME, 0, 2, 0))
	var image := Image.create(8, 20, false, Image.FORMAT_RGBA8)
	image.fill(LIME)
	var texture := ImageTexture.create_from_image(image)
	s.add_theme_icon_override("grabber", texture)
	s.add_theme_icon_override("grabber_highlight", texture)
	s.add_theme_icon_override("grabber_disabled", texture)
	return s
