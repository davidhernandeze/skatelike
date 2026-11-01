extends Node2D
## Other online skaters on the same challenge, drawn as faded boards with their names,
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
@export var name_lift := 34.0
## How far behind the newest actions a ghost plays (steps): enough that the next batch
## (Online.SEND_RATE a second) is normally in before it's needed.
@export var delay_steps := 30
## Ghosts with nothing new for this long are hidden (s).
@export var stale_time := 3.0

## Each id: {skater, sim: Runner (null until the first snapshot), snapshots: [state]
## not reached yet, actions: [[tick, action, a, b]] not applied yet, through: steps
## covered by the actions, play: step being shown (fractional), heard: _clock when
## last heard from, restarts: int}.
var _ghosts := {}
## Seconds since this node started, counted in frames (so it pauses with the game).
var _clock := 0.0

@onready var _runner: Runner = get_parent()


func _ready() -> void:
	Online.ghost_joined.connect(_on_joined)
	Online.ghost_left.connect(_on_left)
	Online.ghost_snapshot.connect(_on_snapshot)
	Online.ghost_actions.connect(_on_actions)


func _on_joined(id: int, skater: String) -> void:
	_on_left(id)
	_ghosts[id] = {skater = skater, sim = null, snapshots = [], actions = [], through = 0,
			play = 0.0, heard = _clock, restarts = 0}


func _on_left(id: int) -> void:
	if _ghosts.has(id) and _ghosts[id].sim:
		_ghosts[id].sim.queue_free()
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
	for ghost in _ghosts.values():
		if ghost.sim != null:
			_advance(ghost, delta)
	queue_redraw()


## Plays the ghost on towards delay_steps behind its newest actions: at normal speed when
## it's there, up to half again faster when further behind, down to half speed when the
## actions run short, and never past them.
func _advance(ghost: Dictionary, delta: float) -> void:
	var behind: float = ghost.through - ghost.play
	var rate := clampf(0.5 + 0.5 * behind / delay_steps, 0.5, 1.5)
	ghost.play = minf(ghost.play + delta * Runner.STEP_RATE * rate, ghost.through)
	var steps := 0
	while ghost.sim.tick < int(ghost.play) and steps < Runner.MAX_STEPS * 2:
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
		if ghost.sim == null or _clock - ghost.heard > stale_time:
			continue
		var sim: Runner = ghost.sim
		var pose := sim.board_pose()
		var center := _runner.from_level(sim.to_level(pose[0]))
		_runner.draw_board_at(self, center, pose[1], pose[2], alpha, ghost_color)
		_draw_name(center, ghost.skater, Color(ghost_color, 0.8))
	var pose := _runner.board_pose()
	_draw_name(pose[0], Profile.skater_name, _runner.player_color)


func _draw_name(center: Vector2, text: String, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	var at := center + Vector2(-width * 0.5, -name_lift)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, 6, Color(0, 0, 0, color.a * 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, color)
