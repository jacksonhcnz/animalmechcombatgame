class_name NetSession
extends Node
## One multiplayer session. The same script runs on every machine:
##
## - On a server (dedicated, or a player hosting) it owns the real mechs. It reads the
##   pilots' inputs, runs the physics and the shooting, decides every hit and runs a timed
##   match with respawns and scores. Clients cannot decide any of that.
## - On a client it holds display copies of the mechs. It sends the local pilot's inputs,
##   moves the copies from the server's snapshots (blended between two snapshots, 0.1 s in
##   the past) and applies the damage events the server reports.
##
## There is no client-side prediction yet: the local mech also moves by snapshot. That is the
## first stage of the netcode (see the design notes); prediction and lag compensation come later.
##
## All remote calls live here, because both ends must have the same node at the same path
## with the same remote calls.

signal joined
signal rejected(reason: String)
signal disconnected(reason: String)
signal match_changed

enum Phase { WAITING, COUNTDOWN, ACTIVE, FINISHED }

## One connected pilot, on the server.
class Slot extends RefCounted:
	var peer: int = 0
	var pilot_name: String = ""
	var mech_id: String = ""
	var team: int = 1
	var spawn_index: int = 0
	var mech: Mech
	var kills: int = 0
	var deaths: int = 0
	var respawn_left: float = -1.0
	var is_local: bool = false

var is_server: bool = false
var rules: Ruleset
var server_name: String = ""
var max_players: int = 2
var port: int = NetProtocol.DEFAULT_PORT
var mechs_root: Node3D
var hud: Hud
var controller: PlayerController
var phase: Phase = Phase.WAITING
var time_left: float = 0.0
## [[peer, name, kills, deaths], ...]
var scores: Array = []
var result_text: String = ""
var local_mech: Mech
var my_id: int = 0
var connected: bool = false

var _slots: Dictionary = {}
var _phase_left: float = 0.0
var _snapshot_timer: float = 0.0
var _clock: float = 0.0
var _next_spawn_index: int = 0
var _responder: LanDiscovery.Responder
# Client side.
var _render_time: float = 0.0
var _have_clock: bool = false
var _display_mechs: Dictionary = {}
var _buffers: Dictionary = {}
var _pilot_name: String = ""
var _mech_choice: String = ""
## Tests only: pretend to have a different balance version.
var test_balance: int = -1


# ---------------------------------------------------------------- starting

## Starts a server. With `local_player` (a dictionary with "name" and "mech") the machine
## also plays, as a listen server; without it the server is dedicated.
## Returns an Error code.
func start_server(port: int, ruleset_id: String, name_text: String, players: int, local_player: Dictionary = {}) -> int:
	is_server = true
	self.port = port
	server_name = name_text
	max_players = clampi(players, 2, NetProtocol.MAX_PLAYERS)
	if GameData.get_entry("rulesets", ruleset_id).is_empty():
		push_error("Unknown ruleset '%s'" % ruleset_id)
		return ERR_DOES_NOT_EXIST
	rules = Ruleset.load_id(ruleset_id)

	var peer := ENetMultiplayerPeer.new()
	var clients := max_players - (1 if not local_player.is_empty() else 0)
	var error := peer.create_server(port, clients)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_left)

	_responder = LanDiscovery.Responder.new()
	_responder.info_provider = _discovery_info
	add_child(_responder)
	_responder.start()

	if not local_player.is_empty():
		my_id = 1
		var slot := _add_slot(1, str(local_player["name"]), str(local_player["mech"]))
		slot.is_local = true
		_spawn_mech(slot, slot.spawn_index)
	connected = true
	_set_phase(Phase.WAITING)
	return OK


