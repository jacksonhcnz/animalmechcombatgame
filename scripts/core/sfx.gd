class_name Sfx
extends RefCounted
## Sound effects. Clips live in assets/audio/<name>.ogg and play on the "Effects" bus, so the
## Options volume sliders apply. Missing clips are ignored (and warned about once).

const DIR := "res://assets/audio/"
const MAX_DISTANCE := 260.0

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


## Plays a clip once at a spot in the world and frees the player afterwards.
static func play_at(parent: Node, name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var clip := stream(name)
	if clip == null or parent == null or not parent.is_inside_tree():
		return null
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
