extends Control

## Global time scale; set below 1 to slow everything down while tuning mechanics.
@export var game_speed := 1.0

const MENU_SCENE := "res://scenes/menu.tscn"

## Whether the stats (speed, last inputs) are shown; kept across restarts.
static var show_stats := false

@onready var play_area: Control = $Layout/PlayArea
@onready var runner: Runner = $Layout/PlayArea/World/Runner
@onready var callouts: Node2D = $Layout/PlayArea/World/Runner/Callouts
@onready var control_panel: PanelContainer = $Layout/ControlPanel
@onready var menu_button: Button = $Layout/PlayArea/HUD/Top/Menu
@onready var stats_button: Button = $Layout/PlayArea/HUD/Top/Stats
@onready var score_label: Label = $Layout/PlayArea/HUD/Top/Score
@onready var speed_label: Label = $Layout/PlayArea/HUD/Top/Speed
@onready var last_input: Label = $Layout/PlayArea/HUD/Top/LastInput
@onready var push_pad: Pad = $Layout/ControlPanel/SafeArea/GroundPads/Push
@onready var trick_pad: TrickPad = $Layout/ControlPanel/SafeArea/AirPads/Trick
@onready var balance_pad: BalancePad = $Layout/ControlPanel/SafeArea/BalancePads/Balance
@onready var balance_pop_pad: Pad = $Layout/ControlPanel/SafeArea/BalancePads/BalancePop
@onready var pop_pads: Array[Pad] = [
	$Layout/ControlPanel/SafeArea/GroundPads/TailPop,
	$Layout/ControlPanel/SafeArea/GroundPads/NosePop,
]
## Guided steps, on tutorial levels only.
var tutorial: Tutorial
## Flow meter and slow-motion button, just above the control panel.
var flow: FlowButton
## Online ghosts and name tags, on challenges with the online switch on.
var ghosts: Node2D
## Fingers holding CATCH.
var _catch_holds := 0
## Actions not yet sent to the ghost room: [tick, action, a, b] each.
var _actions := PackedFloat64Array()
## The latest snapshot and every action since, to send again on (re)connecting.
var _last_snapshot: Array = []
var _actions_since := PackedFloat64Array()
## Time until the next batch of actions goes to the ghost room (s).
var _send_left := 0.0
## The level as defined (not cut at a checkpoint), for finding checkpoints in it.
var _level: Dictionary
## A checkpoint counts as reached this close before its mark, on the ground (px).
const CHECKPOINT_LEAD := 600.0


func _ready() -> void:
	Engine.time_scale = game_speed
	_level = Levels.get_level(Levels.current)
	var level := _level
	if Levels.checkpoint != "":
		level = Levels.from_checkpoint(_level, Levels.checkpoint)
	runner.configure(level)
	# The tutorial freezes the game by pausing the tree: only the world and the
	# balance points stop, the UI keeps taking input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Layout/PlayArea/World.process_mode = Node.PROCESS_MODE_PAUSABLE
	balance_pad.process_mode = Node.PROCESS_MODE_PAUSABLE
	flow = FlowButton.new()
	flow.action = &"flow"
	flow.color = Color(1.0, 0.75, 0.25)
	flow.runner = runner
	flow.base_time_scale = game_speed
	add_child(flow)
	flow.tapped.connect(func() -> void: _on_pad_pressed(&"flow", Time.get_ticks_usec(), Vector2.ZERO))
	runner.landed.connect(flow.on_landed)
	runner.slammed.connect(func(_reason: String) -> void: flow.on_slammed())
	Profile.load_profile()
	if _level.get("challenge", false) and Profile.online:
		ghosts = preload("res://scripts/ghosts.gd").new()
		runner.add_child(ghosts)
		runner.move_child(ghosts, 0)  # Under the callouts.
		Online.join(_level.id)
		runner.acted.connect(func(at_tick: int, action: int, a: float, b: float) -> void:
			_actions.append_array([at_tick, action, a, b])
			_actions_since.append_array([at_tick, action, a, b]))
		Online.status_changed.connect(_on_online_status)
	if level.get("tutorial", false):
		runner.forgiving = true  # No slams in the tutorial.
		tutorial = Tutorial.new()
		tutorial.runner = runner
		tutorial.balance_pad = balance_pad
		tutorial.play_area = play_area
		tutorial.pads = control_panel._pads.duplicate()
		tutorial.pads.append(flow)
		tutorial.flow = flow
		tutorial.start_section = Levels.checkpoint
		add_child(tutorial)
	play_area.resized.connect(_layout_world)
	control_panel.pad_pressed.connect(_on_pad_pressed)
	control_panel.pad_released.connect(_on_pad_released)
	menu_button.icon = Icons.menu_texture(32)
	menu_button.pressed.connect(_to_menu)
	stats_button.button_pressed = show_stats
	stats_button.toggled.connect(_show_stats)
	_show_stats(show_stats)
	runner.airborne_changed.connect(func(_airborne: bool) -> void: _update_layout())
	runner.score_changed.connect(func(score: int) -> void: score_label.text = str(score))
	runner.speed_changed.connect(_show_speed)
	runner.pushed.connect(_on_pushed)
	runner.popped.connect(_on_popped)
	runner.dropped.connect(func() -> void: last_input.text = "drop")
	runner.caught.connect(_on_caught)
	runner.trick_started.connect(func(trick: String) -> void: last_input.text += "\n" + trick)
	runner.trick_caught.connect(func(trick: String) -> void: last_input.text += "\n%s caught" % trick)
	runner.slammed.connect(_on_slammed)
	runner.balance_changed.connect(_on_balance_changed)
	runner.callout.connect(callouts.show_callout)
	balance_pad.fell.connect(func() -> void: runner.act(Runner.Act.LOSE_BALANCE))
	var meter := BalanceMeter.new()
	meter.pad = balance_pad
	runner.add_child(meter)
	runner.landed.connect(func(style: String) -> void: last_input.text += "\n" + style)
	runner.level_cleared.connect(_on_level_cleared)
	runner.game_over.connect(_on_game_over)
	_layout_world()
	_update_layout()
	_show_speed(runner.start_speed * runner.pixels_per_meter)


