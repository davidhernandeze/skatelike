class_name Tutorial
extends Control
## Guided steps for the tutorial level. Each step waits for its trigger, then freezes
## the game (pauses the tree) and shows its instruction, highlighting the pads it
## accepts. The game resumes on a tap that the step accepts, and that tap is applied
## as usual. Taps on other pads, or in the wrong spot, show a hint instead.
## Banner steps show a message for a few seconds without freezing.
##
## Made by Main for levels with `tutorial = true`; full-rect overlay over the whole screen.

@export var font_size := 30
@export var hint_color := Color(1.0, 0.6, 0.4)
@export var highlight_color := Color(1.0, 0.95, 0.5)
## How long banner steps stay up (s).
@export var banner_time := 3.0

var runner: Runner
var balance_pad: BalancePad
var play_area: Control
var pads: Array[Pad] = []
var flow: FlowButton
## Checkpoint (mark) the level restarted from: steps begin at that section.
var start_section := ""

## Each step: {when: Callable -> bool, text: String, wait: Array[StringName] or Callable
## returning one, check: Callable(action, local_pos) -> String (a hint, "" if fine),
## unless: Callable -> bool (skip the step when it triggers), banner: bool,
## section: the mark whose checkpoint restarts here, enter: Callable run as it freezes,
## hold: the press has to be held for HOLD_CONFIRM; the game resumes with it still held}.
var _steps: Array[Dictionary] = []
var _index := 0
var _frozen := false
var _hint := ""
var _banner_left := 0.0
var _box: PanelContainer
var _text: Label
var _hint_label: Label
var _time := 0.0
## Hold steps: real time (ms) when the accepted press started; 0 when none is held.
var _hold_since := 0
## Real time a hold step's press must last before the game resumes (ms).
const HOLD_CONFIRM := 350


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_box()
	_build_steps()
	if start_section != "":
		for i in _steps.size():
			if _steps[i].get("section", "") == start_section:
				_index = i
				break
		_show("Back at the last checkpoint.")
		_banner_left = banner_time


func _exit_tree() -> void:
	get_tree().paused = false


func is_frozen() -> bool:
	return _frozen


## Pads the current freeze waits for (empty when not frozen).
func waiting() -> Array:
	if not _frozen:
		return []
	var wait = _steps[_index].get("wait", [])
	return wait.call() if wait is Callable else wait


## Called by Main before applying a tap. Returns false to drop it while frozen.
func accept(action: StringName, local_pos: Vector2) -> bool:
	if not _frozen:
		return true
	if action not in waiting():
		_show_hint("Tap the highlighted pad.")
		return false
	var step := _steps[_index]
	if step.has("check"):
		var hint: String = step.check.call(action, local_pos)
		if hint != "":
			_show_hint(hint)
			return false
	if step.get("hold", false):
		# Stay frozen until the press has lasted HOLD_CONFIRM (see _process).
		_hold_since = Time.get_ticks_msec()
		_show_hint("Keep holding...")
		return true
	_unfreeze()
	_index += 1
	return true


## A finger lifted (from Main): a hold step's press let go too early starts over.
func released(action: StringName) -> void:
	if _frozen and _hold_since > 0 and action in waiting():
		_hold_since = 0
		_show_hint("Keep holding CATCH until the game moves again.")


func _process(delta: float) -> void:
	_time += delta
	if _frozen and _hold_since > 0 and Time.get_ticks_msec() - _hold_since >= HOLD_CONFIRM:
		_hold_since = 0
		_unfreeze()
		_index += 1
	if _banner_left > 0.0:
		_banner_left -= delta
		if _banner_left <= 0.0 and not _frozen:
			_box.visible = false
	if not _frozen and _index < _steps.size() and runner._started and not runner._dead:
		var step := _steps[_index]
		if step.when.call():
			if step.has("unless") and step.unless.call():
				_index += 1
			elif step.get("banner", false):
				_index += 1
				_show(step.text)
				_banner_left = banner_time
			else:
				if step.has("enter"):
					step.enter.call()
				_freeze(step.text)
	if _box.visible:
		_place_box()
	if _frozen:
		var wait := waiting()
		for pad in pads:
			pad.set_enabled(pad.action in wait)
	queue_redraw()


func _freeze(text: String) -> void:
	_frozen = true
	_banner_left = 0.0
	get_tree().paused = true
	_show(text)


func _unfreeze() -> void:
	_frozen = false
	get_tree().paused = false
	_box.visible = false
	for pad in pads:
		pad.set_enabled(true)  # Main dims the pops and the trick pad again as needed.


