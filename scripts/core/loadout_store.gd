class_name LoadoutStore
extends RefCounted
## The player's saved loadouts, kept in user://loadouts.json. Every mech has four named
## loadout boxes and one of them is in use. Nothing here is a game rule: the server still
## checks whatever loadout is sent against the mech's carry capacity.

const SLOT_COUNT := 4
const NAME_LENGTH := 20

static var path: String = "user://loadouts.json"
static var _data: Dictionary = {}
static var _loaded: bool = false


## Forgets what was read, so the next call reads the file again (used by tests).
static func reset() -> void:
	_data = {}
	_loaded = false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for mech_id in parsed:
				_data[mech_id] = _normalize(parsed[mech_id])


## Turns stored (or missing) data into exactly four boxes of {name, loadout} and an active index.
static func _normalize(entry: Variant) -> Dictionary:
	var stored: Variant = entry.get("slots") if entry is Dictionary else null
	var slots: Array = []
	for i in SLOT_COUNT:
		var slot: Variant = stored[i] if stored is Array and i < stored.size() else null
		var name := "Loadout %d" % (i + 1)
		if slot is Dictionary:
			var given := str(slot.get("name", "")).strip_edges().left(NAME_LENGTH)
			if given != "":
				name = given
		slots.append({"name": name, "loadout": Loadout.complete(slot)})
	var active := clampi(int(entry.get("active", 0)) if entry is Dictionary else 0, 0, SLOT_COUNT - 1)
	return {"active": active, "slots": slots}


static func _mech(mech_id: String) -> Dictionary:
	_ensure()
	if not _data.has(mech_id):
		_data[mech_id] = _normalize(null)
	return _data[mech_id]


## The four boxes for a mech: [{name, loadout}, ...].
static func slots(mech_id: String) -> Array:
	return _mech(mech_id)["slots"]


static func active_index(mech_id: String) -> int:
	return int(_mech(mech_id)["active"])


static func set_active(mech_id: String, index: int) -> void:
	_mech(mech_id)["active"] = clampi(index, 0, SLOT_COUNT - 1)
	save()


static func save_slot(mech_id: String, index: int, slot_name: String, choice: Dictionary) -> void:
	var entry := _mech(mech_id)
	var cleaned := slot_name.strip_edges().left(NAME_LENGTH)
	if cleaned == "":
		cleaned = "Loadout %d" % (index + 1)
	entry["slots"][index] = {"name": cleaned, "loadout": Loadout.complete(choice)}
	save()


## The loadout in use for a mech, ready to send to the server.
static func active_loadout(mech_id: String) -> Dictionary:
	var entry := _mech(mech_id)
	return Loadout.sanitize(GameData.get_entry("mechs", mech_id), entry["slots"][entry["active"]]["loadout"])


static func active_name(mech_id: String) -> String:
	var entry := _mech(mech_id)
	return str(entry["slots"][entry["active"]]["name"])


## "Autocannon, Rocket Pod, Armor Plating, Sprinter" for a loadout.
static func summary(choice: Dictionary) -> String:
	var parts: Array[String] = []
	for slot in Loadout.SLOTS:
		parts.append(str(Loadout.item(slot, choice[slot]).get("name", choice[slot])))
	return ", ".join(parts)


static func save() -> void:
	_ensure()
	var out := {}
	for mech_id in _data:
		var entry: Dictionary = _data[mech_id]
		var slots_out: Array = []
		for slot in entry["slots"]:
			var row: Dictionary = slot["loadout"].duplicate()
			row["name"] = slot["name"]
			slots_out.append(row)
		out[mech_id] = {"active": entry["active"], "slots": slots_out}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(out, "\t"))
