extends Node2D
## Other online skaters on the same challenge, drawn as faded skaters (SkaterView rigs)
## on faded boards with their names,
## plus a name tag over the player's own board. A child of the Runner (shares its
## coordinates).
##
## Each ghost is a simulation: a hidden Runner of the same level, started from the
## rider's snapshot and fed their actions at the steps they did them, so it rides just
## like they did, flips and slams included. It plays delay_steps behind the newest
## actions, speeding up or slowing down a little to stay there. Each later snapshot is
## checked when the simulation reaches its step; if it drifted (or missed something),
## it's restarted from the snapshot.

@export var alpha := 0.45
@export var ghost_color := Color(0.65, 0.8, 1.0)
@export var name_size := 22
## Name tags float this far above the board center (px).
@export var name_lift := 160.0
## How far behind the newest actions a ghost plays (steps): enough that the next batch
## (Online.SEND_RATE a second) is normally in before it's needed.
@export var delay_steps := 30
## A ghost this many delays behind (just started from an older snapshot, or after a
## stall) jumps straight to delay_steps behind, simulated without being drawn, instead of
## visibly speeding up to catch up.
@export var jump_behind := 3.0
## Riders send Online.SEND_RATE batches a second: a ghost with nothing new for this long
## is hidden (s), and dropped after forget_time.
@export var stale_time := 1.0
@export var forget_time := 10.0

## Each id: {skater, sim: Runner (null until the first snapshot), snapshots: [state]
## not reached yet, actions: [[tick, action, a, b]] not applied yet, through: steps
## covered by the actions, play: step being shown (fractional), heard: _clock when
## last heard from, restarts: int}.
var _ghosts := {}
## Seconds since this node started, counted in frames (so it pauses with the game).
var _clock := 0.0

@onready var _runner: Runner = get_parent()
## Draws the name tags: the last child, so they're over the ghosts' figures.
var _tags := Node2D.new()


func _ready() -> void:
	_tags.draw.connect(_draw_tags)
	add_child(_tags)
	Online.ghost_joined.connect(_on_joined)
	Online.ghost_left.connect(_on_left)
	Online.ghost_snapshot.connect(_on_snapshot)
	Online.ghost_actions.connect(_on_actions)
	Online.status_changed.connect(func(status: StringName) -> void:
		if status != &"online":
			_clear())  # On rejoining, the room sends everyone again.


func _clear() -> void:
	for id in _ghosts.keys():
		_on_left(id)


func _on_joined(id: int, skater: String) -> void:
	_on_left(id)
	# The ghost's figure: the same rig as the player's, in the default outfit (outfits
	# aren't sent online), tinted and faded.
	var view := SkaterView.new()
	view.pixel = _runner.skater_pixel
	view.modulate = Color(Color.WHITE.lerp(ghost_color, 0.6), alpha)
	view.visible = false
	add_child(view)
	move_child(view, 0)  # Under the name tags.
	_ghosts[id] = {skater = skater, sim = null, snapshots = [], actions = [], through = 0,
			play = 0.0, heard = _clock, restarts = 0, view = view}


func _on_left(id: int) -> void:
	if _ghosts.has(id) and _ghosts[id].sim:
		_ghosts[id].sim.queue_free()
	if _ghosts.has(id):
		_ghosts[id].view.queue_free()
	_ghosts.erase(id)


func _on_snapshot(id: int, state: Array) -> void:
	if not _ghosts.has(id):
		_on_joined(id, "?????")
	var ghost: Dictionary = _ghosts[id]
	ghost.heard = _clock
	if not _valid(state):
		return
	if ghost.sim == null:
		_restart(ghost, state)  # First sight: start from here.
	elif _tick_of(state) >= ghost.sim.tick:
		ghost.snapshots.append(state)  # Checked when the simulation gets there.


func _on_actions(id: int, through: int, actions: PackedFloat64Array) -> void:
	if not _ghosts.has(id):
		_on_joined(id, "?????")
	var ghost: Dictionary = _ghosts[id]
	ghost.heard = _clock
	for i in range(0, actions.size() - 3, 4):
		ghost.actions.append([int(actions[i]), int(actions[i + 1]), actions[i + 2], actions[i + 3]])
	ghost.through = maxi(ghost.through, through)


func _process(delta: float) -> void:
	_clock += delta
	for id in _ghosts.keys():
		var ghost: Dictionary = _ghosts[id]
		if _clock - ghost.heard > forget_time:
			_on_left(id)
		elif ghost.sim != null:
			_advance(ghost, delta)
	queue_redraw()


