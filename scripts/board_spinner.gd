class_name BoardSpinner
extends Control
## The skater's board floating in the middle of this control: it turns around and
## slowly flips over, so the grip, the deck graphic and the wheels all come round, and
## bobs up and down. The same pixel art as in the game, `zoom` times bigger.

## Times bigger than in the game (whole numbers keep the pixels square).
@export var zoom := 2
## Turns (rad/s): around the deck's up, and over (a slow flip).
@export var spin_speed := 1.1
@export var flip_speed := 0.55
## Bob height (px) and speed (rad/s).
@export var bob := 8.0
@export var bob_speed := 2.0
## Wheel spin (rad/s).
@export var wheel_speed := 9.0

var view: BoardView
var _t := 0.0


func _init() -> void:
	view = BoardView.new()
	add_child(view)


func _ready() -> void:
	view.pixel = Runner.PIXEL * zoom  # Same texels as in the game, drawn `zoom` times bigger.
	view.snap = false
	view.apply_profile()


func _process(delta: float) -> void:
	_t += delta
	view.roll_wheels(wheel_speed * delta)
	var anchor := size * 0.5 + Vector2(0.0, sin(_t * bob_speed) * bob)
	# The deck's middle sits on the anchor.
	view.show_pose(anchor, Vector2(0.0, -7.0), 0.0, _t * flip_speed + 0.4, _t * spin_speed,
			Vector2(zoom, zoom))


## Puts on the board picked on the profile page again (after a change).
func refresh() -> void:
	view.apply_profile()
