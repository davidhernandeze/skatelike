extends Control

## Global time scale; set below 1 to slow everything down while tuning mechanics.
@export var game_speed := 1.0

const MENU_SCENE := "res://scenes/menu.tscn"

## Whether the stats (speed, last inputs) are shown; kept across restarts.
static var show_stats := false
## Whether a lesson's explanation panel is shown; kept across restarts.
static var show_tips := true

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
## The explanation panel and goal, on lessons only.
var lesson: Lesson
## The pause screen (see pause()).
var pause_menu: PauseMenu
## The line in progress, under the score (or under the lesson panel).
var _line_label: LineLabel
## "SWITCH" while riding switch (bottom left of the play area).
var _stance_label: Label
## Flow meter and slow-motion button, just above the control panel.
var flow: FlowButton
## Online ghosts and name tags, on challenges with the online switch on.
var ghosts: Node2D
## Fingers holding CATCH.
var _catch_holds := 0
## The finger holding a pop pad: {action, pad, nose, strength, from, at (global), aim,
## balance}. The pop goes when it lifts, however long it was held; sliding sideways
## BODY_SWIPE pad widths aims it into a body 180 (aim -1 left / +1 right), shown on the
## pad. `balance`: it's the POP of a manual or grind (BALANCE_POP), held by a second
## finger on it or by the finger held from the landing sliding up into it (`action` is
## then &"lock_tilt", the finger's own).
var _pop_finger := {}
const BODY_SWIPE := 0.33
## Actions not yet sent to the ghost room: [tick, action, a, b] each.
var _actions := PackedFloat64Array()
## The latest snapshot and every action since, to send again on (re)connecting.
var _last_snapshot: Array = []
var _actions_since := PackedFloat64Array()
## Time until the next batch of actions goes to the ghost room (s).
var _send_left := 0.0
## The level being played.
var _level: Dictionary


func _ready() -> void:
	Engine.time_scale = game_speed
	_level = Levels.get_level(Levels.current)
	runner.configure(_level)  # Every run starts from the beginning: a slam resets it.
	# Pausing stops the game (everything under Layout, and the flow button) while Main
	# keeps the ghost room fed and the pause screen keeps taking input.
	get_tree().paused = false  # A reload can come from a paused game (e.g. a timer).
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Layout.process_mode = Node.PROCESS_MODE_PAUSABLE
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.play.connect(resume)
	pause_menu.restart.connect(restart)
	pause_menu.home.connect(func() -> void:
		get_tree().paused = false
		_to_menu())
	flow = FlowButton.new()
	flow.process_mode = Node.PROCESS_MODE_PAUSABLE
	flow.action = &"flow"
	flow.color = Color(1.0, 0.75, 0.25)
	flow.runner = runner
	flow.base_time_scale = game_speed
	# Free ride levels (not lessons or gaps): flow state without restrictions.
	flow.unlimited = not _level.has("lesson") and not _level.get("challenge", false)
	add_child(flow)
	flow.tapped.connect(func() -> void: _on_pad_pressed(&"flow", Time.get_ticks_usec(), Vector2.ZERO))
	runner.line_event.connect(flow.on_line_event)
	_stance_label = Label.new()
	_stance_label.text = "SWITCH"
	_stance_label.visible = false
	_stance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stance_label.add_theme_font_size_override("font_size", 30)
	_stance_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_stance_label.add_theme_constant_override("outline_size", 8)
	_stance_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
	play_area.add_child(_stance_label)
	_stance_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stance_label.offset_left = 20.0
	_stance_label.offset_top = -64.0
	var line_label := LineLabel.new()
	_line_label = line_label
	play_area.add_child(line_label)
	line_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	line_label.offset_top = 84.0
	if _level.has("lesson"):
		_add_lesson(_level.lesson)
	line_label.offset_left = 16.0
	line_label.offset_right = -16.0
	flow.line_changed.connect(line_label.show_line)
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
	play_area.resized.connect(_layout_world)
	control_panel.pad_pressed.connect(_on_pad_pressed)
	control_panel.pad_released.connect(_on_pad_released)
	# Restart, next to pause: the level from the start, on every level. (Copied before
	# pause is connected: a copy takes the connections along.)
	var restart_button := menu_button.duplicate() as Button
	restart_button.name = "Restart"
	restart_button.icon = Icons.restart_texture(32)
	menu_button.add_sibling(restart_button)
	restart_button.pressed.connect(restart)
	menu_button.icon = Icons.pause_texture(32)
	menu_button.pressed.connect(pause)
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
	var sfx := Sfx.new()
	sfx.runner = runner
	runner.add_child(sfx)
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
	if get_tree().paused:
		if ghosts:
			_send_run(delta)  # Empty batches: the room keeps us while paused.
		return
	if lesson:
		_frame_below_lesson()
	_stance_label.text = runner.stance_name().to_upper()  # SWITCH or FAKIE.
	_stance_label.visible = _stance_label.text != "" and not runner._dead
	push_pad.set_pie(runner.push_progress(), runner.queued_pushes())
	for pad in pop_pads:
		pad.set_enabled(not runner.is_pushing())
	trick_pad.set_enabled(runner.can_board_trick())
	if runner.is_balancing():
		_follow_balance_finger()
	if not _pop_finger.is_empty():
		var at: Array[Vector2] = control_panel.touches_of(_pop_finger.action)
		if not at.is_empty():
			_pop_finger.at = at.back()
			_aim_pop()
	if ghosts:
		_send_run(delta)


