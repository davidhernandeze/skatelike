class_name FlowButton
extends Pad
## Round flow meter button above the control pads. Landed tricks fill it, harder tricks
## and combos faster. Once full, tapping it starts flow state: the game runs in slow
## motion for `duration` seconds of real time, so inputs can be made slower.
##
## A combo is a chain of scoring tricks with less than combo_window seconds of plain
## riding between them (time in the air or balancing doesn't count). Each trick in the
## chain raises the multiplier by combo_step, up to max_multiplier.

signal tapped

@export var radius := 56.0
## Length of flow state, in real seconds.
@export var duration := 5.0
## Game speed during flow state, as a fraction of the normal speed.
@export var time_scale := 0.35
@export var combo_window := 1.2
@export var combo_step := 0.25
@export var max_multiplier := 3.0

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
var _combo := 0
var _since_trick := 0.0
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


## Fills the meter (the tutorial uses it to show flow state).
func fill() -> void:
	_meter = 1.0


func multiplier() -> float:
	return minf(1.0 + combo_step * maxi(_combo - 1, 0), max_multiplier)


## Starts flow state if the meter is full.
func activate() -> void:
	if not is_full() or in_flow():
		return
	_flow_until = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = base_time_scale * time_scale


## Scores a landing reported by Runner.landed.
func on_landed(style: String) -> void:
	var value := 0.0
	if style.contains("grind") or style.contains("slide"):
		value = grind_value + (double_bonus if style.begins_with("double") else 0.0)
	elif style == "to manual":
		value = 0.0  # A slide running onto the floor: already scored.
	elif style.contains("manual"):
		value = manual_value
	elif style != "roll" and runner._popped:
		value = pop_value
	if style.contains("flip") or style.contains("shuvit"):
		value += board_trick_value + (late_bonus if style.begins_with("late") else 0.0)
	if value > 0.0:
		_combo += 1
		_since_trick = 0.0
		_gain(value * multiplier())


func on_slammed() -> void:
	_combo = 0


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
	elif runner != null and not get_tree().paused:
		if runner.is_balancing():
			_gain((grind_rate if runner.is_grinding() else manual_rate) * multiplier() * delta)
		elif runner.is_grounded():
			_since_trick += delta
			if _since_trick > combo_window:
				_combo = 0
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
	if _combo > 1 and not in_flow():
		draw_string(font, Vector2(0.0, center.y + 34.0), "x%.2f" % multiplier(), HORIZONTAL_ALIGNMENT_CENTER,
				size.x, 18, color.lightened(0.5))
