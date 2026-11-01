extends Node2D
## Other online skaters on the same challenge, drawn as faded boards with their names,
## plus a name tag over the player's own board. A child of the Runner (shares its
## coordinates); poses arrive in level coordinates from Online, Online.POSE_RATE times a
## second, and each ghost is played back interp_delay behind, blending between the two
## poses around that moment, so it moves smoothly instead of hopping from pose to pose.

@export var alpha := 0.45
@export var ghost_color := Color(0.65, 0.8, 1.0)
@export var name_size := 22
## Name tags float this far above the board center (px).
@export var name_lift := 34.0
## How far behind the newest pose a ghost is shown (s): about two pose intervals, so
## there's normally a pose on either side to blend between, despite network jitter.
@export var interp_delay := 0.2
## A pose that's late is guessed on from the last two for at most this long (s), then
## the ghost waits.
@export var max_extrapolate := 0.15
## When a ghost's poses run dry (a stalled connection) it plays on at half speed,
## stretching its delay up to this (s), then catches up 5% fast back to interp_delay.
@export var max_delay := 0.6
## How much of the gap between a pose's arrival and its beat is closed per pose (0..1).
@export var time_sync := 0.1
## A ghost that moves back along the level by more than this is snapped, not blended: it
## restarted after a slam (px).
@export var snap_back := 100.0
## Same for one that moves further than this speed allows since its last pose (px/s):
## faster than any ride or fall.
@export var snap_speed := 8000.0
## Ghosts with no pose for this long are hidden (s).
@export var stale_time := 3.0

## Each id: {skater, samples: [{t, pos (level), angle, scale}] oldest first, delay, pos,
## angle, scale (as shown now)}. Sample times are on _clock, when the pose arrived.
var _ghosts := {}
## Seconds since this node started, counted in frames (so it pauses with the game).
var _clock := 0.0

@onready var _runner: Runner = get_parent()


func _ready() -> void:
	Online.ghost_joined.connect(_on_joined)
	Online.ghost_left.connect(func(id: int) -> void: _ghosts.erase(id))
	Online.ghost_moved.connect(_on_moved)


func _on_joined(id: int, skater: String) -> void:
	_ghosts[id] = {skater = skater, samples = [], delay = interp_delay, pos = Vector2.ZERO,
			angle = 0.0, scale = Vector2.ONE}


func _on_moved(id: int, pose: PackedFloat32Array) -> void:
	if not _ghosts.has(id):
		_on_joined(id, "?????")
	var ghost: Dictionary = _ghosts[id]
	var samples: Array = ghost.samples
	var pos := Vector2(pose[0], pose[1])
	var t := _clock
	if not samples.is_empty():
		var last: Dictionary = samples.back()
		var reach := snap_speed * maxf(t - last.t, 1.0 / Online.POSE_RATE)
		if pos.x < last.pos.x - snap_back or last.pos.distance_to(pos) > reach:
			samples.clear()  # Restarted: start over from here.
		else:
			# The server sends steadily: time each pose on that beat (counting any that got
			# lost), drifting slowly towards when they actually arrive, so network jitter
			# doesn't make the ghost speed up and slow down.
			var step := 1.0 / Online.POSE_RATE
			var due: float = last.t + step * maxf(roundf((t - last.t) / step), 1.0)
			t = due + (t - due) * time_sync
	samples.append({t = t, pos = pos, angle = pose[2], scale = Vector2(pose[3], pose[4])})
	if samples.size() == 1:
		_show(ghost, samples[0])


func _process(delta: float) -> void:
	_clock += delta
	for ghost in _ghosts.values():
		var samples: Array = ghost.samples
		if samples.is_empty():
			continue
		if _clock - ghost.delay > samples.back().t:
			ghost.delay = minf(ghost.delay + delta * 0.5, max_delay)  # Ran dry: slow down.
		else:
			ghost.delay = maxf(ghost.delay - delta * 0.05, interp_delay)  # Catch up.
		var at: float = _clock - ghost.delay
		# Drop poses no longer needed: keep the last one at or before `at`.
		while samples.size() > 2 and samples[1].t <= at:
			samples.pop_front()
		var a: Dictionary = samples[0]
		if at <= a.t or samples.size() == 1:
			_show(ghost, a)  # Not started yet, or waiting for the next pose.
			continue
		var b: Dictionary = samples[1]
		if at <= b.t:
			_blend(ghost, a, b, (at - a.t) / (b.t - a.t))
		else:
			# Late: carry on the way it was going, for a moment.
			var k: float = (minf(at, b.t + max_extrapolate) - a.t) / (b.t - a.t)
			_blend(ghost, a, b, k)
	queue_redraw()


func _show(ghost: Dictionary, sample: Dictionary) -> void:
	ghost.pos = sample.pos
	ghost.angle = sample.angle
	ghost.scale = sample.scale


## Shows the pose `k` of the way from a to b (past 1 to extrapolate).
func _blend(ghost: Dictionary, a: Dictionary, b: Dictionary, k: float) -> void:
	ghost.pos = a.pos.lerp(b.pos, k)
	ghost.angle = a.angle + wrapf(b.angle - a.angle, -PI, PI) * k
	ghost.scale = a.scale.lerp(b.scale, clampf(k, 0.0, 1.0))


func _draw() -> void:
	for ghost in _ghosts.values():
		if ghost.samples.is_empty() or _clock - ghost.samples.back().t > stale_time:
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
