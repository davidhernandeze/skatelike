class_name Runner
extends Node2D
## Side-scrolling skate level: the ground scrolls left, the player stays at a fixed x,
## pushes to keep speed up and pops (tail or nose) or rolls off ledges.
## Every pop or drop-off starts a trick that must be caught before landing.
## Rails float above the ground and are only solid for a board coming down on them
## after a triple catch (a grind); otherwise the board passes through to the floor.
## The ground is a chain of straight, possibly sloped segments; the board rides on
## its two wheels. Everything is drawn with basic shapes.

signal game_over
signal level_cleared
signal score_changed(score: int)
## Emitted on each mid-air catch (1 = tilt lock, 2 = manual catch).
## apex_ms < 0 means before the peak of the jump.
signal caught(catch_index: int, angle_deg: float, apex_ms: int)
signal landed(style: String)
## The rider fell; the board flips and game_over follows after slam_duration.
signal slammed(reason: String)
## Emitted on takeoff with the pop strength (0..1 of the full jump velocity).
signal popped(nose: bool, strength: float)
## Emitted when both wheels leave the ground without a pop; factor scales the spin.
signal dropped(factor: float)
signal pushed(strength: float, speed: float, queued: bool)
signal speed_changed(speed: float)
## True while a trick is in progress (from takeoff until landing).
signal airborne_changed(airborne: bool)
## A flip trick started (kickflip/heelflip, "late " prefix when after a catch).
signal flipped(trick: String)
## The flip was caught in time; the landing still has to be clean.
signal flip_caught(trick: String)
## A balance trick started or ended: &"manual", &"grind" or &"" (none).
signal balance_changed(mode: StringName)

## A stretch of ground: a straight top edge from (x0, y0) to (x1, y1), solid below.
class Seg:
	var x0: float
	var y0: float
	var x1: float
	var y1: float

	func _init(from: Vector2, to: Vector2) -> void:
		x0 = from.x
		y0 = from.y
		x1 = to.x
		y1 = to.y

	## Height of the top edge at x (extrapolated outside the segment).
	func y_at(x: float) -> float:
		return y0 + (y1 - y0) * (x - x0) / (x1 - x0)

	## Positive = downhill (clockwise), like the board angle.
	func angle() -> float:
		return atan2(y1 - y0, x1 - x0)

@export var board_size := Vector2(96.0, 28.0)
@export var player_x_ratio := 0.25
@export var gravity := 3000.0
## Full-strength pop (top of a pop pad).
@export var jump_velocity := 1100.0
## Pop strength at the bottom of a pop pad, as a fraction of jump_velocity.
@export var min_pop := 0.6
## Spin given on pop (rad/s); decays in the air like inertia.
## Tail pop lifts the nose (anticlockwise), nose pop lifts the tail.
@export var jump_spin := 3.5
@export var spin_damping := 4.0
## How fast the board settles to the ground angle after landing.
@export var land_settle := 18.0

@export_group("Drop-off")
## Nose-down spin when the wheels leave a ledge at drop_ref_speed (rad/s).
@export var drop_spin := 2.5
## Spin factor = drop_ref_speed / speed: slow roll-offs tip more, fast ones fly flatter.
@export var drop_ref_speed := 400.0
## Clamp for the speed factor.
@export var drop_factor_range := Vector2(0.5, 2.0)

@export_group("Speed")
@export var start_speed := 400.0
## Friction never slows the board below this. At 0 the board eventually stops.
@export var cruise_speed := 0.0
## Riding slower than this slams the rider.
@export var stop_speed := 5.0
## Speed the terrain is sized for (room before step ups): about where nonstop full
## pushes level off against friction on flat ground.
@export var top_speed := 750.0
## Slopes can't go faster than this.
@export var terminal_speed := 900.0
## Speed lost per second while rolling.
@export var friction := 35.0
## Acceleration along a slope = slope_gravity * sin(angle): downhill speeds up, uphill slows.
@export var slope_gravity := 800.0

@export_group("Push")
## Speed gained by the lightest and the hardest push (bottom/top of the push pad),
## added gradually over the push.
@export var push_gain := Vector2(30.0, 220.0)
## Above 1, gain grows faster than push time, so harder pushes accelerate more:
## light 100 px/s², half 149 px/s², full 220 px/s² with the defaults.
@export var push_curve := 1.5
## How long a push lasts, from the lightest to the hardest (s). No tricks meanwhile.
@export var push_time := Vector2(0.3, 1.0)
## Push acceleration fades above this speed instead of stopping at a limit (px/s).
@export var push_fade_start := 300.0
## How quickly it fades: at push_fade_start + push_fade_width it's down to 37%,
## at twice the width to 2% (px/s).
@export var push_fade_width := 330.0
## Pushes that can wait in line behind the current one.
@export var max_queued_pushes := 2

