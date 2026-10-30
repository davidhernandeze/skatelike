extends Node
## Challenge scoreboards from the skatelike API (server/, `https://skatelike.com/api`):
## each challenge's board lists the skaters who cleared it, in the order they first did.
## Autoloaded as Scoreboard. Only used while Profile.online is on.
##
## Clears are queued in FILE before they're sent, so a clear made offline (or while the
## API is down) goes out later: on the next clear, on the menu, or every RETRY_SECONDS.

## board: {challenge, total, clears: [{skater, clears, first_cleared_at}, ...]}.
signal board_loaded(challenge: String, board: Dictionary)
signal board_failed(challenge: String)
## result: {challenge, skater, clears, first_cleared_at, position}.
signal clear_recorded(challenge: String, result: Dictionary)

const DEFAULT_URL := "https://skatelike.com/api"
const FILE := "user://scoreboard.cfg"
const RETRY_SECONDS := 30.0
const TIMEOUT_SECONDS := 10.0

## Clears not sent yet: [{challenge, skater}, ...], oldest first.
var _pending: Array = []
var _sending := false
var _retry_left := 0.0


func _ready() -> void:
	if Online.is_server:
		set_process(false)
		return
	var file := ConfigFile.new()
	if file.load(FILE) == OK:
		_pending = file.get_value("scoreboard", "pending", [])


## Queues a clear of `challenge` by the current skater and sends it (when online).
func record_clear(challenge: String) -> void:
	if not Profile.online:
		return
	_pending.append({challenge = challenge, skater = Profile.skater_name})
	_save()
	flush()


## Sends queued clears, one at a time, oldest first.
func flush() -> void:
	if _sending or _pending.is_empty() or not Profile.online:
		return
	_sending = true
	var clear: Dictionary = _pending[0]
	var body := JSON.stringify({skater = clear.skater})
	_request("/scoreboards/%s/clears" % clear.challenge.uri_encode(), HTTPClient.METHOD_POST, body,
			_on_clear_sent.bind(clear))


func fetch_board(challenge: String) -> void:
	if not Profile.online:
		return
	_request("/scoreboards/%s" % challenge.uri_encode(), HTTPClient.METHOD_GET, "",
			func(code: int, data: Variant) -> void:
				if code == 200 and data is Dictionary:
					board_loaded.emit(challenge, data)
				else:
					board_failed.emit(challenge))


func _on_clear_sent(code: int, data: Variant, clear: Dictionary) -> void:
	_sending = false
	if code == 200 or code == 201 or code == 400 or code == 404:
		# Recorded, or rejected for good (bad name, unknown challenge): don't resend.
		_pending.pop_front()  # flush() always sends the oldest.
		_save()
		if (code == 200 or code == 201) and data is Dictionary:
			clear_recorded.emit(clear.challenge, data)
		flush()
	else:
		_retry_left = RETRY_SECONDS  # Offline, rate limited or server trouble: later.


func _process(delta: float) -> void:
	if _sending or _pending.is_empty() or not Profile.online:
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		_retry_left = RETRY_SECONDS
		flush()


func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("scoreboard", "pending", _pending)
	file.save(FILE)


## Calls done(code, parsed JSON or null); code 0 when the request didn't get an answer.
func _request(path: String, method: HTTPClient.Method, body: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, response: PackedByteArray) -> void:
			http.queue_free()
			var data: Variant = JSON.parse_string(response.get_string_from_utf8()) if response.size() > 0 else null
			done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data))
	var headers := PackedStringArray(["Content-Type: application/json"]) if body != "" else PackedStringArray()
	if http.request(api_url() + path, headers, method, body) != OK:
		http.queue_free()
		done.call(0, null)


## API base URL: `--api-url=` on the command line, else the SKATELIKE_API_URL environment
## variable, else the project setting skatelike/api/url, else (on the web) /api on the
## page's own origin, else DEFAULT_URL.
func api_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api-url="):
			return arg.get_slice("=", 1)
	if OS.get_environment("SKATELIKE_API_URL") != "":
		return OS.get_environment("SKATELIKE_API_URL")
	var setting: String = ProjectSettings.get_setting("skatelike/api/url", "")
	if setting != "":
		return setting
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin")) + "/api"
	return DEFAULT_URL
