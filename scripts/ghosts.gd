extends Node2D
## Other online skaters on the same challenge, drawn as faded boards with their names,
## plus a name tag over the player's own board. A child of the Runner (shares its
## coordinates); poses arrive in level coordinates from Online and are eased between
## updates (Online.POSE_RATE per second).

@export var alpha := 0.45
@export var ghost_color := Color(0.65, 0.8, 1.0)
@export var name_size := 22
## Name tags float this far above the board center (px).
@export var name_lift := 34.0
## How quickly a ghost eases towards its latest pose (1/s).
@export var smoothing := 18.0
## Jumps longer than this are snapped, not eased (a restart after a slam).
@export var snap_distance := 300.0
## Ghosts with no pose for this long are hidden (s).
@export var stale_time := 3.0

## Each id: {skater, target: Vector2, pos: Vector2 (level), angle, target_angle,
## scale: Vector2, seen: int (ms; 0 = no pose yet)}.
var _ghosts := {}

@onready var _runner: Runner = get_parent()


func _ready() -> void:
	Online.ghost_joined.connect(_on_joined)
	Online.ghost_left.connect(func(id: int) -> void: _ghosts.erase(id))
	Online.ghost_moved.connect(_on_moved)


func _on_joined(id: int, skater: String) -> void:
	_ghosts[id] = {skater = skater, target = Vector2.ZERO, pos = Vector2.ZERO, angle = 0.0,
			target_angle = 0.0, scale = Vector2.ONE, seen = 0}


func _on_moved(id: int, pose: PackedFloat32Array) -> void:
	if not _ghosts.has(id):
		_on_joined(id, "?????")
	var ghost: Dictionary = _ghosts[id]
	var target := Vector2(pose[0], pose[1])
	if ghost.seen == 0 or ghost.pos.distance_to(target) > snap_distance:
		ghost.pos = target
		ghost.angle = pose[2]
	ghost.target = target
	ghost.target_angle = pose[2]
	ghost.scale = Vector2(pose[3], pose[4])
	ghost.seen = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var k := 1.0 - exp(-smoothing * delta)
	for ghost in _ghosts.values():
		ghost.pos = ghost.pos.lerp(ghost.target, k)
		ghost.angle = lerp_angle(ghost.angle, ghost.target_angle, k)
	queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	for ghost in _ghosts.values():
		if ghost.seen == 0 or now - ghost.seen > stale_time * 1000.0:
			continue
		var center := _runner.from_level(ghost.pos)
		_runner.draw_board_at(self, center, ghost.angle, ghost.scale, alpha, ghost_color)
		_draw_name(center, ghost.skater, Color(ghost_color, 0.8))
	var pose := _runner.board_pose()
	_draw_name(pose[0], Profile.skater_name, _runner.player_color)


func _draw_name(center: Vector2, text: String, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	var at := center + Vector2(-width * 0.5, -name_lift)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, 6, Color(0, 0, 0, color.a * 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, color)