@export_group("Terrain")
## Time between platforms at the current speed (s); 0..0 = continuous ground.
@export var gap_time := Vector2(0.0, 0.0)
## Step height range going up (px). Max is capped to what a full pop can clear.
@export var step_up := Vector2(30.0, 110.0)
## Step height range going down (px).
@export var step_down := Vector2(40.0, 180.0)
## Chance that the next random platform is higher than the last.
@export_range(0.0, 1.0) var step_up_chance := 0.5
@export var platform_width := Vector2(180.0, 480.0)
## Chance that a random platform is sloped.
@export_range(0.0, 1.0) var slope_chance := 0.4
## Slope range of random platforms (deg): negative = uphill, positive = downhill.
## Biased downhill since random steps leave little room to push.
@export var random_slope := Vector2(-8.0, 15.0)
## Ground time guaranteed after arriving on a platform before a step up (s).
@export var reaction_time := 0.25
## Distance from the start of the goal platform to the finish flag (px).
@export var goal_offset := 250.0
## Joints bending uphill by more than this are too steep to ride (wall); bending
## downhill by more than this launches the board (deg).
@export var max_transition := 25.0
## A surface this far above the board bottom at its nose counts as a wall (px).
@export var wall_tolerance := 12.0

@export_group("Catch")
## Board angle at the far edges of the catch pad (deg). Right = nose down.
@export var lock_max_angle := 30.0
## Touches this close to the pad center lock perfectly flat (0..1 of half-width).
@export var lock_dead_zone := 0.15
## How fast the board rotates to the caught angle.
@export var lock_snap := 14.0
## Tilt added by the second (manual) catch, relative to the first (deg).
@export var manual_angle := 12.0
## Tilt relative to the ground at which the tail/nose hits the floor (deg).
@export var manual_max_angle := 20.0

@export_group("Grind")
## Speed lost per second while grinding (rails are slower than concrete).
@export var grind_friction := 60.0
@export var rail_color := Color(0.85, 0.87, 0.92)
@export var rail_post_color := Color(0.45, 0.47, 0.55)

@export_group("Flip tricks")
## How long a kickflip/heelflip takes; it must be caught within this time (s).
@export var flip_time := 0.4

@export_group("Landing")
## Allowed difference between the board angle and the ground angle at touchdown (deg).
@export var land_tolerance := 15.0
## Length of the slam animation before game over (s).
@export var slam_duration := 0.8
@export_group("")

@export var player_color := Color(1.0, 0.85, 0.3)
@export var platform_color := Color(0.55, 0.6, 0.75)
## Riding surface line drawn along the top of the ground.
@export var edge_color := Color(0.78, 0.82, 0.92)
## Size of one ground texture tile (px).
@export var ground_tile := 128
@export var truck_color := Color(0.7, 0.72, 0.78)
@export var wheel_color := Color(0.95, 0.95, 0.95)
@export var goal_color := Color(0.4, 0.95, 0.5)

const WHEEL_X := 28.0
const WHEEL_Y := 7.0
const WHEEL_R := 7.0

var _area := Vector2.ZERO
var _started := false
var _dead := false
var _cleared := false
var _speed := 0.0
var _distance := 0.0
var _score := 0

## Point midway between the wheel contacts (bottom center of the board).
var _pos := Vector2.ZERO
var _velocity_y := 0.0
var _grounded := true
## Segment the back wheel rides on while grounded.
var _support: Seg
## Angle of the ground under the wheels while grounded.
var _ground_angle := 0.0
## A pop or drop-off is in progress and has to be landed.
var _in_trick := false
var _airborne := false
## Board rotation; negative is anticlockwise (nose up).
var _angle := 0.0
var _angular_velocity := 0.0
var _locked := false
var _lock_angle := 0.0
var _first_lock_angle := 0.0
## Number of catches in the current trick (0, 1 or 2).
var _catches := 0
## +1 = nose manual, -1 = manual (tail down). Set by the second catch.
var _manual_dir := -1.0
## Manual being ridden on the ground: 0 = none, +1 = nose manual, -1 = manual.
## Set through _set_balance(), which also sets _rail.
var _riding_manual := 0.0
## Rail being ground (null when not grinding). The board isn't _grounded meanwhile.
var _rail: Seg
## The current trick left a rail: grinding again before touching the floor is a double grind.
var _from_rail := false
var _rails: Array[Seg] = []
## Flip in progress: +1 kickflip, -1 heelflip, 0 none.
var _flip := 0
## Time left to catch the flip in progress (s).
var _flip_left := 0.0
## Flip completed (caught) in the current trick: +1 kickflip, -1 heelflip, 0 none.
var _flip_done := 0
## The flip started after a catch (late flip).
var _flip_late := false
## The current trick started with a pop (flips need one; drop-offs don't allow them).
var _popped := false
## Slam animation progress in seconds; negative when not slamming.
var _slam_t := -1.0

