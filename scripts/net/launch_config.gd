class_name LaunchConfig
extends RefCounted
## How this run was started: the menu, a dedicated server, a listen server, or a client.
## The menu fills it in; a command line can fill it in directly, which is how a dedicated
## server on a VPS is started:
##
##   godot --headless --path . -- --server --port=7777 --ruleset=standard --max-players=2
##
## Options: --server (dedicated, no player), --host (listen server, you play too),
## --join=ADDRESS[:PORT], --port=N, --ruleset=ID, --name=PILOT, --mech=ID,
## --max-players=N, --server-name=TEXT.

const SERVER := "server"
const HOST := "host"
const CLIENT := "client"

static var mode: String = ""
static var address: String = "127.0.0.1"
static var port: int = NetProtocol.DEFAULT_PORT
static var ruleset_id: String = "standard"
static var server_name: String = "Animal Mech Combat server"
static var player_name: String = "Pilot"
static var mech_id: String = "lion"
static var max_players: int = 2


## Reads the command line. Returns true if it asked for a server, a host or a join.
static func from_args(args: PackedStringArray) -> bool:
	mode = ""
	for arg in args:
		if arg == "--server":
			mode = SERVER
		elif arg == "--host":
			mode = HOST
		elif arg.begins_with("--join="):
			mode = CLIENT
			var target := arg.trim_prefix("--join=")
			if ":" in target:
				address = target.get_slice(":", 0)
				port = int(target.get_slice(":", 1))
			else:
				address = target
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--ruleset="):
			ruleset_id = arg.trim_prefix("--ruleset=")
		elif arg.begins_with("--name="):
			player_name = arg.trim_prefix("--name=")
		elif arg.begins_with("--mech="):
			mech_id = arg.trim_prefix("--mech=")
		elif arg.begins_with("--max-players="):
			max_players = clampi(int(arg.trim_prefix("--max-players=")), 2, NetProtocol.MAX_PLAYERS)
		elif arg.begins_with("--server-name="):
			server_name = arg.trim_prefix("--server-name=")
	return mode != ""
