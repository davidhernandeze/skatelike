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
## The player did `action` (Act) with arguments a and b, applied before step `at_tick`.
## Replaying the same actions at the same ticks plays the run out the same (ghosts).
signal acted(at_tick: int, action: int, a: float, b: float)
## A landing's parts for lines (see FlowButton): the air trick ("kickflip", "nollie", or
## "" for none), the manual or grind it went into ("" for none), and whether the wheels
## came down (which ends the line).
signal line_event(air: String, balance: String, wheels_down: bool)

## Everything the player can do, as recorded and replayed: see act().
enum Act { POP, PUSH, PRESS_CATCH, RELEASE_CATCH, BOARD_TRICK, BALANCE_POP, END_BALANCE, LOSE_BALANCE,
		BODY_180 }
const TRICKS: Array[StringName] = [&"kickflip", &"heelflip", &"shuvit", &"front shuvit"]
## Physics runs in fixed steps, so a run plays out the same at any frame rate and on any
## device, and can be replayed from its actions; drawing blends between steps.
## The world's pixel size: screen px per art pixel for the board (BoardView.pixel) and
## the terrain tiles. The skater has its own (skater_pixel), sized to the board.
const PIXEL := 3
const STEP_RATE := 120
const STEP := 1.0 / STEP_RATE
## At most this many steps per frame; a longer stall just slows the game down.
const MAX_STEPS := 12
## A snapshot of the state is kept every this many steps (see get_state()).
const SNAPSHOT_STEPS := 120
## The state a snapshot holds (besides the play area and the surfaces ridden).
const STATE := [&"tick", &"_cam", &"_cam_v", &"_dead", &"_cleared", &"_speed", &"_distance",
	&"_score", &"_pos", &"_velocity_y", &"_grounded", &"_ground_angle", &"_in_trick",
	&"_airborne", &"_angle", &"_angular_velocity", &"_locked", &"_lock_angle",
	&"_first_lock_angle", &"_catches", &"_holding", &"_hold_t", &"_hold_offset",
	&"_needs_catch", &"_manual_dir", &"_riding_manual", &"_fifty", &"_balance_tilt",
	&"_from_rail", &"_board_trick", &"_board_trick_t", &"_board_trick_turns", &"_trick_flips", &"_trick_shuvs",
	&"_trick_flip_kind", &"_trick_shuv_kind", &"_trick_window", &"_slide", &"_board_trick_done",
	&"_board_trick_late", &"_popped", &"_pop_nose", &"_pop_spin", &"_past_vertical",
	&"_hop", &"_hop_height", &"_lip_t", &"_slam_t", &"_slam_distance", &"_body_v", &"_impact",
	&"_push_left", &"_push_total", &"_push_peak", &"_push_queue", &"_body_turn", &"_body_turns",
	&"_body_front", &"_switch", &"_pop_stance", &"_dir", &"_air_base", &"_heading", &"_goofy"]

## A straight surface from (x0, y0) to (x1, y1): floor (solid below), the top of a
## platform (solid only from above) or a rail.
class Seg:
	var x0: float
	var y0: float
	var x1: float
	var y1: float
	## Following piece of the same floor or platform top (null at the end), and the one
	## before it (null at the start): see link().
	var next: Seg
	var prev: Seg
	## Part of a platform top.
	var ledge := false
	## Number of stairs drawn on this floor piece (0 = a plain surface). Stairs can't
	## be ridden or landed on: ollie them or grind their handrail.
	var stairs := 0
	## Props standing on it (drawn only): [texture, px from its start] each.
	var props: Array = []
	## Obstacles standing on it (see _add_obstacles): {texture, at (px from its start to
	## the middle), profile (height in px over the floor per texel column)} each.
	var obstacles: Array = []

	## Makes `after` the piece following this one.
	func link(after: Seg) -> void:
		next = after
		after.prev = self

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
## Spin given on pop (rad/s, at full strength): a tail pop lifts the nose
## (anticlockwise), a nose pop the tail. It doesn't decay: the board keeps turning until
## the catch or pop_spin_cap (deg, either way), enough to turn it to a near-vertical
## wall and past it. Other spins (roll-offs, after a trick's kick) decay by spin_damping.
@export var jump_spin := 2.5
@export var spin_damping := 4.0
@export var pop_spin_cap := 120.0
## Popping out of a manual or grind: the highest it goes, as a fraction of a normal pop's
## height, and its spin, as a fraction of jump_spin.
@export var balance_pop_height := 0.6
@export var balance_pop_spin := 0.6
## A board that turned past this angle (deg, either way) is caught back slowly: the
## catch turns it all the way back at catch_slow_turn (deg/s) instead of snapping, so
## it can be timed to meet a steep wall.
@export var catch_slow_after := 90.0
@export var catch_slow_turn := 180.0
## How fast the board settles to the ground angle after landing.
@export var land_settle := 18.0


@export_group("Drop-off")
## Nose-down spin when the wheels leave a floor ledge at drop_ref_speed (rad/s); the
## board has to be caught. Platforms and rail ends drop off flat, no catch needed.
@export var drop_spin := 2.5
## A step down this high or less (px), onto floor right after the edge, isn't a ledge to
## catch: the board drops off it flat like off a platform, no catch needed, and pushing
## off it doesn't slam (the push just ends).
@export var small_drop := 90.0
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
## How many progress marks a level gets (progress()).
@export var progress_marks := 20
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
## A flip keeps rolling, one turn per trick_time (s), and a shuvit keeps turning, half a
## turn per shuvit_spin_time (s), until caught; the catch counts the turns (rounded,
## at least one): a double kickflip, a 360 shuvit. Landing still spinning slams.
@export var trick_time := 0.4
@export var shuvit_spin_time := 0.2
## Combos: each trick tapped keeps the combo open this much longer (s), and tricks tapped
## while it's open join it: flips add flip turns, shuvits half turns (two shuvits and a
## kickflip make a 360 flip). The board spins the whole combo in one cycle, both ways
## at once, and loops it until caught; the catch counts the loops.
@export var combo_unit := 0.2
## Kicking a trick works against the pop's spin: each tap turns the board's pitch spin
## around at this fraction of its speed (a kickflip off an ollie brings the nose back
## down at half the speed it was coming up).
@export var trick_counter_spin := 0.5
## A body 180 (swiping sideways while holding the pop pad) turns the skater and board
## around half a turn in this time (s), and keeps turning until caught: the catch settles
## it on the nearest half turn (180, 360, 540...). Landing before it's settled slams.
@export var body_turn_time := 0.35
## A twisted pop (one with a body 180) keeps only this share of the pop's spin: the
## board barely tips nose up or down.
@export var twist_pop_spin := 0.1
## Caught this little past a half turn (share of one), it settles back on it rather than
## turning on to the next.
@export var body_catch_slack := 0.15
## The quick turn of the head that ends a 180 the way the rider rides after it (s, see
## skater_pose()).
@export var view_flip_time := 0.12

@export_group("Landing")
## Allowed difference between the board angle and the ground angle at touchdown (deg).
@export var land_tolerance := 15.0

@export_group("Transfers and fakie")
## Leaving a ramp at least this steep going up (deg), off its lip or with a pop, is a
## transfer: the board keeps its angle (no catch needed; catches and the pop's spin are
## measured from it, see _air_base). Coming down onto a wall that faces back the way it
## came, it rolls down it backward: fakie.
@export var transfer_angle := 60.0
## How fast the view pans to show more of where the board's going when it changes
## direction (1/s).
@export var pan_rate := 2.5
@export_group("")
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
## Thickness of a floor with another floor under it (px).
@export var floor_slab := 40.0
## Size of one ground texture tile (px), for the generated concrete.
@export var ground_tile := 128
## The terrain skin (made with Sprite Fusion, see assets/tiles): a seamless fill tiled
## inside the ground and a strip along its surface (its top row on the line), drawn
## `tile_pixel` screen px per texel. Null: the generated concrete and a plain line.
@export var fill_texture: Texture2D = preload("res://assets/tiles/concrete_fill.png")
@export var edge_texture: Texture2D = preload("res://assets/tiles/concrete_edge.png")
@export var tile_pixel := PIXEL
## The stage's asset group (SpotArt), "" for the default look: set by configure() from
## the level's `art`. Its props and obstacles are drawn at the world's pixel size (PIXEL);
## props (only scenery) see-through by prop_alpha, so they read as not in the way.
var art := ""
@export var prop_alpha := 0.7
## How far into an obstacle's outline (px) the board can get before it hits it.
@export var obstacle_tolerance := 6.0
## An obstacle's top that can be landed on: its columns at least this share of its height
## (the hood, the roof, the trunk; not the bumpers' rounded ends).
@export var obstacle_top_share := 0.4
@export var truck_color := Color(0.7, 0.72, 0.78)
@export var wheel_color := Color(0.95, 0.95, 0.95)
## The skater (Sprite Fusion, see assets/characters), drawn `skater_pixel` screen px per
## art pixel with its feet on the deck. Null: the placeholder figure below.
@export var skater_texture: Texture2D = preload("res://assets/characters/skater.png")
## Screen px per art pixel of the skater, at the default board_size: 5 makes the 35 px
## sprite about 1.8 boards tall, a real rider's crouched height on a real deck.
@export var skater_pixel := 5
## The push (Sprite Fusion animate): `skater_push_frames` square frames side by side,
## played once over each push. Null: the still sprite while pushing too.
@export var skater_push: Texture2D = preload("res://assets/characters/skater_push.png")
@export var skater_push_frames := 8
## The placeholder skater (draw_skater_at): shirt, pants, skin and shoe colors.
@export var shirt_color := Color(0.9, 0.35, 0.3)
@export var pants_color := Color(0.2, 0.24, 0.36)
@export var skin_color := Color(0.93, 0.76, 0.62)
@export var shoe_color := Color(0.12, 0.12, 0.14)
@export var goal_color := Color(0.4, 0.95, 0.5)

const WHEEL_X := 28.0
## How far off the left of the view the level is kept (px).
const PRUNE_BEHIND := 3000.0
## Highest a step ahead can be and still be a wall the board flies into (px): a floor
## higher than that is overhead (see `at` in Levels).
const WALL_REACH := 150.0
const WHEEL_Y := 7.0
const WHEEL_R := 7.0

## The 3D board drawing this runner's board, if any (it sets itself here).
var board_view: Node2D
## The skater rig (SkaterView) drawing this runner's skater, when set: it skips its own.
var skater_view: Node2D