var _push_left := 0.0
var _push_total := 0.0
## Acceleration of the current push (px/s²).
var _push_rate := 0.0
var _push_queue: Array[float] = []

var _segs: Array[Seg] = []
var _ground_texture: Texture2D
## Time the board spends airborne arriving on the newest platform (s).
var _last_arrival_time := 0.0

var _start_y := 0.7
## Remaining scripted segments: Vector3(width, step, rise), or a Dictionary for a
## platform with a rail (see Levels).
var _segments: Array = []
var _random_left := 0
var _goal_spawned := false
## Finish flag x in play area coordinates; scrolls with the ground.
var _goal_x := INF


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground_texture = _make_ground_texture()


## Sets the layout to play; call before setup().
func configure(level: Dictionary) -> void:
	_start_y = level.get("start_y", 0.7)
	_segments.clear()
	for segment in level.get("segments", []):
		if segment is Vector2:
			segment = Vector3(segment.x, segment.y, 0.0)
		_segments.append(segment)
	_random_left = level.get("random", 0)


func setup(area: Vector2) -> void:
	_area = area
	if _started or area.x <= 0.0 or area.y <= 0.0:
		return
	_started = true
	_speed = start_speed
	var ground_y := _area.y * _start_y
	_pos = Vector2(_area.x * player_x_ratio + board_size.x * 0.5, ground_y)
	# Long starting platform so the player has time to get ready.
	_segs.append(Seg.new(Vector2(-50.0, ground_y), Vector2(_area.x * 1.2 - 50.0, ground_y)))
	_support = _segs[0]
	_fill_platforms()


func can_pop() -> bool:
	return not _dead and (_grounded or _rail != null) and not _in_trick and not is_pushing()


func is_pushing() -> bool:
	return _push_left > 0.0 or not _push_queue.is_empty()


## Remaining fraction of the current push (0 when not pushing).
func push_progress() -> float:
	return _push_left / _push_total if _push_left > 0.0 else 0.0


func queued_pushes() -> int:
	return _push_queue.size()


func is_grounded() -> bool:
	return _grounded


## Riding a manual or a grind (balance points active).
func is_balancing() -> bool:
	return _riding_manual != 0.0 and not _dead


func is_grinding() -> bool:
	return _rail != null and not _dead


## The rider failed to keep balance during a manual or grind.
func lose_balance(reason := "lost balance") -> void:
	if is_balancing() and not _cleared:
		_slam(reason)


## Pops off the tail (ollie) or nose (nollie). strength is -1 (weakest) .. 1 (full).
## Popping the raised end during a manual puts the wheels down; during a grind it
## hops off the rail without spin, and the board still has to be caught.
func pop(nose: bool, strength := 1.0) -> void:
	var contrary := is_balancing() and (1.0 if nose else -1.0) == -_riding_manual
	if contrary and _rail == null:
		_set_balance(0.0)
		return
	if not can_pop():
		return
	var power := lerpf(min_pop, 1.0, _unit(strength))
	_velocity_y = _speed * tan(_ground_angle) - jump_velocity * power
	_from_rail = _rail != null
	_grounded = false
	_start_trick(0.0 if contrary else jump_spin * power * (1.0 if nose else -1.0))
	_popped = not contrary
	popped.emit(nose, power)
	_update_airborne()


## Kicks for speed. strength is -1 (light) .. 1 (full). Queued while already pushing.
func push(strength := 1.0) -> void:
	if _dead or _in_trick or not _grounded or is_balancing():
		return
	var power := _unit(strength)
	if is_pushing():
		if _push_queue.size() < max_queued_pushes:
			_push_queue.append(power)
			pushed.emit(power, _speed, true)
		return
	_start_push(power)


