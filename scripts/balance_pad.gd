class_name BalancePad
extends Pad
## Replaces the push pad while a balance trick (manual or grind) is ridden. Balance
## points pop up inside it and must be tapped before their ring runs out.
## Grinds use the harder settings.

## A balance point ran out before being tapped.
signal point_expired
signal point_hit

## Time from a point appearing until it expires (s).
@export var point_lifetime := 1.4
## Time between new points, random in this range (s).
@export var spawn_interval := Vector2(0.45, 0.9)
## Delay before the first point after the balance starts (s).
@export var first_delay := 0.25
@export var max_points := 3
@export var point_radius := 40.0
## Taps this much farther than the radius still count (forgiving touch targets).
@export var hit_slop := 1.3

@export_group("Hard (grinds)")
@export var hard_point_lifetime := 1.0
@export var hard_spawn_interval := Vector2(0.3, 0.6)
@export var hard_max_points := 4
@export var hard_point_radius := 34.0
@export_group("")

## Each point: {pos: Vector2 (px, local), left: float (s)}.
var _points: Array[Dictionary] = []
var _active := false
var _spawn_in := 0.0
## Settings in use: the normal ones or the hard ones.
var _lifetime := 0.0
var _interval := Vector2.ZERO
var _max := 0
var _radius := 0.0


func _ready() -> void:
	super()
	set_process(false)


## Starts or stops the balance. Stopping clears all points.
func set_active(active: bool, hard := false) -> void:
	_active = active
	_lifetime = hard_point_lifetime if hard else point_lifetime
	_interval = hard_spawn_interval if hard else spawn_interval
	_max = hard_max_points if hard else max_points
	_radius = hard_point_radius if hard else point_radius
	_points.clear()
	_spawn_in = first_delay
	set_process(active)
	queue_redraw()


## Freezes the points where they are (e.g. after a slam), without clearing them.
func freeze() -> void:
	set_process(false)


func points() -> Array[Dictionary]:
	return _points


## Handles a tap at local_pos (-1..1). Returns false if it missed every balance point.
func press(local_pos: Vector2) -> bool:
	if not _active or not is_processing():
		return true  # Not balancing: nothing to miss.
	var at := (local_pos + Vector2.ONE) * 0.5 * size
	var best := -1
	var best_dist := _radius * hit_slop
	for i in _points.size():
		var dist := at.distance_to(_points[i].pos)
		if dist <= best_dist:
			best = i
			best_dist = dist
	if best < 0:
		return false
	_points.remove_at(best)
	queue_redraw()
	point_hit.emit()
	return true


func _process(delta: float) -> void:
	for i in range(_points.size() - 1, -1, -1):
		_points[i].left -= delta
		if _points[i].left <= 0.0:
			_points.remove_at(i)
			queue_redraw()
			point_expired.emit()
			if not is_processing():
				return  # A listener ended the balance.
	_spawn_in -= delta
	if _spawn_in <= 0.0:
		_spawn_in = randf_range(_interval.x, _interval.y)
		if _points.size() < _max:
			_spawn_point()
	queue_redraw()


func _spawn_point() -> void:
	var margin := Vector2.ONE * (_radius + 10.0)
	var area := size - margin * 2.0
	if area.x <= 0.0 or area.y <= 0.0:
		return
	# Find a spot clear of the other points; skip this spawn if there's none.
	for attempt in 12:
		var pos := margin + Vector2(randf() * area.x, randf() * area.y)
		var clear := true
		for p in _points:
			if pos.distance_to(p.pos) < _radius * 2.2:
				clear = false
				break
		if clear:
			_points.append({pos = pos, left = _lifetime})
			return


func _draw() -> void:
	super()
	for p in _points:
		var remaining: float = p.left / _lifetime
		draw_circle(p.pos, _radius * 0.72, Color(color, 0.85))
		draw_circle(p.pos, _radius, Color(0, 0, 0, 0.35), false, 2.0)
		# The ring shrinks clockwise from the top; when it's gone the point expires.
		if remaining > 0.0:
			draw_arc(p.pos, _radius, -PI * 0.5, -PI * 0.5 + TAU * remaining,
					maxi(4, ceili(64.0 * remaining)), color.lightened(0.5), 7.0, true)