var _area := Vector2.ZERO
## Steps run so far.
var tick := 0
## Stepped by its owner with step() instead of by frames (a ghost's simulation).
var manual := false
## Time not yet stepped (s).
var _acc := 0.0
## State after the step before the last one, and the blend of it with the last one
## that's drawn this frame.
var _prev_pos := Vector2.ZERO
var _prev_angle := 0.0
var _prev_distance := 0.0
var _prev_cam := 0.0
var _view_pos := Vector2.ZERO
var _view_angle := 0.0
var _view_dx := 0.0
var _view_cam := 0.0
## Snapshot taken at the latest multiple of SNAPSHOT_STEPS, not yet collected.
var _snapshot: Array = []
## Random terrain, seeded per level so it comes out the same for everyone.
var _rng := RandomNumberGenerator.new()
## Top of the view in this node's coordinates (the node is moved up by it).
var _cam := 0.0
## How fast the view is moving down (px/s).
var _cam_v := 0.0
var _started := false
var _dead := false
var _cleared := false
var _speed := 0.0
## Way the board's rolling: +1 forward (right), -1 backward (left): it rolls back down a
## slope it stopped on. _speed is always the size of the speed; this is its direction.
var _dir := 1.0
## How far off the left of the view the level is kept (px): PRUNE_BEHIND, or all of it
## in a level laid out for riding back through (one with `at`, see configure).
var _keep_behind := PRUNE_BEHIND
## The start platform (see setup), whose far end stops a board rolling back to it.
var _start_seg: Seg
## The angle air catches and the pop's spin limits are measured from: level, or in a
## transfer's air the ramp's it left (see transfer_angle).
var _air_base := 0.0
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
## Time the board trick in progress has been spinning (s).
var _board_trick_t := 0.0
## Time into the body 180 of this jump (s); negative without one. It's frontside
## (_body_front) or backside: in the normal stance a swipe toward the way you're going
## (right) is frontside; riding switch, the other way.
var _body_turn := -1.0
var _body_front := false
## Half turns the body 180 settles on once caught (0 while it's still turning freely).
var _body_turns := 0
## Stance (see stance_name()). The rider is regular (facing the camera riding normal
## to the right) or goofy (`_goofy`, back to it; the profile's pick, set before setup).
## `_heading` is the way the rider faces along the track (+1 right, -1 left): riding
## normal (or switch) the board rolls that way; riding fakie it rolls the other way, so
## only the board rolling backward gets you there (landing on a wall that faces back,
## rolling back down a slope). A 180 while fakie turns the rider to face the way it rolls:
## riding normal again (a half cab). A nose pop, a push, or a manual or grind out of fakie
## is riding switch instead: the rider takes the way it rolls as its heading without
## turning, the other foot forward. Riding switch: the other way round (after a 180 riding
## normal; another one turns back). `_pop_stance` is how the pop was named.
var _switch := false
var _heading := 1.0
var _goofy := false
var _pop_stance := ""
## Body 180s with board tricks that have their own names: [frontside, trick] -> name.
const BODY_COMBOS := {
	[true, "kickflip"]: "frontside flip",
	[false, "kickflip"]: "backside flip",
	[true, "heelflip"]: "frontside heelflip",
	[false, "heelflip"]: "backside heelflip",
	[false, "360 shuvit"]: "bigspin",
	[true, "360 front shuvit"]: "frontside bigspin",
	[false, "360 flip"]: "bigspin flip",
	[true, "laser flip"]: "frontside bigspin heelflip",
}
## Loops of its combo the board trick done (caught) made.
var _board_trick_turns := 1
## The combo: flips and shuvit half turns per loop, which way each goes (the first one
## tapped decides), and how long more tricks can still join it (s).
var _trick_flips := 0
var _trick_shuvs := 0
var _trick_flip_kind := &""
var _trick_shuv_kind := &""
var _trick_window := 0.0
## Combos with their own names: [shuvit kind, degrees, flip kind] -> name.
const COMBO_NAMES := {
	[&"shuvit", 180, &"kickflip"]: "varial kickflip",
	[&"shuvit", 360, &"kickflip"]: "360 flip",
	[&"front shuvit", 180, &"kickflip"]: "hardflip",
	[&"front shuvit", 180, &"heelflip"]: "varial heelflip",
	[&"shuvit", 180, &"heelflip"]: "inward heelflip",
	[&"front shuvit", 360, &"heelflip"]: "laser flip",
}
## 0..1: how far the board is swung into a slide (eases towards 1 on a ledge, 0 otherwise).
var _slide := 0.0
## Board trick completed (caught) in the current jump, or &"".
var _board_trick_done := &""
## The board trick started after a catch (late).
var _board_trick_late := false
## The current trick started with a pop (board tricks need one; drop-offs don't allow them).
var _popped := false
## That pop was off the end ahead, the way the board rolls (nollie): the nose rolling
## forward, the tail rolling backward.
var _pop_nose := false
## The free spin is a pop's: undamped, capped at pop_spin_cap.
var _pop_spin := false
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
## The skater figure, drawing only (not in STATE): how crouched (0 standing .. 1 tucked),
## whether on the board last step, and after a slam where the rider came off (step
## coordinates, with _distance then), its velocity (px/s) and how long ago (s; -1 = riding).
var _crouch := 0.2
var _fig_down := true
## How long a settled body turn has held (s), for the quick turn of the head at its end
## (skater_pose()).
var _view_flip_t := 0.0
var _fall_at := Vector2.ZERO
var _fall_distance := 0.0
var _fall_vy := 0.0
var _fall_vx := 0.0
var _fall_t := -1.0
## Velocity the board came down with this frame, before touchdown took it (px/s): a
## slam on landing lets the board go with it.
var _impact := Vector2.ZERO

var _push_left := 0.0
var _push_total := 0.0
## Peak force of the current push (N).
var _push_peak := 0.0
var _push_queue: Array[float] = []

var _segs: Array[Seg] = []
## The level's props on the start platform ([name, px from its end] each) and the prop
## textures loaded so far (name -> texture), see `art`.
var _start_props: Array = []
var _prop_textures := {}
var _ground_texture: Texture2D
## Screen px one repeat of the ground texture covers.
var _ground_repeat := Vector2.ONE
## The edge strip (edge_texture with hard pixels), null for the plain line.
var _edge_strip: Texture2D
## The skater sprite (nearest filtered) and where its feet are in it (art px): between
## the shoes, on the soles.
var _skater: Texture2D
var _skater_feet := Vector2.ZERO
## The push frames and, per frame, the point in it drawn on the pose's base: the front
## foot kept where it is in the still sprite, so it stays planted while the back leg pushes.
var _push_sheet: Texture2D
var _push_anchors: Array[Vector2] = []
## Time the board spends airborne arriving on the newest platform (s).
var _last_arrival_time := 0.0

var _start_y := 0.7
## Remaining scripted segments: Vector3(width, step, rise), or a Dictionary for a
## platform with a rail (see Levels).
var _segments: Array = []
## Progress (progress()): marks spread evenly along the level's own floor pieces, each
## {seg, t (fraction along it), side (of the board, -1/+1)}, and how many were crossed.
var _progress_marks: Array = []
var _marks_crossed := 0
## The level's own floor pieces as laid (for the progress marks).
var _level_segs: Array[Seg] = []
## Screen position of the level origin (end of the start platform) when the run started.
var _origin := Vector2.ZERO
var _random_left := 0
var _goal_spawned := false
## Finish flag x in play area coordinates; scrolls with the ground.
var _goal_x := INF
## The ground's height at a flag a level places (`goal` in Levels; INF for the usual one
## after the last obstacle): reached rolling past it either way, on that floor.
var _goal_y := INF
## Marked level features: segment `mark` name -> Vector2(start x, end x) of its rail,
## platform or floor piece. Filled as the terrain is generated and scrolled with it
## (tests and bots use them).
var marks := {}


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_apply_skin()
	if skater_texture:
		_skater = _pixel_texture(skater_texture)
		_skater_feet = _feet_anchor(skater_texture.get_image())
		if skater_push:
			_push_sheet = _pixel_texture(skater_push)
			_push_anchors = _push_frame_anchors(skater_texture.get_image(), skater_push.get_image(),
					skater_push_frames)


## The ground's textures from fill_texture and edge_texture (or the generated concrete).
func _apply_skin() -> void:
	if fill_texture:
		_ground_texture = _pixel_texture(fill_texture)
		_ground_repeat = fill_texture.get_size() * tile_pixel
	else:
		_ground_texture = _make_ground_texture()
		_ground_repeat = Vector2(ground_tile, ground_tile)
	_edge_strip = _pixel_texture(edge_texture) if edge_texture else null


## Sets the layout to play; call before setup().
func configure(level: Dictionary) -> void:
	_start_y = level.get("start_y", 0.7)
	_segments.clear()
	for segment in level.get("segments", []):
		if segment is Vector2:
			segment = Vector3(segment.x, segment.y, 0.0)
		_segments.append(segment)
	_random_left = level.get("random", 0)
	_keep_behind = PRUNE_BEHIND
	for segment in _segments:
		if segment is Dictionary and segment.has("at"):
			_keep_behind = INF  # Floors to ride back along, way behind: keep everything.
	max_fall = level.get("max_fall", max_fall)
	_rng.seed = hash(level.get("id", ""))
	_start_props = level.get("start_props", [])
	if level.get("art", "") != "" and level.art != art:
		art = level.art
		fill_texture = SpotArt.fill(art)
		edge_texture = SpotArt.edge(art)
		_prop_textures.clear()
		_apply_skin()


func setup(area: Vector2) -> void:
	_area = area
	if _started or area.x <= 0.0 or area.y <= 0.0:
		return
	_started = true
	_speed = start_speed * pixels_per_meter
	_slide = 0.0
	var ground_y := _area.y * _start_y
	_pos = Vector2(_area.x * player_x_ratio + board_size.x * 0.5, ground_y)
	# Long starting platform so the player has time to get ready.
	# (It reaches a screen back too, for rolling back onto: its far end stops the board.)
	_segs.append(Seg.new(Vector2(-50.0 - _area.x, ground_y), Vector2(_area.x * 1.2 - 50.0, ground_y)))
	_start_seg = _segs[0]
	_support = _segs[0]
	_origin = Vector2(_segs[0].x1, ground_y)
	_add_props(_start_seg, _start_props, _start_seg.x1 - _start_seg.x0)
	_fill_platforms()
	_place_progress_marks()
	_settle_view()
	_snapshot = get_state()


func can_pop() -> bool:
	if _dead or is_pushing():
		return false
	if _lip_t > 0.0 and not _popped and _catches == 0:
		return true  # Just off a lip: still in time to pop it.
	return (_grounded or _rail != null) and not _in_trick


## The rider's chest is to the camera (else the back): regular riding normal to the
## right, or fakie rolling left; goofy riding switch to the right...
func facing_camera() -> bool:
	return (_goofy == _switch) != (_heading < 0.0)


## Rolling the other way to the rider's heading.
func is_fakie() -> bool:
	return _dir != _heading


## A body turn swiped `swipe` (+ right) is frontside: turning the chest toward the way
## the board rolls (else backside).
func swipe_is_frontside(swipe: float) -> bool:
	return (swipe > 0.0) == (facing_camera() == (_dir > 0.0))


## The stance tricks are named with: "fakie", "switch" or "" (normal).
func stance_name() -> String:
	if is_fakie():
		return "fakie"
	return "switch" if _switch else ""


## The way the board rolls changed (`dir`). The rider keeps facing the same way, so
## rolling against its heading is riding fakie, and with it again normal (or switch).
func _set_dir(dir: float) -> void:
	_dir = dir


## Fakie no more: on to switch (a nose pop, a push, a manual or grind out of fakie): the
## rider takes the way it rolls as its heading without turning.
func _fakie_to_switch() -> void:
	if is_fakie():
		_heading = _dir
		_switch = true


func is_pushing() -> bool:
	return _push_left > 0.0 or not _push_queue.is_empty()


## Remaining fraction of the current push (0 when not pushing).
func push_progress() -> float:
	return _push_left / _push_total if _push_left > 0.0 else 0.0


func queued_pushes() -> int:
	return _push_queue.size()


func is_grounded() -> bool:
	return _grounded


## How fast the board rolls along the screen (px/s, + to the right): what the wheels
## turn at while they touch something.
func rolling_velocity() -> float:
	return _dir * _speed


## The wheels touch the ground or a rail (rolling, manualling or grinding).
func wheels_down() -> bool:
	return (_grounded or _rail != null) and _slide <= 0.0 and _fall_t < 0.0


## In the air for the air pads: hops and the moment off a lip still count as riding.
func is_airborne() -> bool:
	return _airborne


## How far along the level the board is, 0..1: the share of the progress marks it has
## crossed (see progress_marks), 1 once it's cleared.
func progress() -> float:
	if _cleared:
		return 1.0
	var crossed := float(_marks_crossed) / maxf(_progress_marks.size(), 1.0)
	return clampf(crossed, 0.0, 0.99)


## Spreads progress_marks marks evenly along the level's own floor pieces (by width), the
## last at the end of the last one. Laying the level out comes first.
func _place_progress_marks() -> void:
	_progress_marks.clear()
	_marks_crossed = 0
	var total := 0.0
	for s in _level_segs:
		total += s.x1 - s.x0
	if total <= 0.0:
		return
	var along := 0.0
	var k := 1
	for s in _level_segs:
		var width := s.x1 - s.x0
		while k <= progress_marks and k * total / progress_marks <= along + width + 0.001:
			var t := clampf((k * total / progress_marks - along) / maxf(width, 0.001), 0.0, 1.0)
			_progress_marks.append({seg = s, t = t, side = signf(_pos.x - lerpf(s.x0, s.x1, t))})
			k += 1
		along += width