## Keeps the box in the half of the play area away from the board.
func _place_box() -> void:
	var area := play_area.get_global_rect()
	var board_y := (runner.get_global_transform() * runner.board_position()).y
	# Zero height at the anchor line, so the box takes its text's height and grows
	# up from the bottom or down from the top.
	var low := board_y < area.get_center().y
	var y := area.end.y - 24.0 if low else area.position.y + 150.0
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN if low else Control.GROW_DIRECTION_END
	_box.offset_top = y - global_position.y
	_box.offset_bottom = _box.offset_top


func _show(text: String) -> void:
	_text.text = text
	_hint = ""
	_hint_label.visible = false
	_box.visible = true


func _show_hint(hint: String) -> void:
	_hint = hint
	_hint_label.text = hint
	_hint_label.visible = true


func _draw() -> void:
	if not _frozen:
		return
	var area := play_area.get_global_rect()
	draw_rect(Rect2(area.position - global_position, area.size), Color(0, 0, 0, 0.3))
	# Pulse a frame around each pad that would resume the game.
	var pulse := 0.8 + 0.2 * sin(_time * 8.0)
	var wait := waiting()
	for pad in pads:
		if pad.action in wait and pad.is_visible_in_tree():
			var rect := pad.get_global_rect().grow(6.0)
			rect.position -= global_position
			draw_rect(rect, Color(highlight_color, pulse), false, 6.0)


func _build_box() -> void:
	_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(22)
	style.border_color = highlight_color
	style.set_border_width_all(3)
	_box.add_theme_stylebox_override("panel", style)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_right = 1.0
	_box.offset_left = 24.0
	_box.offset_right = -24.0
	_box.visible = false
	add_child(_box)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(column)
	_text = _make_label(Color.WHITE)
	column.add_child(_text)
	_hint_label = _make_label(hint_color)
	column.add_child(_hint_label)


