class_name BalancePad
extends Pad
## The bottom row of the balance layout, while a balance trick (manual or grind) is ridden.
## It runs the balance needle (shown above the board by BalanceMeter): the needle tips
## away from the middle by itself, faster the further it's gone, and the finger still
## holding from the landing steers it by sliding left or right (steer). It falls off
## either end: a slam (fell). Other taps do nothing. 5-0s, nosegrinds and slides use the
## harder settings.
##
## It starts settling: the steering reference glides from where the finger landed to the
## pad's middle and the needle is pulled to the middle, so the finger can move to the
## middle (wherever it landed) with room to steer both ways. Once it's there, or after
## settle_time, the needle turns unstable and is steered from the middle.

## The needle fell off an end.
signal fell

## How fast the needle tips away from the middle, per unit off it (1/s²), and the steady
## push of random drift that changes every drift_time (1/s²).
@export var instability := 6.0
@export var drift := 1.0
@export var drift_time := Vector2(0.4, 1.0)
## Instability grows by this fraction per second held: long balances get harder.
@export var ramp := 0.06
## Push from the finger per pad half-width off the middle (1/s²), and damping of the
## needle's swing (1/s).
@export var steer_gain := 28.0
@export var damping := 3.0
## Settling: how fast the reference glides to the middle (pad widths per second), how
## strongly the needle is pulled to the middle meanwhile (1/s²), how near the middle the
## finger counts as there (fraction of the half-width), and the longest it lasts (s).
@export var glide_speed := 1.2
@export var settle_pull := 30.0
@export var centered := 0.15
@export var settle_time := 1.0

@export_group("Hard (grinds)")
@export var hard_instability := 9.0
@export var hard_drift := 1.6
@export_group("")

## Needle position, -1 (left end) .. 1 (right end), and its speed (1/s).
var needle := 0.0
var _needle_v := 0.0
var _active := false
## Still settling (see above), and for how long so far (s).
var _settling := false
var _settle_t := 0.0
## Time balanced, past settling (s).
var _held_t := 0.0
## Steering reference and the finger, as local x (px); the finger is NAN until steer().
var _reference := 0.0
var _finger := NAN
var _drift_now := 0.0
var _drift_left := 0.0
## Settings in use: the normal ones or the hard ones.
var _instability := 0.0
var _drift := 0.0


func _ready() -> void:
	super()
	set_process(false)


## Starts or stops the balance.
func set_active(active: bool, hard := false) -> void:
	_active = active
	_instability = hard_instability if hard else instability
	_drift = hard_drift if hard else drift
	needle = 0.0
	_needle_v = 0.0
	_settling = true
	_settle_t = 0.0
	_held_t = 0.0
	_finger = NAN
	_drift_left = 0.0
	set_process(active)
	queue_redraw()


## Freezes the needle where it is (e.g. after a slam).
func freeze() -> void:
	set_process(false)


func is_active() -> bool:
	return _active


## Past settling: the needle is live.
func is_settled() -> bool:
	return _active and not _settling


## The finger playing the balance is at global x `x`. Works while frozen too (the
## tutorial waits for a slide). Returns how far it is from where it first touched, as a
## fraction of the half-width.
func steer(x: float) -> float:
	if not _active:
		return 0.0
	var local := x - global_position.x
	if is_nan(_finger):
		_reference = local  # Where the finger landed is neutral, to start with.
	_finger = local
	queue_redraw()
	return absf(local - _reference) / _half_width() if _settling else 1.0


## The finger is near the pad's middle (where steering is measured from once settled).
func finger_centered() -> bool:
	return _active and not is_nan(_finger) and absf(_finger - size.x * 0.5) <= centered * _half_width()


func _half_width() -> float:
	return maxf(size.x * 0.5, 1.0)


func _process(delta: float) -> void:
	var middle := size.x * 0.5
	var steer_off := 0.0
	if not is_nan(_finger):
		steer_off = clampf((_finger - _reference) / _half_width(), -1.0, 1.0)
	var push := steer_gain * steer_off - damping * _needle_v
	if _settling:
		_settle_t += delta
		_reference = move_toward(_reference, middle, glide_speed * size.x * delta)
		push -= settle_pull * needle
		var finger_in := not is_nan(_finger) and absf(_finger - middle) <= centered * _half_width()
		if (finger_in and is_equal_approx(_reference, middle)) or _settle_t >= settle_time:
			_settling = false
			_reference = middle
	else:
		_held_t += delta
		_drift_left -= delta
		if _drift_left <= 0.0:
			_drift_left = randf_range(drift_time.x, drift_time.y)
			_drift_now = randf_range(-1.0, 1.0) * _drift
		push += _instability * (1.0 + ramp * _held_t) * needle + _drift_now
	_needle_v += push * delta
	needle += _needle_v * delta
	queue_redraw()
	if absf(needle) >= 1.0:
		needle = signf(needle)
		set_process(false)
		fell.emit()


func _draw() -> void:
	super()
	if not _active:
		return
	# The steering reference and the finger, so a glance makes sense of it.
	var y := size.y * 0.5
	draw_line(Vector2(_reference, 12.0), Vector2(_reference, size.y - 12.0), Color(color, 0.7), 4.0)
	if not is_nan(_finger):
		draw_circle(Vector2(_finger, y), 18.0, Color(color.lightened(0.5), 0.85))