## Counts the progress marks the board crosses (either way), on the floor that's under
## the board there: a floor running above or below doesn't count.
func _cross_progress_marks() -> void:
	for mark: Dictionary in _progress_marks:
		if mark.side == 0.0:
			continue  # Crossed already.
		var s: Seg = mark.seg
		var x := lerpf(s.x0, s.x1, mark.t)
		var side := signf(_pos.x - x)
		if side != mark.side and side != 0.0:
			if _seg_at(x, _pos.y) == s:
				mark.side = 0.0
				_marks_crossed += 1
			else:
				mark.side = side


## How far the level has scrolled in all as drawn this frame (px), for things pinned to
## a spot in it.
func scrolled() -> float:
	return _distance - _view_dx


## The board's position as drawn this frame (between the last two steps).
func view_position() -> Vector2:
	return _view_pos


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
		line_event.emit("", "", true)  # Wheels down.
		return
	if rail.ledge:
		_support = rail
		_grounded = true
		line_event.emit("", "", true)  # Rolling along the ledge top.
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
	var from_balance := is_balancing()
	var spin := jump_spin * power * (balance_pop_spin if from_balance else 1.0)
	if from_balance:
		power *= sqrt(balance_pop_height)  # Height goes with the square of the pop speed.
	if _grounded or _rail != null:
		_take_off()
	_lip_t = 0.0
	_velocity_y -= jump_velocity * power
	_from_rail = _rail != null
	_grounded = false
	_start_trick(0.0 if contrary else spin * (1.0 if nose else -1.0))
	_popped = not contrary
	_pop_stance = stance_name()
	_pop_nose = nose and not is_fakie()
	if is_fakie() and nose:
		_pop_stance = "switch"  # Fakie pops the tail; off the nose it's a switch trick (it lands switch).
	_pop_spin = not contrary
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
## do nothing. Catching a board trick completes it and locks the tilt like a first catch;
## a body turn settles on its nearest half turn (_catch_body_turn()).
func lock_tilt(offset: float) -> void:
	if not _in_trick or _dead:
		return
	_catch_body_turn()  # A body turn settles on its half turn with the catch.
	if _board_trick != &"":
		_board_trick_turns = maxi(1, roundi(_board_trick_t / _trick_cycle()))
		_trick_window = 0.0
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
		var x := _pos.x + _dir * _speed * t
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


## A board trick can start (after a pop, one per jump), or join the combo still open.
func can_board_trick() -> bool:
	if not _in_trick or not _popped or _dead or _grounded or _catches >= 2:
		return false
	return (_board_trick == &"" and _board_trick_done == &"") or (_board_trick != &"" and _trick_window > 0.0)


## Starts a flip or shuvit (&"kickflip", &"heelflip", &"shuvit", &"front shuvit"), or adds
## it to the combo still open (see combo_unit). It spins until caught.
func board_trick(kind: StringName) -> void:
	if not can_board_trick():
		return
	if _board_trick == &"":
		_trick_flips = 0
		_trick_shuvs = 0
		_trick_flip_kind = &""
		_trick_shuv_kind = &""
		_trick_window = 0.0
		_board_trick_t = 0.0
		_board_trick_turns = 1
		_board_trick_late = _catches > 0
	if kind.ends_with("shuvit"):
		_trick_shuvs += 1
		if _trick_shuv_kind == &"":
			_trick_shuv_kind = kind
	else:
		_trick_flips += 1
		if _trick_flip_kind == &"":
			_trick_flip_kind = kind
	_trick_window += combo_unit
	_angular_velocity *= -trick_counter_spin
	_pop_spin = false  # Turned back, the pop's spin dies out like any other.
	_board_trick = StringName(_combo_name(1))
	trick_started.emit(_board_trick_name())


## A body 180: the skater turns around with the board, in the air after a pop (caught
## or not), once per jump (see body_turn_time). `swipe` is the swipe's direction (+1
## right): see _body_front.
func body_180(swipe := 1.0) -> void:
	if _dead or not _in_trick or not _popped or _body_turn >= 0.0:
		return
	_body_turn = 0.0
	_body_turns = 1 if _catches > 0 else 0  # Caught already: just the 180.
	_body_front = swipe_is_frontside(swipe)
	if _pop_spin:
		_angular_velocity *= twist_pop_spin  # A twisted pop barely tips the board.
	trick_started.emit(_pop_callout(""))


## The catch settles a body turn on the nearest half turn (at least one), past it by no
## more than body_catch_slack, else the next: it turns on to it, or back that little.
func _catch_body_turn() -> void:
	if _body_turn < 0.0 or _body_turns > 0:
		return
	_body_turns = maxi(1, ceili(_body_turn / body_turn_time - body_catch_slack))
	_body_turn = minf(_body_turn, _body_turns * body_turn_time)


## The body turn has settled (caught, and turned to its half turn), or there's none.
func _body_settled() -> bool:
	return _body_turn < 0.0 or (_body_turns > 0 and _body_turn >= _body_turns * body_turn_time - 0.0001)


## Half turns of the body turn: settled on, or the nearest so far.
func _body_half_turns() -> int:
	return _body_turns if _body_turns > 0 else maxi(1, roundi(_body_turn / body_turn_time))


## Time for one loop of the combo: its flips at trick_time each and its shuvit half
## turns at shuvit_spin_time each, whichever takes longer (both finish together).
func _trick_cycle() -> float:
	return maxf(maxf(_trick_flips * trick_time, _trick_shuvs * shuvit_spin_time), 0.01)


## The combo's name over `loops` loops: "kickflip", "double kickflip", "360 shuvit",
## "360 flip", "double 360 flip", "540 shuvit double kickflip".
func _combo_name(loops: int) -> String:
	if loops > 1 and _trick_flips == 1 and _trick_shuvs > 0:
		var once := _combo_name(1)
		if once in COMBO_NAMES.values():
			return ["", "", "double ", "triple ", "quadruple "][mini(loops, 4)] + once  # "double 360 flip"
	var flips := _trick_flips * loops
	var degrees := _trick_shuvs * loops * 180
	var flip := ""
	if flips > 0:
		flip = ["", "", "double ", "triple ", "quadruple "][mini(flips, 4)] + _trick_flip_kind
	if degrees == 0:
		return flip
	if flips == 1 and COMBO_NAMES.has([_trick_shuv_kind, degrees, _trick_flip_kind]):
		return COMBO_NAMES[[_trick_shuv_kind, degrees, _trick_flip_kind]]
	var shuv := String(_trick_shuv_kind) if degrees == 180 else "%d %s" % [degrees, _trick_shuv_kind]
	return shuv if flips == 0 else shuv + " " + flip


## Flip turns and shuvit half turns of the board trick caught this jump (for scoring).
func board_trick_units() -> int:
	return (_trick_flips + _trick_shuvs) * _board_trick_turns


## Board angle for a first catch at offset -1..1 on the catch pad.
func _tilt_for(offset: float) -> float:
	var t := 0.0
	if absf(offset) > lock_dead_zone:
		t = signf(offset) * inverse_lerp(lock_dead_zone, 1.0, absf(offset))
	return _air_base + deg_to_rad(t * lock_max_angle)


## Name of the current or completed board trick, e.g. "late kickflip", with its loops
## once caught: "double kickflip", "360 shuvit", "360 flip".
func _board_trick_name() -> String:
	var kind := String(_board_trick)
	if _board_trick == &"" and _board_trick_done != &"":
		kind = _combo_name(_board_trick_turns)
	if _half_cab():
		# Fakie, backside: a half cab or full cab ("half cab flip", "full cab heelflip").
		kind = _cab_name() + " " + ("flip" if kind == "kickflip" else kind)
	elif _body_turn >= 0.0:
		# With a body 180: its own name ("frontside flip", "bigspin"), or "backside 180 ...",
		# "frontside 360 kickflip".
		var combo = BODY_COMBOS.get([_body_front, kind]) if _body_half_turns() == 1 else null
		kind = combo if combo != null else _body_name() + " " + kind
	return ("late " if _board_trick_late else "") + kind


## A backside body turn popped fakie (off the nose rolling backward): a half cab (180) or
## full cab (360).
func _half_cab() -> bool:
	return _body_turn >= 0.0 and not _body_front and _popped and _pop_stance == "fakie"


## "half cab", "full cab", or past that "fakie backside 540".
func _cab_name() -> String:
	match _body_half_turns():
		1: return "half cab"
		2: return "full cab"
	return "fakie " + _body_name()


## How the rider looks after half a body turn (an odd number of them): [chest to the
## camera, heading]. Out of fakie it turns to face the way it rolls (a half cab: the
## other side, facing the other way); else normal and switch swap (the other side, the
## same way: a switch rider looks ahead with the back to the camera).
func _turned_view() -> Array:
	var heading := _heading
	var turned := _switch
	if is_fakie():
		heading = _dir
	else:
		turned = not turned
	return [(_goofy == turned) != (heading < 0.0), heading]


## The stance after this landing (the board rolling the way it does now, so a landing
## that turned it around counts): [heading, switch]. A nose pop out of fakie lands switch;
## then an odd number of half turns of a body turn: fakie turns to normal (a half cab, or
## a 180 into a transfer to fakie: your original stance), normal to switch and switch to
## normal; a 360 leaves it; then a manual or grind (`balance`) out of fakie is switch.
func _stance_after_landing(balance: bool) -> Array:
	var heading := _heading
	var turned := _switch
	if _dir != heading and _popped and _pop_stance == "switch":
		heading = _dir
		turned = true
	if _body_turn >= 0.0 and _body_half_turns() % 2 == 1:
		if _dir != heading:
			heading = _dir
		else:
			turned = not turned
	if _dir != heading and balance:
		heading = _dir
		turned = true
	return [heading, turned]


## Landed: the stance becomes what _stance_after_landing() says, and the body turn ends.
func _end_body_turn(balance := false) -> void:
	var after := _stance_after_landing(balance)
	_heading = after[0]
	_switch = after[1]
	_body_turn = -1.0
	_body_turns = 0


## The name of a balance trick landed now (`kind`: "manual", "5-0 grind"...) with its
## board trick: the stance it's ridden in after landing, and the pop's when they differ
## ("kickflip 5-0 grind", "switch kickflip nose manual", "fakie kickflip switch 5-0 grind").
## Returns [the whole name, the balance part alone].
func _balance_names(kind: String) -> Array:
	var after := _stance_after_landing(true)
	var ridden := "switch" if after[1] else ""
	var part := (ridden + " " if ridden != "" else "") + kind
	var board := _trick_prefix()
	if board == "":
		return [part, part]
	var popped_in := _pop_stance if _popped else ridden
	var name := (popped_in + " " if popped_in != "" else "") + board
	name += part if popped_in != ridden else kind
	return [name, part]


## "frontside 180", "backside 360"...
func _body_name() -> String:
	return ("frontside" if _body_front else "backside") + " %d" % (180 * _body_half_turns())


## Callout for a landed pop: "ollie"/"nollie", or the board trick ("nollie kickflip").
## The stance at the pop comes first ("switch kickflip", "fakie kickflip"), after "late".
## Cabs are named on their own ("half cab", "full cab flip", "late half cab flip").
func _pop_callout(trick: String) -> String:
	if _half_cab():
		# The cab's name says fakie already: "half cab", "full cab flip".
		return _cab_name() if trick == "" else trick
	var stance := _pop_stance + " " if _pop_stance != "" else ""
	if trick == "":
		if _body_turn >= 0.0:
			return stance + ("nollie " if _pop_nose else "") + _body_name()
		return stance + ("nollie" if _pop_nose else "ollie")
	var late := "late " if trick.begins_with("late ") else ""
	return late + stance + ("nollie " if _pop_nose else "") + trick.trim_prefix("late ")


## The air part of a landing for lines: the board trick ("kickflip", "nollie 360 flip"),
## else "ollie" or "nollie" after a pop, else "" (a drop-off or hop).
func _air_name() -> String:
	if _board_trick_done != &"":
		return _pop_callout(_board_trick_name())
	if _popped:
		return _pop_callout("")
	return ""


