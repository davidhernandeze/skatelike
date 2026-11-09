extends Node
## Online ghosts: other skaters riding the same challenge show up as faded boards with
## their names. Purely visual, no competition, nothing is simulated on the server.
##
## Riders don't send where they are but what they do: their actions (Runner.act), each
## stamped with the physics step it applied before, and every second a snapshot of
## their state (Runner.get_state). Ghosts replay that on their own Runner a little
## behind, and a snapshot both lets a late joiner start and corrects any drift.
##
## One script for both ends, autoloaded as Online so the RPC path (/root/Online) is the
## same on client and server. Transport is WebSocket (the only one web builds have) with
## Godot's high-level multiplayer.
##
## Client (the game): with Profile.online on, starting a challenge joins that challenge's
## room; Main then sends its actions SEND_RATE times a second (send_actions) and its
## snapshots as they're taken (send_snapshot), and everyone else's arrive through
## ghost_actions and ghost_snapshot.
##
## Server: the same project run headless, `godot --headless --path . -- --server
## [--port=8910]` (or an export with the dedicated_server feature). It listens for plain
## WebSocket (put TLS in front of it), keeps one room per challenge and relays what each
## rider sends to the rest of the room, keeping their latest snapshot and the actions
## since, for whoever joins next. See docs/online.md.
##
## Client and server must be built from the same version of this script (Godot numbers
## RPCs by their order). PROTOCOL, the WebSocket subprotocol both sides announce, makes a
## mismatch fail at the handshake instead of misrouting calls: bump it whenever the RPCs
## below change.

signal ghost_joined(id: int, skater: String)
signal ghost_left(id: int)
## A rider's state (Runner.get_state()), to start or correct their ghost from.
signal ghost_snapshot(id: int, state: Array)
## A rider's actions as [tick, action, a, b] each (see Runner.act()); every action before
## step `through` has now been sent.
signal ghost_actions(id: int, through: int, actions: PackedFloat64Array)
## &"off", &"connecting", &"online" or &"offline" (failed or lost; retried while online is on).
signal status_changed(status: StringName)

## WebSocket subprotocol: the ghost-room protocol version.
const PROTOCOL := "skatelike-9"
const DEFAULT_PORT := 8910
const DEFAULT_URL := "wss://skatelike.com/online"
## Batches of actions sent per second.
const SEND_RATE := 10.0
## Server limits: riders per room; per rider, the biggest snapshot and action batch, the
## shortest time between them, and the most actions kept since the last snapshot.
const MAX_ROOM := 32
const MAX_SNAPSHOT_BYTES := 4096
const MIN_SNAPSHOT_MS := 400
const MAX_BATCH_ACTIONS := 64
const MIN_BATCH_MS := 40
const MAX_HELD_ACTIONS := 512
## Riders in a room send SEND_RATE batches a second: one silent this long is gone (e.g.
## its phone changed network and the old connection hangs) and is dropped (ms).
const IDLE_MS := 5000
const RETRY_SECONDS := 3.0
## Server main loop rate (frames, i.e. network polls, per second).
const SERVER_FPS := 60

var is_server := false
var status: StringName = &"off"

## Client: challenge room joined ("" = none).
var _room := ""
## Client: this run of the app. Reconnecting (on another network, say) with the same one
## tells the server the old connection is gone.
var _session := randi()
var _retry_left := 0.0
## Server: peer id -> {room: String, skater: String, session: int, snapshot:
## PackedByteArray (latest), actions: PackedFloat64Array (since it), through: int,
## last_snapshot, last_batch: int (ms)}.
var _riders := {}
## Server: time until the next check for silent riders (s).
var _idle_check_left := 1.0


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
		_join.rpc_id(1, _room, Profile.skater_name, _session)
	else:
		_connect()


func leave() -> void:
	if status == &"online" and _room != "":
		_leave.rpc_id(1)
	_room = ""


## Sends this rider's state to the room (Runner.get_state()).
func send_snapshot(state: Array) -> void:
	if status == &"online" and _room != "":
		_snapshot.rpc_id(1, var_to_bytes(state))


## Sends this rider's actions to the room: all of them before step `through`.
func send_actions(through: int, actions: PackedFloat64Array) -> void:
	if status == &"online" and _room != "":
		_actions.rpc_id(1, through, actions)


func _connect() -> void:
	if status == &"connecting" or status == &"online":
		return
	var peer := WebSocketMultiplayerPeer.new()
	peer.supported_protocols = PackedStringArray([PROTOCOL])
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
	# Join first: whoever reacts to going online (Main resending its run) is then in the room.
	if _room != "":
		_join.rpc_id(1, _room, Profile.skater_name, _session)
	_set_status(&"online")


func _on_lost() -> void:
	multiplayer.multiplayer_peer = null
	_set_status(&"offline")
	_retry_left = RETRY_SECONDS


