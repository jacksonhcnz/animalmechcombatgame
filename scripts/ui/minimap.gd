class_name Minimap
extends Control
## A round radar in the corner of the screen. It does not show mechs: it shows sounds. Every sound
## the game plays (footsteps, shots, explosions) appears as a pulse where it came from, for as long
## as it can be heard. The top of the map is where the mech faces.

const RADIUS := 84.0
## Metres from the middle to the edge of the map. Louder sounds beyond this pin to the rim.
const MAP_RANGE := 150.0
const PULSE_TIME := 1.8
## A sound this close to the listener is their own, so it is not drawn.
const OWN_SOUND_RADIUS := 14.0

var mech: Mech
var _seen: int = 0
var _pulses: Array[Dictionary] = []


func _init() -> void:
	custom_minimum_size = Vector2.ONE * (RADIUS * 2.0 + 8.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Where a sound at `world` shows, in pixels from the middle of the map, for a listener at `from`
## facing `yaw`. Returns `{"offset": Vector2, "pinned": bool}`; pinned sounds are beyond MAP_RANGE
## and sit on the rim in the right direction.
static func project(from: Vector3, yaw: float, world: Vector3) -> Dictionary:
	var delta := world - from
	var flat := Vector2(delta.x, delta.z)
	# Rotate so the listener's forward (-z turned by yaw) points up the screen.
	var local := flat.rotated(yaw)
	var dist := local.length()
	if dist <= 0.001:
		return {"offset": Vector2.ZERO, "pinned": false}
	var scaled := minf(dist, MAP_RANGE) / MAP_RANGE * RADIUS
	return {"offset": local / dist * scaled, "pinned": dist > MAP_RANGE}


## Whether the listener can hear this sound, and it was not their own.
static func audible(event: Dictionary, from: Vector3, own_team: int) -> bool:
	var dist := Vector2(event["pos"].x - from.x, event["pos"].z - from.z).length()
	if dist > float(event["range"]):
		return false
	return not (int(event["team"]) == own_team and dist < OWN_SOUND_RADIUS)


func _process(_delta: float) -> void:
	if mech == null or not is_instance_valid(mech):
		return
	var now := Time.get_ticks_msec() / 1000.0
	for event in Sfx.events:
		if int(event["id"]) <= _seen:
			continue
		_seen = int(event["id"])
		if audible(event, mech.global_position, mech.team):
			_pulses.append(event)
	while not _pulses.is_empty() and now - float(_pulses[0]["time"]) > PULSE_TIME:
		_pulses.pop_front()
	queue_redraw()


func _draw() -> void:
	var middle := size * 0.5
	draw_circle(middle, RADIUS, Color(0.02, 0.05, 0.04, 0.55))
	for fraction in [0.5, 1.0]:
		draw_arc(middle, RADIUS * fraction, 0.0, TAU, 48, Color(0.45, 0.85, 0.6, 0.35), 1.5, true)
	draw_line(middle - Vector2(RADIUS, 0), middle + Vector2(RADIUS, 0), Color(0.45, 0.85, 0.6, 0.15), 1.0)
	draw_line(middle - Vector2(0, RADIUS), middle + Vector2(0, RADIUS), Color(0.45, 0.85, 0.6, 0.15), 1.0)
	if mech == null or not is_instance_valid(mech):
		return
	var now := Time.get_ticks_msec() / 1000.0
	for pulse in _pulses:
		var age := (now - float(pulse["time"])) / PULSE_TIME
		if age < 0.0 or age > 1.0:
			continue
		var spot := project(mech.global_position, mech.rotation.y, pulse["pos"])
		var colour := _colour_for(int(pulse["team"]))
		colour.a = (1.0 - age) * (0.55 if spot["pinned"] else 1.0)
		var at: Vector2 = middle + spot["offset"]
		# Louder sounds make bigger blips.
		var weight := clampf(float(pulse["range"]) / 150.0, 0.5, 2.0)
		draw_circle(at, 3.0 * weight, colour)
		draw_arc(at, (3.0 + age * 14.0) * weight, 0.0, TAU, 20, colour, 1.5, true)
	# The listener, pointing up.
	draw_colored_polygon(PackedVector2Array([middle + Vector2(0, -7), middle + Vector2(5, 5), middle + Vector2(-5, 5)]), Color(1, 1, 1, 0.9))


func _colour_for(team: int) -> Color:
	if team == mech.team:
		return Color("#6ad4ff")
	if team < 0:
		return Color("#cfd6dc")
	return Color("#ff5a4a")
