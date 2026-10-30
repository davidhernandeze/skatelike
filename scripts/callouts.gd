extends Node2D
## Comic-style onomatopoeias next to the board ("kickflip!", "slam!"). A child of the
## Runner, so it shares its coordinates. Bursts pop in, float up and fade; sustained
## ones (manuals, grinds) follow the board and shake until end_sustained().

@export var font: Font = preload("res://assets/fonts/BubblezGraffiti-Regular.ttf")
## Manuals, grinds and slams; pop tricks use pop_font_size.
@export var font_size := 46
@export var pop_font_size := 38
@export var trick_color := Color(1.0, 0.85, 0.3)
@export var balance_color := Color(0.4, 0.9, 1.0)
@export var slam_color := Color(1.0, 0.35, 0.3)
@export var outline_color := Color(0.08, 0.06, 0.12)
## How long a burst stays on screen (s).
@export var burst_time := 0.9
## Height above the board where callouts appear (px).
@export var lift := 70.0

## Each: {text, color, age, life (INF while sustained), tilt, size, sustained}.
var _items: Array[Dictionary] = []

@onready var _runner: Runner = get_parent()


## Shows `text` + "!" by the board. Sustained callouts stay until end_sustained().
func show_callout(text: String, sustained := false) -> void:
	end_sustained()
	_items.append({
		text = text + "!", color = balance_color if sustained else trick_color, age = 0.0,
		life = INF if sustained else burst_time, tilt = randf_range(-0.14, 0.14),
		size = font_size if sustained else pop_font_size, sustained = sustained, y = 0.0,
	})


func slam() -> void:
	end_sustained()
	_items.append({
		text = "slam!", color = slam_color, age = 0.0, life = burst_time * 1.3,
		tilt = randf_range(-0.2, 0.2), size = font_size + 14, sustained = false, y = 0.0,
	})


## Lets the sustained callout (if any) fade out like a burst.
func end_sustained() -> void:
	for item in _items:
		if item.sustained:
			item.sustained = false
			item.life = item.age + 0.3


func _process(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		_items[i].age += delta
		if _items[i].age >= _items[i].life:
			_items.remove_at(i)
	queue_redraw()


func _draw() -> void:
	var board := _runner.board_position()
	for item in _items:
		var age: float = item.age
		# Pop in with a little overshoot, then settle.
		var grow := clampf(age / 0.15, 0.0, 1.0)
		var scale_k := lerpf(0.4, 1.0, grow) + sin(grow * PI) * 0.2
		var pos := board + Vector2(0.0, -lift)
		var alpha := 1.0
		if item.sustained:
			# Shake while the trick lasts.
			pos += Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		else:
			var left: float = item.life - age
			alpha = clampf(left / 0.3, 0.0, 1.0)
			# Bursts float up from where they appeared.
			if item.y == 0.0:
				item.y = pos.y
			pos.y = item.y - age * 50.0
		var tilt: float = item.tilt + (sin(age * 40.0) * 0.06 if item.sustained else 0.0)
		var size: int = item.size
		var width := font.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := Vector2(-width * 0.5, size * 0.35)
		draw_set_transform(pos, tilt, Vector2.ONE * scale_k)
		draw_string_outline(font, at, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, roundi(size * 0.22),
				Color(outline_color, alpha))
		draw_string(font, at, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(item.color, alpha))
	draw_set_transform(Vector2.ZERO)