func _process(delta: float) -> void:
	push_pad.set_pie(runner.push_progress(), runner.queued_pushes())
	for pad in pop_pads:
		pad.set_enabled(not runner.is_pushing())
	trick_pad.set_enabled(runner.can_board_trick())
	if runner.is_balancing():
		_follow_balance_finger()
	_update_checkpoint()
	if ghosts:
		_send_run(delta)


## The finger still down from landing plays the balance trick: sliding it left or right
## steers the balance needle, sliding it up into POP pops out. Runs while frozen too.
func _follow_balance_finger() -> void:
	var fingers: Array[Vector2] = control_panel.touches_of(&"lock_tilt")
	if fingers.is_empty():
		return
	var at: Vector2 = fingers[0]
	balance_pad.steer(at.x)
	if tutorial and balance_pad.finger_centered():
		tutorial.accept(&"balance", Vector2.ZERO)
	if balance_pop_pad.get_global_rect().has_point(at) and (not tutorial or tutorial.accept(&"balance_pop", Vector2.ZERO)):
		balance_pop_pad.flash()
		runner.act(Runner.Act.BALANCE_POP)


func _update_layout() -> void:
	control_panel.set_layout(runner.is_airborne(), runner.is_balancing())


func _exit_tree() -> void:
	if ghosts:
		Online.leave()


## Just connected (late, or again): the room gets the run so far, from the latest
## snapshot on.
func _on_online_status(status: StringName) -> void:
	if status == &"online" and not _last_snapshot.is_empty():
		Online.send_snapshot(_last_snapshot)
		Online.send_actions(runner.tick, _actions_since)
		_actions = PackedFloat64Array()
		_send_left = 1.0 / Online.SEND_RATE  # The server drops batches sent too close.


## Sends the run to the ghost room so others can replay it: the actions, Online.SEND_RATE
## times a second, and the runner's snapshots as they're taken.
func _send_run(delta: float) -> void:
	var snapshot := runner.take_snapshot()
	if not snapshot.is_empty():
		_last_snapshot = snapshot
		_actions_since = _actions.duplicate()  # Not sent yet: they're after it.
		Online.send_snapshot(snapshot)
	_send_left -= delta
	if _send_left > 0.0:
		return
	_send_left = 1.0 / Online.SEND_RATE
	Online.send_actions(runner.tick, _actions)
	_actions = PackedFloat64Array()


## Records the furthest marked segment coming up while riding calmly (on the ground,
## not balancing), so a slam in what follows restarts there.
func _update_checkpoint() -> void:
	if not _level.get("checkpoints", true) or not runner.is_grounded() or runner.is_balancing():
		return
	var x := runner.board_position().x
	var best := Levels.mark_index(_level, Levels.checkpoint)
	for mark in runner.marks:
		var index := Levels.mark_index(_level, mark)
		if index > best and runner.marks[mark].x - x < CHECKPOINT_LEAD:
			best = index
			Levels.checkpoint = mark