## Starts a client and connects. The result arrives as the `joined`, `rejected` or
## `disconnected` signal. Returns an Error code for an immediate failure.
func start_client(address: String, port: int, pilot_name: String, mech_id: String) -> int:
	is_server = false
	_pilot_name = pilot_name
	_mech_choice = mech_id
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: disconnected.emit("Could not connect to %s:%d" % [address, port]))
	multiplayer.server_disconnected.connect(func() -> void:
		connected = false
		disconnected.emit("Lost the connection to the server"))
	return OK


func player_count() -> int:
	return _slots.size()


## Stops networking. The session node should be freed afterwards.
func stop() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	connected = false


func _discovery_info() -> Dictionary:
	return {
		"name": server_name,
		"map": "Test arena",
		"mode": rules.display_name,
		"players": _slots.size(),
		"max_players": max_players,
		"balance_version": GameData.balance_version(),
		"protocol": NetProtocol.VERSION,
		"port": port,
	}


# ---------------------------------------------------------------- per-frame

func _physics_process(delta: float) -> void:
	if is_server:
		_server_tick(delta)
	elif connected:
		_client_tick(delta)
	_update_hud(delta)


func _controls_open() -> bool:
	return phase == Phase.WAITING or phase == Phase.ACTIVE


# ================================================================ SERVER

func _server_tick(delta: float) -> void:
	_clock += delta
	match phase:
		Phase.WAITING:
			if _slots.size() >= 2:
				_set_phase(Phase.COUNTDOWN)
		Phase.COUNTDOWN:
			_phase_left -= delta
			if _slots.size() < 2:
				_set_phase(Phase.WAITING)
			elif _phase_left <= 0.0:
				_set_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			time_left -= delta
			if _slots.size() < 2:
				_set_phase(Phase.WAITING)
			elif time_left <= 0.0:
				_set_phase(Phase.FINISHED)
		Phase.FINISHED:
			_phase_left -= delta
			if _phase_left <= 0.0:
				_set_phase(Phase.COUNTDOWN if _slots.size() >= 2 else Phase.WAITING)

	if phase == Phase.WAITING or phase == Phase.ACTIVE:
		for slot: Slot in _slots.values():
			if slot.respawn_left >= 0.0:
				slot.respawn_left -= delta
				if slot.respawn_left < 0.0:
					_spawn_mech(slot, _safest_spawn(slot))

	# Only send snapshots when someone is listening.
	_snapshot_timer += delta
	if _snapshot_timer >= 1.0 / NetProtocol.SNAPSHOT_RATE:
		_snapshot_timer = 0.0
		if not multiplayer.get_peers().is_empty():
			_send_snapshots()


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	match phase:
		Phase.WAITING:
			_reset_scores()
			time_left = 0.0
			result_text = ""
		Phase.COUNTDOWN:
			_reset_scores()
			result_text = ""
			_phase_left = NetProtocol.COUNTDOWN_TIME
			for slot: Slot in _slots.values():
				_spawn_mech(slot, slot.spawn_index)
		Phase.ACTIVE:
			time_left = rules.match_time if rules.match_time > 0.0 else NetProtocol.DEFAULT_MATCH_TIME
		Phase.FINISHED:
			result_text = _work_out_result()
			_phase_left = NetProtocol.RESULT_TIME
	for slot: Slot in _slots.values():
		if not _controls_open() and slot.mech != null:
			slot.mech.controls.clear()
	_refresh_local_controller()
	_broadcast_match()


func _reset_scores() -> void:
	for slot: Slot in _slots.values():
		slot.kills = 0
		slot.deaths = 0


func _work_out_result() -> String:
	var best := -1
	var leaders: Array[Slot] = []
	for slot: Slot in _slots.values():
		if slot.kills > best:
			best = slot.kills
			leaders = [slot]
		elif slot.kills == best:
			leaders.append(slot)
	if leaders.size() == 1:
		return "%s wins" % leaders[0].pilot_name
	return "Draw"


