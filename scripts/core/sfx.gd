class_name Sfx
extends RefCounted
## Sound effects. Clips live in assets/audio/<name>.ogg and play on the "Effects" bus, so the
## Options volume sliders apply. Missing clips are ignored (and warned about once).

const DIR := "res://assets/audio/"
const MAX_DISTANCE := 260.0

## How far a clip carries to a listener, in metres. Anything not listed carries DEFAULT_NOISE.
const NOISE: Dictionary = {
	"lion_step": 70.0, "raptor_step": 55.0, "elephant_step": 90.0, "wing_flap": 80.0,
	"machine_gun_shot": 130.0, "autocannon_shot": 150.0, "rocket_launch": 150.0, "grenade_launch": 110.0,
	"flak_shot": 130.0, "air_bomb_drop": 120.0, "claw_strike": 60.0, "talon_strike": 55.0, "jaw_bite": 60.0,
	"ion_blast": 260.0, "sniper_shot": 280.0, "sniper_breath": 12.0,
	"rocket_burst": 190.0, "grenade_burst": 170.0, "flak_pop": 110.0, "air_bomb_burst": 260.0, "mech_destroyed": 300.0,
}
const DEFAULT_NOISE := 100.0
## Sounds kept for the minimap, which reads each one once.
const EVENT_LIFETIME := 4.0

static var events: Array[Dictionary] = []
static var _next_event: int = 0
static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


static func stream(name: String) -> AudioStream:
	if name.is_empty():
		return null
	if not _cache.has(name):
		var path := DIR + name + ".ogg"
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
		if _cache[name] == null and not _warned.has(name):
			_warned[name] = true
			push_warning("Sfx: no clip %s" % path)
	return _cache[name]


## Notes that a sound was made at `pos` by `team` (-1 when unknown), for the minimap. `loudness`
## scales how far it carries.
static func note_event(name: String, pos: Vector3, team: int = -1, loudness: float = 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not events.is_empty() and now - float(events[0]["time"]) > EVENT_LIFETIME:
		events.pop_front()
	_next_event += 1
	events.append({"id": _next_event, "clip": name, "pos": pos, "team": team, "time": now,
			"range": float(NOISE.get(name, DEFAULT_NOISE)) * loudness})


## Plays a clip once at a spot in the world and frees the player afterwards. `loudness` (1 is normal)
## scales how far it carries on the minimap; `team` is who made it.
static func play_at(parent: Node, name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0,
		team: int = -1, loudness: float = 1.0) -> AudioStreamPlayer3D:
	var clip := stream(name)
	if clip == null or parent == null or not parent.is_inside_tree():
		return null
	note_event(name, pos, team, loudness)
	var player := make_player(clip, volume_db, pitch)
	parent.add_child(player)
	player.global_position = pos
	player.finished.connect(player.queue_free)
	player.play()
	return player


## A 3D player set up for effects; the caller adds it to the tree and plays it.
static func make_player(clip: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = clip
	player.bus = "Effects" if AudioServer.get_bus_index("Effects") != -1 else "Master"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = MAX_DISTANCE
	player.unit_size = 14.0
	return player