## Catches the board during a trick. offset is -1 (left edge) .. 1 (right edge).
## The first catch locks the tilt; a second one adds manual tilt for the landing.
## The first catch locks the tilt, the second adds manual tilt, the third readies a grind.
## Catching a flip completes it and locks the tilt like a first catch.
func lock_tilt(offset: float) -> void:
	if not _in_trick or _dead:
		return
	if _flip != 0:
		_flip_done = _flip
		_flip = 0
		_catches = 1
		_first_lock_angle = _tilt_for(offset)
		_lock_angle = _first_lock_angle
		_locked = true
		_angular_velocity = 0.0
		flip_caught.emit(_flip_name())
		caught.emit(1, rad_to_deg(_lock_angle), int(_velocity_y / gravity * 1000.0))
		return
	if _catches >= 3:
		return
	_catches += 1
	if _catches == 3:
		pass  # Grind catch: makes rails solid; keeps the manual tilt.
	elif _catches == 1:
		_first_lock_angle = _tilt_for(offset)
		_lock_angle = _first_lock_angle
	else:
		_manual_dir = 1.0 if offset > lock_dead_zone else -1.0
		_lock_angle = _first_lock_angle + deg_to_rad(manual_angle) * _manual_dir
	_locked = true
	_angular_velocity = 0.0
	caught.emit(_catches, rad_to_deg(_lock_angle), int(_velocity_y / gravity * 1000.0))


func can_flip() -> bool:
	return _in_trick and _popped and not _dead and not _grounded \
			and _flip == 0 and _flip_done == 0 and _catches < 2


## Starts a kickflip (kick = true) or heelflip; it has to be caught within flip_time.
func flip(kick: bool) -> void:
	if not can_flip():
		return
	_flip = 1 if kick else -1
	_flip_left = flip_time
	_flip_late = _catches > 0
	flipped.emit(_flip_name())


## Board angle for a first catch at offset -1..1 on the catch pad.
func _tilt_for(offset: float) -> float:
	var t := 0.0
	if absf(offset) > lock_dead_zone:
		t = signf(offset) * inverse_lerp(lock_dead_zone, 1.0, absf(offset))
	return deg_to_rad(t * lock_max_angle)


## Name of the current or completed flip, e.g. "late kickflip".
func _flip_name() -> String:
	var kind := _flip if _flip != 0 else _flip_done
	return ("late " if _flip_late else "") + ("kickflip" if kind > 0 else "heelflip")


func _process(delta: float) -> void:
	if _slam_t >= 0.0:
		_step_slam(delta)
		return
	if not _started or _dead or _cleared:
		return

	var prev_speed := _speed
	if _grounded or _rail != null:
		_speed += slope_gravity * sin(_ground_angle) * delta
		if _speed > cruise_speed:
			var drag := grind_friction if _rail != null else friction
			_speed = maxf(_speed - drag * delta, cruise_speed)
		if _push_left > 0.0:
			_speed += _push_rate * _push_falloff() * delta
		_speed = minf(_speed, terminal_speed)
	if int(_speed) != int(prev_speed):
		speed_changed.emit(_speed)
	if (_grounded or _rail != null) and _speed <= stop_speed:
		_slam("stopped")
		return
	_distance += _speed * delta
	var score := int(_distance / 50.0)
	if score != _score:
		_score = score
		score_changed.emit(_score)

	for s in _segs:
		s.x0 -= _speed * delta
		s.x1 -= _speed * delta
	_goal_x -= _speed * delta
	while _segs.size() > 1 and _segs[0].x1 < -100.0 and _segs[0] != _support:
		_segs.pop_front()
	for rail in _rails:
		rail.x0 -= _speed * delta
		rail.x1 -= _speed * delta
	while not _rails.is_empty() and _rails[0].x1 < -100.0 and _rails[0] != _rail:
		_rails.pop_front()
	_fill_platforms()

	if _rail != null:
		_step_grind()
	elif _grounded:
		_step_pushes(delta)
		_step_ground()
	else:
		if _flip != 0:
			_flip_left -= delta
			if _flip_left <= 0.0:
				_slam("flip not caught")
				return
		_step_air(delta)
	if _dead:
		return
	_update_airborne()
	_step_rotation(delta)
	if _grounded and not _in_trick and _pos.x >= _goal_x:
		_cleared = true
		level_cleared.emit()
	queue_redraw()


## power is 0 (lightest) .. 1 (hardest).
func _start_push(power: float) -> void:
	_push_total = lerpf(push_time.x, push_time.y, power)
	_push_rate = lerpf(push_gain.x, push_gain.y, pow(power, push_curve)) / _push_total
	_push_left = _push_total
	_set_balance(0.0)  # Putting a foot down ends a manual.
	pushed.emit(power, _speed, false)


