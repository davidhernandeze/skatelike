extends Control

## Global time scale; set below 1 to slow everything down while tuning mechanics.
@export var game_speed := 1.0

const MENU_SCENE := "res://scenes/menu.tscn"

@onready var play_area: Control = $Layout/PlayArea
@onready var runner: Runner = $Layout/PlayArea/World/Runner
@onready var control_panel: PanelContainer = $Layout/ControlPanel
@onready var menu_button: Button = $Layout/PlayArea/HUD/Top/Menu
@onready var score_label: Label = $Layout/PlayArea/HUD/Top/Score
@onready var speed_label: Label = $Layout/PlayArea/HUD/Top/Speed
@onready var last_input: Label = $Layout/PlayArea/HUD/Top/LastInput
@onready var push_pad: Pad = $Layout/ControlPanel/SafeArea/GroundPads/Push
@onready var trick_pad: Pad = $Layout/ControlPanel/SafeArea/AirPads/Trick
@onready var balance_pad: BalancePad = $Layout/ControlPanel/SafeArea/GroundPads/Balance
@onready var pop_pads: Array[Pad] = [
	$Layout/ControlPanel/SafeArea/GroundPads/TailPop,
	$Layout/ControlPanel/SafeArea/GroundPads/NosePop,
]


func _ready() -> void:
	Engine.time_scale = game_speed
	runner.configure(Levels.get_level(Levels.current))
	play_area.resized.connect(_layout_world)
	control_panel.pad_pressed.connect(_on_pad_pressed)
	menu_button.pressed.connect(_to_menu)
	runner.airborne_changed.connect(control_panel.set_airborne)
	runner.score_changed.connect(func(score: int) -> void: score_label.text = str(score))
	runner.speed_changed.connect(_show_speed)
	runner.pushed.connect(_on_pushed)
	runner.popped.connect(_on_popped)
	runner.dropped.connect(func(factor: float) -> void: last_input.text = "drop x%.1f" % factor)
	runner.caught.connect(_on_caught)
	runner.flipped.connect(func(trick: String) -> void: last_input.text += "\n" + trick)
	runner.flip_caught.connect(func(trick: String) -> void: last_input.text += "\n%s caught" % trick)
	runner.slammed.connect(_on_slammed)
	runner.balance_changed.connect(_on_balance_changed)
	balance_pad.point_expired.connect(runner.lose_balance)
	runner.landed.connect(func(style: String) -> void: last_input.text += "\n" + style)
	runner.level_cleared.connect(_on_level_cleared)
	runner.game_over.connect(_on_game_over)
	_layout_world()
	_show_speed(runner.start_speed)


func _process(_delta: float) -> void:
	push_pad.set_pie(runner.push_progress(), runner.queued_pushes())
	for pad in pop_pads:
		pad.set_enabled(not runner.is_pushing())
	trick_pad.set_enabled(runner.can_flip())


func _layout_world() -> void:
	runner.setup(play_area.size)


func _on_pad_pressed(action: StringName, _time_usec: int, local_pos: Vector2) -> void:
	# Pop and push strength come from touch height (top = strongest),
	# the tilt lock angle from touch x.
	match action:
		&"tail_pop":
			runner.pop(false, -local_pos.y)
		&"nose_pop":
			runner.pop(true, -local_pos.y)
		&"push":
			runner.push(-local_pos.y)
		&"balance":
			if not balance_pad.press(local_pos):
				runner.lose_balance("missed balance")
		&"lock_tilt":
			runner.lock_tilt(local_pos.x)
		&"trick":
			runner.flip(local_pos.y > 0.0)  # Top half heelflip, bottom half kickflip.


func _show_speed(speed: float) -> void:
	speed_label.text = "%d px/s" % speed


func _on_pushed(strength: float, speed: float, queued: bool) -> void:
	last_input.text = "push %d%%%s" % [roundi(strength * 100.0), "  (queued)" if queued else ""]
	_show_speed(speed)


func _on_popped(nose: bool, strength: float) -> void:
	last_input.text = "%s pop %d%%" % ["nose" if nose else "tail", roundi(strength * 100.0)]


func _on_slammed(reason: String) -> void:
	balance_pad.freeze()
	last_input.text += "\nSLAM: " + reason


## While a manual or grind is ridden the push pad turns into the balance pad
## (harder on rails).
func _on_balance_changed(mode: StringName) -> void:
	var balancing := mode != &""
	push_pad.visible = not balancing
	balance_pad.visible = balancing
	balance_pad.set_active(balancing, mode == &"grind")
	if not balancing and runner.is_grounded():
		last_input.text += "\nwheels down"


func _on_caught(catch_index: int, angle_deg: float, apex_ms: int) -> void:
	var what: String = ["catch %+.0f°" % angle_deg, "manual catch", "grind catch"][catch_index - 1]
	last_input.text += "\n%s  apex %+d ms" % [what, apex_ms]


func _on_level_cleared() -> void:
	last_input.text = "CLEARED!"
	Levels.last_cleared = Levels.current
	await get_tree().create_timer(1.0, true, false, true).timeout
	_to_menu()


func _to_menu() -> void:
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _on_game_over() -> void:
	get_tree().reload_current_scene.call_deferred()