func _make_label(color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# --- Steps ---------------------------------------------------------------------

## The board is within `lead` px of the start of mark `name` (+ `offset` into it).
func _near(name: String, lead: float, offset := 0.0) -> bool:
	return runner.marks.has(name) and runner._pos.x >= runner.marks[name].x + offset - lead


func _past(name: String, offset := 0.0) -> bool:
	return _near(name, 0.0, offset)


## Ready to pop at `lead` px before mark `name`.
func _pop_at(name: String, lead := 150.0) -> Callable:
	return func() -> bool: return _near(name, lead) and runner.can_pop()


## In the air and close to the top of the jump.
func _near_apex(vy := -150.0) -> Callable:
	return func() -> bool: return runner._in_trick and runner._velocity_y > vy


## Already caught: the player did it without help.
func _caught() -> bool:
	return runner._catches > 0


## Caught, airborne and coming down: time to hold CATCH (with room for hold_delay).
## `rails` counts rails as something to land on.
func _touchdown_soon(rails: bool) -> Callable:
	return func() -> bool:
		return runner._in_trick and runner._catches == 1 \
				and runner.time_to_touchdown(rails) < runner.hold_delay + 0.25


## Manuals need a side: a hold in the middle of CATCH is a 50-50, for rails and ledges.
func _side_hold(_action: StringName, local_pos: Vector2) -> String:
	return "Hold on the left or right half for a manual. The middle is a 50-50, for rails." \
			if absf(local_pos.x) <= runner.lock_dead_zone else ""


func _full_pop(_action: StringName, local_pos: Vector2) -> String:
	return "Tap higher on the pad for a stronger pop." if local_pos.y > 0.0 else ""


func _flat_catch(_action: StringName, local_pos: Vector2) -> String:
	return "Tap near the middle line to catch the board flat." \
			if absf(local_pos.x) > runner.lock_dead_zone else ""


func _on_point(_action: StringName, local_pos: Vector2) -> String:
	return "" if balance_pad.hits(local_pos) else "Tap right on the balance point."


## The pop on the raised end: nose pop after a (tail) manual, tail pop after a nose manual.
func _raised_end() -> Array:
	return [&"nose_pop" if runner._riding_manual < 0.0 else &"tail_pop"]


func _build_steps() -> void:
	var always := func() -> bool: return true
	var catch := [&"lock_tilt"]
	_steps = [
		{when = func() -> bool: return _time > 0.6, wait = [&"push"],
			text = "Welcome! The board keeps its speed on flat ground. PUSH to go faster: tap higher for a harder kick."},
		{section = "ollie", when = _pop_at("ollie"), wait = [&"tail_pop"], check = _full_pop,
			text = "A step ahead. TAIL POP to ollie up onto it. Tap near the top for a full pop."},
		{when = _near_apex(), wait = catch, check = _flat_catch,
			text = "Catch the board before you land, or you slam. Tap CATCH near its middle line to land flat."},
		{section = "drop", when = func() -> bool: return _past("drop") and runner._in_trick, wait = catch, check = _flat_catch,
			text = "Rolling off a ledge needs a catch too. (Don't push right before a ledge: that slams.)"},
		{section = "nollie", when = _pop_at("nollie"), wait = [&"nose_pop"], check = _full_pop,
			text = "NOSE POP pops off the front: a nollie. Then catch it yourself."},
		{section = "flip", when = _pop_at("flip", 80.0), wait = [&"tail_pop"], check = _full_pop,
			text = "Big drop ahead. Pop off the edge for lots of air."},
		{when = _near_apex(-700.0), wait = [&"trick"],
			text = "TRICK pad: the column on your pop side does shuvits, the other column flips. Pick any trick."},
		{when = func() -> bool: return runner._board_trick != &"" and runner._board_trick_left < runner.trick_time * 0.6,
			wait = catch, check = _flat_catch,
			text = "Catch the trick before it finishes (0.4 s), or you slam."},
		{section = "steps", when = func() -> bool: return _past("steps", -300.0), banner = true,
			text = "Your turn: ollie up the steps and catch each jump."},
		{section = "late", when = _pop_at("late", 80.0), wait = [&"tail_pop"], check = _full_pop,
			text = "Another drop. Pop off the edge again."},
		{when = _near_apex(-500.0), wait = catch, check = _flat_catch,
			text = "Late trick: catch first..."},
		{when = always, wait = [&"trick"], text = "...then pick a TRICK..."},
		{when = func() -> bool: return runner._board_trick != &"" and runner._board_trick_left < runner.trick_time * 0.6,
			wait = catch, check = _flat_catch, text = "...and catch it again."},
		{section = "manual", when = func() -> bool: return _past("manual") and runner._in_trick, wait = catch, check = _flat_catch,
			text = "Manual: catch once to lock the board..."},
		{when = _touchdown_soon(false), wait = catch, hold = true, check = _side_hold,
			text = "...then press and HOLD CATCH as you come down: holding readies a manual. Left half = on the tail, right half = nose manual. Keep holding until you land."},
		{when = func() -> bool: return runner.is_balancing() and not balance_pad.points().is_empty(),
			wait = [&"balance"],
			check = _on_point,
			text = "Keep your balance: tap each point before its ring runs out. Tapping an empty spot slams."},
		{when = func() -> bool: return _past("rail", -700.0), wait = _raised_end,
			unless = func() -> bool: return not runner.is_balancing(),
			text = "Pop the raised end to put the wheels down."},
		{section = "rail", when = _pop_at("rail"), wait = [&"tail_pop"], check = _full_pop,
			text = "A rail! Ollie toward it."},
		{when = _near_apex(-250.0), wait = catch, check = _flat_catch, text = "Catch to lock the board..."},
		{when = _touchdown_soon(true), wait = catch, hold = true,
			text = "...and HOLD CATCH coming down onto the rail to grind it. Hold the middle for a 50-50 (the easiest), a side for a 5-0 or nosegrind. Letting go cancels it."},
		{when = func() -> bool: return runner.is_grinding() and not balance_pad.points().is_empty(),
			wait = [&"balance"],
			check = _on_point,
			text = "Grinding! Keep balancing. On a 5-0 or nosegrind the points come faster and are smaller; a 50-50 is gentler."},
		{when = func() -> bool: return runner.is_grinding() and _past("rail", -350.0 + runner.marks.rail.y - runner.marks.rail.x),
			wait = _raised_end, unless = func() -> bool: return not runner.is_grinding(),
			text = "Pop the raised end to hop off the rail. You'll have to catch the board."},
		{when = func() -> bool: return (runner._in_trick and runner._velocity_y > -200.0) or _near("ledge", 700.0),
			unless = func() -> bool: return not runner._in_trick or not runner._needs_catch or _caught(),
			wait = catch, check = _flat_catch, text = "Hopping off needs a catch. Catch it!"},
		{section = "ledge", when = func() -> bool: return _near("ledge", 600.0), banner = true,
			text = "Ledges work like rails: hold CATCH onto one to tailslide or noseslide."},
		{when = _pop_at("ledge"), wait = [&"tail_pop"], check = _full_pop, text = "Ollie toward the ledge."},
		{when = _near_apex(-250.0), wait = catch, check = _flat_catch, text = "Catch to lock..."},
		{when = _touchdown_soon(true), wait = catch, hold = true, text = "...and HOLD CATCH onto the ledge: slide it!"},
		{when = func() -> bool: return runner._in_trick and runner._from_rail and not runner._needs_catch,
			banner = true, text = "Dropping off the end of a ledge or rail needs no catch."},
		{when = func() -> bool: return runner.is_grounded() and not runner.is_balancing(),
			enter = func() -> void: flow.fill(), wait = [&"flow"],
			text = "Tricks fill the FLOW button: harder tricks and combos fill it faster. When it's full, tap it for 5 s of slow motion."},
		{when = always, banner = true, text = "That's everything! Roll on to the flag."},
	]
