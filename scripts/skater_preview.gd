class_name SkaterPreview
extends Control
## The skater in the middle of this control wearing the outfit picked on the profile
## page: riding in place, with a push every few seconds to show it moving. The same rig
## as in the game (SkaterView), `zoom` times bigger.

## Times bigger than in the game.
@export var zoom := 1.6
## Seconds between pushes, and how long one takes.
@export var push_every := 2.5
@export var push_time := 0.6

var view: SkaterView
var _t := 0.0


func _init() -> void:
	view = SkaterView.new()
	add_child(view)


func _ready() -> void:
	view.apply_profile()


func _process(delta: float) -> void:
	_t += delta
	var base := Vector2(size.x * 0.5, size.y - 24.0)
	var half := SkaterView.REST_FOOT * zoom
	var rear := base - Vector2(half, 0.0)
	var front := base + Vector2(half, 0.0)
	var phase := fmod(_t, push_every) / push_time
	var push := -1.0
	if phase < 1.0:
		# Like Runner.skater_pose(): the back foot steps down to the ground and kicks back.
		push = phase
		var drop := 21.0 * zoom
		rear = base + Vector2(lerpf(-half * 0.3, -half * 2.6, phase), drop * sin(PI * minf(phase * 1.3, 1.0)))
	view.show_pose({base = base, angle = 0.0, feet = [rear, front], crouch = 0.35 if push >= 0.0 else 0.2,
		face = 1.0, back = Profile.goofy, mirror = false, fall = -1.0, manual = 0.0, push = push}, zoom)


## Puts on the outfit picked on the profile page again (after a change).
func refresh() -> void:
	view.set_outfit(Profile.outfit)
