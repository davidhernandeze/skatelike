class_name Runner
extends Node2D
## Side-scrolling skate level: the ground scrolls left, the player stays at a fixed x,
## pushes to keep speed up and pops (tail or nose) or rolls off ledges.
## Every pop or roll-off of a floor ledge starts a trick that must be caught before
## landing; rolling off a platform or the end of a rail doesn't need a catch (the board
## levels itself).
## Manuals and grinds come from holding CATCH: it readies the balance for as long as it's
## held, and whatever the board touches down on meanwhile starts it (rail or platform top
## = grind/slide, floor = manual). The trick is named from how the board actually meets
## the surface (see fifty_band): level is a 50-50, nose down a nosegrind/noseslide/nose
## manual, tail down a 5-0/tailslide/manual. Where CATCH is held only tilts the board on
## the way down (left tail, right nose, middle level). The press that catches the board has to be held for
## hold_delay first, so quick catches stay catches; a later press readies it at once.
## Letting go cancels it, so a rider can let a rail pass and press again to manual on the
## floor under it.
## Rails float above the ground and are only solid for a board coming down on them
## with the balance ready; otherwise the board passes through to the floor.
## Platforms (ledges, boxes, bridges) are only solid from above: the board lands or
## rides on their top, slides it with the balance ready, and passes through their sides.
## The ground is a chain of straight, possibly sloped segments; the board rides on
## its two wheels. Everything is drawn with basic shapes.

signal game_over
signal level_cleared
signal score_changed(score: int)
## Emitted on each mid-air catch change (1 = tilt locked, 2 = balance ready, CATCH held).
## apex_ms < 0 means before the peak of the jump.
signal caught(catch_index: int, angle_deg: float, apex_ms: int)
signal landed(style: String)
## The rider fell; the board flips and game_over follows after slam_duration.
signal slammed(reason: String)
## In forgiving mode, what would have been a slam; the rider was put back on the ground.
signal forgiven(reason: String)
## Emitted on takeoff with the pop strength (0..1 of the full jump velocity).
signal popped(nose: bool, strength: float)
## Emitted when the board leaves a ledge, platform or rail end without a pop.
signal dropped
signal pushed(strength: float, speed: float, queued: bool)
signal speed_changed(speed: float)
## True while a trick is in progress (from takeoff until landing).
signal airborne_changed(airborne: bool)
## A board trick (flip or shuvit) started; "late " prefix when after a catch.
signal trick_started(trick: String)
## The board trick was caught in time; the landing still has to be clean.
signal trick_caught(trick: String)
## A trick worth a callout landed: a pop trick ("ollie", "nollie kickflip"), or a
## manual/grind (sustained = lasts until balance_changed(&"")).
signal callout(text: String, sustained: bool)
## A balance trick started or ended: &"manual", &"grind", &"fifty" (a 50-50 grind) or
## &"" (none).
signal balance_changed(mode: StringName)

## A straight surface from (x0, y0) to (x1, y1): floor (solid below), the top of a
## platform (solid only from above) or a rail.
class Seg:
	var x0: float
	var y0: float
	var x1: float
	var y1: float
	## Following piece of the same floor or platform top (null at the end).
	var next: Seg
	## Part of a platform top.
	var ledge := false
	## Number of stairs drawn on this floor piece (0 = a plain surface). Stairs can't
	## be ridden or landed on: ollie them or grind their handrail.
	var stairs := 0

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
## A nollie's spin doesn't decay: the nose keeps going down until this angle (deg) or
## the catch. Enough to turn the board to a near-vertical wall and past it.
@export var nollie_spin_cap := 120.0
## A board that turned past this angle (deg, either way) is caught back slowly: the
## catch turns it all the way back at catch_slow_turn (deg/s) instead of snapping, so
## it can be timed to meet a steep wall.
@export var catch_slow_after := 90.0
@export var catch_slow_turn := 180.0
## How fast the board settles to the ground angle after landing.
@export var land_settle := 18.0

## Never slam: put the rider back on the ground instead (forgiven). For the tutorial.
@export var forgiving := false

@export_group("Drop-off")
## Nose-down spin when the wheels leave a floor ledge at drop_ref_speed (rad/s); the
## board has to be caught. Platforms and rail ends drop off flat, no catch needed.
@export var drop_spin := 2.5
## Spin factor = drop_ref_speed / speed: slow roll-offs tip more, fast ones fly flatter (m/s).
@export var drop_ref_speed := 3.3
## Clamp for the speed factor.
@export var drop_factor_range := Vector2(0.5, 2.0)
## Over a crest (a ramp going flat, the top of a hill) the board keeps its momentum and
## flies on if that would lift it at least this high (px): (v sin(bend))² / 2g.
@export var launch_min := 6.0
## Launches up to this high (px) are hops: like a drop-off, no catch needed, but the
## board keeps the angle it left at and must still land within land_tolerance (catch to
## fix it). A manual carries on over them. Higher ones are caught like a roll-off.
@export var hop_max := 40.0
## Hops up to this high (px) land at any angle, uncaught: too short to need levelling.
@export var hop_level_free := 20.0
## After flying off a crest the lip can still be popped for this long (s): the pop adds
## to the launch.
@export var lip_pop_time := 0.12

@export_group("Physics")
## Rolling follows dv/dt = (F_push(t) - c_r m g cos(a) - c_d v^2) / m + g sin(a), with
## v along the surface and a its slope (positive = downhill); the board moves by
## (v cos(a), v sin(a)). Everything in this group is in SI units (m, s, kg, N).
## Screen scale: the 96 px board is a 0.8 m deck.
@export var pixels_per_meter := 120.0
## Rider plus board (kg).
@export var mass := 75.0
## Rolling resistance coefficient: urethane wheels on smooth concrete are ~0.002-0.01.
@export var rolling_resistance := 0.003
## Aerodynamic drag factor c_d = 0.5 * air density * Cd * frontal area (kg/m):
## an upright rider is about 0.5 * 1.2 * 0.35 m².
@export var drag := 0.2
## Gravity along slopes (m/s²). The jumps keep their own, game-tuned gravity.
@export var slope_g := 9.81
@export var start_speed := 3.3
## Riding slower than this slams the rider (m/s).
@export var stop_speed := 0.05
## Speed the terrain is sized for (room before step ups): where nonstop full pushes top
## out on flat ground (7.8 m/s with the defaults).
@export var top_speed := 7.8
## Hard limit (m/s): about 43 km/h, where a street board starts to speed-wobble. Drag
## and the push limit keep normal riding far below it; only long hills get close.
@export var max_speed := 12.0

@export_group("Push")
## Peak push force of the lightest and the hardest kick (bottom/top of the push pad), N.
## Each kick is a half-sine pulse F_push(t) = F sin(pi t / T) over the push time T.
@export var push_force := Vector2(500.0, 1200.0)
## How long a push lasts, from the lightest to the hardest (s). No tricks meanwhile.
@export var push_time := Vector2(0.1, 0.25)
## Fastest the foot can sweep back along the ground (m/s): a kick only drives the board
## while the board is slower, and the force fades linearly to 0 at this speed. So
## nonstop pushing tops out near 7.8 m/s (28 km/h), like a strong skater.
@export var foot_speed := 8.0
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
## The view follows the ground under the board up and down, keeping it between these
## fractions of the play area's height (normal levels stay inside: the view stays put).
@export var camera_band := Vector2(0.25, 0.88)
## In the air the view frames the board instead: it stays between these fractions of the
## height.
@export var camera_air_band := Vector2(0.15, 0.8)
## Falling into a deep drop, the view takes on the board's speed as the board goes down
## the screen between these fractions of the height.
@export var camera_fall_blend := Vector2(0.35, 0.6)
## The board stays at least this fraction of the height below the top of the view, and
## (over ground) above the bottom.
@export var camera_top_margin := 0.06
@export var camera_bottom_margin := 0.08
## Stiffness of the critically damped spring the view follows with (1/s): it eases in
## and out instead of jumping when what it frames changes suddenly.
@export var camera_follow := 5.0
## Landing on a slope so steep that the touching wheel's spot is this much higher than
## the board's middle moves the level under the board to that spot (px).
@export var land_snap := 40.0
## A surface this far above the board bottom at its nose counts as a wall (px).
@export var wall_tolerance := 12.0

