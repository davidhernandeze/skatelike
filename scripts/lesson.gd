class_name Lesson
extends Control
## A practice lesson (a level with a `lesson` entry, see Levels): an explanation panel at
## the top of the play area with the mechanic's text, its goal and how it's going, and a
## miniature of the control panel where a finger loops the input to make. The panel
## never takes touches. Main hides it with the Tips checkbox, and asks goal_met() when
## the flag is reached: a lesson only clears with its goal met.
##
## lesson = {title, text, demo = [step, ...], goal = {...}}:
## - demo steps: {pad = action, at = Vector2(-1..1 in the pad), hold = s} taps (or holds)
##   a pad, sliding to `to` while pressed if given; {wait = s} pauses; {layout = &"ground" | &"air" | &"balance"} switches pads.
## - goal: {speed = km/h} to reach; {trick = "360 flip", count = n} to land n times
##   (default once): a trick of a line (Runner.line_event) named that, or ending in it
##   ("nollie 360 flip" counts as a 360 flip; a nollie isn't an ollie), or with
##   match = "contains" / "starts" one containing or starting with it; or {line = n}, a
##   line of n tricks (FlowButton). `text` words it for the panel ("land a late trick").
##   No goal: reaching the flag clears it.

signal goal_reached

## The pads of each layout, left to right (or top to bottom for air and balance).
const LAYOUTS := {
	&"ground": [&"tail_pop", &"push", &"nose_pop"],
	&"air": [&"trick", &"lock_tilt"],
	&"balance": [&"balance_pop", &"balance"],
}
const PANEL_COLOR := Color(0.07, 0.08, 0.12, 0.82)
const TEXT_COLOR := Color(0.88, 0.9, 0.96)
const GOAL_COLOR := Color(1.0, 0.85, 0.3)
const DONE_COLOR := Color(0.5, 0.9, 0.5)
## Size of the miniature control panel (px).
const MINI_SIZE := Vector2(230.0, 150.0)

var runner: Runner
## For line goals.
var flow: FlowButton
## Pads of the real control panel, by action: their colors and labels are reused.
var pads := {}

var _lesson: Dictionary
var _goal: Dictionary
var _met := false
var _best_speed := 0.0
## Tricks landed towards a trick goal.
var _landed := 0
var _title := Label.new()
var _text := Label.new()
var _goal_label := Label.new()
## Demo playback: step index, time in it, the layout shown, the finger (pad and spot),
## and whether it's pressing.
var _step := 0
var _step_t := 0.0
var _layout: StringName = &"ground"
var _finger_pad: StringName = &""
var _finger_at := Vector2.ZERO
var _finger_from := Vector2.ZERO
var _pressing := false


func setup(lesson: Dictionary) -> void:
	_lesson = lesson
	_goal = lesson.get("goal", {})
	_title.text = lesson.get("title", "")
	_text.text = lesson.get("text", "")
	_update_goal()


func goal_met() -> bool:
	return _goal.is_empty() or _met


## What's missing, for when the flag is reached without it.
func goal_text() -> String:
	if _goal.has("text"):
		return _goal.text
	if _goal.has("line"):
		return "land a line of %d tricks" % _goal.line
	if _goal.has("speed"):
		return "reach %d km/h" % _goal.speed
	if _goal.has("trick"):
		var trick := String(_goal.trick)
		var count: int = _goal.get("count", 1)
		if count > 1:
			return "land %d %ss" % [count, trick]
		return "land %s %s" % ["an" if "aeiou".contains(trick[0]) else "a", trick]
	return ""


func show_failed() -> void:
	visible = true
	_goal_label.text = "Goal not met: %s. Again!" % goal_text()
	_goal_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label: Label in [_title, _text, _goal_label]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", TEXT_COLOR)
		add_child(label)
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", GOAL_COLOR)
	_text.add_theme_font_size_override("font_size", 24)
	_goal_label.add_theme_font_size_override("font_size", 24)
	resized.connect(_place)
	if runner:
		runner.line_event.connect(_on_line_event)
	if flow:
		flow.line_changed.connect(func(tricks: PackedStringArray, _ended: StringName) -> void:
			if _goal.has("line") and not _met and tricks.size() >= _goal.line:
				_reach()
				_update_goal())
	_place()