## Board trick prefix for a landing name ("kickflip "), or "" without one.
func _trick_prefix() -> String:
	return _board_trick_name() + " " if _board_trick_done != &"" else ""


func _process(delta: float) -> void:
	if manual:
		return
	_acc += delta
	var steps := 0
	while _acc >= STEP:
		_acc -= STEP
		step()
		steps += 1
		if steps >= MAX_STEPS:
			_acc = 0.0
			break
	set_view(_acc / STEP)


## Runs one fixed step of the game.
func step() -> void:
	_prev_pos = _pos
	_prev_angle = _angle
	_prev_distance = _distance
	_prev_cam = _cam
	_step(STEP)
	if not _dead:
		_hit_obstacles()
	_step_figure(STEP)
	if not _dead:
		_cross_progress_marks()
	tick += 1
	if tick % SNAPSHOT_STEPS == 0:
		_snapshot = get_state()


## The skater figure follows the board (drawing only): crouches in the air, tucks for
## board tricks, squats on landing, and after a slam falls where it came off.
func _step_figure(delta: float) -> void:
	if _body_turn >= 0.0 and _body_settled() and not _grounded and _rail == null:
		_view_flip_t += delta
	else:
		_view_flip_t = 0.0
	if not _dead:
		_fall_t = -1.0
	if _fall_t >= 0.0:
		_fall_t += delta
		_fall_vy += gravity * delta
		_fall_at += Vector2(_fall_vx, _fall_vy) * delta
		var ground := _seg_at(_fall_at.x - (_distance - _fall_distance), _fall_at.y - _fall_vy * delta)
		if ground != null:
			var floor_y := ground.y_at(_fall_at.x - (_distance - _fall_distance))
			if _fall_at.y >= floor_y and _fall_vy >= 0.0:
				_fall_at.y = floor_y
				_fall_vy = 0.0
				_fall_vx *= exp(-4.0 * delta)  # Sliding to a stop.
		return
	var down := _grounded or _rail != null
	var target := 0.2
	if not down:
		target = 1.0 if _board_trick != &"" else 0.55
	elif is_pushing():
		target = 0.35
	if down and not _fig_down:
		_crouch = 1.0  # Touchdown: soak it up.
	_fig_down = down
	_crouch = lerpf(_crouch, target, 1.0 - exp(-8.0 * delta))


## Where the skater figure is drawn this frame, for draw_skater_at(): {base (middle of
## the deck, between the feet), angle (of the body's up), feet (rear, front), crouch,
## face (1 chest to the camera .. -1 back to it, through a body 180), fall (s since
## slamming, or -1)}. Ghosts reuse it.
func skater_pose() -> Dictionary:
	var pose := board_pose()
	var center: Vector2 = pose[0]
	var angle := _view_angle
	var along := Vector2.RIGHT.rotated(angle)
	var up := Vector2.UP.rotated(angle)
	var deck := board_size.y / 28.0 * 7.0
	var base := center + up * deck
	var lift := 0.0
	if _board_trick != &"" and _fall_t < 0.0:
		# Feet up off the board while it flips and spins underneath.
		base = _view_pos + up * (board_size.y / 28.0 * 21.0)
		lift = 18.0
	var body_angle := angle
	if (_grounded or _rail != null) and _tilt_dir() != 0.0:
		body_angle = _ground_angle  # Balancing: the board tips, the skater stays upright.
	var half := board_size.x / 96.0 * 22.0
	var rear := base - along * half + up * lift
	var front := base + along * half + up * lift
	if _push_left > 0.0 and _fall_t < 0.0:
		# Pushing: the rear foot steps down to the ground and kicks back.
		var phase := 1.0 - _push_left / _push_total
		var drop := deck + board_size.y / 28.0 * 14.0
		rear = base + along * lerpf(-half * 0.3, -half * 2.6, phase) - up * drop * sin(PI * minf(phase * 1.3, 1.0))
	# The view (SkaterView): front or back (chest or back to the camera), facing left or
	# right (`mirror`), and how wide (|face|: edge-on in the middle of a turn).
	var back := not facing_camera()
	var mirror := _heading < 0.0
	var face := 1.0
	if _body_turn >= 0.0 and not _grounded and _rail == null:
		# A body turn spins the figure: past each edge-on point the other side shows,
		# facing the other way, so a 360 comes all the way round (front, back facing the
		# other way, front).
		var c := cos(_body_turn / body_turn_time * PI)
		face = absf(c)
		if c < 0.0:
			back = not back
			mirror = not mirror
		# Settled on an odd number of half turns, where that spin doesn't end the way the
		# rider rides after it (switch looks ahead, back to the camera, see
		# _turned_view()): a quick turn of the head to it, over view_flip_time.
		if _body_settled() and _body_half_turns() % 2 == 1:
			var after := _turned_view()
			if (not after[0]) != back or (after[1] < 0.0) != mirror:
				var k := clampf(_view_flip_t / view_flip_time, 0.0, 1.0)
				face = absf(cos(k * PI))
				if k >= 0.5:
					back = not after[0]
					mirror = after[1] < 0.0
	face *= -1.0 if back else 1.0  # Signed, for the flat fallbacks (no rig).
	var fall := -1.0
	if _fall_t >= 0.0:
		fall = _fall_t
		base = _fall_at - Vector2(scrolled() - _fall_distance, board_size.y / 28.0 * 8.0 * smoothstep(0.0, 0.35, _fall_t))
		body_angle = lerp_angle(body_angle, PI * 0.5, smoothstep(0.0, 0.35, _fall_t))
		var flat := Vector2.RIGHT.rotated(body_angle)
		rear = base - flat * 4.0
		front = base + flat * 4.0
	var push := 1.0 - _push_left / _push_total if _push_left > 0.0 and _fall_t < 0.0 else -1.0
	return {base = base, angle = body_angle, feet = [rear, front], crouch = _crouch, face = face, fall = fall,
		push = push, back = back, mirror = mirror,
		manual = _tilt_dir() if (_grounded or _rail != null) else 0.0}


## Draws a placeholder skater on `canvas` at a pose from skater_pose(), moved by
## `offset`, faded by `alpha` and with `shirt` (shirt_color by default) for the shirt.
func draw_skater_at(canvas: CanvasItem, pose: Dictionary, offset := Vector2.ZERO, alpha := 1.0,
		shirt := shirt_color) -> void:
	if _skater:
		_draw_skater_sprite(canvas, pose, offset, alpha, shirt)
		return
	var s := board_size.x / 96.0
	var angle: float = pose.angle
	var up := Vector2.UP.rotated(angle)
	var fwd := Vector2.RIGHT.rotated(angle)
	var base: Vector2 = pose.base + offset
	var feet: Array = [pose.feet[0] + offset, pose.feet[1] + offset]
	var crouch: float = pose.crouch
	var face: float = pose.face
	var manual: float = pose.manual
	var fallen: bool = pose.fall >= 0.0
	var outline := Color(0.05, 0.05, 0.08, alpha)
	var hip: Vector2 = base + up * lerpf(54.0, 34.0, crouch) * s + fwd * (manual * 8.0 - 3.0) * s
	if fallen:
		hip = base + up * 46.0 * s
	var shoulder: Vector2 = hip + up * 34.0 * s + fwd * lerpf(2.0, 8.0, crouch) * s
	var head: Vector2 = shoulder + up * 15.0 * s + fwd * 2.0 * s
	var limb := 8.0 * s
	# Legs: thigh and shin of equal length, knees bending forward.
	for i in 2:
		var foot: Vector2 = feet[i]
		var knee := _knee(hip, foot, 30.0 * s, fwd)
		var pants := Color(pants_color.darkened(0.25 if i == 0 else 0.0), alpha)
		canvas.draw_polyline(PackedVector2Array([hip, knee, foot]), outline, limb + 4.0)
		canvas.draw_polyline(PackedVector2Array([hip, knee, foot]), pants, limb)
		canvas.draw_circle(foot - up * 1.0 * s + fwd * 3.0 * s, 6.0 * s, Color(shoe_color, alpha))
	# Arms out for balance, raised in the air and while crouched.
	var raise := crouch * 14.0 * s
	var hands := [
		shoulder - fwd * 26.0 * s - up * (14.0 * s - raise),
		shoulder + fwd * 26.0 * s - up * (6.0 * s - raise),
	]
	if fallen:
		hands = [shoulder + fwd * 18.0 * s + up * 6.0 * s, shoulder + fwd * 22.0 * s - up * 4.0 * s]
	var sleeve := Color(shirt.darkened(0.2 if face < 0.0 else 0.0), alpha)
	for hand: Vector2 in hands:
		var elbow: Vector2 = (shoulder + hand) * 0.5 - up * 5.0 * s
		canvas.draw_polyline(PackedVector2Array([shoulder, elbow, hand]), outline, limb * 0.8 + 4.0)
		canvas.draw_polyline(PackedVector2Array([shoulder, elbow, hand]), sleeve, limb * 0.8)
		canvas.draw_circle(hand, 4.0 * s, Color(skin_color, alpha))
	# Torso: wide with the chest or back to the camera, thin mid-180.
	var width := lerpf(9.0, 16.0, absf(face)) * s
	canvas.draw_line(hip, shoulder, outline, width + 4.0)
	canvas.draw_line(hip, shoulder, Color(shirt.darkened(0.25 if face < 0.0 else 0.0), alpha), width)
	if face > 0.3:
		canvas.draw_line(hip.lerp(shoulder, 0.45) - fwd * width * 0.3, hip.lerp(shoulder, 0.45) + fwd * width * 0.3,
				Color(1, 1, 1, alpha * 0.8), 3.0 * s)  # A stripe on the chest.
	# Head, looking the way the board goes (a cap's brim), hair at the back.
	var r := 10.0 * s
	canvas.draw_circle(head, r + 2.0, outline)
	canvas.draw_circle(head, r, Color(skin_color, alpha))
	if face < -0.3:
		canvas.draw_circle(head - fwd * 1.0 * s, r * 0.85, Color(0.25, 0.17, 0.12, alpha))  # Back of the head.
	elif face > 0.3:
		canvas.draw_circle(head + fwd * 4.0 * s + up * 1.0 * s, 1.8 * s, outline)  # Eye.
	canvas.draw_colored_polygon(PackedVector2Array([
		head - fwd * r + up * 1.0 * s, head + up * r * 1.05, head + fwd * r + up * 1.0 * s,
	]), Color(shirt.darkened(0.35), alpha))  # Cap.
	canvas.draw_line(head + fwd * r * 0.4 + up * 2.0 * s, head + fwd * r * 1.6 + up * 1.0 * s,
			Color(shirt.darkened(0.35), alpha), 3.0 * s)  # Brim.


## The skater sprite at a pose from skater_pose(): feet on the pose's base, turned with
## the body, squatting down a few rows as it crouches, narrowing through a body 180 and
## mirrored with the back to the camera. A ghost (`shirt` not the skater's) is tinted.
func _draw_skater_sprite(canvas: CanvasItem, pose: Dictionary, offset: Vector2, alpha: float,
		shirt: Color) -> void:
	var s := board_size.x / 96.0 * skater_pixel
	var face: float = pose.face
	var crouch := clampf((float(pose.crouch) - 0.2) / 0.8, 0.0, 1.0)
	var squat := 1.0 if pose.fall >= 0.0 else lerpf(1.0, 0.86, crouch)
	var width := signf(face if face != 0.0 else 1.0) * maxf(absf(face), 0.3)
	var base: Vector2 = pose.base + offset
	base = (base / PIXEL).round() * PIXEL  # On the world's pixel grid, like the board.
	var tint := Color.WHITE if shirt == shirt_color else Color.WHITE.lerp(shirt, 0.6)
	tint.a = alpha
	canvas.draw_set_transform(base, pose.angle, Vector2(width, squat) * s)
	var push: float = pose.get("push", -1.0)
	if push >= 0.0 and _push_sheet and not _push_anchors.is_empty():
		var frame := mini(int(push * _push_anchors.size()), _push_anchors.size() - 1)
		var size := float(skater_push.get_height())
		canvas.draw_texture_rect_region(_push_sheet, Rect2(-_push_anchors[frame], Vector2(size, size)),
				Rect2(frame * size, 0.0, size, size), tint)
	else:
		canvas.draw_texture(_skater, -_skater_feet, tint)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## Per push frame (`frames` squares side by side in `sheet`), the point that goes on the
