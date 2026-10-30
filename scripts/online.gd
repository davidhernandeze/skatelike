extends Node
## Online ghosts: other skaters riding the same challenge show up as faded boards with
## their names. Purely visual, no competition, nothing is simulated on the server.
##
## One script for both ends, autoloaded as Online so the RPC path (/root/Online) is the
## same on client and server. Transport is WebSocket (the only one web builds have) with
## Godot's high-level multiplayer.
##
## Client (the game): with Profile.online on, starting a challenge joins that challenge's
## room; Main then sends the board pose ~15 times a second (send_pose), and the poses of
## everyone else in the room arrive through ghost_moved.
##
## Server: the same project run headless, `godot --headless --path . -- --server
## [--port=8910]` (or an export with the dedicated_server feature). It listens for plain
## WebSocket (put TLS in front of it), keeps one room per challenge and relays poses.
## See docs/online.md.

signal ghost_joined(id: int, skater: String)
signal ghost_left(id: int)
## pose: POSE_SIZE floats, see send_pose().
signal ghost_moved(id: int, pose: PackedFloat32Array)
## &"off", &"connecting", &"online" or &"offline" (failed or lost; retried while online is on).
signal status_changed(status: StringName)

const DEFAULT_PORT := 8910
const DEFAULT_URL := "wss://skatelike.com/online"
## level x, level y, angle, scale x, scale y (see Runner.board_pose and to_level).
const POSE_SIZE := 5
## Server limits: riders per room, and the shortest time between relayed poses per rider.
const MAX_ROOM := 32
const MIN_POSE_INTERVAL_MS := 40
const RETRY_SECONDS := 3.0

var is_server := false
var status: StringName = &"off"

## Client: challenge room joined ("" = none).
var _room := ""
var _retry_left := 0.0
## Server: peer id -> {room: String, skater: String, last_pose: int (ms)}.
var _riders := {}


func _ready() -> void:
	is_server = OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()
	if is_server:
		_start_server()
		return
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_lost)
	multiplayer.server_disconnected.connect(_on_lost)


# --- Client -----------------------------------------------------------------------

## Connects now if online is on (e.g. to show the status on the menu), or disconnects.
func refresh() -> void:
	if Profile.online:
		_connect()
	else:
		_disconnect()


## Joins the ghost room of challenge `room` (when online is on).
func join(room: String) -> void:
	_room = room
	if not Profile.online:
		return
	if status == &"online":
		_join.rpc_id(1, _room, Profile.skater_name)
	else:
		_connect()


func leave() -> void:
	if status == &"online" and _room != "":
		_leave.rpc_id(1)
	_room = ""


## Sends this rider's pose to the room: Runner.to_level(center), angle, scale.
func send_pose(pose: PackedFloat32Array) -> void:
	if status == &"online" and _room != "":
		_pose.rpc_id(1, pose)


func _connect() -> void:
	if status == &"connecting" or status == &"online":
		return
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(_url())
	if error != OK:
		_set_status(&"offline")
		return
	multiplayer.multiplayer_peer = peer
	_set_status(&"connecting")


func _disconnect() -> void:
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_set_status(&"off")


func _on_connected() -> void:
	_set_status(&"online")
	if _room != "":
		_join.rpc_id(1, _room, Profile.skater_name)


func _on_lost() -> void:
	multiplayer.multiplayer_peer = null
	_set_status(&"offline")
	_retry_left = RETRY_SECONDS


func _process(delta: float) -> void:
	if is_server or status != &"offline" or not Profile.online:
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		_connect()


func _set_status(new_status: StringName) -> void:
	if new_status != status:
		status = new_status
		status_changed.emit(status)


## Server address: `--online-url=` on the command line, else the SKATELIKE_ONLINE_URL
## environment variable, else the project setting skatelike/online/url, else (on the
## web) /online on the page's own host, else DEFAULT_URL.
func _url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-url="):
			return arg.get_slice("=", 1)
	if OS.get_environment("SKATELIKE_ONLINE_URL") != "":
		return OS.get_environment("SKATELIKE_ONLINE_URL")
	var setting: String = ProjectSettings.get_setting("skatelike/online/url", "")
	if setting != "":
		return setting
	if OS.has_feature("web"):
		var secure: bool = JavaScriptBridge.eval("location.protocol") == "https:"
		return ("wss://" if secure else "ws://") + str(JavaScriptBridge.eval("location.host")) + "/online"
	return DEFAULT_URL


# --- Server -----------------------------------------------------------------------

func _start_server() -> void:
	var port := DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.get_slice("=", 1).to_int()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		printerr("skatelike server: can't listen on port %d (error %d)" % [port, error])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false  # Clients only ever talk to the server.
	multiplayer.peer_connected.connect(func(id: int) -> void: print("rider %d connected" % id))
	multiplayer.peer_disconnected.connect(_on_rider_disconnected)
	get_tree().call_deferred("unload_current_scene")  # No menu or game on the server.
	print("skatelike server: listening for WebSocket on port %d" % port)


func _on_rider_disconnected(id: int) -> void:
	_leave_room(id)
	_riders.erase(id)
	print("rider %d disconnected" % id)


func _leave_room(id: int) -> void:
	if not _riders.has(id):
		return
	var room: String = _riders[id].room
	_riders[id].room = ""
	for other in _room_members(room):
		_ghost_left.rpc_id(other, id)


func _room_members(room: String) -> Array:
	var members := []
	if room == "":
		return members
	for id in _riders:
		if _riders[id].room == room:
			members.append(id)
	return members


static func _is_challenge(room: String) -> bool:
	var level := Levels.get_level(room)
	return level.id == room and level.get("challenge", false)


# --- RPCs: client -> server ---------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _join(room: String, skater: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _is_challenge(room) or not Profile.is_valid(skater) or _room_members(room).size() >= MAX_ROOM:
		return
	_leave_room(id)
	_riders[id] = {room = room, skater = skater, last_pose = 0}
	for other in _room_members(room):
		if other != id:
			_ghost_joined.rpc_id(other, id, skater)
			_ghost_joined.rpc_id(id, other, _riders[other].skater)
	print("rider %d (%s) joined %s: %d riding" % [id, skater, room, _room_members(room).size()])


@rpc("any_peer", "call_remote", "reliable")
func _leave() -> void:
	if is_server:
		_leave_room(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pose(pose: PackedFloat32Array) -> void:
	if not is_server or pose.size() != POSE_SIZE:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _riders.has(id) or _riders[id].room == "":
		return
	var now := Time.get_ticks_msec()
	if now - _riders[id].last_pose < MIN_POSE_INTERVAL_MS:
		return
	_riders[id].last_pose = now
	for other in _room_members(_riders[id].room):
		if other != id:
			_ghost_pose.rpc_id(other, id, pose)


# --- RPCs: server -> client ---------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _ghost_joined(id: int, skater: String) -> void:
	ghost_joined.emit(id, skater)


@rpc("authority", "call_remote", "reliable")
func _ghost_left(id: int) -> void:
	ghost_left.emit(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func _ghost_pose(id: int, pose: PackedFloat32Array) -> void:
	ghost_moved.emit(id, pose)