func _process(delta: float) -> void:
	if is_server:
		_drop_idle(delta)
		return
	if status != &"offline" or not Profile.online:
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
	peer.supported_protocols = PackedStringArray([PROTOCOL])
	var error := peer.create_server(port)
	if error != OK:
		printerr("skatelike server: can't listen on port %d (error %d)" % [port, error])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false  # Clients only ever talk to the server.
	# Headless, the main loop would spin as fast as it can; batches arrive SEND_RATE times
	# a second, so polling at SERVER_FPS keeps latency low at a fraction of the CPU.
	Engine.max_fps = SERVER_FPS
	multiplayer.peer_connected.connect(_on_rider_connected)
	multiplayer.peer_disconnected.connect(_on_rider_disconnected)
	get_tree().call_deferred("unload_current_scene")  # No menu or game on the server.
	print("skatelike server: listening for WebSocket on port %d" % port)


## Clients from another protocol version (or none) would misread the RPCs: drop them.
func _on_rider_connected(id: int) -> void:
	var peer: WebSocketMultiplayerPeer = multiplayer.multiplayer_peer
	var protocol := peer.get_peer(id).get_selected_protocol()
	if protocol != PROTOCOL:
		print("rider %d dropped: protocol '%s', not %s" % [id, protocol, PROTOCOL])
		peer.disconnect_peer(id)
		return
	print("rider %d connected" % id)


## Once a second: disconnects riders in a room that have gone silent (they reconnect and
## rejoin if they're still there).
func _drop_idle(delta: float) -> void:
	_idle_check_left -= delta
	if _idle_check_left > 0.0:
		return
	_idle_check_left = 1.0
	var now := Time.get_ticks_msec()
	for id in _riders.keys():
		var rider: Dictionary = _riders[id]
		if rider.room != "" and now - rider.last_batch > IDLE_MS:
			print("rider %d silent: dropped" % id)
			_leave_room(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)


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
func _join(room: String, skater: String, session: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	# The same app on a new connection: its old one is gone, whatever TCP still thinks.
	for other in _riders.keys():
		if other != id and _riders[other].session == session:
			print("rider %d replaced by %d" % [other, id])
			_leave_room(other)
			_riders.erase(other)
			multiplayer.multiplayer_peer.disconnect_peer(other)
	if not _is_challenge(room) or not Profile.is_valid(skater) or _room_members(room).size() >= MAX_ROOM:
		return
	_leave_room(id)
	_riders[id] = {room = room, skater = skater, session = session, snapshot = PackedByteArray(),
			actions = PackedFloat64Array(), through = 0, last_snapshot = 0,
			last_batch = Time.get_ticks_msec()}
	for other in _room_members(room):
		if other != id:
			_ghost_joined.rpc_id(other, id, skater)
			var rider: Dictionary = _riders[other]
			_ghost_joined.rpc_id(id, other, rider.skater)
			# Enough to start their ghost mid-run.
			if not rider.snapshot.is_empty():
				_ghost_snapshot.rpc_id(id, other, rider.snapshot)
				_ghost_actions.rpc_id(id, other, rider.through, rider.actions)
	print("rider %d (%s) joined %s: %d riding" % [id, skater, room, _room_members(room).size()])


@rpc("any_peer", "call_remote", "reliable")
func _leave() -> void:
	if is_server:
		_leave_room(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _snapshot(state: PackedByteArray) -> void:
	if not is_server or state.size() > MAX_SNAPSHOT_BYTES:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _riders.has(id) or _riders[id].room == "":
		return
	var rider: Dictionary = _riders[id]
	var now := Time.get_ticks_msec()
	if now - rider.last_snapshot < MIN_SNAPSHOT_MS:
		return
	rider.last_snapshot = now
	rider.snapshot = state
	rider.actions = PackedFloat64Array()  # Older ones aren't needed to start from it.
	for other in _room_members(rider.room):
		if other != id:
			_ghost_snapshot.rpc_id(other, id, state)


@rpc("any_peer", "call_remote", "reliable")
func _actions(through: int, actions: PackedFloat64Array) -> void:
	if not is_server or actions.size() % 4 != 0 or actions.size() > MAX_BATCH_ACTIONS * 4:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _riders.has(id) or _riders[id].room == "":
		return
	var rider: Dictionary = _riders[id]
	var now := Time.get_ticks_msec()
	if now - rider.last_batch < MIN_BATCH_MS or through < rider.through:
		return
	rider.last_batch = now
	rider.through = through
	if rider.actions.size() + actions.size() <= MAX_HELD_ACTIONS * 4:
		rider.actions.append_array(actions)
	for other in _room_members(rider.room):
		if other != id:
			_ghost_actions.rpc_id(other, id, through, actions)


# --- RPCs: server -> client ---------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _ghost_joined(id: int, skater: String) -> void:
	ghost_joined.emit(id, skater)


@rpc("authority", "call_remote", "reliable")
func _ghost_left(id: int) -> void:
	ghost_left.emit(id)


@rpc("authority", "call_remote", "reliable")
func _ghost_snapshot(id: int, state: PackedByteArray) -> void:
	var decoded = bytes_to_var(state)  # Never objects: only plain values come through.
	if decoded is Array:
		ghost_snapshot.emit(id, decoded)


@rpc("authority", "call_remote", "reliable")
func _ghost_actions(id: int, through: int, actions: PackedFloat64Array) -> void:
	ghost_actions.emit(id, through, actions)