## Fraction of the push acceleration left at the current speed: 1 below
## push_fade_start, then a smooth bell-shaped fall towards 0.
func _push_falloff() -> float:
	var over := maxf(_speed - push_fade_start, 0.0) / push_fade_width
	return exp(-over * over)


func _step_pushes(delta: float) -> void:
	if _push_left > 0.0:
		_push_left = maxf(_push_left - delta, 0.0)
	if _push_left <= 0.0 and not _push_queue.is_empty():
		_start_push(_push_queue.pop_front())


func _step_ground() -> void:
	var w := _wheel_offset()
	# Hand over to the next segment once the back wheel rolls past the end of this one.
	while _pos.x - w > _support.x1:
		var next := _next_seg(_support)
		if next == null:
			break
		if _joint(_support, next) == &"smooth":
			_support = next
		else:
			_leave_ground()  # Rolled off a ledge or got launched.
			return

	var angle := _support.angle()
	var y := _support.y_at(_pos.x)
	var next := _next_seg(_support)
	if next != null and _pos.x + board_size.x * 0.5 > _support.x1:
		var joint := _joint(_support, next)
		if joint == &"step_up":
			_slam("wall")
			return
		if _pos.x + w > _support.x1:
			if joint == &"too_steep":
				_slam("too steep")
				return
			if joint == &"smooth":
				# Wheels on two segments: the board spans the bend.
				var back := Vector2(_pos.x - w, _support.y_at(_pos.x - w))
				var front := Vector2(_pos.x + w, next.y_at(_pos.x + w))
				angle = (front - back).angle()
				y = (back.y + front.y) * 0.5
			# Ledge or launch ahead: the front wheel hangs, the back wheel carries the board.
	_pos.y = y
	_ground_angle = angle


func _leave_ground() -> void:
	if is_pushing():
		_slam("pushing")
		return
	_grounded = false
	_velocity_y = _speed * tan(_ground_angle)
	var factor := clampf(drop_ref_speed / _speed, drop_factor_range.x, drop_factor_range.y)
	_start_trick(drop_spin * factor)
	dropped.emit(factor)


func _step_grind() -> void:
	if _pos.x > _rail.x1:
		# Slid off the end: like rolling off a ledge.
		_from_rail = true
		_velocity_y = _speed * tan(_ground_angle)
		var factor := clampf(drop_ref_speed / _speed, drop_factor_range.x, drop_factor_range.y)
		_start_trick(drop_spin * factor)
		dropped.emit(factor)
		return
	_pos.y = _rail.y_at(_pos.x)
	_ground_angle = _rail.angle()


## Starts or ends a balance trick: direction +1 nose / -1 tail / 0 none, on `rail` if grinding.
func _set_balance(direction: float, rail: Seg = null) -> void:
	var old := _balance_mode()
	_riding_manual = direction
	_rail = rail if direction != 0.0 else null
	var mode := _balance_mode()
	if mode != old:
		balance_changed.emit(mode)


func _balance_mode() -> StringName:
	if _riding_manual == 0.0:
		return &""
	return &"grind" if _rail != null else &"manual"


func _step_air(delta: float) -> void:
	var prev_y := _pos.y
	_velocity_y += gravity * delta
	_pos.y += _velocity_y * delta
	if _pos.y > _area.y:
		_die()
		return
	if _velocity_y >= 0.0 and _catches == 3:
		# Rails only catch a board that was triple caught, at the middle of the board.
		for rail in _rails:
			if _pos.x < rail.x0 or _pos.x > rail.x1:
				continue
			var top := rail.y_at(_pos.x)
			var rail_reach := 1.0 + absf(_speed * delta * tan(rail.angle()))
			if _pos.y >= top and prev_y <= top + rail_reach:
				_start_grind(rail)
				return
	if _velocity_y >= 0.0:
		# Land on the highest surface under a wheel that the board just reached.
		var w := _wheel_offset()
		var best: Seg = null
		var best_y := INF
		for x in [_pos.x - w, _pos.x + w]:
			var s := _seg_at(x)
			if s == null:
				continue
			var ground := s.y_at(x)
			# The ground scrolls under the board, so slopes rise/fall by speed * tan(angle).
			var reach := 1.0 + absf(_speed * delta * tan(s.angle()))
			if _pos.y >= ground and prev_y <= ground + reach and ground < best_y:
				best = s
				best_y = ground
		if best != null:
			_land(best)
			return
	var nose_x := _pos.x + board_size.x * 0.5
	var ahead := _seg_at(nose_x)
	if ahead != null and ahead.y_at(nose_x) < _pos.y - wall_tolerance:
		_slam("wall")


