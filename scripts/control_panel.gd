extends PanelContainer
## Bottom input panel. Emits a timestamped signal when a pad is tapped and swaps
## between three layouts: ground (pops and push), air (trick and catch) and balance
## (pop over balance, while a manual or grind is ridden).
##
## Touches are hit-tested here directly (instead of using Buttons) so that
## multiple fingers work and the press is registered on touch-down. Each finger
## remembers the pad it pressed and where it is now, so a held press can be followed
## as it slides (the balance tricks are played with the finger that held CATCH).

## local_pos is the touch position inside the pad, normalized to -1..1 on each axis.
signal pad_pressed(action: StringName, time_usec: int, local_pos: Vector2)
## The finger that pressed a pad lifted (wherever it is now), for pads that care about holds.
signal pad_released(action: StringName)

@onready var ground_pads: Control = $SafeArea/GroundPads
@onready var air_pads: Control = $SafeArea/AirPads
@onready var balance_pads: Control = $SafeArea/BalancePads

var _pads: Array[Pad] = []
## Touch index -> {action: the pad it pressed, pos: where it is now (global)}, until it lifts.
var _touches := {}


func _ready() -> void:
	_collect_pads(self)
	set_layout(false, false)


## Ground pads, air pads, or (balancing wins) the balance pads.
func set_layout(airborne: bool, balancing: bool) -> void:
	ground_pads.visible = not airborne and not balancing
	air_pads.visible = airborne and not balancing
	balance_pads.visible = balancing


## Where the fingers that pressed `action` are now (global positions).
func touches_of(action: StringName) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for touch in _touches.values():
		if touch.action == action:
			found.append(touch.pos)
	return found


## Fingers that pressed `action` stop counting as it (their lift reports &"").
func spend(action: StringName) -> void:
	for touch in _touches.values():
		if touch.action == action:
			touch.action = &""


func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index].pos = event.position
		return
	if not event is InputEventScreenTouch:
		return
	if not event.pressed:
		if _touches.has(event.index):
			var action: StringName = _touches[event.index].action
			_touches.erase(event.index)
			pad_released.emit(action)
		return
	var time_usec := Time.get_ticks_usec()
	for pad in _pads:
		var rect := pad.get_global_rect()
		if pad.is_visible_in_tree() and rect.has_point(event.position):
			var local_pos: Vector2 = (event.position - rect.get_center()) / (rect.size * 0.5)
			pad.flash()
			_touches[event.index] = {action = pad.action, pos = event.position}
			pad_pressed.emit(pad.action, time_usec, local_pos)
			get_viewport().set_input_as_handled()
			return


func _collect_pads(node: Node) -> void:
	for child in node.get_children():
		if child is Pad:
			_pads.append(child)
		_collect_pads(child)