func _layout_world() -> void:
	runner.setup(play_area.size)
	if flow:
		var area := play_area.get_global_rect()
		flow.position = Vector2(area.get_center().x - flow.radius, area.end.y - flow.radius * 2.0 - 16.0)


func _on_pad_pressed(action: StringName, _time_usec: int, local_pos: Vector2) -> void:
	# Pop and push strength come from touch height (top = strongest),
	# the tilt lock angle from touch x.
	if action == &"balance" or action == &"balance_pop":
		if tutorial:
			tutorial.hint_balance_tap()
		return
	if tutorial and not tutorial.accept(action, local_pos):
		return
	match action:
		&"tail_pop":
			runner.act(Runner.Act.POP, 0.0, -local_pos.y)
		&"nose_pop":
			runner.act(Runner.Act.POP, 1.0, -local_pos.y)
		&"push":
			runner.act(Runner.Act.PUSH, -local_pos.y)
		&"balance", &"balance_pop":
			pass  # Only the finger held from the landing plays these (_follow_balance_finger).
		&"lock_tilt":
			_catch_holds += 1
			runner.act(Runner.Act.PRESS_CATCH, local_pos.x)
		&"trick":
			runner.act(Runner.Act.BOARD_TRICK, Runner.TRICKS.find(trick_pad.trick_at(local_pos)))
		&"flow":
			flow.activate()


func _show_stats(shown: bool) -> void:
	show_stats = shown
	speed_label.visible = shown
	last_input.visible = shown


## A finger lifted. CATCH counts its fingers: the hold ends when the last one lifts. If
## a manual or grind is being ridden, that ends it cleanly.
func _on_pad_released(action: StringName) -> void:
	if tutorial:
		tutorial.released(action)
	if action == &"lock_tilt":
		_catch_holds = maxi(_catch_holds - 1, 0)
		if _catch_holds == 0:
			runner.act(Runner.Act.RELEASE_CATCH)
			runner.act(Runner.Act.END_BALANCE)


## `speed` in px/s, shown in km/h.
func _show_speed(speed: float) -> void:
	speed_label.text = "%.1f km/h" % (speed / runner.pixels_per_meter * 3.6)


func _on_pushed(strength: float, speed: float, queued: bool) -> void:
	last_input.text = "push %d%%%s" % [roundi(strength * 100.0), "  (queued)" if queued else ""]
	_show_speed(speed)


func _on_popped(nose: bool, strength: float) -> void:
	trick_pad.set_pop_side(nose)
	last_input.text = "%s pop %d%%" % ["nose" if nose else "tail", roundi(strength * 100.0)]


func _on_slammed(reason: String) -> void:
	balance_pad.freeze()
	callouts.slam()
	last_input.text += "\nSLAM: " + reason


## While a manual or grind is ridden the pads switch to the balance layout: POP (from
## the end being ridden) over the balance strip (harder on 5-0s, nosegrinds and slides).
func _on_balance_changed(mode: StringName) -> void:
	var balancing := mode != &""
	if not balancing:
		callouts.end_sustained()
		# The finger that played it is used up (e.g. still down after popping out): it
		# mustn't count as holding CATCH in the next trick.
		control_panel.spend(&"lock_tilt")
		_catch_holds = 0
	_update_layout()
	balance_pad.set_active(balancing, mode == &"grind")
	balance_pop_pad.set_label("POP NOSE" if runner._riding_manual > 0.0 and mode != &"fifty" else "POP TAIL")
	if not balancing and runner.is_grounded():
		last_input.text += "\nwheels down"


func _on_caught(catch_index: int, angle_deg: float, apex_ms: int) -> void:
	var what: String = ["catch %+.0f°" % angle_deg, "timed catch"][catch_index - 1]
	last_input.text += "\n%s  apex %+d ms" % [what, apex_ms]


func _on_level_cleared() -> void:
	last_input.text = "CLEARED!"
	Levels.record(Levels.current, 1.0)
	Levels.checkpoint = ""
	if _level.get("challenge", false) and Profile.online:
		# On the board: send the clear and show the board when back on the menu.
		Scoreboard.record_clear(_level.id)
		preload("res://scripts/menu.gd").page = "board:" + _level.id
	await get_tree().create_timer(1.0, true, false, true).timeout
	_to_menu()


func _to_menu() -> void:
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _on_game_over() -> void:
	Levels.record(Levels.current, runner.progress())
	get_tree().reload_current_scene.call_deferred()