## pose's base: the frame's front foot (rightmost opaque pixel of its soles' row) put
## where the still sprite's front foot is, relative to the still's feet anchor.
static func _push_frame_anchors(still: Image, sheet: Image, frames: int) -> Array[Vector2]:
	var feet := _feet_anchor(still)
	var front := _front_foot(still, Rect2i(Vector2i.ZERO, still.get_size()))
	var anchors: Array[Vector2] = []
	var size := sheet.get_height()
	for i in frames:
		var f := _front_foot(sheet, Rect2i(i * size, 0, size, size))
		anchors.append(f - (front - feet) - Vector2(i * size, 0.0))
	return anchors


## The bottom-right corner of the lowest row's rightmost opaque pixel in `rect`.
static func _front_foot(image: Image, rect: Rect2i) -> Vector2:
	for y in range(rect.end.y - 1, rect.position.y - 1, -1):
		for x in range(rect.end.x - 1, rect.position.x - 1, -1):
			if image.get_pixel(x, y).a > 0.5:
				return Vector2(x + 1, y + 1)
	return Vector2(rect.end)


## Between the outermost opaque pixels of a sprite's bottom row, on its bottom edge.
static func _feet_anchor(image: Image) -> Vector2:
	var h := image.get_height()
	var y := h - 1
	var left := -1
	var right := -1
	for x in image.get_width():
		if image.get_pixel(x, y).a > 0.5:
			right = x
			if left < 0:
				left = x
	if left < 0:
		return Vector2(image.get_width() * 0.5, h)
	return Vector2((left + right + 1) * 0.5, h)


## Where a knee goes, between `hip` and `foot` with both bones `bone` long, bent `fwd`.
static func _knee(hip: Vector2, foot: Vector2, bone: float, fwd: Vector2) -> Vector2:
	var d := foot - hip
	var half := d.length() * 0.5
	var mid := hip + d * 0.5
	if half >= bone or half < 0.001:
		return mid
	var side := d.orthogonal().normalized()
	if side.dot(fwd) < 0.0:
		side = -side
	return mid + side * sqrt(bone * bone - half * half)


## Draws the game `alpha` of the way from the step before the last to the last.
func set_view(alpha: float) -> void:
	_view_pos = _prev_pos.lerp(_pos, alpha)
	_view_angle = lerpf(_prev_angle, _angle, alpha)
	_view_dx = (1.0 - alpha) * (_distance - _prev_distance)
	_view_cam = lerpf(_prev_cam, _cam, alpha)
	position.y = -_view_cam
	queue_redraw()


## Draws the latest step as it is (no blend with the one before).
func _settle_view() -> void:
	_prev_pos = _pos
	_prev_angle = _angle
	_prev_distance = _distance
	_prev_cam = _cam
	set_view(1.0)


## The latest snapshot (see get_state()) if it hasn't been collected yet, else [].
func take_snapshot() -> Array:
	var taken := _snapshot
	_snapshot = []
	return taken


## Does what the player did (Act) and reports it (acted), for ghosts to replay: a is
## the pop side (1 = nose), the press offset or the board trick (index in TRICKS); b the
## pop strength. Push strength is a.
func act(action: int, a := 0.0, b := 0.0) -> void:
	acted.emit(tick, action, a, b)
	match action:
		Act.POP:
			pop(a > 0.5, b)
		Act.PUSH:
			push(a)
		Act.PRESS_CATCH:
			press_catch(a)
		Act.RELEASE_CATCH:
			release_catch()
		Act.BOARD_TRICK:
			board_trick(TRICKS[clampi(int(a), 0, TRICKS.size() - 1)])
		Act.BALANCE_POP:
			balance_pop()
		Act.END_BALANCE:
			end_balance()
		Act.LOSE_BALANCE:
			lose_balance()
		Act.BODY_180:
			body_180(a)


## Everything needed to carry on from this step: [play area, STATE values..., the
## surface ridden and the rail or ledge ground, as [x0, y0, x1, y1] from the level's
## start (or null)]. Restore it with set_state() on a fresh runner of the same level.
func get_state() -> Array:
	var state: Array = [_area]
	for name: StringName in STATE:
		state.append(get(name))
	state.append(_surface_key(_support))
	state.append(_surface_key(_rail))
	return state


## Restores get_state()'s `state` on a runner just configured for the same level (not
## set up yet): lays the level out for that play area and scrolls it to where the
## state was.
func set_state(state: Array) -> void:
	setup(state[0])
	var values := state.slice(1, 1 + STATE.size())
	_scroll(values[STATE.find(&"_distance")])
	for i in STATE.size():
		if STATE[i] == &"_push_queue":
			_push_queue.assign(values[i])
		else:
			set(STATE[i], values[i])
	_support = _find_surface(state[-2], _segs + _ledges)
	_rail = _find_surface(state[-1], _rails + _ledges)
	if _support == null:
		_support = _seg_at(_pos.x, _pos.y)
	_settle_view()


## Whether `state` (from get_state()) is this one, within rounding.
func matches_state(state: Array) -> bool:
	var mine := get_state()
	if mine.size() != state.size():
		return false
	for i in mine.size():
		var a = mine[i]
		var b = state[i]
		if typeof(a) != typeof(b):
			return false
		match typeof(a):
			TYPE_FLOAT:
				if absf(a - b) > 0.01 and not (is_inf(a) and is_inf(b)):
					return false
			TYPE_VECTOR2, TYPE_VECTOR4:
				if not (a - b).is_zero_approx() and (a - b).length() > 0.01:
					return false
			TYPE_ARRAY:
				if a.size() != b.size():
					return false
			_:
				if a != b:
					return false
	return true


func _surface_key(s: Seg) -> Variant:
	if s == null:
		return null
	return Vector4(s.x0 + _distance, s.y0, s.x1 + _distance, s.y1)


func _find_surface(key: Variant, among: Array) -> Seg:
	if key == null:
		return null
	for s: Seg in among:
		if (_surface_key(s) - key).length() < 0.5:
			return s
	return null


func _step(delta: float) -> void:
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
	# Along the surface on the ground; in the air _speed is the horizontal speed.
	var dx := _dir * _speed * delta
	if _grounded or _rail != null:
		dx *= cos(_ground_angle)
	var score := int((_distance + dx) / 50.0)
	if score > _score:  # Only ever up: riding back (fakie) doesn't take it away.
		_score = score
		score_changed.emit(_score)

	_scroll(dx)

	if _rail != null:
		_step_grind()
	elif _grounded:
		_step_pushes(delta)
		_step_ground()
	else:
		if _board_trick != &"":
			_board_trick_t += delta
			_trick_window = maxf(_trick_window - delta, 0.0)
		if _body_turn >= 0.0:
			_body_turn += delta
			if _body_turns > 0:
				_body_turn = minf(_body_turn, _body_turns * body_turn_time)  # Settled.
		_lip_t -= delta
		_step_hold(delta)
		_step_air(delta)
	if _dead:
		return
	_update_airborne()
	_step_rotation(delta)
	_pan(delta)
	_follow_ground(delta)
	var sliding := _rail != null and _rail.ledge and not _fifty
	_slide = move_toward(_slide, 1.0 if sliding else 0.0, delta / slide_swing_time)
	if _grounded and not _in_trick and _at_goal():
		_cleared = true
		level_cleared.emit()


## The board has reached the finish flag.
func _at_goal() -> bool:
	if is_inf(_goal_y):
		return _pos.x >= _goal_x
	return absf(_pos.x - _goal_x) <= 30.0 and absf(_pos.y - _goal_y) <= 40.0


## Moves the view so the floor under the board stays inside camera_band (e.g. down a
## tall ramp), and the board below the top margin. When that floor is far below the
## board (falling along a tall wall), the board is kept nearer the middle instead.
## Over a pit there's nothing to follow: a board falling in leaves the view and dies.
## Floor height `dist` px ahead along what the board can roll onto: past a lip or a
## gap it stays at the edge, so the view doesn't dive before the board does.
func _ground_ahead(dist: float) -> float:
	var s := _support
	var x := _pos.x + _dir * dist
	while _beyond(x, _ahead_end(s)):
		var next := _continuation(s)
		if next == null:
			return _ahead_end_y(s)
		s = next
	return s.y_at(x)


## Scrolls the level left by dx (px), dropping what's gone off the left and adding
## what comes in on the right.
func _scroll(dx: float) -> void:
	_shift_world(dx)
	# What's gone off the left is kept a while: the board can roll back to it (fakie).
	while _segs.size() > 1 and _segs[0].x1 < -_keep_behind and _segs[0] != _support:
		_segs.pop_front()
	while not _rails.is_empty() and _rails[0].x1 < -_keep_behind and _rails[0] != _rail:
		_rails.pop_front()
	while not _platforms.is_empty() and _platforms[0].top.back().x1 < -_keep_behind \
			and not (_support in _platforms[0].top) and not (_rail in _platforms[0].top):
		for ledge in _platforms.pop_front().top:
			_ledges.erase(ledge)
	_fill_platforms()


## Scrolls the level left by dx (px) under the board.
func _shift_world(dx: float) -> void:
	_distance += dx
	for s in _segs + _rails + _ledges:
		s.x0 -= dx
		s.x1 -= dx
	_goal_x -= dx
	for mark in marks:
		marks[mark] -= Vector2.ONE * dx


## Pans the view toward showing more of the way the board's going: the board sits
## player_x_ratio from the left going forward, as far from the right going backward.
## The world moves with the board, so nothing changes but the view.
func _pan(delta: float) -> void:
	var target := _area.x * (player_x_ratio if _dir > 0.0 else 1.0 - player_x_ratio) + board_size.x * 0.5 * _dir
	if absf(target - _pos.x) < 0.5:
		return
	var d := (target - _pos.x) * (1.0 - exp(-pan_rate * delta))
	_pos.x += d
	_shift_world(-d)


func _follow_ground(delta: float) -> void:
	var target := _cam
	var below := _seg_at(_pos.x, _pos.y)
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
		var climb := _dir * _speed * sin(_ground_angle)
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


## Integrates the speed along the surface for one frame (see the Physics group).
func _step_speed(delta: float) -> void:
	var v := _speed / pixels_per_meter
	var roll := rolling_resistance
	if _rail != null:
		roll *= ledge_friction if _rail.ledge else rail_friction
	# Resistance only ever slows the board down, never pushes it backwards.
	var resistance := roll * slope_g * cos(_ground_angle) + drag * v * v / mass
	v = maxf(v - resistance * delta, 0.0)
	# Signed, + to the right. Pushes always drive the board forward (right): rolling
	# backward, they brake it first.
	var u := _dir * v
	u += (slope_g * sin(_ground_angle) + _push_force(u) / mass) * delta
	if u * _dir < 0.0:
		# Rolled to a stop going up a slope or rail (or pushed out of rolling backward):
		# it rolls the other way. (On flat ground it just stands until the next push.)
		_set_dir(-_dir)
	_speed = clampf(absf(u), 0.0, max_speed) * pixels_per_meter


## F_push(t) (N): the current kick's half-sine pulse, fading as the board's speed v
## (m/s, + forward) approaches foot_speed.
func _push_force(v: float) -> float:
	if _push_left <= 0.0:
		return 0.0
	var phase := 1.0 - _push_left / _push_total
	return _push_peak * sin(PI * phase) * clampf(1.0 - v / foot_speed, 0.0, 1.0)