## Plays the ghost on towards delay_steps behind its newest actions: at normal speed when
## it's there, a little faster (up to 1.1x) when behind, slower (down to 0.75x) when the
## actions run short, and never past them. Far behind, it jumps.
func _advance(ghost: Dictionary, delta: float) -> void:
	var behind: float = ghost.through - ghost.play
	var max_steps := Runner.MAX_STEPS * 2
	if behind > delay_steps * jump_behind:
		ghost.play = ghost.through - delay_steps
		max_steps = int(behind) + 1  # Catch up all at once, not drawn on the way.
	else:
		var rate := clampf(1.0 + 0.25 * (behind - delay_steps) / delay_steps, 0.75, 1.1)
		ghost.play = minf(ghost.play + delta * Runner.STEP_RATE * rate, ghost.through)
	var steps := 0
	while ghost.sim.tick < int(ghost.play) and steps < max_steps:
		_check_snapshot(ghost)  # May restart it: a new sim.
		_apply_actions(ghost)
		ghost.sim.step()
		steps += 1
	var sim: Runner = ghost.sim
	if sim.tick < int(ghost.play):
		ghost.play = sim.tick  # Too far behind to catch up in one frame.
	sim.set_view(ghost.play - floorf(ghost.play))


## At a snapshot's step: if the simulation isn't where the rider was, restart it there.
func _check_snapshot(ghost: Dictionary) -> void:
	var snapshots: Array = ghost.snapshots
	while not snapshots.is_empty() and _tick_of(snapshots[0]) < ghost.sim.tick:
		snapshots.pop_front()  # Passed (it came in late).
	if snapshots.is_empty() or _tick_of(snapshots[0]) != ghost.sim.tick:
		return
	var state: Array = snapshots.pop_front()
	if not ghost.sim.matches_state(state):
		_restart(ghost, state)


## Applies the actions done before the step the simulation is about to run.
func _apply_actions(ghost: Dictionary) -> void:
	var actions: Array = ghost.actions
	var sim: Runner = ghost.sim
	while not actions.is_empty() and actions[0][0] <= sim.tick:
		var action: Array = actions.pop_front()
		if action[0] == sim.tick:  # Older ones were before the snapshot it started from.
			sim.act(action[1], action[2], action[3])


## (Re)starts the ghost's simulation from a snapshot.
func _restart(ghost: Dictionary, state: Array) -> void:
	if ghost.sim:
		ghost.sim.queue_free()
		ghost.restarts += 1
	var sim := Runner.new()
	sim.manual = true
	sim.visible = false
	sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)
	sim.configure(Levels.get_level(Levels.current))
	sim.set_state(state)
	ghost.sim = sim
	ghost.play = maxf(ghost.play, sim.tick)
	ghost.through = maxi(ghost.through, sim.tick)
	var snapshots: Array = ghost.snapshots
	while not snapshots.is_empty() and _tick_of(snapshots[0]) <= sim.tick:
		snapshots.pop_front()


func _tick_of(state: Array) -> int:
	return state[1 + Runner.STATE.find(&"tick")]


## A state from get_state(), as far as can be told without trusting it.
func _valid(state: Array) -> bool:
	return state.size() == Runner.STATE.size() + 3 and state[0] is Vector2 \
			and state[0].x > 0.0 and state[0].y > 0.0 and state[0].x < 10000.0 and state[0].y < 10000.0 \
			and state[1 + Runner.STATE.find(&"tick")] is int


func _draw() -> void:
	for ghost in _ghosts.values():
		var view: SkaterView = ghost.view
		view.visible = ghost.sim != null and _clock - ghost.heard <= stale_time
		if not view.visible:
			continue
		var sim: Runner = ghost.sim
		var pose := sim.board_pose()
		var center := _runner.from_level(sim.to_level(pose[0]))
		var figure := sim.skater_pose()
		view.show_pose(_moved(figure, center - pose[0]), sim.board_size.x / 96.0)
		# Seen from behind, the board is in front of the feet (see SkaterView): drawn over
		# the figure, with the name tags.
		ghost.board = [center, pose[1], pose[2]]
		ghost.board_over = figure.get("back", false)
		if not ghost.board_over:
			_runner.draw_board_at(self, center, pose[1], pose[2], alpha, ghost_color)
		ghost.center = center
	_tags.queue_redraw()


## The name tags, over the ghosts' figures (on _tags, the last child), and the boards of
## ghosts seen from behind (over their figures).
func _draw_tags() -> void:
	for ghost in _ghosts.values():
		if ghost.view.visible and ghost.get("board_over", false):
			var b: Array = ghost.board
			_runner.draw_board_at(_tags, b[0], b[1], b[2], alpha, ghost_color)
	for ghost in _ghosts.values():
		if ghost.view.visible and ghost.has("center"):
			_draw_name(ghost.center, ghost.skater, Color(ghost_color, 0.8))
	var pose := _runner.board_pose()
	_draw_name(pose[0], Profile.skater_name, _runner.player_color)


## A skater_pose() moved by `offset`.
static func _moved(pose: Dictionary, offset: Vector2) -> Dictionary:
	var out := pose.duplicate()
	out.base = pose.base + offset
	out.feet = [pose.feet[0] + offset, pose.feet[1] + offset]
	return out


func _draw_name(center: Vector2, text: String, color: Color) -> void:
	var font: Font = UiKit.UI_FONT
	# The same size on screen however small the world is drawn (Main.world_zoom).
	var unzoom := 1.0 / maxf(_tags.get_global_transform().get_scale().x, 0.1)
	var font_size := roundi(name_size * unzoom)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := center + Vector2(-width * 0.5, -name_lift)
	_tags.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, roundi(6 * unzoom),
			Color(0, 0, 0, color.a * 0.8))
	_tags.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
