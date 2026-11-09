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

## Half the dial's size (px): the brass dial (UiKit.DIAL) at the UI's pixel size.
@export var radius := UiKit.DIAL.get_width() * UiKit.PIXEL * 0.5
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
## No restrictions (free ride levels): the meter is always full, and a tap turns flow
## state on for as long as it's wanted, another tap off.
var unlimited := false
## In unrestricted flow state (see unlimited).
var _free_flow := false

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
	return _flow_until > 0 or _free_flow


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


## Starts flow state if the meter is full; unrestricted, turns it on or off.
func activate() -> void:
	if unlimited:
		_free_flow = not _free_flow
		Engine.time_scale = base_time_scale * (time_scale if _free_flow else 1.0)
		return
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
	if unlimited:
		_meter = 1.0  # Always ready.
	elif in_flow():
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
	# An analog brass dial: the needle sweeps over the arc as the meter fills (in flow it
	# shows the time left), and the bulb under it lights up, pulsing, once it's full.
	var p := float(UiKit.PIXEL)
	var center := size * 0.5
	var full := is_full() and not in_flow()
	var dial := _dial_texture()
	var top_left := ((center - dial.get_size() * 0.5) / p).floor() * p
	draw_texture(dial, top_left)
	var hub := top_left + Vector2(23, 23) * p  # The dial's hub, in its art.
	var angle := lerpf(PI + 0.35, TAU - 0.35, clampf(_meter, 0.0, 1.0))
	var tip := hub + Vector2.from_angle(angle) * 15.0 * p
	for i in 16:
		var at := (hub.lerp(tip, i / 15.0) / p).floor() * p
		draw_rect(Rect2(at, Vector2(p, p)), Color("a8261c") if i > 9 else UiKit.INK)
	draw_rect(Rect2(hub - Vector2(p, p), Vector2(p * 2, p * 2)), Color("6a4a1a"))
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
	var bulb := hub + Vector2(-p, p * 15)  # On the bezel, under the name.
	UiKit.draw_bulbs(self, bulb, bulb, 1, full or in_flow(), Time.get_ticks_msec() / 1000.0,
			1.0 + pulse * 1.5 if full else 1.0)
	var font := get_theme_default_font()
	var text := "FLOW" if full or in_flow() else "%d%%" % floori(_meter * 100.0)
	draw_string(font, Vector2(0.0, hub.y + p * 11), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, UiKit.INK)
	if _line.size() > 1 and not in_flow():
		var at := Vector2(0.0, top_left.y - p)
		draw_string_outline(font, at, "x%d" % multiplier(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, 8, UiKit.INK)
		draw_string(font, at, "x%d" % multiplier(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, UiKit.BULB)


static var _dial: Texture2D


## The dial's art at the UI's pixel size (made once).
static func _dial_texture() -> Texture2D:
	if _dial == null:
		_dial = ImageTexture.create_from_image(UiKit.scaled(UiKit.DIAL.get_image()))
	return _dial