## power is 0 (lightest) .. 1 (hardest).
func _start_push(power: float) -> void:
	_fakie_to_switch()  # Pushing out of fakie: riding switch.
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
	# The wheels sit w apart along the surface: only w cos(slope) across, which on a steep
	# wall is very little. Everything here works either way the board rolls, written for
	# rolling forward and mirrored by the direction helpers (_ahead_end(), _beyond(),
	# _linked_ahead(), _rel(), _joint(..., _dir)).
	var w := _wheel_offset()
	var d := _dir
	# Hand over to the next surface once the trailing wheel rolls past the end of this one.
	while _beyond(_pos.x - d * w * cos(_support.angle()), _ahead_end(_support)):
		var next := _continuation(_support)
		if next != null and _over_crest(next):
			return
		if next == null:
			if d > 0.0 and _support == _segs.back():
				break  # End of generated floor (never reached in play).
			if d < 0.0 and _support == _start_seg:
				# The start platform's far end: the board stops against it.
				_shift_world(_support.x0 - w * cos(_support.angle()) - _pos.x)
				_speed = 0.0
				break
			_leave_ground()  # Rolled off a ledge or got launched.
			return
		_support = next

	var angle := _support.angle()
	var y := _support.y_at(_pos.x)
	var next := _continuation(_support)
	var ahead := _linked_ahead(_support)
	if _beyond(_pos.x + d * board_size.x * 0.5, _ahead_end(_support)):
		# Floor ahead that the board can't roll onto (platforms have no walls).
		var joint := _joint(_support, ahead, d) if ahead and next == null else &""
		# A higher floor right at the edge is a wall; across a gap the board drops first.
		if joint == &"step_up" and _gap(_support, ahead) <= 1.0:
			_slam("wall")
			return
		if _beyond(_pos.x + d * w * cos(angle), _ahead_end(_support)):
			if joint == &"too_steep":
				_slam("too steep")
				return
			# Over a crest it'll fly off, the board doesn't tilt over the bend: that would
			# turn its speed forward for a moment before the take-off.
			if next != null and _crest_height(next) < _launch_height():
				# Wheels on two surfaces: the board spans the bend.
				var back_x := _pos.x - d * w * cos(angle)
				var front_x := _pos.x + d * w * cos(next.angle())
				var back := Vector2(back_x, _support.y_at(back_x))
				var front := Vector2(front_x, next.y_at(front_x))
				angle = (front - back).angle() if d > 0.0 else (back - front).angle()
				y = (back.y + front.y) * 0.5
			# Ledge or launch ahead: the front wheel hangs, the back wheel carries the board.
	_pos.y = y
	_ground_angle = angle


## Direction helpers: the ground code reads "ahead" as the way the board rolls (_dir).
## The x of the end of `s` the board rolls toward (and its height), and the end it
## comes from.
func _ahead_end(s: Seg) -> float:
	return s.x1 if _dir > 0.0 else s.x0


func _ahead_end_y(s: Seg) -> float:
	return s.y1 if _dir > 0.0 else s.y0


## Whether x is past `edge` the way the board rolls.
func _beyond(x: float, edge: float) -> bool:
	return x > edge if _dir > 0.0 else x < edge


## The piece linked after `s` the way the board rolls (null if none).
func _linked_ahead(s: Seg) -> Seg:
	return s.next if _dir > 0.0 else s.prev


## A slope's angle as seen rolling the board's way: positive downhill.
func _rel(angle: float) -> float:
	return angle if _dir > 0.0 else -angle


## Horizontal gap from the end of `a` to the start of `b`, the way the board rolls.
func _gap(a: Seg, b: Seg) -> float:
	return b.x0 - a.x1 if _dir > 0.0 else a.x0 - b.x1


## Going up a ramp at `angle` steep enough for a transfer (see transfer_angle).
func _steep_up(angle: float) -> bool:
	return _dir * angle <= -deg_to_rad(transfer_angle)


func _leave_ground() -> void:
	if _steep_up(_support.angle()):
		# Off the lip of a steep ramp: a transfer (_take_off). No catch needed; pop it at
		# the lip.
		_ground_angle = _support.angle()
		_stop_pushing()
		_drop_off()
		_lip_t = lip_pop_time
		return
	# A lip: a bend too sharp to follow, or a ramp going up that ends (a kicker).
	var ahead := _linked_ahead(_support)
	var lip := (ahead != null and _joint(_support, ahead, _dir) == &"launch") \
			or (not _support.ledge and _rel(_support.angle()) < 0.0)
	var small := not lip and _small_drop_ahead()
	if is_pushing():
		if not lip and not small:
			_slam("pushing")
			return
		_stop_pushing()
	if _support.ledge or small:
		_drop_off()  # Off the end of a platform or a small step down: no catch needed.
		return
	# Off a floor ledge: the nose tips down and the board has to be caught.
	_roll_off()
	if lip:
		_lip_t = lip_pop_time


## The floor goes on just past the edge the board's rolling off, at most small_drop lower.
func _small_drop_ahead() -> bool:
	var ahead := _linked_ahead(_support)
	if ahead == null or _gap(_support, ahead) > board_size.x * 0.5:
		return false
	var drop := (ahead.y0 if _dir > 0.0 else ahead.y1) - _ahead_end_y(_support)
	return drop > 0.0 and drop <= small_drop


## The leading end tips down off the edge (the nose, or the tail rolling backward): the
## board has to be caught.
func _roll_off() -> void:
	_grounded = false
	_take_off()
	var factor := clampf(drop_ref_speed * pixels_per_meter / _speed, drop_factor_range.x, drop_factor_range.y)
	_start_trick(drop_spin * factor * _dir)
	dropped.emit()


## How high the speed across `next` would lift the board over the crest onto it (px):
## (v sin(bend))² / 2g; 0 where the ground bends up.
func _crest_height(next: Seg) -> float:
	var bend := _rel(next.angle()) - _rel(_support.angle())
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
	if _beyond(_pos.x, _ahead_end(_rail)) and _rail.ledge:
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
				line_event.emit("", "", true)
			else:
				_set_balance(_riding_manual, null, false, _balance_tilt)
				landed.emit("to manual")
				var stance := "switch " if _switch or is_fakie() else ""
				_fakie_to_switch()
				callout.emit(stance + ("nose manual" if _riding_manual > 0.0 else "manual"), true)
			_step_ground()
			return
	if _beyond(_pos.x, _ahead_end(_rail)):
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
	var under := _seg_at(_pos.x, prev_y)
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
				if _from_rail and s.ledge and _beyond(_pos.x, _ahead_end(s)):
					continue  # Slid off the end of a ledge: the trailing wheel doesn't land back on it.
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
	var nose_x := _pos.x + board_size.x * 0.5 * _dir  # The leading end.
	var ahead := _seg_at(nose_x, _pos.y - WALL_REACH)
	if ahead != null and ahead.y_at(nose_x) < _pos.y - wall_tolerance and _wall_between(nose_x):
		_slam("wall")


## A face of a step up stands between the board and `nose_x`: ground that's higher
## because it rises along a ramp (up a quarter pipe) isn't a wall to fly into.
func _wall_between(nose_x: float) -> bool:
	var lo := minf(_pos.x, nose_x)
	var hi := maxf(_pos.x, nose_x)
	for s in _segs:
		if s.next == null or s.next.x0 < lo or s.next.x0 > hi or s.y1 < _pos.y - WALL_REACH or s.y1 > _pos.y + 2.0:
			continue
		var step := s.next.y0 - s.y1
		if (_dir > 0.0 and step < -1.0) or (_dir < 0.0 and step > 1.0):
			return true
		if absf(rad_to_deg(s.next.angle() - s.angle())) > max_transition:
			return true  # A bend too sharp to ride is a wall too.
	return false


## Rolling off a platform or a rail end: no catch needed. Off a platform the board keeps
## its angle and the landing rules hold, so a catch can be needed to land (or wanted, for
## a manual); off a grind (_from_rail) it levels out to the ground below by itself.
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
	_velocity_y = _dir * _speed * sin(_ground_angle)
	_speed *= cos(_ground_angle)
	if _rail == null and _steep_up(_ground_angle):
		# Off a steep ramp: a transfer. Catches and the pop's spin start from its angle.
		_air_base = _ground_angle


## Slams if touching down on `surface` now would be harder than a max_fall drop.
func _too_hard(surface: Seg) -> bool:
	if max_fall <= 0.0:
		return false
	var a := surface.angle()
	var into := maxf(_velocity_y * cos(a) - _dir * _speed * sin(a), 0.0)  # Speed into the surface.
	if into * into <= 2.0 * gravity * max_fall:
		return false
	_slam("fell too far")
	return true


## Touching down on `surface`: keeps the velocity's component along it as the new
## speed; the part into the surface is absorbed by the legs.
func _touch_down(surface: Seg) -> void:
	var a := surface.angle()
	var along := _dir * _speed * cos(a) + _velocity_y * sin(a)
	if along != 0.0:
		_set_dir(signf(along))  # Coming down a wall backward: rolling fakie.
	_speed = clampf(absf(along), 0.0, max_speed * pixels_per_meter)
	_velocity_y = 0.0


func _step_hold(delta: float) -> void:
	if _from_rail and not _needs_catch and _catches == 0:
		# Off the end of a grind: the board levels out to the ground below by itself.
		var below := _seg_at(_pos.x, _pos.y)
		if below != null:
			_lock_angle = below.angle()
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
	_pop_spin = false
	_past_vertical = false
	_hop = false
	_body_turn = -1.0
	_body_turns = 0
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
	_impact = Vector2(_dir * _speed, _velocity_y)
	if _too_hard(on):
		return
	if absf(on.y_at(_pos.x) - on.y_at(x)) > land_snap:
		# A wheel met a steep surface well above the middle of the board: bring that
		# spot under the board instead of dropping the board down to it.
		_shift_world(x - _pos.x)
	_touch_down(on)
	_air_base = 0.0
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
		line_event.emit("", "", true)
		return
	if _board_trick != &"":
		_slam("landed mid-" + _board_trick)
		return
	if not _body_settled():
		_slam("landed mid-" + _body_name())
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
		var names := _balance_names("nose manual" if tilt > 0.0 else "manual")
		landed.emit(names[0])
		line_event.emit(_air_name(), names[1], false)
		_end_body_turn(true)
		callout.emit(names[0], true)
		return
	var error := rad_to_deg(absf(_angle - _ground_angle))
	if hop and _catches == 0 and _hop_height <= hop_level_free:
		error = 0.0  # A small hop: the wheels just come down, at any angle.
	if error > land_tolerance:
		_slam("off by %d°" % roundi(error))
		return
	if hop and _catches == 0:
		landed.emit("roll")  # Rolled through a hop: nothing to score.
		line_event.emit("", "", true)
		return
	landed.emit(trick + "clean" if trick else "clean")
	line_event.emit(_air_name(), "", true)
	if _popped:
		callout.emit(_pop_callout(trick.strip_edges()), false)
	_end_body_turn()


## Locks onto a rail or platform edge with the balance ready: like landing a manual on it.
func _start_grind(rail: Seg) -> void:
	_impact = Vector2(_dir * _speed, _velocity_y)
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
	if not _body_settled():
		_slam("landed mid-" + _body_name())
		return
	var kind := ""
	# Named from how the board meets it, whatever side CATCH was held on.
	var tilt := _tilt_against(_ground_angle)
	if absf(tilt) > grind_max_angle:
		_slam("off by %d° on %s" % [roundi(absf(tilt)), "ledge" if rail.ledge else "rail"])
		return
	if absf(tilt) <= fifty_band:
		# 50-50: both trucks on it, board level along it.
		_set_balance(1.0, rail, true)
		kind = "50-50 grind"
	else:
		_set_balance(signf(tilt), rail, false, deg_to_rad(tilt))
		if rail.ledge:
			kind = "noseslide" if tilt > 0.0 else "tailslide"
		else:
			kind = "nosegrind" if tilt > 0.0 else "5-0 grind"
	var names := _balance_names(kind)
	var double := "double " if _from_rail else ""
	landed.emit(double + names[0])
	line_event.emit(_air_name(), double + names[1], false)
	_end_body_turn(true)
	callout.emit(double + names[0], true)


## The board's angle against a surface at `surface_angle`, in degrees: positive nose down.
func _tilt_against(surface_angle: float) -> float:
	return rad_to_deg(wrapf(_angle - surface_angle, -PI, PI))


