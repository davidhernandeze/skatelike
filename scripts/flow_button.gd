class_name FlowButton
extends Pad
## Round flow meter button above the control pads. Landed tricks fill it, harder tricks
## and combos faster. Once full, tapping it starts flow state: the game runs in slow
## motion for `duration` seconds of real time, so inputs can be made slower.
##
## A line is a chain of tricks without the wheels coming down in between: each air trick
## (a board trick, or an ollie/nollie) and each manual, grind or slide landed into joins
## it, and the n-th one scores n times its value (up to max_multiplier), as does
## balancing meanwhile. A clean landing (wheels down) adds its trick and closes the line;
## a slam loses it.

signal tapped
## The line so far changed: its tricks in order, and how it ended (&"" while going on,
## &"landed" or &"slammed").
signal line_changed(tricks: PackedStringArray, ended: StringName)

@export var radius := 56.0
## Length of flow state, in real seconds.
@export var duration := 5.0
## Game speed during flow state, as a fraction of the normal speed.
@export var time_scale := 0.35
@export var max_multiplier := 10.0

@export_group("Meter per trick")
## Fractions of a full meter, before the combo multiplier.
@export var pop_value := 0.03
## Added for a flip or shuvit, and again for a late one.
@export var board_trick_value := 0.07
@export var late_bonus := 0.03
@export var manual_value := 0.05
## Grinds and slides; double grinds add double_bonus.
@export var grind_value := 0.07
@export var double_bonus := 0.05
## Per second while balancing: manuals, then grinds and slides.
@export var manual_rate := 0.03
@export var grind_rate := 0.05
@export_group("")

var runner: Runner
## Engine.time_scale outside flow state.
var base_time_scale := 1.0

var _meter := 0.0
## The line so far.
var _line := PackedStringArray()
## Real time (ms) when flow state ends; 0 when not in flow.
var _flow_until := 0


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * radius * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())  # Round: drawn in _draw.
	_apply_alpha()


func is_full() -> bool:
	return _meter >= 1.0


func in_flow() -> bool:
	return _flow_until > 0


## The current line's multiplier: its length (at least 1).
func multiplier() -> float:
	return clampf(_line.size(), 1.0, max_multiplier)


## Flow state lasts real seconds: a pause holds them, and resume() gives them back.
var _held_left := -1


func hold() -> void:
	if in_flow():
		_held_left = _flow_until - Time.get_ticks_msec()


func resume() -> void:
	if _held_left >= 0:
		_flow_until = Time.get_ticks_msec() + _held_left
		_held_left = -1


## Starts flow state if the meter is full.
func activate() -> void:
	if not is_full() or in_flow():
		return
	_flow_until = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = base_time_scale * time_scale


## Scores a landing's parts (Runner.line_event): each joins the line and scores at its
## place in it; the wheels coming down close the line.
func on_line_event(air: String, balance: String, wheels_down: bool) -> void:
	if air != "":
		var value := pop_value
		if runner._board_trick_done != &"":
			# Once per flip turn and shuvit half turn: a double kickflip counts twice, a 360
			# flip three times.
			value += board_trick_value * runner.board_trick_units() + (late_bonus if air.begins_with("late") else 0.0)
		if runner._body_turn >= 0.0:
			value += board_trick_value  # A body 180.
		_add(air, value)
	if balance != "":
		var value := manual_value
		if balance.contains("grind") or balance.contains("slide"):
			value = grind_value + (double_bonus if balance.begins_with("double") else 0.0)
		_add(balance, value)
	if wheels_down and not _line.is_empty():
		line_changed.emit(_line, &"landed")
		_line = PackedStringArray()


func _add(trick: String, value: float) -> void:
	_line.append(trick)
	_gain(value * multiplier())
	line_changed.emit(_line, &"")


func on_slammed() -> void:
	if not _line.is_empty():
		line_changed.emit(_line, &"slammed")
	_line = PackedStringArray()


func _gain(amount: float) -> void:
	if not in_flow():
		_meter = minf(_meter + amount, 1.0)


func flash() -> void:
	pass  # Drawn by _draw instead of the pad's panel.


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed) or not is_visible_in_tree():
		return
	if (event.position - get_global_rect().get_center()).length() <= radius:
		get_viewport().set_input_as_handled()
		tapped.emit()


func _process(delta: float) -> void:
	if in_flow():
		var left := _flow_until - Time.get_ticks_msec()
		_meter = clampf(left / (duration * 1000.0), 0.0, 1.0)
		if left <= 0:
			_flow_until = 0
			_meter = 0.0
			Engine.time_scale = base_time_scale
	elif runner != null:
		if runner.is_balancing():
			_gain((grind_rate if runner.is_grinding() else manual_rate) * multiplier() * delta)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var full := is_full() and not in_flow()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
	draw_circle(center, radius, color.darkened(0.6 if not full else 0.2 - 0.15 * pulse))
	draw_circle(center, radius - 10.0, Color(0, 0, 0, 0.35))
	# The meter fills the ring clockwise from the top; in flow it shows the time left.
	if _meter > 0.0:
		draw_arc(center, radius - 5.0, -PI * 0.5, -PI * 0.5 + TAU * _meter,
				maxi(4, ceili(64.0 * _meter)), color.lightened(0.4 if full or in_flow() else 0.0), 10.0, true)
	draw_arc(center, radius, 0.0, TAU, 64, color, 3.0, true)
	var font := get_theme_default_font()
	var text := "FLOW" if full or in_flow() else "%d%%" % floori(_meter * 100.0)
	draw_string(font, Vector2(0.0, center.y + 9.0), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26)
	if _line.size() > 1 and not in_flow():
		draw_string(font, Vector2(0.0, center.y + 34.0), "x%d" % multiplier(), HORIZONTAL_ALIGNMENT_CENTER,
				size.x, 18, color.lightened(0.5))
