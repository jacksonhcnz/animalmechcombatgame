class_name ScopeOverlay
extends Control
## The sniper scope: the screen goes black outside a round lens, with fine cross hairs and the
## zoom in the corner. Drawn only while the mech is in sniper mode.

var zoom: float = 1.0
var aligned: bool = false
var ammo_text: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	var size_now := get_viewport_rect().size
	var centre := size_now * 0.5
	var radius := minf(size_now.x, size_now.y) * 0.46
	# Black outside the lens: a ring of quads from the lens edge out past the screen edge.
	var edge := Color(0, 0, 0, 1)
	var far_radius := size_now.length()
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		draw_colored_polygon(PackedVector2Array([centre + d0 * radius, centre + d1 * radius, centre + d1 * far_radius, centre + d0 * far_radius]), edge)
	var ring := PackedVector2Array()
	for i in 97:
		var angle := TAU * float(i) / 96.0
		ring.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	var line := Color(0.05, 0.05, 0.05, 0.9)
	draw_polyline(ring, line, 3.0)
	draw_line(centre + Vector2(-radius, 0), centre + Vector2(-14, 0), line, 2.0)
	draw_line(centre + Vector2(14, 0), centre + Vector2(radius, 0), line, 2.0)
	draw_line(centre + Vector2(0, -radius), centre + Vector2(0, -14), line, 2.0)
	draw_line(centre + Vector2(0, 14), centre + Vector2(0, radius), line, 2.0)
	var dot := Color(1.0, 0.25, 0.2) if aligned else Color(1.0, 0.75, 0.2)
	draw_circle(centre, 2.5, dot)
	var font := ThemeDB.fallback_font
	draw_string(font, centre + Vector2(radius * 0.55, radius * 0.9), "x%.1f" % zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_string(font, centre + Vector2(radius * 0.55, radius * 0.9 + 28.0), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, centre + Vector2(-radius * 0.9, radius * 0.9), "READY" if aligned else "TURNING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, dot)


func show_scope(on: bool, new_zoom: float, is_aligned: bool, ammo: String) -> void:
	if on != visible or not is_equal_approx(new_zoom, zoom) or is_aligned != aligned or ammo != ammo_text:
		visible = on
		zoom = new_zoom
		aligned = is_aligned
		ammo_text = ammo
		queue_redraw()