## The finger still down from landing plays the balance trick: sliding it left or right
## steers the balance needle, sliding it up into POP holds a pop out (see _pop_finger),
## which goes when it lifts.
func _follow_balance_finger() -> void:
	var fingers: Array[Vector2] = control_panel.touches_of(&"lock_tilt")
	if fingers.is_empty():
		return
	var at: Vector2 = fingers[0]
	var on_pop := balance_pop_pad.get_global_rect().has_point(at)
	var holding: bool = _pop_finger.get("action", &"") == &"lock_tilt"
	if on_pop and _pop_finger.is_empty():
		_hold_pop(&"lock_tilt", 1.0, balance_pop_pad, true)  # Pops when it lifts.
	elif holding and not on_pop and at.y > balance_pop_pad.get_global_rect().end.y:
		_pop_finger.pad.set_aim(false)  # Slid back down: balancing on, no pop.
		_pop_finger = {}
	if _pop_finger.get("action", &"") != &"lock_tilt":
		balance_pad.steer(at.x)  # (Held on POP itself, the needle keeps the last steer.)


## The lesson's explanation panel under the top bar, and the Tips checkbox for it.
func _add_lesson(spec: Dictionary) -> void:
	lesson = Lesson.new()
	lesson.runner = runner
	lesson.flow = flow
	for pad: Pad in control_panel._pads:
		lesson.pads[pad.action] = pad
	play_area.add_child(lesson)
	lesson.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lesson.offset_top = 96.0
	lesson.offset_bottom = 96.0 + 300.0
	lesson.offset_left = 12.0
	lesson.offset_right = -12.0
	lesson.setup(spec)
	lesson.visible = show_tips
	lesson.goal_reached.connect(func() -> void: callouts.show_callout("goal"))
	# A big toggle in the top right corner, its box drawn (the web font has no box glyphs).
	var tips := Button.new()
	tips.text = " TIPS "
	tips.toggle_mode = true
	tips.button_pressed = show_tips
	tips.focus_mode = Control.FOCUS_NONE
	tips.custom_minimum_size = Vector2(170, 72)
	tips.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tips.add_theme_font_size_override("font_size", 32)
	tips.icon = Icons.box_texture(40, show_tips)
	tips.toggled.connect(func(on: bool) -> void:
		show_tips = on
		lesson.visible = on
		tips.icon = Icons.box_texture(40, on))
	_frame_below_lesson()
	stats_button.get_parent().add_child(tips)  # Last in the top bar: the right edge.


## While the explanation panel shows, the view keeps the ground (with room for a pop) and
## the board below it, so neither hides behind it. Its height follows the text.
func _frame_below_lesson() -> void:
	var defaults: Runner = Runner.new()
	var band := defaults.camera_band
	var air_band := defaults.camera_air_band
	defaults.free()
	if lesson.visible and play_area.size.y > 0.0:
		var under := (lesson.offset_bottom + 12.0) / play_area.size.y
		band.x = maxf(band.x, under + 0.22)
		air_band.x = maxf(air_band.x, under + 0.04)
	runner.camera_band = band
	runner.camera_air_band = air_band
	_line_label.offset_top = lesson.offset_bottom + 8.0 if lesson.visible else 84.0


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


func _layout_world() -> void:
	runner.setup(play_area.size)
	if flow:
		var area := play_area.get_global_rect()
		flow.position = Vector2(area.get_center().x - flow.radius, area.end.y - flow.radius * 2.0 - 16.0)