func _start_trick(spin: float) -> void:
	_in_trick = true
	_locked = false
	_catches = 0
	_popped = false
	_flip = 0
	_flip_done = 0
	_grounded = false
	_set_balance(0.0)
	_angular_velocity = spin


func _update_airborne() -> void:
	if _in_trick != _airborne:
		_airborne = _in_trick
		airborne_changed.emit(_airborne)


func _land(on: Seg) -> void:
	_grounded = true
	_support = on
	_ground_angle = on.angle()
	_pos.y = on.y_at(_pos.x)
	var was_trick := _in_trick
	_in_trick = false
	_locked = false
	_from_rail = false
	if not was_trick:
		landed.emit("roll")
		return
	if _flip != 0:
		_slam("landed mid-flip")
		return
	if _catches == 0:
		_slam("no catch")
		return
	var trick := _flip_name() + " " if _flip_done != 0 else ""
	if _catches >= 2:
		# Tilt relative to the ground, positive in the manual's direction.
		var tilt := rad_to_deg(_angle - _ground_angle) * _manual_dir
		if tilt > manual_max_angle:
			_slam("nose strike" if _manual_dir > 0.0 else "tail strike")
			return
		var manual_error := absf(tilt - manual_angle)
		if manual_error > land_tolerance:
			_slam("off by %d°" % roundi(manual_error))
			return
		_set_balance(_manual_dir)
		landed.emit(trick + ("nose manual" if _manual_dir > 0.0 else "manual"))
		return
	var error := rad_to_deg(absf(_angle - _ground_angle))
	if error > land_tolerance:
		_slam("off by %d°" % roundi(error))
		return
	landed.emit(trick + "clean" if trick else "clean")


## Locks onto a rail after a triple catch: like landing a manual, on the rail.
func _start_grind(rail: Seg) -> void:
	_ground_angle = rail.angle()
	_pos.y = rail.y_at(_pos.x)
	_in_trick = false
	_locked = false
	if _flip != 0:
		_slam("landed mid-flip")
		return
	var tilt := rad_to_deg(_angle - _ground_angle) * _manual_dir
	var error := absf(tilt - manual_angle)
	if error > land_tolerance:
		_slam("off by %d° on rail" % roundi(error))
		return
	var trick := ("double " if _from_rail else "") + (_flip_name() + " " if _flip_done != 0 else "")
	_set_balance(_manual_dir, rail)
	landed.emit(trick + ("nosegrind" if _manual_dir > 0.0 else "5-0 grind"))


func _step_rotation(delta: float) -> void:
	if _grounded or _rail != null:
		_angular_velocity = 0.0
		var target := _ground_angle + deg_to_rad(manual_angle) * _riding_manual
		_angle = lerpf(_angle, target, 1.0 - exp(-land_settle * delta))
	elif _locked:
		_angle = lerpf(_angle, _lock_angle, 1.0 - exp(-lock_snap * delta))
	else:
		_angle += _angular_velocity * delta
		_angular_velocity *= exp(-spin_damping * delta)


## Maps a pad offset (-1..1) to 0..1.
func _unit(offset: float) -> float:
	return (clampf(offset, -1.0, 1.0) + 1.0) * 0.5


func _wheel_offset() -> float:
	return WHEEL_X * board_size.x / 96.0


func _seg_at(x: float) -> Seg:
	for s in _segs:
		if x >= s.x0 and x <= s.x1:
			return s
	return null


func _next_seg(s: Seg) -> Seg:
	var i := _segs.find(s)
	return _segs[i + 1] if i >= 0 and i + 1 < _segs.size() else null


## How the ground continues from a to b: step_up (wall), step_down (ledge or gap),
## too_steep (bends up too sharply), launch (bends down too sharply) or smooth.
func _joint(a: Seg, b: Seg) -> StringName:
	var step := b.y0 - a.y1
	if step < -1.0:
		return &"step_up"
	if step > 1.0 or b.x0 - a.x1 > 1.0:
		return &"step_down"
	var bend := rad_to_deg(b.angle() - a.angle())
	if bend < -max_transition:
		return &"too_steep"
	if bend > max_transition:
		return &"launch"
	return &"smooth"


