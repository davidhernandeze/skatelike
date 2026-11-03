class_name BalanceMeter
extends Node2D
## The balance needle (BalancePad.needle) drawn as a meter above the board while a
## manual or grind is ridden, where the eyes already are. A child of the Runner (shares
## its coordinates).

## Above the board's middle (px), and the arc's radius and spread each side (deg).
@export var lift := 165.0
@export var radius := 46.0
@export var spread := 60.0
@export var safe_color := Color(0.4, 0.9, 0.5)
@export var danger_color := Color(1.0, 0.35, 0.3)
@export var needle_color := Color(1.0, 1.0, 1.0)
@export var outline_color := Color(0.08, 0.06, 0.12)

var pad: BalancePad

@onready var _runner: Runner = get_parent()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if pad == null or not pad.is_active() or not _runner.is_balancing():
		return
	var center := _runner.view_position() + Vector2(0.0, -lift)
	var steps := 12
	# The arc, green in the middle to red at the ends.
	for i in steps:
		var a0 := lerpf(-spread, spread, float(i) / steps)
		var a1 := lerpf(-spread, spread, float(i + 1) / steps)
		var k := absf((a0 + a1) * 0.5) / spread
		var c := safe_color.lerp(danger_color, smoothstep(0.35, 0.9, k))
		draw_arc(center, radius, deg_to_rad(a0 - 90.0), deg_to_rad(a1 - 90.0), 4, outline_color, 13.0)
		draw_arc(center, radius, deg_to_rad(a0 - 90.0), deg_to_rad(a1 - 90.0), 4, c, 8.0)
	# The needle; dimmed while settling (it can't fall yet).
	var tip := center + Vector2.from_angle(deg_to_rad(pad.needle * spread - 90.0)) * (radius + 8.0)
	var shade := needle_color if pad.is_settled() else Color(needle_color, 0.5)
	draw_line(center, tip, outline_color, 7.0)
	draw_line(center, tip, shade, 4.0)
	draw_circle(center, 6.0, outline_color)
	draw_circle(center, 4.0, shade)