## Text on the left, the miniature controls on the right.
func _place() -> void:
	var pad := 16.0
	var text_w := size.x - MINI_SIZE.x - pad * 3.0
	_title.position = Vector2(pad, pad)
	_title.size = Vector2(text_w, 0)
	_text.position = Vector2(pad, pad + 48.0)
	_text.size = Vector2(text_w, 0)
	_goal_label.size = Vector2(size.x - pad * 2.0, 0)
	_fit()


## The goal line goes right under the text, and the panel grows (down) to fit it all.
func _fit() -> void:
	var pad := 16.0
	# Wrapped labels only grow on their own: back to their text's height.
	_text.size = Vector2(_text.size.x, 0)
	_goal_label.size = Vector2(_goal_label.size.x, 0)
	_goal_label.position = Vector2(pad, _text.position.y + _text.size.y + 8.0)
	var needed := maxf(_goal_label.position.y + _goal_label.size.y + pad, MINI_SIZE.y + pad * 2.0)
	if absf(size.y - needed) > 1.0:
		offset_bottom = offset_top + needed


func _process(delta: float) -> void:
	if runner and _goal.has("speed") and not _met:
		var kmh := runner._speed / runner.pixels_per_meter * 3.6
		_best_speed = maxf(_best_speed, kmh)
		if kmh >= _goal.speed:
			_reach()
		_update_goal()
	_play_demo(delta)
	_fit()
	queue_redraw()


func _on_line_event(air: String, balance: String, _wheels_down: bool) -> void:
	if not _goal.has("trick") or _met:
		return
	var trick := String(_goal.trick)
	var match_by: String = _goal.get("match", "end")
	for name: String in [air, balance]:
		if name == "":
			continue
		if (match_by == "contains" and name.contains(trick)) or (match_by == "starts" and name.begins_with(trick)) \
				or (match_by == "end" and (name == trick or name.ends_with(" " + trick))):
			_landed += 1
	if _landed >= _goal.get("count", 1):
		_reach()
	_update_goal()


func _reach() -> void:
	_met = true
	goal_reached.emit()


func _update_goal() -> void:
	if _goal.is_empty():
		_goal_label.text = "Ride to the flag."
		return
	_goal_label.add_theme_color_override("font_color", DONE_COLOR if _met else GOAL_COLOR)
	if _met:
		_goal_label.text = "Goal met: %s. Ride to the flag!" % goal_text()
	elif _goal.has("speed"):
		_goal_label.text = "Goal: %s (best %d)" % [goal_text(), floori(_best_speed)]
	elif _goal.get("count", 1) > 1:
		_goal_label.text = "Goal: %s (%d/%d)" % [goal_text(), _landed, _goal.count]
	else:
		_goal_label.text = "Goal: %s, then ride to the flag." % goal_text()


## Steps through the demo loop: the finger glides to each pad, presses, lifts.
func _play_demo(delta: float) -> void:
	var demo: Array = _lesson.get("demo", [])
	if demo.is_empty():
		return
	_step_t += delta
	var step: Dictionary = demo[_step % demo.size()]
	if step.has("layout"):
		_layout = step.layout
		_next_step()
		return
	if step.has("wait"):
		_pressing = false
		if _step_t >= step.wait:
			_next_step()
		return
	# A tap: glide there (0.25 s), press for `hold`, lift.
	if _finger_pad != step.pad or _step_t <= delta:
		_finger_from = _finger_spot()
		_finger_pad = step.pad
		_finger_at = step.get("at", Vector2.ZERO)
	var glide := 0.25
	_pressing = _step_t >= glide and _step_t < glide + step.get("hold", 0.12)
	if step.has("to") and _step_t >= glide:
		# A slide: pressing all the way from `at` to `to`.
		_finger_at = step.get("at", Vector2.ZERO).lerp(step.to, clampf((_step_t - glide) / step.get("hold", 0.12), 0.0, 1.0))
	if _step_t >= glide + step.get("hold", 0.12):
		_next_step()