@export_group("Catch")
## Board angle at the far edges of the catch pad (deg). Right = nose down.
@export var lock_max_angle := 30.0
## Touches this close to the pad center lock perfectly flat (0..1 of half-width).
@export var lock_dead_zone := 0.15
## How fast the board rotates to the caught angle.
@export var lock_snap := 14.0
## Tilt added while the balance is ready (CATCH held), relative to the catch (deg).
@export var manual_angle := 12.0
## How long the press that catches the board must be held to ready a manual or grind (s).
## Later presses ready it at once.
@export var hold_delay := 0.15
## Balance landings are named from the board's angle against the surface at touchdown:
## within this of level both trucks take it (a 50-50 on rails and ledges, a plain landing
## on the floor); beyond it, nose or tail down (deg).
@export var fifty_band := 6.0
## Steepest angle against a rail or ledge that still grinds; beyond it, a slam (deg).
@export var grind_max_angle := 27.0
## Tilt relative to the ground at which the tail/nose hits the floor (deg).
@export var manual_max_angle := 20.0

@export_group("Grind")
## Friction while grinding a rail, as a factor of the rolling friction (0 = none).
@export var rail_friction := 0.0
## Friction while sliding a platform edge (tailslide/noseslide), as a factor of rolling friction.
@export var ledge_friction := 8.0
## How far a slide turns the board across the ledge (deg; 90 = end-on).
@export var slide_angle := 70.0
## Time to swing the board into or out of a slide (s).
@export var slide_swing_time := 0.1
@export var rail_color := Color(0.85, 0.87, 0.92)
@export var rail_post_color := Color(0.45, 0.47, 0.55)
## Thickness of a platform where it overhangs a gap (px).
@export var overhang_depth := 40.0
## Tint over the ground texture for platforms.
@export var platform_tint := Color(0.78, 0.76, 0.86)

@export_group("Board tricks")
## How long a flip or shuvit takes; it must be caught within this time (s).
@export var trick_time := 0.4
## Shuvits finish their half turn in this time (s); the catch window is still trick_time.
@export var shuvit_spin_time := 0.2

@export_group("Landing")
## Allowed difference between the board angle and the ground angle at touchdown (deg).
@export var land_tolerance := 15.0
## Length of the slam before game over (s): the board tumbles on as a loose body.
@export var slam_duration := 1.0
## Spin the loose board picks up from a slam, per m/s it was going (rad/s), at least 3.
@export var slam_spin := 0.8
## The loose board's bounce off surfaces (0..1) and how fast it stops sliding (1/s).
@export var slam_bounce := 0.3
@export var slam_friction := 2.5
## Hardest landing the legs take, as a fall height (px): only the speed into the
## surface counts, so dropping onto a steep ramp is fine where the same drop to flat
## ground slams. 0 = no limit. A level can set its own (`max_fall`).
@export var max_fall := 550.0
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
## Top of the view in this node's coordinates (the node is moved up by it).
var _cam := 0.0
## How fast the view is moving down (px/s).
var _cam_v := 0.0
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
## 0 = not caught, 1 = caught (tilt locked), 2 = balance ready (CATCH held long enough).
var _catches := 0
## CATCH is held: since when (s, game time, counted once the board is caught) and where.
var _holding := false
var _hold_t := 0.0
var _hold_offset := 0.0
## The current trick came from a pop (or a hop off a rail) and must be caught.
var _needs_catch := true
## Tilt readied by where CATCH is held: +1 nose down, -1 tail down, 0 level (the middle).
## It only tilts the board in the air; the trick is named at touchdown.
var _manual_dir := -1.0
## Manual being ridden on the ground: 0 = none, +1 = nose manual, -1 = manual.
## Set through _set_balance(), which also sets _rail and _fifty.
var _riding_manual := 0.0
## Riding a 50-50: both trucks on the rail or ledge, board level along it.
var _fifty := false
## Board angle against the surface while balancing (rad, positive nose down): the angle
## it touched down at.
var _balance_tilt := 0.0
## Rail or platform edge being ground (null when not grinding). Not _grounded meanwhile.
var _rail: Seg
## The current trick left a rail: grinding again before touching the floor is a double grind.
var _from_rail := false
var _rails: Array[Seg] = []
## Each platform: {top = chain of Segs, deck = thickness drawn (0 = down to the floor)}.
## _ledges has all the top pieces in one list.
var _platforms: Array[Dictionary] = []
var _ledges: Array[Seg] = []
## Board trick in progress: &"kickflip", &"heelflip", &"shuvit", &"front shuvit" or &"".
var _board_trick := &""
## Time left to catch the board trick in progress (s).
var _board_trick_left := 0.0
## 0..1: how far the board is swung into a slide (eases towards 1 on a ledge, 0 otherwise).
var _slide := 0.0
## Board trick completed (caught) in the current jump, or &"".
var _board_trick_done := &""
## The board trick started after a catch (late).
var _board_trick_late := false
## The current trick started with a pop (board tricks need one; drop-offs don't allow them).
var _popped := false
## That pop was off the nose (nollie).
var _pop_nose := false
## The free spin is a nollie's: undamped, capped at nollie_spin_cap.
var _nollie_spin := false
## The board turned past catch_slow_after in this trick.
var _past_vertical := false
## The current trick is a hop over a crest (see hop_max), and how high it goes (px).
var _hop := false
var _hop_height := 0.0
## Time left to pop off the lip just flown off (s).
var _lip_t := 0.0
## Slam animation progress in seconds; negative when not slamming.
var _slam_t := -1.0
## Distance ridden when the rider slammed: the loose board's tumble after doesn't count.
var _slam_distance := INF
## Velocity of the loose board while slamming (px/s).
var _body_v := Vector2.ZERO
## Velocity the board came down with this frame, before touchdown took it (px/s): a
## slam on landing lets the board go with it.
var _impact := Vector2.ZERO

var _push_left := 0.0
var _push_total := 0.0
## Peak force of the current push (N).
var _push_peak := 0.0
var _push_queue: Array[float] = []

var _segs: Array[Seg] = []
var _ground_texture: Texture2D
## Time the board spends airborne arriving on the newest platform (s).
var _last_arrival_time := 0.0

var _start_y := 0.7
## Extra start height (px), when resuming from a checkpoint.
var _start_dy := 0.0
## Remaining scripted segments: Vector3(width, step, rise), or a Dictionary for a
## platform with a rail (see Levels).
var _segments: Array = []
## Length of the level from the board's start to the goal (px), for progress().
var _length := 0.0
## Screen position of the level origin (end of the start platform) when the run started.
var _origin := Vector2.ZERO
var _random_left := 0
var _goal_spawned := false
## Finish flag x in play area coordinates; scrolls with the ground.
var _goal_x := INF
## Marked level features: segment `mark` name -> Vector2(start x, end x) of its rail,
## platform or floor piece. Filled as the terrain is generated and scrolled with it
## (used by the tutorial).
var marks := {}


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground_texture = _make_ground_texture()


## Sets the layout to play; call before setup().
func configure(level: Dictionary) -> void:
	_start_y = level.get("start_y", 0.7)
	_start_dy = level.get("start_dy", 0.0)
	_segments.clear()
	for segment in level.get("segments", []):
		if segment is Vector2:
			segment = Vector3(segment.x, segment.y, 0.0)
		_segments.append(segment)
	_random_left = level.get("random", 0)
	max_fall = level.get("max_fall", max_fall)


