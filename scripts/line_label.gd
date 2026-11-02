class_name LineLabel
extends Label
## The line in progress (see FlowButton): "kickflip, x2 nosegrind, x3 heelflip", under the
## score. When the line ends it stays a moment (red after a slam), then fades.

## Tricks shown at most: older ones are left out ("…, x7 manual, x8 ollie").
@export var max_shown := 6
## How long a finished line stays before fading out (s).
@export var hold_time := 1.6
@export var line_color := Color(1.0, 0.85, 0.3)
@export var slam_color := Color(1.0, 0.35, 0.3)

var _fade_in := INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("font_size", 22)
	add_theme_constant_override("outline_size", 8)
	add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
	modulate.a = 0.0


func show_line(tricks: PackedStringArray, ended: StringName) -> void:
	var parts := PackedStringArray()
	var first := maxi(tricks.size() - max_shown, 0)
	if first > 0:
		parts.append("…")
	for i in range(first, tricks.size()):
		parts.append(tricks[i] if i == 0 else "x%d %s" % [i + 1, tricks[i]])
	text = ", ".join(parts)
	add_theme_color_override("font_color", slam_color if ended == &"slammed" else line_color)
	modulate.a = 1.0
	_fade_in = hold_time if ended != &"" else INF


func _process(delta: float) -> void:
	if _fade_in == INF:
		return
	_fade_in -= delta
	if _fade_in < 0.0:
		modulate.a = maxf(modulate.a - delta * 3.0, 0.0)
		if modulate.a <= 0.0:
			_fade_in = INF
