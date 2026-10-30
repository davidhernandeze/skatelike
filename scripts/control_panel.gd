extends PanelContainer
## Bottom input panel. Emits a timestamped signal when a pad is tapped and swaps
## between the ground layout (pop/push) and the air layout (board controls).
##
## Touches are hit-tested here directly (instead of using Buttons) so that
## multiple fingers work and the press is registered on touch-down.

## local_pos is the touch position inside the pad, normalized to -1..1 on each axis.
signal pad_pressed(action: StringName, time_usec: int, local_pos: Vector2)

@onready var ground_pads: Control = $SafeArea/GroundPads
@onready var air_pads: Control = $SafeArea/AirPads

var _pads: Array[Pad] = []


func _ready() -> void:
	_collect_pads(self)
	set_airborne(false)


func set_airborne(airborne: bool) -> void:
	ground_pads.visible = not airborne
	air_pads.visible = airborne


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	var time_usec := Time.get_ticks_usec()
	for pad in _pads:
		var rect := pad.get_global_rect()
		if pad.is_visible_in_tree() and rect.has_point(event.position):
			var local_pos: Vector2 = (event.position - rect.get_center()) / (rect.size * 0.5)
			pad.flash()
			pad_pressed.emit(pad.action, time_usec, local_pos)
			get_viewport().set_input_as_handled()
			return


func _collect_pads(node: Node) -> void:
	for child in node.get_children():
		if child is Pad:
			_pads.append(child)
		_collect_pads(child)
