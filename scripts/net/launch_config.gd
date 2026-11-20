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
## --max-players=N, --server-name=TEXT, --practice=1|2|3 (play offline against computer pilots, that many a side) and --bot-level=easy|normal|hard, --map=field|canyon (practice), and --primary=ID --secondary=ID --equipment=ID --perk=ID.

const SERVER := "server"
const HOST := "host"
const CLIENT := "client"
## An offline match against computer pilots: no network at all.
const PRACTICE := "practice"

static var mode: String = ""
static var address: String = "127.0.0.1"
static var port: int = NetProtocol.DEFAULT_PORT
static var ruleset_id: String = "standard"
static var server_name: String = "Animal Mech Combat server"
static var player_name: String = "Pilot"
## True when --name= was given, so the name saved in settings does not replace it.
static var name_from_args: bool = false
static var mech_id: String = "lion"
## The four loadout slots (primary, secondary, equipment, perk) as item ids.
static var loadout: Dictionary = {}
static var max_players: int = 2
## Practice matches: pilots on each side (1 is 1v1, 3 is 3v3) and how sharp the computer pilots are.
static var team_size: int = 1
static var bot_level: String = ""
## Practice matches: the map to play on ("" keeps the ruleset's own: the open field).
static var map: String = ""


## Reads the command line. Returns true if it asked for a server, a host or a join.
static func from_args(args: PackedStringArray) -> bool:
	mode = ""
	for arg in args:
		if arg == "--server":
			mode = SERVER
		elif arg == "--host":
			mode = HOST
		elif arg.begins_with("--practice="):
			mode = PRACTICE
			team_size = clampi(int(arg.trim_prefix("--practice=")), 1, 3)
			ruleset_id = "practice_match"
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--bot-level="):
			bot_level = arg.trim_prefix("--bot-level=")
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
			name_from_args = true
		elif arg.begins_with("--mech="):
			mech_id = arg.trim_prefix("--mech=")
		elif arg.begins_with("--primary="):
			loadout["primary"] = arg.trim_prefix("--primary=")
		elif arg.begins_with("--secondary="):
			loadout["secondary"] = arg.trim_prefix("--secondary=")
		elif arg.begins_with("--equipment="):
			loadout["equipment"] = arg.trim_prefix("--equipment=")
		elif arg.begins_with("--perk="):
			loadout["perk"] = arg.trim_prefix("--perk=")
		elif arg.begins_with("--max-players="):
			max_players = clampi(int(arg.trim_prefix("--max-players=")), 2, NetProtocol.MAX_PLAYERS)
		elif arg.begins_with("--server-name="):
			server_name = arg.trim_prefix("--server-name=")
	return mode != ""