func _on_pad_pressed(action: StringName, _time_usec: int, local_pos: Vector2) -> void:
	# Pop and push strength come from touch height (top = strongest),
	# the tilt lock angle from touch x.
	# During a manual, a second finger on POP pops out too (on grinds only the held one does).
	if action == &"balance_pop" and runner.is_balancing() and not runner.is_grinding():
		if _pop_finger.is_empty():
			_hold_pop(action, 1.0, balance_pop_pad, true)  # Pops when it lifts.
		return
	if action == &"balance" or action == &"balance_pop":
		return  # Only the finger held from the landing plays these (_follow_balance_finger).
	match action:
		&"tail_pop", &"nose_pop":
			_hold_pop(action, -local_pos.y)  # Pops when it lifts.
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


## A finger went down on a pop pad: the pop waits for it to lift (strength from where it
## went down), aimed by sliding meanwhile.
func _hold_pop(action: StringName, strength: float, pad: Pad = null, balance := false) -> void:
	var at: Array[Vector2] = control_panel.touches_of(action)
	if pad == null:
		pad = pop_pads[0] if action == &"tail_pop" else pop_pads[1]
	var from: Vector2 = at.back() if not at.is_empty() else pad.get_global_rect().get_center()
	_pop_finger = {action = action, pad = pad, nose = action == &"nose_pop", strength = strength,
			from = from, at = from, aim = 0, balance = balance}
	pad.set_aim(true)


## How far the held pop finger has slid aims it: a 180 left or right, named for the stance
## (riding switch, the sides swap).
func _aim_pop() -> void:
	var pad: Pad = _pop_finger.pad
	var dx: float = _pop_finger.at.x - _pop_finger.from.x
	var aim := int(signf(dx)) if absf(dx) >= BODY_SWIPE * pad.get_global_rect().size.x else 0
	_pop_finger.aim = aim
	var front := (aim > 0) != runner.riding_switch()
	pad.set_aim(true, aim, ("FS 180" if front else "BS 180") if aim != 0 else "")


## The held pop goes: popped as aimed (with a 180 if it was slid far enough).
func _release_pop() -> void:
	var held := _pop_finger
	_pop_finger = {}
	held.pad.set_aim(false)
	if held.balance:
		if not runner.is_balancing():
			return  # The manual or grind ended meanwhile: nothing to pop out of.
		held.pad.flash()
		runner.act(Runner.Act.BALANCE_POP)
	else:
		runner.act(Runner.Act.POP, 1.0 if held.nose else 0.0, held.strength)
	if held.aim != 0:
		runner.act(Runner.Act.BODY_180, held.aim)


## A finger lifted. CATCH counts its fingers: the hold ends when the last one lifts. If
## a manual or grind is being ridden, that ends it cleanly.
func _on_pad_released(action: StringName) -> void:
	if not _pop_finger.is_empty() and action == _pop_finger.action:
		_release_pop()
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
	if lesson and not lesson.goal_met():
		# The flag without the goal: say what's missing and go again.
		lesson.show_failed()
		await get_tree().create_timer(2.0, true, false, true).timeout
		get_tree().reload_current_scene.call_deferred()
		return
	last_input.text = "CLEARED!"
	Levels.record(Levels.current, 1.0)
	if _level.get("challenge", false) and Profile.online:
		# On the board: send the clear and show the board when back on the menu.
		Scoreboard.record_clear(_level.id)
		preload("res://scripts/menu.gd").page = "board:" + _level.id
	await get_tree().create_timer(1.0, true, false, true).timeout
	_to_menu()


## Stops the game under the pause screen. Fingers on the pads are let go (their lifts
## during the pause would be lost).
func pause() -> void:
	if get_tree().paused:
		return
	if not _pop_finger.is_empty():
		_pop_finger.pad.set_aim(false)
		_pop_finger = {}  # A held pop is called off, not fired.
	control_panel.release_all()
	flow.hold()
	get_tree().paused = true
	pause_menu.visible = true


func resume() -> void:
	pause_menu.visible = false
	get_tree().paused = false
	flow.resume()


## Switching away (another window, tab or app) pauses the game; Play resumes it.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_inside_tree() and runner and runner._started:
		pause()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _on_game_over() -> void:
	Levels.record(Levels.current, runner.progress())
	get_tree().reload_current_scene.call_deferred()


## Starts the level over from the start (the restart button, or Restart on the pause
## screen). The run so far counts for best progress, as a slam would.
func restart() -> void:
	get_tree().paused = false
	Levels.record(Levels.current, runner.progress())
	get_tree().reload_current_scene.call_deferred()