func setup(area: Vector2) -> void:
	_area = area
	if _started or area.x <= 0.0 or area.y <= 0.0:
		return
	_started = true
	_speed = start_speed * pixels_per_meter
	_slide = 0.0
	var ground_y := _area.y * _start_y + _start_dy
	_pos = Vector2(_area.x * player_x_ratio + board_size.x * 0.5, ground_y)
	# Long starting platform so the player has time to get ready.
	_segs.append(Seg.new(Vector2(-50.0, ground_y), Vector2(_area.x * 1.2 - 50.0, ground_y)))
	_support = _segs[0]
	_origin = Vector2(_segs[0].x1, ground_y)
	_length = _segs[0].x1 - _pos.x + goal_offset
	for segment in _segments:
		_length += segment.width + segment.get("gap", 0.0) if segment is Dictionary else segment.x
	_fill_platforms()


func can_pop() -> bool:
	if _dead or is_pushing():
		return false
	if _lip_t > 0.0 and not _popped and _catches == 0:
		return true  # Just off a lip: still in time to pop it.
	return (_grounded or _rail != null) and not _in_trick


func is_pushing() -> bool:
	return _push_left > 0.0 or not _push_queue.is_empty()


## Remaining fraction of the current push (0 when not pushing).
func push_progress() -> float:
	return _push_left / _push_total if _push_left > 0.0 else 0.0


func queued_pushes() -> int:
	return _push_queue.size()


func is_grounded() -> bool:
	return _grounded


## In the air for the air pads: hops and the moment off a lip still count as riding.
func is_airborne() -> bool:
	return _airborne


## How far along the level the board is, 0..1 (approximate).
func progress() -> float:
	return 1.0 if _cleared else clampf(minf(_distance, _slam_distance) / _length, 0.0, 0.99)


## How far the level has scrolled in all (px), for things pinned to a spot in it.
func scrolled() -> float:
	return _distance


## Bottom center of the board, in this node's coordinates.
func board_position() -> Vector2:
	return _pos


## Riding a manual or a grind (balance points active).
func is_balancing() -> bool:
	return _riding_manual != 0.0 and not _dead


func is_grinding() -> bool:
	return _rail != null and not _dead


## The rider failed to keep balance during a manual or grind.
func lose_balance(reason := "lost balance") -> void:
	if is_balancing() and not _cleared:
		_slam(reason)


## The balance finger lifted: the manual or grind ends cleanly. A manual puts the wheels
## down, a grind leaves the rail (dropping off, no catch needed) and a slide carries on
## rolling along the ledge top.
func end_balance() -> void:
	if not is_balancing():
		return
	var rail := _rail
	_set_balance(0.0)
	if rail == null:
		return
	if rail.ledge:
		_support = rail
		_grounded = true
	else:
		_from_rail = true
		_drop_off()


## Pops out of the balance trick from the end it's riding: the nose for nose tricks, the
## tail for tail tricks and 50-50s. A normal pop: it needs a catch.
func balance_pop() -> void:
	if is_balancing():
		pop(_riding_manual > 0.0 and not _fifty, 1.0)


## Pops off the tail (ollie) or nose (nollie). strength is -1 (weakest) .. 1 (full).
## Popping the raised end during a manual puts the wheels down; during a grind it
## hops off the rail without spin, and the board still has to be caught.
func pop(nose: bool, strength := 1.0) -> void:
	# A 50-50 has no raised end: either pop is a plain ollie off the rail.
	var contrary := is_balancing() and not _fifty and (1.0 if nose else -1.0) == -_riding_manual
	if contrary and _rail == null:
		_set_balance(0.0)
		return
	if not can_pop():
		return
	var power := lerpf(min_pop, 1.0, _unit(strength))
	if _grounded or _rail != null:
		_take_off()
	_lip_t = 0.0
	_velocity_y -= jump_velocity * power
	_from_rail = _rail != null
	_grounded = false
	_start_trick(0.0 if contrary else jump_spin * power * (1.0 if nose else -1.0))
	_popped = not contrary
	_pop_nose = nose
	_nollie_spin = nose and not contrary
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


## A press on CATCH at offset -1 (left edge) .. 1 (right edge). If the board isn't caught
## yet it catches it (lock_tilt), and holding it for hold_delay readies a manual or grind;
## on a board already caught it readies one at once. Either way it stays ready until
## release_catch. The press's offset picks the side: left tail, right nose.
func press_catch(offset: float) -> void:
	var already_caught := _in_trick and _catches >= 1 and _board_trick == &""
	lock_tilt(offset)
	_holding = true
	_hold_t = 0.0
	_hold_offset = offset
	if already_caught and not _dead:
		_ready_balance(offset)


## CATCH let go: a ready manual or grind is cancelled if the board is still in the air.
func release_catch() -> void:
	_holding = false
	if _catches == 2 and _in_trick:
		_catches = 1
		_lock_angle = _first_lock_angle
		caught.emit(1, rad_to_deg(_lock_angle), int(_velocity_y / gravity * 1000.0))


## A tap on CATCH (a press that isn't held): the first one locks the tilt; later ones
## do nothing. Catching a board trick completes it and locks the tilt like a first catch.
func lock_tilt(offset: float) -> void:
	if not _in_trick or _dead:
		return
	if _board_trick != &"":
		_board_trick_done = _board_trick
		_board_trick = &""
		_catches = 1
		_first_lock_angle = _tilt_for(offset)
		_lock_angle = _first_lock_angle
		_locked = true
		_angular_velocity = 0.0
		trick_caught.emit(_board_trick_name())
		caught.emit(1, rad_to_deg(_lock_angle), int(_velocity_y / gravity * 1000.0))
		return
	if _catches != 0:
		return
	_catches = 1
	_first_lock_angle = _tilt_for(offset)
	_lock_angle = _first_lock_angle
	_locked = true
	_angular_velocity = 0.0
	caught.emit(_catches, rad_to_deg(_lock_angle), int(_velocity_y / gravity * 1000.0))


## Readies a manual or grind toward the held side (CATCH held for hold_delay).
## In the middle of the pad (the dead zone), a 50-50: the board stays level, no tilt.
func _ready_balance(offset: float) -> void:
	_catches = 2
	if absf(offset) <= lock_dead_zone:
		_manual_dir = 0.0
	else:
		_manual_dir = 1.0 if offset > 0.0 else -1.0
	_lock_angle = _first_lock_angle + deg_to_rad(manual_angle) * _manual_dir
	_locked = true
	_angular_velocity = 0.0
	caught.emit(_catches, rad_to_deg(_lock_angle), int(_velocity_y / gravity * 1000.0))


## Predicted time (s) until the airborne board comes down on something at its middle:
## floor or a platform top, or also a rail when `rails`. INF if not within 2 s.
func time_to_touchdown(rails := true) -> float:
	const STEP := 1.0 / 120.0
	var y := _pos.y
	var vy := _velocity_y
	var t := 0.0
	while t < 2.0:
		var prev := y
		vy += gravity * STEP
		y += vy * STEP
		t += STEP
		if vy < 0.0:
			continue
		# The terrain scrolls left under the board: look ahead by the distance covered.
		var x := _pos.x + _speed * t
		var surfaces := _surfaces_at(x)
		if rails:
			for rail in _rails:
				if x >= rail.x0 and x <= rail.x1:
					surfaces.append(rail)
		for surface in surfaces:
			var top := surface.y_at(x)
			if y >= top and prev <= top + 2.0:
				return t
	return INF


