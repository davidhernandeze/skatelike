class_name Pad
extends Panel
## A tappable zone in the control panel. Hit-testing is done by ControlPanel.

## What this pad does; interpreted by whoever listens to ControlPanel.pad_pressed.
@export var action: StringName
@export var color := Color.WHITE
@export var label := ""
## When set, `label` goes in the top half, this in the bottom half, with a divider between.
@export var label_bottom := ""
@export var font_size := 36
## Draws a vertical line at the center, for pads where touch position matters.
@export var center_mark := false
## Shown faded, for pads without a function yet.
@export var dimmed := false

var _style := StyleBoxFlat.new()
var _tween: Tween
var _enabled := true
## Pie indicator (e.g. push cooldown): remaining fraction, hidden at 0.
var _pie := 0.0
var _pie_queue := 0


func _ready() -> void:
	_style.bg_color = color.darkened(0.45)
	_style.set_corner_radius_all(24)
	_style.set_border_width_all(4)
	_style.border_color = color
	add_theme_stylebox_override("panel", _style)
	_apply_alpha()
	if label_bottom != "":
		_add_label(label, Control.PRESET_TOP_WIDE)
		_add_label(label_bottom, Control.PRESET_BOTTOM_WIDE)
	elif label != "":
		_add_label(label, Control.PRESET_FULL_RECT)


func _add_label(string: String, preset: Control.LayoutPreset) -> void:
	var text := Label.new()
	text.text = string
	text.add_theme_font_size_override("font_size", font_size)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_and_offsets_preset(preset)
	if preset != Control.PRESET_FULL_RECT:
		text.anchor_top = 0.0 if preset == Control.PRESET_TOP_WIDE else 0.5
		text.anchor_bottom = text.anchor_top + 0.5
		text.offset_top = 0.0
		text.offset_bottom = 0.0
	add_child(text)


## Fades the pad when its action isn't available right now.
func set_enabled(enabled: bool) -> void:
	if enabled != _enabled:
		_enabled = enabled
		_apply_alpha()


## Shows a pie in the corner: `remaining` 0..1 of the current cycle, plus a dot per queued one.
func set_pie(remaining: float, queued: int) -> void:
	if not is_equal_approx(remaining, _pie) or queued != _pie_queue:
		_pie = remaining
		_pie_queue = queued
		queue_redraw()


func _apply_alpha() -> void:
	modulate.a = 0.35 if dimmed or not _enabled else 1.0


func _draw() -> void:
	if label_bottom != "":
		var y := size.y * 0.5
		draw_line(Vector2(12.0, y), Vector2(size.x - 12.0, y), Color(color, 0.6), 3.0)
	if center_mark:
		var x := size.x * 0.5
		draw_line(Vector2(x, 12.0), Vector2(x, size.y - 12.0), Color(color, 0.6), 3.0)
	if _pie > 0.0 or _pie_queue > 0:
		var radius := 24.0
		var center := Vector2(size.x - radius - 14.0, radius + 14.0)
		draw_circle(center, radius, Color(0, 0, 0, 0.4))
		if _pie > 0.0:
			var points := PackedVector2Array([center])
			var steps := maxi(2, ceili(_pie * 32.0))
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * _pie * float(i) / steps
				points.append(center + Vector2(cos(a), sin(a)) * radius)
			draw_colored_polygon(points, color.lightened(0.3))
		for i in _pie_queue:
			draw_circle(center + Vector2(0.0, radius + 16.0 + i * 18.0), 6.0, color.lightened(0.3))


func flash() -> void:
	if _tween:
		_tween.kill()
	_style.bg_color = color
	_tween = create_tween()
	_tween.tween_property(_style, "bg_color", color.darkened(0.45), 0.15)
