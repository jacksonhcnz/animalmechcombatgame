class_name LanDiscovery
extends RefCounted
## Finding servers on the local network without any central service.
##
## A server runs a Responder, which answers a small UDP query with a description of itself.
## A Scanner sends that query (by broadcast, or straight to one address) and reports every
## answer. Nothing here needs the official server, so LAN play always works.

const QUERY := "AMCG?"


## Answers discovery queries for a running server.
class Responder extends Node:
	## Returns the dictionary to send back (name, players, and so on).
	var info_provider: Callable
	var _udp := PacketPeerUDP.new()
	var running: bool = false

	func start() -> bool:
		running = _udp.bind(NetProtocol.DISCOVERY_PORT) == OK
		return running

	func _process(_delta: float) -> void:
		if not running:
			return
		while _udp.get_available_packet_count() > 0:
			var text := _udp.get_packet().get_string_from_utf8()
			var from_ip := _udp.get_packet_ip()
			var from_port := _udp.get_packet_port()
			if text != QUERY or not info_provider.is_valid():
				continue
			_udp.set_dest_address(from_ip, from_port)
			_udp.put_packet(JSON.stringify(info_provider.call()).to_utf8_buffer())

	func _exit_tree() -> void:
		_udp.close()


## Sends the query and collects the answers.
class Scanner extends Node:
	signal found(info: Dictionary)
	var results: Dictionary = {}
	var _udp := PacketPeerUDP.new()
	var _open: bool = false

	## Asks every address (default: the whole local network) for its server details.
	func scan(addresses: Array = ["255.255.255.255"]) -> void:
		if not _open:
			_open = _udp.bind(0) == OK
		_udp.set_broadcast_enabled(true)
		for address in addresses:
			_udp.set_dest_address(str(address), NetProtocol.DISCOVERY_PORT)
			_udp.put_packet(QUERY.to_utf8_buffer())

	func _process(_delta: float) -> void:
		if not _open:
			return
		while _udp.get_available_packet_count() > 0:
			var text := _udp.get_packet().get_string_from_utf8()
			var from_ip := _udp.get_packet_ip()
			var parsed: Variant = JSON.parse_string(text)
			if not parsed is Dictionary:
				continue
			var info: Dictionary = parsed
			info["address"] = from_ip
			results[from_ip] = info
			found.emit(info)

	func _exit_tree() -> void:
		_udp.close()