func can_board_trick() -> bool:
	return _in_trick and _popped and not _dead and not _grounded \
			and _board_trick == &"" and _board_trick_done == &"" and _catches < 2


## Starts a flip or shuvit (&"kickflip", &"heelflip", &"shuvit", &"front shuvit");
## it has to be caught within trick_time.
func board_trick(kind: StringName) -> void:
	if not can_board_trick():
		return
	_board_trick = kind
	_board_trick_left = trick_time
	_board_trick_late = _catches > 0
	trick_started.emit(_board_trick_name())


## Board angle for a first catch at offset -1..1 on the catch pad.
func _tilt_for(offset: float) -> float:
	var t := 0.0
	if absf(offset) > lock_dead_zone:
		t = signf(offset) * inverse_lerp(lock_dead_zone, 1.0, absf(offset))
	return deg_to_rad(t * lock_max_angle)


## Name of the current or completed board trick, e.g. "late kickflip".
func _board_trick_name() -> String:
	var kind := _board_trick if _board_trick != &"" else _board_trick_done
	return ("late " if _board_trick_late else "") + kind


## Callout for a landed pop: "ollie"/"nollie", or the board trick ("nollie kickflip").
func _pop_callout(trick: String) -> String:
	if trick == "":
		return "nollie" if _pop_nose else "ollie"
	return ("nollie " if _pop_nose else "") + trick


## Board trick prefix for a landing name ("kickflip "), or "" without one.
func _trick_prefix() -> String:
	return _board_trick_name() + " " if _board_trick_done != &"" else ""


func _process(delta: float) -> void:
	if _slam_t >= 0.0:
		_step_slam(delta)
		return
	if not _started or _dead or _cleared:
		return
	_impact = Vector2.ZERO

	var prev_speed := _speed
	if _grounded or _rail != null:
		_step_speed(delta)
	if int(_speed) != int(prev_speed):
		speed_changed.emit(_speed)
	if (_grounded or _rail != null) and _speed <= stop_speed * pixels_per_meter:
		_slam("stopped")
		return
	# Along the surface on the ground; in the air _speed is the horizontal speed.
	var dx := _speed * delta
	if _grounded or _rail != null:
		dx *= cos(_ground_angle)
	var score := int((_distance + dx) / 50.0)
	if score != _score:
		_score = score
		score_changed.emit(_score)

	_shift_world(dx)
	while _segs.size() > 1 and _segs[0].x1 < -100.0 and _segs[0] != _support:
		_segs.pop_front()
	while not _rails.is_empty() and _rails[0].x1 < -100.0 and _rails[0] != _rail:
		_rails.pop_front()
	while not _platforms.is_empty() and _platforms[0].top.back().x1 < -100.0 \
			and not (_support in _platforms[0].top) and not (_rail in _platforms[0].top):
		for ledge in _platforms.pop_front().top:
			_ledges.erase(ledge)
	_fill_platforms()

	if _rail != null:
		_step_grind()
	elif _grounded:
		_step_pushes(delta)
		_step_ground()
	else:
		if _board_trick != &"":
			_board_trick_left -= delta
			if _board_trick_left <= 0.0:
				_slam(_board_trick + " not caught")
				return
		_lip_t -= delta
		_step_hold(delta)
		_step_air(delta)
	if _dead:
		return
	_update_airborne()
	_step_rotation(delta)
	_follow_ground(delta)
	var sliding := _rail != null and _rail.ledge and not _fifty
	_slide = move_toward(_slide, 1.0 if sliding else 0.0, delta / slide_swing_time)
	if _grounded and not _in_trick and _pos.x >= _goal_x:
		_cleared = true
		level_cleared.emit()
	queue_redraw()


## Moves the view so the floor under the board stays inside camera_band (e.g. down a
## tall ramp), and the board below the top margin. When that floor is far below the
## board (falling along a tall wall), the board is kept nearer the middle instead.
## Over a pit there's nothing to follow: a board falling in leaves the view and dies.
## Floor height `dist` px ahead along what the board can roll onto: past a lip or a
## gap it stays at the edge, so the view doesn't dive before the board does.
func _ground_ahead(dist: float) -> float:
	var s := _support
	var x := _pos.x + dist
	while x > s.x1:
		var next := _continuation(s)
		if next == null:
			return s.y1
		s = next
	return s.y_at(x)


## Scrolls the level left by dx (px) under the board.
func _shift_world(dx: float) -> void:
	_distance += dx
	for s in _segs + _rails + _ledges:
		s.x0 -= dx
		s.x1 -= dx
	_goal_x -= dx
	for mark in marks:
		marks[mark] -= Vector2.ONE * dx


func _follow_ground(delta: float) -> void:
	var target := _cam
	var below := _seg_at(_pos.x)
	if _grounded or _rail != null:
		if below != null:
			var ground := below.y_at(_pos.x)
			var framed := ground
			if _grounded:
				# Look ahead along the ground, so a fast ride down a tall ramp stays in view.
				framed = maxf(ground, _ground_ahead(_speed * 0.3))
			# Where both can't hold (riding fast down a tall wall), the floor under the
			# board stays below the band's top over showing the floor ahead.
			target = minf(maxf(_cam, framed - _area.y * camera_band.y), ground - _area.y * camera_band.x)
	else:
		# In the air: frame the board, not the floor under it, which can drop away (off a
		# lip onto a tall wall).
		target = minf(maxf(_cam, _pos.y - _area.y * camera_air_band.y), _pos.y - _area.y * camera_air_band.x)
	# The view takes on more of the board's up or down speed the nearer the board gets to
	# that edge of the screen, so a fast ride or fall can't outrun it, without a jolt
	# when it starts.
	var target_v := 0.0
	var low := (_pos.y - _cam) / _area.y
	if _grounded or _rail != null:
		var climb := _speed * sin(_ground_angle)
		if climb > 0.0:
			target_v = climb * smoothstep(camera_band.y - 0.15, camera_band.y, low)
		else:
			target_v = climb * smoothstep(camera_band.x + 0.2, camera_band.x, low)
	elif _velocity_y > 0.0 and below != null:
		# Falling into a deep drop (not a hop or a pit): from camera_fall_blend.x down the
		# screen to .y, plus gravity's pull over the spring's response time so it doesn't
		# fall behind as the board speeds up. The board stays up, with what's below in view.
		# The loose board after a slam is followed down anything.
		var deep := 1.0 if _slam_t >= 0.0 else smoothstep(0.3, 0.6, (below.y_at(_pos.x) - _pos.y) / _area.y)
		var fall := _velocity_y + gravity / camera_follow * clampf(_velocity_y / 600.0, 0.0, 1.0)
		target_v = fall * deep * smoothstep(camera_fall_blend.x, camera_fall_blend.y, low)
	elif _velocity_y < 0.0 and _slam_t >= 0.0:
		# The loose board flung up (off a ramp) is followed up too.
		target_v = _velocity_y * smoothstep(camera_air_band.x + 0.25, camera_air_band.x, low)
	# Critically damped spring (exact step) on the offset from the target, so the speed
	# never jumps.
	var k := camera_follow
	var off := _cam - target
	var rel_v := _cam_v - target_v
	var pull := (rel_v + k * off) * delta
	var decay := exp(-k * delta)
	var cam := target + target_v * delta + (off + pull) * decay
	_cam_v = (rel_v - k * pull) * decay + target_v
	# Hard limits keep the board itself in view: they move with it, so they're smooth too.
	# Over a pit there's no bottom limit, so a falling board leaves the view.
	var held := minf(cam, _pos.y - _area.y * camera_top_margin)
	if below != null:
		held = maxf(held, _pos.y - _area.y * (1.0 - camera_bottom_margin))
	if held != cam:
		_cam_v = (held - _cam) / delta
	_cam = held
	position.y = -_cam