func _step_rotation(delta: float) -> void:
	if _grounded or _rail != null:
		_angular_velocity = 0.0
		var target := _ground_angle + _balance_tilt  # The angle it touched down at.
		# Fast through a curve, it turns as quickly as it rolls round it.
		var settle := maxf(land_settle, _speed / _wheel_offset())
		_angle = lerpf(_angle, target, 1.0 - exp(-settle * delta))
	elif _locked:
		if _past_vertical:
			_angle = move_toward(_angle, _lock_angle, deg_to_rad(catch_slow_turn) * delta)
		else:
			_angle = lerpf(_angle, _lock_angle, 1.0 - exp(-lock_snap * delta))
	elif _pop_spin:
		var cap := deg_to_rad(pop_spin_cap)
		_angle = clampf(_angle + _angular_velocity * delta, _air_base - cap, _air_base + cap)
	else:
		_angle += _angular_velocity * delta
		_angular_velocity *= exp(-spin_damping * delta)
	if not _grounded and _rail == null and absf(_angle - _air_base) > deg_to_rad(catch_slow_after):
		_past_vertical = true


## Maps a pad offset (-1..1) to 0..1.
func _unit(offset: float) -> float:
	return (clampf(offset, -1.0, 1.0) + 1.0) * 0.5


func _wheel_offset() -> float:
	return WHEEL_X * board_size.x / 96.0


## The floor at x: the highest piece there that's no higher than `y` (2 px of slack),
## for the floor under a point where one floor runs above another (see `at` in Levels).
## Without `y`, the top one.
func _seg_at(x: float, y := -INF) -> Seg:
	var best: Seg = null
	var best_y := INF
	for s in _segs:
		if x >= s.x0 and x <= s.x1:
			var top := s.y_at(x)
			if top >= y - 2.0 and top < best_y:
				best = s
				best_y = top
	return best


## Floor and platform tops at x, every floor that runs there included.
func _surfaces_at(x: float) -> Array[Seg]:
	var found: Array[Seg] = []
	for s in _segs:
		if x >= s.x0 and x <= s.x1:
			found.append(s)
	for ledge in _ledges:
		if x >= ledge.x0 and x <= ledge.x1:
			found.append(ledge)
	return found


## The surface the board rolls onto past the end of `s`: its next piece if the joint is
## smooth, else floor or a platform top carrying on from where `s` ends at the same
## height and a rideable angle (e.g. a bridge over a pit). null if there is none.
## (Both the way the board rolls: rolling backward, past the start of `s`.)
func _continuation(s: Seg) -> Seg:
	var linked := _linked_ahead(s)
	if linked != null and _joint(s, linked, _dir) == &"smooth":
		return linked
	var end := _ahead_end(s)
	for other: Seg in _segs + _ledges:
		if other == s:
			continue
		if _dir > 0.0 and (end < other.x0 - 1.0 or end >= other.x1):
			continue
		if _dir < 0.0 and (end > other.x1 + 1.0 or end <= other.x0):
			continue
		var bend := rad_to_deg(_rel(other.angle()) - _rel(s.angle()))
		if absf(other.y_at(end) - _ahead_end_y(s)) <= 2.0 and absf(bend) <= max_transition:
			return other
	return null


## How the ground continues from a to b going `direction` (+1 right, -1 left): step_up
## (wall), step_down (ledge or gap), too_steep (bends up too sharply), launch (bends down
## too sharply) or smooth.
func _joint(a: Seg, b: Seg, direction := 1.0) -> StringName:
	var forward := direction > 0.0
	var step := (b.y0 - a.y1) if forward else (b.y1 - a.y0)
	if step < -1.0:
		return &"step_up"
	if step > 1.0 or ((b.x0 - a.x1) if forward else (a.x0 - b.x1)) > 1.0:
		return &"step_down"
	var bend := rad_to_deg(b.angle() - a.angle()) * (1.0 if forward else -1.0)
	if bend < -max_transition:
		return &"too_steep"
	if bend > max_transition:
		return &"launch"
	return &"smooth"


func _fill_platforms() -> void:
	# The level's own pieces all at once (a floor can run under another: see `at` in
	# Levels), then keep spawning until there's ground beyond the right edge.
	while not _segments.is_empty() or _rightmost().x0 < _area.x + 200.0:
		if not _segments.is_empty():
			var segment = _segments.pop_front()
			var laid := _segs.size()
			if segment is Dictionary and segment.has("at"):
				_start_floor(segment.at, segment.width, segment.get("rise", 0.0))
			elif segment is Dictionary:
				_append_platform(segment.width, segment.get("step", 0.0), segment.get("rise", 0.0),
						segment.get("gap", 0.0))
			if segment is Dictionary:
				_segs.back().stairs = segment.get("stairs", 0)
				_add_props(_segs.back(), segment.get("props", []))
				_add_obstacles(_segs.back(), segment.get("obstacles", []))
				if segment.has("rail"):
					_add_rail(_segs.back(), segment.rail)
				if segment.has("platform"):
					_add_platform(_segs.back(), segment.platform, segment.get("deck", 0.0))
				if segment.has("mark"):
					_mark(segment)
				if segment.has("goal"):
					# The flag goes here, `goal` px into the piece, instead of after the end.
					var piece: Seg = _segs.back()
					_goal_spawned = true
					_goal_x = piece.x0 + segment.goal
					_goal_y = piece.y_at(_goal_x)
			else:
				_append_platform(segment.x, segment.y, segment.z)
			_level_segs.append_array(_segs.slice(laid))
		elif _random_left > 0:
			_random_left -= 1
			_append_random_platform()
		elif not _goal_spawned:
			_goal_spawned = true
			_append_platform(2000.0, 0.0, 0.0, 0.0, _rightmost())
			_goal_x = _segs.back().x0 + goal_offset
		else:
			_append_platform(2000.0, 0.0, 0.0, 0.0, _rightmost())


## Stands `props` ([name, px] each: a SpotArt prop of the stage's art, its middle `from`
## + px along `on`) on a floor piece.
func _add_props(on: Seg, props: Array, from := 0.0) -> void:
	for prop: Array in props:
		if not _prop_textures.has(prop[0]):
			var texture := SpotArt.prop(art, prop[0])
			_prop_textures[prop[0]] = _pixel_texture(texture) if texture else null
		if _prop_textures[prop[0]]:
			on.props.append([_prop_textures[prop[0]], from + float(prop[1])])


## Stands `obstacles` ([name, px] each: a SpotArt prop, its middle px along `on`) on a
## floor piece as things in the way: drawn solid, their outline (the top of each texel
## column of the sprite) slams a board running into it (_hit_obstacles), and their top
## (the columns at least obstacle_top_share of the height, simplified to a few pieces) is
## a platform to land on, ride and grind, drawn by the sprite itself. Jump them off a
## kicker or land on them.
func _add_obstacles(on: Seg, obstacles: Array) -> void:
	for entry: Array in obstacles:
		var texture := SpotArt.prop(art, entry[0])
		if texture == null:
			continue
		var image := texture.get_image()
		var profile := PackedFloat32Array()
		for x in image.get_width():
			var top := image.get_height()
			for y in image.get_height():
				if image.get_pixel(x, y).a >= 0.5:
					top = y
					break
			profile.append((image.get_height() - top) * PIXEL)
		var obstacle := {texture = _pixel_texture(texture), at = float(entry[1]), profile = profile}
		on.obstacles.append(obstacle)
		var left: float = obstacle.at - image.get_width() * PIXEL * 0.5
		var tallest: float = Array(profile).max()
		var top: Array[Vector2] = []
		for x in profile.size():
			if profile[x] >= tallest * obstacle_top_share:
				top.append(Vector2(left + (x + 0.5) * PIXEL, profile[x]))
		top = _simplified(top, PIXEL * 1.5)
		if top.size() >= 2:
			_add_platform(on, top)
			_platforms.back()["hidden"] = true