func _fill_platforms() -> void:
	# Keep spawning until there's ground beyond the right edge.
	while _segs.back().x0 < _area.x + 200.0:
		if not _segments.is_empty():
			var segment = _segments.pop_front()
			if segment is Dictionary:
				_append_platform(segment.width, segment.get("step", 0.0), segment.get("rise", 0.0))
				_add_rail(_segs.back(), segment.rail)
			else:
				_append_platform(segment.x, segment.y, segment.z)
		elif _random_left > 0:
			_random_left -= 1
			_append_random_platform()
		elif not _goal_spawned:
			_goal_spawned = true
			_append_platform(2000.0, 0.0, 0.0)
			_goal_x = _segs.back().x0 + goal_offset
		else:
			_append_platform(2000.0, 0.0, 0.0)


func _append_random_platform() -> void:
	var last_y: float = _segs.back().y1
	var top := _area.y * 0.35
	var bottom := _area.y * 0.85
	var max_rise := minf(step_up.y, jump_velocity * jump_velocity / (2.0 * gravity) * 0.6)
	var up := randf() < step_up_chance
	# Force the direction near the vertical limits so steps never flatten out.
	if last_y - step_up.x < top:
		up = false
	elif last_y + step_down.x > bottom:
		up = true
	var y := last_y
	if up:
		y = maxf(y - randf_range(step_up.x, max_rise), top)
	else:
		y = minf(y + randf_range(step_down.x, step_down.y), bottom)
	var width := randf_range(platform_width.x, platform_width.y)
	var rise := 0.0
	if randf() < slope_chance:
		rise = tan(deg_to_rad(randf_range(random_slope.x, random_slope.y))) * width
		rise = clampf(y + rise, top, bottom) - y
	_append_platform(width, y - last_y, rise)


## Adds ground after the last segment: `step` is the vertical jump at its start,
## `rise` the height change along it (negative = up, positive = down).
func _append_platform(width: float, step: float, rise: float) -> void:
	var last: Seg = _segs.back()
	if step < 0.0:
		# The board must be able to land on `last` and pop again before this wall.
		# Sized for max speed, since the player can push up to it before arriving.
		# Plus a board length: rolling off a ledge, the tail leaves it last.
		var room := top_speed * (_last_arrival_time + reaction_time) + board_size.x
		if last.x1 - last.x0 < room:
			# Extend with flat ground (not along the slope, which could leave the screen).
			var end := Vector2(last.x1, last.y1)
			last = Seg.new(end, end + Vector2(room - (last.x1 - last.x0), 0.0))
			_segs.append(last)
		_last_arrival_time = _full_pop_landing_time(-step)
	elif step > 0.0:
		_last_arrival_time = sqrt(2.0 * step / gravity)
	else:
		_last_arrival_time = 0.0
	# Gap scales with speed so it's measured in time, not pixels.
	var gap := _speed * randf_range(gap_time.x, gap_time.y)
	var from := Vector2(last.x1 + gap, last.y1 + step)
	_segs.append(Seg.new(from, from + Vector2(width, rise)))


## Adds a rail above `on`, parallel to it: rail = Vector3(start offset, length, height).
func _add_rail(on: Seg, rail: Vector3) -> void:
	var x0 := on.x0 + rail.x
	var x1 := x0 + rail.y
	_rails.append(Seg.new(Vector2(x0, on.y_at(x0) - rail.z), Vector2(x1, on.y_at(x1) - rail.z)))


## Time from a full pop until landing on a surface `height` px higher.
func _full_pop_landing_time(height: float) -> float:
	var v := jump_velocity
	return (v + sqrt(maxf(v * v - 2.0 * gravity * height, 0.0))) / gravity


func _die() -> void:
	if _dead:
		return
	_dead = true
	game_over.emit()


func _slam(reason: String) -> void:
	if _dead:
		return
	_dead = true
	_slam_t = 0.0
	slammed.emit(reason)


func _step_slam(delta: float) -> void:
	_slam_t += delta
	_angle = lerpf(_angle, 0.0, 1.0 - exp(-10.0 * delta))
	queue_redraw()
	if _slam_t >= slam_duration:
		_slam_t = -1.0
		game_over.emit()


func _draw() -> void:
	for s in _segs:
		var bottom := maxf(_area.y, maxf(s.y0, s.y1) + 1.0)
		var points := PackedVector2Array([
			Vector2(s.x0, s.y0), Vector2(s.x1, s.y1), Vector2(s.x1, bottom), Vector2(s.x0, bottom),
		])
		# UVs in world space (scrolled by distance travelled) so the texture moves with the ground.
		var uvs := PackedVector2Array()
		for p in points:
			uvs.append((p + Vector2(_distance, 0.0)) / float(ground_tile))
		draw_colored_polygon(points, Color.WHITE, uvs, _ground_texture)
	for s in _segs:
		draw_line(Vector2(s.x0, s.y0), Vector2(s.x1, s.y1), edge_color, 5.0)
	_draw_rails()
	_draw_goal()
	_draw_board()