## Integrates the speed along the surface for one frame (see the Physics group).
func _step_speed(delta: float) -> void:
	var v := _speed / pixels_per_meter
	var roll := rolling_resistance
	if _rail != null:
		roll *= ledge_friction if _rail.ledge else rail_friction
	# Resistance only ever slows the board down, never pushes it backwards.
	var resistance := roll * slope_g * cos(_ground_angle) + drag * v * v / mass
	v = maxf(v - resistance * delta, 0.0)
	v += (slope_g * sin(_ground_angle) + _push_force(v) / mass) * delta
	_speed = clampf(v, 0.0, max_speed) * pixels_per_meter


## F_push(t) (N): the current kick's half-sine pulse, fading as the board's speed v
## (m/s) approaches foot_speed.
func _push_force(v: float) -> float:
	if _push_left <= 0.0:
		return 0.0
	var phase := 1.0 - _push_left / _push_total
	return _push_peak * sin(PI * phase) * clampf(1.0 - v / foot_speed, 0.0, 1.0)


## power is 0 (lightest) .. 1 (hardest).
func _start_push(power: float) -> void:
	_push_total = lerpf(push_time.x, push_time.y, power)
	_push_peak = lerpf(push_force.x, push_force.y, power)
	_push_left = _push_total
	_set_balance(0.0)  # Putting a foot down ends a manual.
	pushed.emit(power, _speed, false)


func _step_pushes(delta: float) -> void:
	if _push_left > 0.0:
		_push_left = maxf(_push_left - delta, 0.0)
	if _push_left <= 0.0 and not _push_queue.is_empty():
		_start_push(_push_queue.pop_front())


func _step_ground() -> void:
	var w := _wheel_offset()
	# Hand over to the next surface once the back wheel rolls past the end of this one.
	while _pos.x - w > _support.x1:
		var next := _continuation(_support)
		if next != null and _over_crest(next):
			return
		if next == null:
			if _support.next == null and not _support.ledge:
				break  # End of generated floor (never reached in play).
			_leave_ground()  # Rolled off a ledge or got launched.
			return
		_support = next

	var angle := _support.angle()
	var y := _support.y_at(_pos.x)
	var next := _continuation(_support)
	if _pos.x + board_size.x * 0.5 > _support.x1:
		# Floor ahead that the board can't roll onto (platforms have no walls).
		var joint := _joint(_support, _support.next) if _support.next and next == null else &""
		# A higher floor right at the edge is a wall; across a gap the board drops first.
		if joint == &"step_up" and _support.next.x0 - _support.x1 <= 1.0:
			_slam("wall")
			return
		if _pos.x + w > _support.x1:
			if joint == &"too_steep":
				_slam("too steep")
				return
			# Over a crest it'll fly off, the board doesn't tilt over the bend: that would
			# turn its speed forward for a moment before the take-off.
			if next != null and _crest_height(next) < _launch_height():
				# Wheels on two surfaces: the board spans the bend.
				var back := Vector2(_pos.x - w, _support.y_at(_pos.x - w))
				var front := Vector2(_pos.x + w, next.y_at(_pos.x + w))
				angle = (front - back).angle()
				y = (back.y + front.y) * 0.5
			# Ledge or launch ahead: the front wheel hangs, the back wheel carries the board.
	_pos.y = y
	_ground_angle = angle


func _leave_ground() -> void:
	var lip := _support.next != null and _joint(_support, _support.next) == &"launch"
	if is_pushing():
		if not lip:
			_slam("pushing")
			return
		_stop_pushing()
	if _support.ledge:
		_drop_off()  # Off the end of a platform: no catch needed.
		return
	# Off a floor ledge: the nose tips down and the board has to be caught.
	_roll_off()
	if lip:
		_lip_t = lip_pop_time


## Nose tips down off the edge: the board has to be caught.
func _roll_off() -> void:
	_grounded = false
	_take_off()
	var factor := clampf(drop_ref_speed * pixels_per_meter / _speed, drop_factor_range.x, drop_factor_range.y)
	_start_trick(drop_spin * factor)
	dropped.emit()


## How high the speed across `next` would lift the board over the crest onto it (px):
## (v sin(bend))² / 2g; 0 where the ground bends up.
func _crest_height(next: Seg) -> float:
	var bend := next.angle() - _support.angle()
	if bend <= 0.0:
		return 0.0
	var across := _speed * sin(bend)
	return across * across / (2.0 * gravity)


## Lowest crest launch (px): launch_min, or hop_max during a manual (it rides over hops).
func _launch_height() -> float:
	return hop_max if is_balancing() else launch_min


## The back wheel is passing a crest onto `next` (a smooth joint): flies on if it's
## high enough. Returns whether it took off.
func _over_crest(next: Seg) -> bool:
	var height := _crest_height(next)
	if height < _launch_height():
		return false
	_stop_pushing()
	_ground_angle = _support.angle()
	if height <= hop_max:
		_drop_off()
		_hop = true
		_hop_height = height
	else:
		_roll_off()
	_lip_t = lip_pop_time
	return true


func _stop_pushing() -> void:
	_push_left = 0.0
	_push_queue.clear()


func _step_grind() -> void:
	if _pos.x > _rail.x1 and _rail.ledge:
		var next := _continuation(_rail)
		if next != null and next.ledge:
			_rail = next  # Next piece of the same platform edge.
		elif next != null:
			# The edge ran down onto the floor: carry on as a manual (a 50-50 just rolls).
			_support = next
			_grounded = true
			if _fifty:
				_set_balance(0.0)
				landed.emit("roll")
			else:
				_set_balance(_riding_manual, null, false, _balance_tilt)
				landed.emit("to manual")
				callout.emit("nose manual" if _riding_manual > 0.0 else "manual", true)
			_step_ground()
			return
	if _pos.x > _rail.x1:
		# Slid off the end: like rolling off a ledge.
		_from_rail = true
		_drop_off()
		return
	_pos.y = _rail.y_at(_pos.x)
	_ground_angle = _rail.angle()


## Starts or ends a balance trick: direction +1 nose / -1 tail / 0 none, on `rail` if
## grinding; `fifty` for a 50-50 (direction then only marks it as ridden). `tilt` is the
## board's angle against the surface to hold (rad).
func _set_balance(direction: float, rail: Seg = null, fifty := false, tilt := 0.0) -> void:
	var old := _balance_mode()
	_riding_manual = direction
	_rail = rail if direction != 0.0 else null
	_fifty = fifty and direction != 0.0
	_balance_tilt = tilt if direction != 0.0 else 0.0
	var mode := _balance_mode()
	if mode != old:
		balance_changed.emit(mode)


func _balance_mode() -> StringName:
	if _riding_manual == 0.0:
		return &""
	if _fifty:
		return &"fifty"
	return &"grind" if _rail != null else &"manual"


## Which way the board tilts while balancing: +1 nose, -1 tail, 0 level (none or 50-50).
func _tilt_dir() -> float:
	return 0.0 if _fifty else _riding_manual


func _step_air(delta: float) -> void:
	var prev_y := _pos.y
	_velocity_y += gravity * delta
	_pos.y += _velocity_y * delta
	var under := _seg_at(_pos.x)
	if _pos.y > _cam + _area.y and (under == null or _pos.y > under.y_at(_pos.x)):
		_die()  # Fell out of view: there was no ground under it to follow.
		return
	if _velocity_y >= 0.0 and _catches == 2:
		# Rails and platform edges only hold a board with the balance ready, at its middle.
		for rail in _rails + _ledges:
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
		var best_x := _pos.x
		for x in [_pos.x - w, _pos.x + w]:
			for s in _surfaces_at(x):
				var ground := s.y_at(x)
				# The ground scrolls under the board, so slopes rise/fall by speed * tan(angle).
				var reach := 1.0 + absf(_speed * delta * tan(s.angle()))
				if _pos.y >= ground and prev_y <= ground + reach and ground < best_y:
					best = s
					best_y = ground
					best_x = x
		if best != null:
			if _catches == 2 and best.ledge:
				_start_grind(best)  # A grind coming down on a platform top: tailslide or noseslide.
			else:
				_land(best, best_x)
			return
	var nose_x := _pos.x + board_size.x * 0.5
	var ahead := _seg_at(nose_x)
	if ahead != null and ahead.y_at(nose_x) < _pos.y - wall_tolerance:
		_slam("wall")