func _add_slot(peer: int, pilot_name: String, mech_id: String) -> Slot:
	var slot := Slot.new()
	slot.peer = peer
	slot.pilot_name = pilot_name
	slot.mech_id = mech_id
	slot.spawn_index = _next_spawn_index
	_next_spawn_index += 1
	slot.team = peer
	_slots[peer] = slot
	return slot


func _safest_spawn(slot: Slot) -> int:
	var best_index := slot.spawn_index
	var best_distance := -1.0
	for index in Arena.MATCH_SPAWNS:
		var spot := Arena.spawn_transform(index).origin
		var nearest := 1.0e9
		for other: Slot in _slots.values():
			if other != slot and other.mech != null and is_instance_valid(other.mech) and not other.mech.is_dead():
				nearest = minf(nearest, spot.distance_to(other.mech.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best_index = index
	return best_index


## Creates (or re-creates) the real mech for a pilot at a spawn point.
func _spawn_mech(slot: Slot, spawn_index: int) -> void:
	_remove_mech(slot)
	var mech := Mech.create(slot.mech_id, rules)
	mech.team = slot.team
	mech.altitude_limit = Arena.MATCH_ALTITUDE_LIMIT
	mechs_root.add_child(mech)
	var spot := Arena.spawn_transform(spawn_index)
	mech.global_transform = Transform3D(spot.basis, spot.origin + Vector3(0.0, mech.spawn_height(), 0.0))
	slot.mech = mech
	slot.respawn_left = -1.0
	mech.destroyed.connect(func(dead: Mech) -> void: _on_mech_destroyed(slot, dead))
	mech.hit_taken.connect(func(result: Dictionary) -> void: _on_mech_hit(slot, result))
	mech.fired.connect(func(from: Vector3, to: Vector3, color: Color) -> void:
		if not multiplayer.get_peers().is_empty():
			s_tracer.rpc(from, to, color.to_html(false)))
	if slot.is_local:
		mech.make_player()
		local_mech = mech
		controller.mech = mech
		hud.bind(mech, rules)
		_refresh_local_controller()
	if not _controls_open():
		mech.controls.clear()
	if not multiplayer.get_peers().is_empty():
		s_spawn.rpc(_spawn_info(slot))


func _remove_mech(slot: Slot) -> void:
	if slot.mech == null:
		return
	if is_instance_valid(slot.mech):
		slot.mech.queue_free()
	slot.mech = null
	if not multiplayer.get_peers().is_empty():
		s_despawn.rpc(slot.peer)


func _spawn_info(slot: Slot) -> Dictionary:
	var mech := slot.mech
	return {
		"peer": slot.peer,
		"name": slot.pilot_name,
		"mech_id": slot.mech_id,
		"team": slot.team,
		"pos": mech.global_position,
		"yaw": mech.rotation.y,
		"state": mech.damage.export_state(),
	}


func _on_mech_destroyed(slot: Slot, dead: Mech) -> void:
	slot.respawn_left = NetProtocol.RESPAWN_TIME
	if phase == Phase.ACTIVE:
		slot.deaths += 1
		var killer := dead.last_attacker
		for other: Slot in _slots.values():
			if other != slot and other.mech == killer and killer != null:
				other.kills += 1
		_broadcast_match()
	if slot.is_local:
		_refresh_local_controller()


func _on_mech_hit(slot: Slot, result: Dictionary) -> void:
	if not multiplayer.get_peers().is_empty():
		s_hit.rpc(slot.peer, str(result["part"]), float(result["raw"]))


func _on_peer_left(peer: int) -> void:
	if not _slots.has(peer):
		return
	var slot: Slot = _slots[peer]
	_remove_mech(slot)
	_slots.erase(peer)
	_broadcast_match()


func _broadcast_match() -> void:
	_apply_match(_match_state())
	if not multiplayer.get_peers().is_empty():
		s_match.rpc(_match_state())


func _match_state() -> Dictionary:
	var table: Array = []
	for slot: Slot in _slots.values():
		table.append([slot.peer, slot.pilot_name, slot.kills, slot.deaths])
	return {"phase": int(phase), "time_left": time_left, "scores": table, "result": result_text}


func _send_snapshots() -> void:
	var entries: Array = []
	for slot: Slot in _slots.values():
		var mech := slot.mech
		if mech == null or not is_instance_valid(mech):
			continue
		entries.append([slot.peer, mech.global_position, mech.rotation.y, mech.velocity, mech.is_on_floor(), mech.aim_yaw, mech.aim_pitch])
	s_state.rpc(_clock, entries)
	for slot: Slot in _slots.values():
		if slot.is_local or slot.mech == null or not is_instance_valid(slot.mech):
			continue
		var ammo := {}
		for weapon in slot.mech.weapons:
			ammo[weapon.mount_id] = weapon.ammo
		s_self.rpc_id(slot.peer, ammo)


func _refresh_local_controller() -> void:
	if controller != null:
		controller.enabled = _controls_open() and local_mech != null and is_instance_valid(local_mech) and not local_mech.is_dead()


# ---- remote calls, client to server

## First message from a client: who they are and which versions they have.
@rpc("any_peer", "call_remote", "reliable")
func c_hello(info: Dictionary) -> void:
	if not is_server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if _slots.has(peer):
		return
	var reason := _check_hello(info)
	if reason != "":
		s_rejected.rpc_id(peer, reason)
		get_tree().create_timer(0.4).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer != null and multiplayer.get_peers().has(peer):
				multiplayer.multiplayer_peer.disconnect_peer(peer))
		return
	var existing: Array = []
	for slot: Slot in _slots.values():
		if slot.mech != null and is_instance_valid(slot.mech):
			existing.append(_spawn_info(slot))
	s_welcome.rpc_id(peer, {
		"your_id": peer,
		"server_name": server_name,
		"ruleset_id": rules.id,
		"ruleset": rules.to_dict(),
		"mechs": existing,
		"match": _match_state(),
	})
	var slot := _add_slot(peer, _clean_name(str(info["name"])), str(info["mech"]))
	_spawn_mech(slot, slot.spawn_index)
	_broadcast_match()


func _check_hello(info: Dictionary) -> String:
	if int(info.get("protocol", -1)) != NetProtocol.VERSION:
		return "Different game version (network protocol %d, this server uses %d)" % [int(info.get("protocol", -1)), NetProtocol.VERSION]
	if int(info.get("balance", -1)) != GameData.balance_version():
		return "Balance version mismatch (you have %d, this server uses %d). Update the game." % [int(info.get("balance", -1)), GameData.balance_version()]
	if _slots.size() >= max_players:
		return "The server is full"
	if not GameData.ids("mechs").has(str(info.get("mech", ""))):
		return "Unknown mech '%s'" % str(info.get("mech", ""))
	return ""


func _clean_name(text: String) -> String:
	var cleaned := text.strip_edges().strip_escapes().left(20)
	return cleaned if cleaned != "" else "Pilot"


## The pilot's controls for one frame.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_input(data: Array) -> void:
	if not is_server:
		return
	var slot: Slot = _slots.get(multiplayer.get_remote_sender_id())
	if slot == null or slot.mech == null or not is_instance_valid(slot.mech):
		return
	if slot.mech.is_dead() or not _controls_open():
		slot.mech.controls.clear()
		return
	NetProtocol.apply_input(slot.mech.controls, data)


# ================================================================ CLIENT

func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	c_hello.rpc_id(1, {
		"protocol": NetProtocol.VERSION,
		"balance": test_balance if test_balance >= 0 else GameData.balance_version(),
		"name": _pilot_name,
		"mech": _mech_choice,
	})


func _client_tick(delta: float) -> void:
	_render_time += delta
	for peer in _display_mechs:
		var mech: Mech = _display_mechs[peer]
		if is_instance_valid(mech):
			_place_display_mech(peer, mech)
	if local_mech != null and is_instance_valid(local_mech):
		var data: Array
		if local_mech.is_dead() or not _controls_open():
			data = NetProtocol.pack_input(MechControls.new(), local_mech.aim_yaw, local_mech.aim_pitch)
		else:
			data = NetProtocol.pack_input(local_mech.controls, local_mech.aim_yaw, local_mech.aim_pitch)
		c_input.rpc_id(1, data)
		_refresh_local_controller()


## Moves a display mech to where it was `INTERP_DELAY` ago, blending the two snapshots around that time.
func _place_display_mech(peer: int, mech: Mech) -> void:
	var buffer: Array = _buffers.get(peer, [])
	if buffer.is_empty():
		return
	var first: Dictionary = buffer[0]
	var last: Dictionary = buffer[buffer.size() - 1]
	var pos: Vector3
	var yaw: float
	var vel: Vector3
	var aim_yaw: float
	var aim_pitch: float
	var grounded: bool
	if _render_time <= float(first["t"]):
		pos = first["pos"]; yaw = first["yaw"]; vel = first["vel"]
		aim_yaw = first["ay"]; aim_pitch = first["ap"]; grounded = first["gr"]
	elif _render_time >= float(last["t"]):
		# Ran out of snapshots (a late packet): carry on at the last known speed for a moment.
		var gap := minf(_render_time - float(last["t"]), 0.15)
		pos = (last["pos"] as Vector3) + (last["vel"] as Vector3) * gap
		yaw = last["yaw"]; vel = last["vel"]
		aim_yaw = last["ay"]; aim_pitch = last["ap"]; grounded = last["gr"]
	else:
		var index := 0
		while index < buffer.size() - 2 and float(buffer[index + 1]["t"]) < _render_time:
			index += 1
		var a: Dictionary = buffer[index]
		var b: Dictionary = buffer[index + 1]
		var span := float(b["t"]) - float(a["t"])
		var f := clampf((_render_time - float(a["t"])) / span, 0.0, 1.0) if span > 0.0 else 1.0
		pos = (a["pos"] as Vector3).lerp(b["pos"], f)
		yaw = lerp_angle(float(a["yaw"]), float(b["yaw"]), f)
		vel = (a["vel"] as Vector3).lerp(b["vel"], f)
		aim_yaw = lerp_angle(float(a["ay"]), float(b["ay"]), f)
		aim_pitch = lerpf(float(a["ap"]), float(b["ap"]), f)
		grounded = a["gr"]
	mech.global_position = pos
	mech.rotation.y = yaw
	mech.velocity = vel
	mech.remote_grounded = grounded
	if mech != local_mech:
		# The local pilot's own head turns at once from their own input.
		mech.aim_yaw = aim_yaw
		mech.aim_pitch = aim_pitch


func _client_spawn(info: Dictionary) -> void:
	var peer := int(info["peer"])
	_client_despawn(peer)
	var mech := Mech.create_remote(str(info["mech_id"]), rules)
	mech.team = int(info["team"])
	mechs_root.add_child(mech)
	mech.global_transform = Transform3D(Basis(Vector3.UP, float(info["yaw"])), info["pos"])
	mech.mirror_state(info["state"])
	_display_mechs[peer] = mech
	_buffers[peer] = []
	if peer == my_id:
		local_mech = mech
		mech.make_player()
		controller.mech = mech
		hud.bind(mech, rules)
		_refresh_local_controller()


func _client_despawn(peer: int) -> void:
	if _display_mechs.has(peer):
		var mech: Mech = _display_mechs[peer]
		if is_instance_valid(mech):
			mech.queue_free()
		if mech == local_mech:
			local_mech = null
		_display_mechs.erase(peer)
	_buffers.erase(peer)


# ---- remote calls, server to clients

@rpc("authority", "call_remote", "reliable")
func s_welcome(info: Dictionary) -> void:
	rules = Ruleset.from_dict(info["ruleset"], str(info["ruleset_id"]))
	server_name = str(info["server_name"])
	_apply_match(info["match"])
	for mech_info: Dictionary in info["mechs"]:
		_client_spawn(mech_info)
	connected = true
	joined.emit()


@rpc("authority", "call_remote", "reliable")
func s_rejected(reason: String) -> void:
	connected = false
	rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func s_spawn(info: Dictionary) -> void:
	if connected:
		_client_spawn(info)


@rpc("authority", "call_remote", "reliable")
func s_despawn(peer: int) -> void:
	_client_despawn(peer)


## Damage that the server decided, replayed here so the copy matches. `part` is the part that
## really took the damage.
@rpc("authority", "call_remote", "reliable")
func s_hit(peer: int, part: String, raw_damage: float) -> void:
	var mech: Mech = _display_mechs.get(peer)
	if mech != null and is_instance_valid(mech):
		mech.take_hit(part, raw_damage)
		_refresh_local_controller()


@rpc("authority", "call_remote", "reliable")
func s_match(state: Dictionary) -> void:
	_apply_match(state)


@rpc("authority", "call_remote", "unreliable")
func s_tracer(from: Vector3, to: Vector3, color_html: String) -> void:
	Mech.spawn_tracer(mechs_root, from, to, Color.html(color_html))


## Where every mech is, a few times a second.
@rpc("authority", "call_remote", "unreliable_ordered")
func s_state(server_time: float, entries: Array) -> void:
	var target := server_time - NetProtocol.INTERP_DELAY
	if not _have_clock or absf(_render_time - target) > 0.25:
		_render_time = target
		_have_clock = true
	else:
		_render_time = lerpf(_render_time, target, 0.1)
	for entry: Array in entries:
		var peer := int(entry[0])
		if not _buffers.has(peer):
			continue
		var buffer: Array = _buffers[peer]
		buffer.append({"t": server_time, "pos": entry[1], "yaw": entry[2], "vel": entry[3], "gr": entry[4], "ay": entry[5], "ap": entry[6]})
		while buffer.size() > 12:
			buffer.pop_front()


## Private details for the local pilot: ammunition.
@rpc("authority", "call_remote", "unreliable_ordered")
func s_self(ammo: Dictionary) -> void:
	if local_mech == null or not is_instance_valid(local_mech):
		return
	for weapon in local_mech.weapons:
		if ammo.has(weapon.mount_id):
			weapon.ammo = int(ammo[weapon.mount_id])


# ---------------------------------------------------------------- shared

func _apply_match(state: Dictionary) -> void:
	phase = int(state["phase"]) as Phase
	time_left = float(state["time_left"])
	scores = state["scores"]
	result_text = str(state["result"])
	_refresh_local_controller()
	match_changed.emit()


func _update_hud(delta: float) -> void:
	if hud == null:
		return
	if not is_server and phase == Phase.ACTIVE:
		time_left = maxf(0.0, time_left - delta)
	hud.set_timer(time_left if phase == Phase.ACTIVE else -1.0)
	var parts: Array[String] = []
	for row: Array in scores:
		parts.append("%s %d" % [row[1], row[2]])
	hud.set_scoreline("   ".join(parts))
	var message := ""
	var dead := local_mech != null and is_instance_valid(local_mech) and local_mech.is_dead()
	match phase:
		Phase.WAITING:
			message = "Waiting for an opponent\n%d / %d pilots" % [_pilot_total(), max_players]
		Phase.COUNTDOWN:
			message = str(ceili(_phase_left)) if is_server else "Get ready"
		Phase.FINISHED:
			message = "%s\nNext match shortly" % result_text
	if dead and phase != Phase.FINISHED:
		message = "DESTROYED\nRespawning shortly"
	hud.show_message(message)


func _pilot_total() -> int:
	return _slots.size() if is_server else scores.size()