func _next_step() -> void:
	_step += 1
	_step_t = 0.0


func _mini_rect() -> Rect2:
	return Rect2(Vector2(size.x - MINI_SIZE.x - 16.0, 16.0), MINI_SIZE)


## Each pad of the layout shown and its rectangle in the miniature.
func _mini_pads() -> Array:
	var area := _mini_rect()
	var actions: Array = LAYOUTS[_layout]
	var out := []
	var gap := 5.0
	for i in actions.size():
		var r: Rect2
		if _layout == &"ground":
			var w := (area.size.x - gap * (actions.size() - 1)) / actions.size()
			r = Rect2(area.position + Vector2((w + gap) * i, 0.0), Vector2(w, area.size.y))
		else:
			var h := (area.size.y - gap) / 2.0
			r = Rect2(area.position + Vector2(0.0, (h + gap) * i), Vector2(area.size.x, h))
		out.append([actions[i], r])
	return out


## Where the finger is drawn now: gliding from where it was to the step's spot.
func _finger_spot() -> Vector2:
	for entry in _mini_pads():
		if entry[0] == _finger_pad:
			var r: Rect2 = entry[1]
			var target := r.get_center() + _finger_at * r.size * 0.4
			return _finger_from.lerp(target, clampf(_step_t / 0.25, 0.0, 1.0)) if _finger_from != Vector2.ZERO else target
	return _mini_rect().get_center()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_COLOR)
	var font := ThemeDB.fallback_font
	for entry in _mini_pads():
		var action: StringName = entry[0]
		var r: Rect2 = entry[1]
		var pad: Pad = pads.get(action)
		var color: Color = pad.color if pad else Color(0.5, 0.5, 0.6)
		var lit := _pressing and action == _finger_pad
		draw_rect(r, color.darkened(0.1 if lit else 0.5))
		draw_rect(r, color, false, 2.0)
		# The pad's label, short: its first part, a line at a time.
		var label: String = (pad.label if pad and pad.label != "" else String(action).to_upper()).get_slice("  ·", 0)
		var lines := label.split("\n")
		for i in lines.size():
			var y := r.get_center().y + (i - (lines.size() - 1) * 0.5) * 20.0 + 6.0
			draw_string(font, Vector2(r.position.x, y), lines[i].strip_edges(), HORIZONTAL_ALIGNMENT_CENTER,
					r.size.x, 17, TEXT_COLOR)
	if _finger_pad != &"":
		_draw_finger(_finger_spot(), _pressing)


## A placeholder finger reaching in from the lower right: hovering just above the spot
## (with its shadow on the pad), or pressing it (tip down, a ring rippling out).
func _draw_finger(at: Vector2, pressing: bool) -> void:
	const SKIN := Color(0.96, 0.8, 0.68)
	const OUTLINE := Color(0.12, 0.08, 0.06)
	var tip := at if pressing else at + Vector2(-4.0, -12.0)
	if pressing:
		var ring := fmod(_step_t * 4.0, 1.0)
		draw_circle(at, 14.0 + ring * 12.0, Color(1, 1, 1, 0.7 * (1.0 - ring)), false, 3.0)
	else:
		draw_circle(at + Vector2(3.0, 3.0), 9.0, Color(0, 0, 0, 0.35))  # Shadow.
	var knuckle := tip + Vector2(26.0, 44.0)
	draw_line(tip, knuckle, OUTLINE, 26.0)
	draw_circle(tip, 13.0, OUTLINE)
	draw_line(tip, knuckle, SKIN, 20.0)
	draw_circle(tip, 10.0, SKIN)
	draw_circle(tip + Vector2(1.0, 2.0), 5.0, SKIN.lightened(0.35))  # Nail.