## Rolling off a platform or a rail end: no catch needed, but the board keeps its angle
## and the landing rules hold, so a catch can be needed to land (or wanted, for a manual).
func _drop_off() -> void:
	_grounded = false
	_take_off()
	_start_trick(0.0)
	_needs_catch = false
	_locked = true
	_lock_angle = _ground_angle  # The surface it left (a grind's tilt ends with it).
	dropped.emit()


## Leaving a surface: splits the speed along it into horizontal (_speed while in the
## air) and vertical parts, (v cos(a), v sin(a)).
func _take_off() -> void:
	_velocity_y = _speed * sin(_ground_angle)
	_speed *= cos(_ground_angle)


## Slams if touching down on `surface` now would be harder than a max_fall drop.
func _too_hard(surface: Seg) -> bool:
	if max_fall <= 0.0:
		return false
	var a := surface.angle()
	var into := maxf(_velocity_y * cos(a) - _speed * sin(a), 0.0)  # Speed into the surface.
	if into * into <= 2.0 * gravity * max_fall:
		return false
	_slam("fell too far")
	return true


## Touching down on `surface`: keeps the velocity's component along it as the new
## speed; the part into the surface is absorbed by the legs.
func _touch_down(surface: Seg) -> void:
	var a := surface.angle()
	_speed = clampf(_speed * cos(a) + _velocity_y * sin(a), 0.0, max_speed * pixels_per_meter)
	_velocity_y = 0.0


func _step_hold(delta: float) -> void:
	if _holding and _catches == 1 and _board_trick == &"":
		_hold_t += delta
		if _hold_t >= hold_delay:
			_ready_balance(_hold_offset)


func _start_trick(spin: float) -> void:
	_holding = false  # A finger still down from the last trick doesn't count.
	_in_trick = true
	_needs_catch = true
	_locked = false
	_catches = 0
	_popped = false
	_board_trick = &""
	_board_trick_done = &""
	_grounded = false
	_nollie_spin = false
	_past_vertical = false
	_hop = false
	_set_balance(0.0)
	_angular_velocity = spin


func _update_airborne() -> void:
	var airborne := _in_trick and _lip_t <= 0.0
	if airborne != _airborne:
		_airborne = airborne
		airborne_changed.emit(_airborne)


## Touches down on `on`, where the wheel at x met it.
func _land(on: Seg, x: float) -> void:
	if on.stairs > 0:
		_slam("landed on the stairs")
		return
	_impact = Vector2(_speed, _velocity_y)
	if _too_hard(on):
		return
	if absf(on.y_at(_pos.x) - on.y_at(x)) > land_snap:
		# A wheel met a steep surface well above the middle of the board: bring that
		# spot under the board instead of dropping the board down to it.
		_shift_world(x - _pos.x)
	_touch_down(on)
	_grounded = true
	_support = on
	_ground_angle = on.angle()
	_pos.y = on.y_at(_pos.x)
	var was_trick := _in_trick
	var hop := _hop
	_in_trick = false
	_hop = false
	_locked = false
	_from_rail = false
	_lip_t = 0.0
	if not was_trick:
		landed.emit("roll")
		return
	if _board_trick != &"":
		_slam("landed mid-" + _board_trick)
		return
	if _catches == 0 and _needs_catch:
		_slam("no catch")
		return
	var trick := _trick_prefix()
	var tilt := _tilt_against(_ground_angle)
	if _catches >= 2 and absf(tilt) > fifty_band:
		# Balance ready and touching down on the tail or the nose: a manual. (Level, it
		# just lands.)
		if absf(tilt) > manual_max_angle:
			_slam("nose strike" if tilt > 0.0 else "tail strike")
			return
		_set_balance(signf(tilt), null, false, deg_to_rad(tilt))
		var manual := trick + ("nose manual" if tilt > 0.0 else "manual")
		landed.emit(manual)
		callout.emit(manual, true)
		return
	var error := rad_to_deg(absf(_angle - _ground_angle))
	if hop and _catches == 0 and _hop_height <= hop_level_free:
		error = 0.0  # A small hop: the wheels just come down, at any angle.
	if error > land_tolerance:
		_slam("off by %d°" % roundi(error))
		return
	if hop and _catches == 0:
		landed.emit("roll")  # Rolled through a hop: nothing to score.
		return
	landed.emit(trick + "clean" if trick else "clean")
	if _popped:
		callout.emit(_pop_callout(trick.strip_edges()), false)


## Locks onto a rail or platform edge with the balance ready: like landing a manual on it.
func _start_grind(rail: Seg) -> void:
	_impact = Vector2(_speed, _velocity_y)
	if _too_hard(rail):
		return
	_touch_down(rail)
	_ground_angle = rail.angle()
	_pos.y = rail.y_at(_pos.x)
	_in_trick = false
	_locked = false
	if _board_trick != &"":
		_slam("landed mid-" + _board_trick)
		return
	var trick := ("double " if _from_rail else "") + _trick_prefix()
	# Named from how the board meets it, whatever side CATCH was held on.
	var tilt := _tilt_against(_ground_angle)
	if absf(tilt) > grind_max_angle:
		_slam("off by %d° on %s" % [roundi(absf(tilt)), "ledge" if rail.ledge else "rail"])
		return
	if absf(tilt) <= fifty_band:
		# 50-50: both trucks on it, board level along it.
		_set_balance(1.0, rail, true)
		trick += "50-50 grind"
	else:
		_set_balance(signf(tilt), rail, false, deg_to_rad(tilt))
		if rail.ledge:
			trick += "noseslide" if tilt > 0.0 else "tailslide"
		else:
			trick += "nosegrind" if tilt > 0.0 else "5-0 grind"
	landed.emit(trick)
	callout.emit(trick, true)


## The board's angle against a surface at `surface_angle`, in degrees: positive nose down.
func _tilt_against(surface_angle: float) -> float:
	return rad_to_deg(wrapf(_angle - surface_angle, -PI, PI))


func _step_rotation(delta: float) -> void:
	if _grounded or _rail != null:
		_angular_velocity = 0.0
		var target := _ground_angle + _balance_tilt  # The angle it touched down at.
		_angle = lerpf(_angle, target, 1.0 - exp(-land_settle * delta))
	elif _locked:
		if _past_vertical:
			_angle = move_toward(_angle, _lock_angle, deg_to_rad(catch_slow_turn) * delta)
		else:
			_angle = lerpf(_angle, _lock_angle, 1.0 - exp(-lock_snap * delta))
	elif _nollie_spin:
		_angle = minf(_angle + _angular_velocity * delta, deg_to_rad(nollie_spin_cap))
	else:
		_angle += _angular_velocity * delta
		_angular_velocity *= exp(-spin_damping * delta)
	if not _grounded and _rail == null and absf(_angle) > deg_to_rad(catch_slow_after):
		_past_vertical = true


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


## Floor and platform tops under x.
func _surfaces_at(x: float) -> Array[Seg]:
	var found: Array[Seg] = []
	var ground := _seg_at(x)
	if ground != null:
		found.append(ground)
	for ledge in _ledges:
		if x >= ledge.x0 and x <= ledge.x1:
			found.append(ledge)
	return found