## A concrete-like tile: base color with speckles and seams on two edges.
func _make_ground_texture() -> Texture2D:
	var image := Image.create(ground_tile, ground_tile, false, Image.FORMAT_RGBA8)
	image.fill(platform_color)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in ground_tile * ground_tile / 12:
		var shade := rng.randf_range(-0.06, 0.06)
		var c := platform_color.lightened(shade) if shade > 0.0 else platform_color.darkened(-shade)
		image.set_pixel(rng.randi_range(0, ground_tile - 1), rng.randi_range(0, ground_tile - 1), c)
	var seam := platform_color.darkened(0.12)
	for i in ground_tile:
		image.set_pixel(0, i, seam)
		image.set_pixel(1, i, seam)
		image.set_pixel(i, 0, seam)
	return ImageTexture.create_from_image(image)


func _draw_rails() -> void:
	for rail in _rails:
		var length := rail.x1 - rail.x0
		var posts := maxi(2, ceili(length / 240.0) + 1)
		for i in posts:
			var x := rail.x0 + 12.0 + (length - 24.0) * i / (posts - 1)
			var ground := _seg_at(x)
			var bottom := ground.y_at(x) if ground else _area.y
			draw_line(Vector2(x, rail.y_at(x)), Vector2(x, bottom), rail_post_color, 6.0)
		draw_line(Vector2(rail.x0, rail.y0), Vector2(rail.x1, rail.y1), rail_color, 7.0)


func _draw_goal() -> void:
	if not _goal_spawned or not is_finite(_goal_x):
		return
	var goal_seg := _seg_at(_goal_x)
	var ground := goal_seg.y_at(_goal_x) if goal_seg else _area.y
	var top := ground - 140.0
	draw_line(Vector2(_goal_x, ground), Vector2(_goal_x, top), goal_color, 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(_goal_x, top), Vector2(_goal_x + 60.0, top + 22.0), Vector2(_goal_x, top + 44.0),
	]), goal_color)


func _draw_board() -> void:
	# Local space: x = -48..48, wheels touch y = +14, kicktails reach y = -13.
	# The board is placed so an anchor point in local space sits on a point in the
	# world: the wheel contact midpoint, or the rolling wheel during a manual.
	var board_scale := board_size / Vector2(96.0, 28.0)
	var anchor := _pos
	var local_anchor := Vector2(0.0, 14.0)
	if (_grounded or _rail != null) and _riding_manual != 0.0 and _slam_t < 0.0:
		var wheel := _riding_manual  # Manual (-1) rolls on the back wheel, nose manual (+1) on the front.
		anchor = _pos + Vector2(wheel * _wheel_offset(), 0.0).rotated(_ground_angle)
		local_anchor = Vector2(wheel * WHEEL_X, 14.0)
	if _slam_t >= 0.0:
		# Hop and flip upside down over the first part of the slam animation.
		var k := clampf(_slam_t / (slam_duration * 0.6), 0.0, 1.0)
		anchor.y -= sin(k * PI) * board_size.y * 2.5
		board_scale.y *= cos(k * PI)
	elif _flip != 0:
		# Roll around the long axis about the middle of the board.
		anchor = _pos + (Vector2(0.0, -7.0) * board_scale).rotated(_angle)
		local_anchor = Vector2(0.0, -7.0)
		board_scale.y *= cos((1.0 - _flip_left / flip_time) * TAU)
	var center := anchor - (local_anchor * board_scale).rotated(_angle)
	draw_set_transform(center, _angle, board_scale)
	for x in [-WHEEL_X, WHEEL_X]:
		draw_rect(Rect2(x - 7.0, -1.0, 14.0, 5.0), truck_color)
		draw_circle(Vector2(x, WHEEL_Y), WHEEL_R, wheel_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-48, -13), Vector2(-38, -7), Vector2(38, -7), Vector2(48, -13),
		Vector2(49, -8), Vector2(38, -1), Vector2(-38, -1), Vector2(-49, -8),
	]), player_color if board_scale.y >= 0.0 else player_color.darkened(0.45))
	draw_set_transform(Vector2.ZERO)