## `points` with the ones within `tolerance` of the line through their neighbours left
## out (Douglas-Peucker), keeping the ends.
static func _simplified(points: Array[Vector2], tolerance: float) -> Array[Vector2]:
	if points.size() <= 2:
		return points
	var a := points[0]
	var b: Vector2 = points.back()
	var far := 0
	var far_d := 0.0
	for i in range(1, points.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(points[i], a, b).distance_to(points[i])
		if d > far_d:
			far_d = d
			far = i
	if far_d <= tolerance:
		return [a, b]
	var left := _simplified(points.slice(0, far + 1), tolerance)
	var right := _simplified(points.slice(far), tolerance)
	left.pop_back()
	left.append_array(right)
	return left


## Slams if the board ran into an obstacle (_add_obstacles): its middle or either end
## inside one's outline. Not while riding or grinding on top of something.
func _hit_obstacles() -> void:
	if (_grounded and _support.ledge) or _rail != null:
		return
	for s in _segs:
		for obstacle: Dictionary in s.obstacles:
			var profile: PackedFloat32Array = obstacle.profile
			var left: float = s.x0 + obstacle.at - profile.size() * PIXEL * 0.5
			if _pos.x + board_size.x < left or _pos.x - board_size.x > left + profile.size() * PIXEL:
				continue
			for x in [_pos.x, _pos.x + board_size.x * 0.5, _pos.x - board_size.x * 0.5]:
				var column := floori((x - left) / PIXEL)
				if column < 0 or column >= profile.size():
					continue
				if _pos.y > s.y_at(x) - profile[column] + obstacle_tolerance:
					_slam("hit an obstacle")
					return


## Starts a new stretch of floor at `at` (level coordinates: px from the end of the start
## platform, and down from its height), not joined to the last piece: it can run under
## floor laid already.
func _start_floor(at: Vector2, width: float, rise: float) -> void:
	var from := at + Vector2(_origin.x - _distance, _origin.y)
	_segs.append(Seg.new(from, from + Vector2(width, rise)))


## The floor piece reaching furthest right (the last laid, unless a level laid floor
## out to the left with `at`): the goal and endless floor go on after it.
func _rightmost() -> Seg:
	var best: Seg = _segs.back()
	for s in _segs:
		if s.x1 > best.x1:
			best = s
	return best


func _append_random_platform() -> void:
	var last_y: float = _segs.back().y1
	var top := _area.y * 0.35
	var bottom := _area.y * 0.85
	var max_rise := minf(step_up.y, jump_velocity * jump_velocity / (2.0 * gravity) * 0.6)
	var up := _rng.randf() < step_up_chance
	# Force the direction near the vertical limits so steps never flatten out.
	if last_y - step_up.x < top:
		up = false
	elif last_y + step_down.x > bottom:
		up = true
	var y := last_y
	if up:
		y = maxf(y - _rng.randf_range(step_up.x, max_rise), top)
	else:
		y = minf(y + _rng.randf_range(step_down.x, step_down.y), bottom)
	var width := _rng.randf_range(platform_width.x, platform_width.y)
	var rise := 0.0
	if _rng.randf() < slope_chance:
		rise = tan(deg_to_rad(_rng.randf_range(random_slope.x, random_slope.y))) * width
		rise = clampf(y + rise, top, bottom) - y
	_append_platform(width, y - last_y, rise)


## Adds ground after the last segment (or `after`): `step` is the vertical jump at its
## start, `rise` the height change along it (negative = up, positive = down).
func _append_platform(width: float, step: float, rise: float, gap := 0.0, after: Seg = null) -> void:
	var last: Seg = after if after != null else _segs.back()
	if step < 0.0:
		# The board must be able to land on `last` and pop again before this wall.
		# Sized for max speed, since the player can push up to it before arriving.
		# Plus a board length: rolling off a ledge, the tail leaves it last.
		var room := top_speed * pixels_per_meter * (_last_arrival_time + reaction_time) + board_size.x
		if last.x1 - last.x0 < room:
			# Extend with flat ground (not along the slope, which could leave the screen).
			var end := Vector2(last.x1, last.y1)
			var extension := Seg.new(end, end + Vector2(room - (last.x1 - last.x0), 0.0))
			last.link(extension)
			last = extension
			_segs.append(last)
		_last_arrival_time = _full_pop_landing_time(-step)
	elif step > 0.0:
		_last_arrival_time = sqrt(2.0 * step / gravity)
	else:
		_last_arrival_time = 0.0
	# Random gaps scale with speed so they're measured in time, not pixels.
	gap += _speed * _rng.randf_range(gap_time.x, gap_time.y)
	var from := Vector2(last.x1 + gap, last.y1 + step)
	last.link(Seg.new(from, from + Vector2(width, rise)))
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
			chain.back().link(piece)
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
	_dead = true
	_slam_t = 0.0
	_let_go()
	slammed.emit(reason)


## The rider is off: the board flies on as a loose body with the velocity it had,
## tumbling forward.
func _let_go() -> void:
	_slam_distance = _distance
	_fall_at = _pos
	_fall_distance = _distance
	_fall_vy = minf(_velocity_y, 0.0) if not _grounded else 0.0
	_fall_vx = _dir * _speed * 0.6
	_fall_t = 0.0
	if _impact != Vector2.ZERO:
		_body_v = _impact  # Slammed touching down: it hits with the speed it came down at.
	elif _grounded or _rail != null:
		_body_v = Vector2.from_angle(_ground_angle) * _speed * _dir
	else:
		_body_v = Vector2(_dir * _speed, _velocity_y)
	_air_base = 0.0
	_angular_velocity = maxf(slam_spin * _body_v.length() / pixels_per_meter, 3.0)
	_grounded = false
	_rail = null
	_slide = 0.0


func _step_slam(delta: float) -> void:
	_slam_t += delta
	_step_loose(delta)
	_velocity_y = _body_v.y  # For the view.
	_follow_ground(delta)
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
	var ground := _seg_at(_pos.x, prev.y)
	var was := _seg_at(prev.x, prev.y)
	if ground != null and was != null and ground != was and _joint(was, ground, 1.0 if _body_v.x >= 0.0 else -1.0) == &"step_up" \
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
	# The level is drawn where it was between the last two steps; the board likewise
	# (board_pose()).
	draw_set_transform(Vector2(_view_dx, 0.0))
	var prev_of := {}
	for s in _segs:
		if s.next != null:
			prev_of[s.next] = s
	for s in _segs:
		if not _on_screen(s):
			continue
		var bottom := maxf(maxf(_cam, _view_cam) + _area.y, maxf(s.y0, s.y1) + 1.0)
		var points := _surface_line(s)
		if _floor_below(s):
			# Another floor runs under it: a slab floor_slab px thick, not filled down,
			# mitred with the pieces either side so the bends have no notches.
			points.append_array([Vector2(s.x1, s.y1) + _slab_offset(s, s.next),
					Vector2(s.x0, s.y0) + _slab_offset(s, prev_of.get(s))])
		else:
			points.append_array([Vector2(s.x1, bottom), Vector2(s.x0, bottom)])
		# UVs in world space (scrolled by distance travelled) so the texture moves with the ground.
		var uvs := PackedVector2Array()
		for p in points:
			uvs.append(_ground_uv(p))
		draw_colored_polygon(points, Color.WHITE, uvs, _ground_texture)
	for s in _segs:
		if _on_screen(s):
			if _edge_strip:
				_draw_edge_strip(_surface_line(s))
			else:
				draw_polyline(_surface_line(s), edge_color, 5.0)
	_draw_props()
	_draw_platforms()
	_draw_rails()
	_draw_goal()
	draw_set_transform(Vector2.ZERO)
	if not is_instance_valid(skater_view):
		draw_skater_at(self, skater_pose())
	_draw_board()


## Some of `s` is across the view (drawn this frame, shifted by _view_dx).
func _on_screen(s: Seg) -> bool:
	return s.x1 + _view_dx >= -100.0 and s.x0 + _view_dx <= _area.x + 100.0


## Another floor runs under some of `s` (see `at` in Levels).
func _floor_below(s: Seg) -> bool:
	for other in _segs:
		var lo := maxf(s.x0, other.x0)
		var hi := minf(s.x1, other.x1)
		if other != s and hi > lo and other.y_at((lo + hi) * 0.5) > s.y_at((lo + hi) * 0.5) + floor_slab:
			return true
	return false


## Where the underside of a slab (see _floor_below) is below the end of `s` it shares
## with `beside` (null: a square end): floor_slab down, along both pieces' normals.
func _slab_offset(s: Seg, beside: Seg) -> Vector2:
	var down := Vector2.from_angle(s.angle()).orthogonal() * -1.0
	if beside == null:
		return down * floor_slab
	var mitre := (down + Vector2.from_angle(beside.angle()).orthogonal() * -1.0).normalized()
	return mitre * floor_slab / maxf(mitre.dot(down), 0.3)


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


## Where `p` (drawn this frame) is on the ground texture: world space, scrolled by the
## distance travelled, so the texture moves with the ground.
func _ground_uv(p: Vector2) -> Vector2:
	return (p + Vector2(_distance, 0.0)) / _ground_repeat


## `texture` drawn with hard pixels, repeating.
static func _pixel_texture(texture: Texture2D) -> Texture2D:
	var canvas := CanvasTexture.new()
	canvas.diffuse_texture = texture
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return canvas


## The edge strip under a surface line: a band edge_texture tall (at tile_pixel) hanging
## below each piece, repeating along x. Stair risers (vertical) get none.
func _draw_edge_strip(line: PackedVector2Array) -> void:
	var repeat := edge_texture.get_size() * tile_pixel
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var d := b - a
		if absf(d.x) < 0.5:
			continue
		var down := Vector2(-d.y, d.x).normalized()
		if down.y < 0.0:
			down = -down
		var u0 := (a.x + _distance) / repeat.x
		var u1 := (b.x + _distance) / repeat.x
		draw_colored_polygon(PackedVector2Array([a, b, b + down * repeat.y, a + down * repeat.y]), Color.WHITE,
				PackedVector2Array([Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)]), _edge_strip)


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


## The props and obstacles on the floor (see _add_props, _add_obstacles): standing on
## its surface line, behind the platforms, rails and the skater; props see-through.
func _draw_props() -> void:
	for s in _segs:
		for prop: Array in s.props:
			_draw_standing(s, prop[0], prop[1], Color(1, 1, 1, prop_alpha))
		for obstacle: Dictionary in s.obstacles:
			_draw_standing(s, obstacle.texture, obstacle.at, Color.WHITE)


## `texture` standing on `s`, its middle `at` px along it, at PIXEL.
func _draw_standing(s: Seg, texture: Texture2D, at: float, modulate: Color) -> void:
	var size := (texture.get_size() as Vector2) * PIXEL
	var x := s.x0 + at
	if x + size.x * 0.5 + _view_dx < 0.0 or x - size.x * 0.5 + _view_dx > _area.x:
		return
	# Its bottom row on the line.
	var corner := Vector2(x - size.x * 0.5, s.y_at(x) - size.y)
	draw_texture_rect(texture, Rect2(corner.round(), size), false, modulate)


func _draw_platforms() -> void:
	for platform in _platforms:
		if platform.get("hidden", false):
			continue  # An obstacle's top: its sprite draws it.
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
				var top := _platform_top(chain, x)
				var ground := _seg_at(x, top)
				points.append(Vector2(x, ground.y_at(x) if ground else top + overhang_depth))
				if x <= first.x0:
					break
				x = maxf(x - 16.0, first.x0)
		var uvs := PackedVector2Array()
		for p in points:
			uvs.append(_ground_uv(p))
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
			var ground := _seg_at(x, rail.y_at(x))
			if ground != null:  # No posts over gaps: the rail spans them.
				draw_line(Vector2(x, rail.y_at(x)), Vector2(x, ground.y_at(x)), rail_post_color, 6.0)
		draw_line(Vector2(rail.x0, rail.y0), Vector2(rail.x1, rail.y1), rail_color, 7.0)


func _draw_goal() -> void:
	if not _goal_spawned or not is_finite(_goal_x):
		return
	var goal_seg := _seg_at(_goal_x, _goal_y)
	var ground := goal_seg.y_at(_goal_x) if goal_seg else _area.y
	var top := ground - 140.0
	draw_line(Vector2(_goal_x, ground), Vector2(_goal_x, top), goal_color, 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(_goal_x, top), Vector2(_goal_x + 60.0, top + 22.0), Vector2(_goal_x, top + 44.0),
	]), goal_color)


func _draw_board() -> void:
	if is_instance_valid(board_view):
		return  # The 3D board (BoardView) draws it.
	var pose := board_pose()
	draw_board_at(self, pose[0], pose[1], pose[2])


## How the board sits this frame, for the 3D board (BoardView) and board_pose():
## {anchor (a point on screen), local_anchor (the point of the board placed on it),
## angle (in the screen plane), roll (flips: turns around the long axis), yaw (shuvits,
## body turns and slides: turns around the deck's up)}. Board space (px at the default
## board_size): x = -48..48 along the deck, y down (wheels touch y = +14, kicktails
## reach y = -13), z toward the camera. Roll and yaw follow the right hand rule in a
## y-up space: a kickflip rolls the toe edge down, a backside shuvit takes the tail
## behind the skater's back.
func board_motion() -> Dictionary:
	# The anchor: the wheel contact midpoint, or the rolling wheel during a manual.
	var base_scale := board_size / Vector2(96.0, 28.0)
	var anchor := _view_pos
	var local_anchor := Vector2(0.0, 14.0)
	var roll := 0.0
	var yaw := 0.0
	var facing := 1.0 if facing_camera() else -1.0  # Chest to the camera, or back to it.
	if (_grounded or _rail != null) and _tilt_dir() != 0.0 and _slam_t < 0.0:
		var wheel := _riding_manual  # Manual (-1) rolls on the back wheel, nose manual (+1) on the front.
		anchor = _view_pos + Vector2(wheel * _wheel_offset(), 0.0).rotated(_ground_angle)
		local_anchor = Vector2(wheel * WHEEL_X, 14.0)
	if _board_trick != &"" and _slam_t < 0.0:
		var loop := _board_trick_t / _trick_cycle()
		if _trick_flips > 0:
			# Flips roll around the long axis about the middle of the board.
			anchor = _view_pos + (Vector2(0.0, -7.0) * base_scale).rotated(_view_angle)
			local_anchor = Vector2(0.0, -7.0)
			roll = loop * _trick_flips * TAU * facing * (1.0 if _trick_flip_kind == &"kickflip" else -1.0)
		if _trick_shuvs > 0:
			# Shuvits turn around the vertical axis, half a turn each.
			yaw += loop * _trick_shuvs * PI * facing * (-1.0 if _trick_shuv_kind == &"shuvit" else 1.0)
	if _body_turn >= 0.0 and _slam_t < 0.0 and not _grounded and _rail == null:
		# Body 180: the board turns around its vertical axis with the skater.
		yaw += _body_turn / body_turn_time * PI * facing * (1.0 if _body_front else -1.0)
	if _slide > 0.0 and _slam_t < 0.0:
		# Slide: the board swings across the ledge (seen end-on, so it shortens) and
		# rests on its tail or nose, with the trucks hanging over the edge.
		var k := smoothstep(0.0, 1.0, _slide)
		yaw += deg_to_rad(slide_angle) * k
		if _rail != null and _rail.ledge:
			anchor = _view_pos
			local_anchor = local_anchor.lerp(Vector2(signf(_riding_manual) * 40.0, -1.0), k)
	return {anchor = anchor, local_anchor = local_anchor, angle = _view_angle, roll = roll, yaw = yaw}


## Where and how the board is drawn flat this frame: [center, angle, scale], with the
## scale's signs and size carrying flips, shuvits and slides (board_motion() seen from
## the side). Ghosts reuse it.
func board_pose() -> Array:
	var m := board_motion()
	var board_scale := board_size / Vector2(96.0, 28.0) * Vector2(cos(m.yaw), cos(m.roll))
	var local_anchor: Vector2 = m.local_anchor
	var anchor: Vector2 = m.anchor
	return [anchor - (local_anchor * board_scale).rotated(m.angle), m.angle, board_scale]


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
## Both work on what's drawn this frame (between the last two steps).
func to_level(screen: Vector2) -> Vector2:
	return Vector2(screen.x + _distance - _view_dx - _origin.x, screen.y - _origin.y)


func from_level(level: Vector2) -> Vector2:
	return Vector2(level.x - _distance + _view_dx + _origin.x, level.y + _origin.y)