## The surface the board rolls onto past the end of `s`: its next piece if the joint is
## smooth, else floor or a platform top carrying on from where `s` ends at the same
## height and a rideable angle (e.g. a bridge over a pit). null if there is none.
func _continuation(s: Seg) -> Seg:
	if s.next != null and _joint(s, s.next) == &"smooth":
		return s.next
	for other: Seg in _segs + _ledges:
		if other == s or s.x1 < other.x0 - 1.0 or s.x1 >= other.x1:
			continue
		var bend := rad_to_deg(other.angle() - s.angle())
		if absf(other.y_at(s.x1) - s.y1) <= 2.0 and absf(bend) <= max_transition:
			return other
	return null


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
				_append_platform(segment.width, segment.get("step", 0.0), segment.get("rise", 0.0),
						segment.get("gap", 0.0))
				_segs.back().stairs = segment.get("stairs", 0)
				if segment.has("rail"):
					_add_rail(_segs.back(), segment.rail)
				if segment.has("platform"):
					_add_platform(_segs.back(), segment.platform, segment.get("deck", 0.0))
				if segment.has("mark"):
					_mark(segment)
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
func _append_platform(width: float, step: float, rise: float, gap := 0.0) -> void:
	var last: Seg = _segs.back()
	if step < 0.0:
		# The board must be able to land on `last` and pop again before this wall.
		# Sized for max speed, since the player can push up to it before arriving.
		# Plus a board length: rolling off a ledge, the tail leaves it last.
		var room := top_speed * pixels_per_meter * (_last_arrival_time + reaction_time) + board_size.x
		if last.x1 - last.x0 < room:
			# Extend with flat ground (not along the slope, which could leave the screen).
			var end := Vector2(last.x1, last.y1)
			var extension := Seg.new(end, end + Vector2(room - (last.x1 - last.x0), 0.0))
			last.next = extension
			last = extension
			_segs.append(last)
		_last_arrival_time = _full_pop_landing_time(-step)
	elif step > 0.0:
		_last_arrival_time = sqrt(2.0 * step / gravity)
	else:
		_last_arrival_time = 0.0
	# Random gaps scale with speed so they're measured in time, not pixels.
	gap += _speed * randf_range(gap_time.x, gap_time.y)
	var from := Vector2(last.x1 + gap, last.y1 + step)
	last.next = Seg.new(from, from + Vector2(width, rise))
	_segs.append(last.next)


func _mark(segment: Dictionary) -> void:
	var span := Vector2(_segs.back().x0, _segs.back().x1)
	if segment.has("rail"):
		span = Vector2(_rails.back().x0, _rails.back().x1)
	elif segment.has("platform"):
		var top: Array[Seg] = _platforms.back().top
		span = Vector2(top[0].x0, top.back().x1)
	marks[segment.mark] = span


## Adds a rail above `on`, parallel to it: rail = Vector3(start offset, length, height).
## Or rail = [Vector2(x, height), Vector2(x, height)]: a straight rail between two points,
## x from the start of `on` and height above its (extended) surface line, so it can slope
## down across a gap or start before `on` (negative x).
func _add_rail(on: Seg, rail) -> void:
	if rail is Array:
		var a: Vector2 = rail[0]
		var b: Vector2 = rail[1]
		_rails.append(Seg.new(Vector2(on.x0 + a.x, on.y_at(on.x0 + a.x) - a.y),
				Vector2(on.x0 + b.x, on.y_at(on.x0 + b.x) - b.y)))
		return
	var line: Vector3 = rail
	var x0 := on.x0 + line.x
	var x1 := x0 + line.y
	_rails.append(Seg.new(Vector2(x0, on.y_at(x0) - line.z), Vector2(x1, on.y_at(x1) - line.z)))


## Adds a platform on `on`: its top runs through `points`, each Vector2(x offset from
## the start of `on`, height above `on` there). It's drawn down to the floor, or as a
## slab `deck` px thick (a bridge).
func _add_platform(on: Seg, points: Array, deck := 0.0) -> void:
	var chain: Array[Seg] = []
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var from := Vector2(on.x0 + a.x, on.y_at(on.x0 + a.x) - a.y)
		var to := Vector2(on.x0 + b.x, on.y_at(on.x0 + b.x) - b.y)
		var piece := Seg.new(from, to)
		piece.ledge = true
		if not chain.is_empty():
			chain.back().next = piece
		chain.append(piece)
	_platforms.append({top = chain, deck = deck})
	_ledges.append_array(chain)


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
	if forgiving:
		_recover(reason)
		return
	_dead = true
	_slam_t = 0.0
	_let_go()
	slammed.emit(reason)


## The rider is off: the board flies on as a loose body with the velocity it had,
## tumbling forward.
func _let_go() -> void:
	_slam_distance = _distance
	if _impact != Vector2.ZERO:
		_body_v = _impact  # Slammed touching down: it hits with the speed it came down at.
	elif _grounded or _rail != null:
		_body_v = Vector2.from_angle(_ground_angle) * _speed
	else:
		_body_v = Vector2(_speed, _velocity_y)
	_angular_velocity = maxf(slam_spin * _body_v.length() / pixels_per_meter, 3.0)
	_grounded = false
	_rail = null
	_slide = 0.0


## Forgiving mode instead of a slam: back on the floor under the board (on the step it
## hit, for a wall), level, rolling at least at start_speed, nothing in progress.
func _recover(reason: String) -> void:
	var under: Seg = null
	if reason == "wall":
		under = _seg_at(_pos.x + board_size.x * 0.5)
	if under == null:
		under = _seg_at(_pos.x)
	if under == null:
		for s in _segs:
			if s.x0 > _pos.x:
				under = s
				break
	if under == null:
		return
	_set_balance(0.0)
	_in_trick = false
	_locked = false
	_catches = 0
	_holding = false
	_board_trick = &""
	_board_trick_done = &""
	_push_left = 0.0
	_push_queue.clear()
	_support = under
	_grounded = true
	_ground_angle = under.angle()
	_pos.y = under.y_at(_pos.x)
	_angle = _ground_angle
	_angular_velocity = 0.0
	_velocity_y = 0.0
	_speed = maxf(_speed, start_speed * pixels_per_meter)
	_update_airborne()
	forgiven.emit(reason)


func _step_slam(delta: float) -> void:
	_slam_t += delta
	_step_loose(delta)
	_velocity_y = _body_v.y  # For the view.
	_follow_ground(delta)
	queue_redraw()
	if _slam_t >= slam_duration:
		_slam_t = -1.0
		game_over.emit()


## Moves the loose board: gravity, spin, bouncing off and sliding along floors and
## platform tops, and stopping against a step up. The level stays put meanwhile.
func _step_loose(delta: float) -> void:
	var prev := _pos
	_body_v.y += gravity * delta
	# The level scrolls under it, as while riding.
	var dx := _body_v.x * delta
	_shift_world(dx)
	prev.x -= dx
	_pos.y += _body_v.y * delta
	_angle += _angular_velocity * delta
	var ground := _seg_at(_pos.x)
	var was := _seg_at(prev.x)
	if ground != null and was != null and ground != was and _joint(was, ground) == &"step_up" \
			and ground.y_at(_pos.x) < prev.y - 1.0:
		# Ran into a step up: knocked back.
		_shift_world(prev.x - _pos.x)
		_body_v.x *= -slam_bounce
	var best: Seg = null
	for surface in _surfaces_at(_pos.x):
		var top := surface.y_at(_pos.x)
		if _pos.y >= top and prev.y <= surface.y_at(prev.x) + 2.0 and (best == null or top < best.y_at(_pos.x)):
			best = surface
	if best == null:
		return
	_pos.y = best.y_at(_pos.x)
	var along := Vector2.from_angle(best.angle())
	var up := Vector2(along.y, -along.x)
	var into := _body_v.dot(up)
	if into < 0.0:
		_body_v -= up * into * (1.0 + slam_bounce)
		_angular_velocity *= 0.6
	if into > -150.0:
		# Resting on it: slides to a stop, lying flat (wheels or deck down).
		_body_v -= along * _body_v.dot(along) * (1.0 - exp(-slam_friction * delta))
		var flat := best.angle() + PI * roundf((_angle - best.angle()) / PI)
		_angle = lerpf(_angle, flat, 1.0 - exp(-12.0 * delta))
		_angular_velocity *= exp(-10.0 * delta)


func _draw() -> void:
	for s in _segs:
		var bottom := maxf(_cam + _area.y, maxf(s.y0, s.y1) + 1.0)
		var points := _surface_line(s)
		points.append_array([Vector2(s.x1, bottom), Vector2(s.x0, bottom)])
		# UVs in world space (scrolled by distance travelled) so the texture moves with the ground.
		var uvs := PackedVector2Array()
		for p in points:
			uvs.append((p + Vector2(_distance, 0.0)) / float(ground_tile))
		draw_colored_polygon(points, Color.WHITE, uvs, _ground_texture)
	for s in _segs:
		draw_polyline(_surface_line(s), edge_color, 5.0)
	_draw_platforms()
	_draw_rails()
	_draw_goal()
	_draw_board()


## The top edge of a floor piece, left to right: straight, or stepped for stairs.
func _surface_line(s: Seg) -> PackedVector2Array:
	var line := PackedVector2Array([Vector2(s.x0, s.y0)])
	if s.stairs > 0:
		var run := (s.x1 - s.x0) / s.stairs
		var drop := (s.y1 - s.y0) / s.stairs
		for i in s.stairs:
			line.append(Vector2(s.x0 + run * (i + 1), s.y0 + drop * i))
			line.append(Vector2(s.x0 + run * (i + 1), s.y0 + drop * (i + 1)))
		return line
	line.append(Vector2(s.x1, s.y1))
	return line


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


func _draw_platforms() -> void:
	for platform in _platforms:
		var chain: Array = platform.top
		var first: Seg = chain[0]
		var last: Seg = chain.back()
		var points := PackedVector2Array([Vector2(first.x0, first.y0)])
		for piece: Seg in chain:
			points.append(Vector2(piece.x1, piece.y1))
		if platform.deck > 0.0:
			for i in range(chain.size(), -1, -1):
				points.append(points[i] + Vector2(0.0, platform.deck))
		else:
			# Down to the floor where there is one; over a gap, a slab overhang_depth thick.
			var x := last.x1
			while true:
				var ground := _seg_at(x)
				var top := _platform_top(chain, x)
				points.append(Vector2(x, ground.y_at(x) if ground else top + overhang_depth))
				if x <= first.x0:
					break
				x = maxf(x - 16.0, first.x0)
		var uvs := PackedVector2Array()
		for p in points:
			uvs.append((p + Vector2(_distance, 0.0)) / float(ground_tile))
		draw_colored_polygon(points, platform_tint, uvs, _ground_texture)
		for piece: Seg in chain:
			draw_line(Vector2(piece.x0, piece.y0), Vector2(piece.x1, piece.y1), rail_color, 5.0)


## Height of a platform's top at x.
func _platform_top(chain: Array, x: float) -> float:
	for piece: Seg in chain:
		if x <= piece.x1:
			return piece.y_at(x)
	return chain.back().y1


func _draw_rails() -> void:
	for rail in _rails:
		var length := rail.x1 - rail.x0
		var posts := maxi(2, ceili(length / 240.0) + 1)
		for i in posts:
			var x := rail.x0 + 12.0 + (length - 24.0) * i / (posts - 1)
			var ground := _seg_at(x)
			if ground != null:  # No posts over gaps: the rail spans them.
				draw_line(Vector2(x, rail.y_at(x)), Vector2(x, ground.y_at(x)), rail_post_color, 6.0)
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
	var pose := board_pose()
	draw_board_at(self, pose[0], pose[1], pose[2])


## Where and how the board is drawn this frame: [center, angle, scale], with the
## scale's signs and size carrying flips, shuvits and slides. Ghosts reuse it.
func board_pose() -> Array:
	# Local space: x = -48..48, wheels touch y = +14, kicktails reach y = -13.
	# The board is placed so an anchor point in local space sits on a point in the
	# world: the wheel contact midpoint, or the rolling wheel during a manual.
	var board_scale := board_size / Vector2(96.0, 28.0)
	var anchor := _pos
	var local_anchor := Vector2(0.0, 14.0)
	if (_grounded or _rail != null) and _tilt_dir() != 0.0 and _slam_t < 0.0:
		var wheel := _riding_manual  # Manual (-1) rolls on the back wheel, nose manual (+1) on the front.
		anchor = _pos + Vector2(wheel * _wheel_offset(), 0.0).rotated(_ground_angle)
		local_anchor = Vector2(wheel * WHEEL_X, 14.0)
	if _board_trick != &"" and _slam_t < 0.0:
		var phase := 1.0 - _board_trick_left / trick_time
		if _board_trick.ends_with("flip"):
			# Roll around the long axis about the middle of the board.
			anchor = _pos + (Vector2(0.0, -7.0) * board_scale).rotated(_angle)
			local_anchor = Vector2(0.0, -7.0)
			board_scale.y *= cos(phase * TAU)
		else:
			# Shuvit: half a turn around the vertical axis, quicker than the catch window.
			var spin := clampf(phase * trick_time / shuvit_spin_time, 0.0, 1.0)
			board_scale.x *= cos(spin * PI)
	if _slide > 0.0 and _slam_t < 0.0:
		# Slide: the board swings across the ledge (seen end-on, so it shortens) and
		# rests on its tail or nose, with the trucks hanging over the edge.
		var k := smoothstep(0.0, 1.0, _slide)
		board_scale.x *= lerpf(1.0, cos(deg_to_rad(slide_angle)), k)
		if _rail != null and _rail.ledge:
			anchor = _pos
			local_anchor = local_anchor.lerp(Vector2(signf(_riding_manual) * 40.0, -1.0), k)
	return [anchor - (local_anchor * board_scale).rotated(_angle), _angle, board_scale]


## Draws a board on `canvas` at a pose from board_pose(), faded by `alpha` and tinted
## `deck` (player_color by default).
func draw_board_at(canvas: CanvasItem, center: Vector2, angle: float, board_scale: Vector2,
		alpha := 1.0, deck := player_color) -> void:
	canvas.draw_set_transform(center, angle, board_scale)
	for x in [-WHEEL_X, WHEEL_X]:
		canvas.draw_rect(Rect2(x - 7.0, -1.0, 14.0, 5.0), Color(truck_color, alpha))
		canvas.draw_circle(Vector2(x, WHEEL_Y), WHEEL_R, Color(wheel_color, alpha))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-48, -13), Vector2(-38, -7), Vector2(38, -7), Vector2(48, -13),
		Vector2(49, -8), Vector2(38, -1), Vector2(-38, -1), Vector2(-49, -8),
	]), Color(deck if board_scale.y >= 0.0 else deck.darkened(0.45), alpha))
	canvas.draw_set_transform(Vector2.ZERO)


## Level coordinates: px from where the level's first segment starts (x) and from the
## start platform's height (y). They're the same on every screen size, so ghosts of
## other players line up; screen coordinates depend on the play area's size.
func to_level(screen: Vector2) -> Vector2:
	return Vector2(screen.x + _distance - _origin.x, screen.y - _origin.y)


func from_level(level: Vector2) -> Vector2:
	return Vector2(level.x - _distance + _origin.x, level.y + _origin.y)
