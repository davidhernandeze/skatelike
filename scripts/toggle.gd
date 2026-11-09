class_name Toggle
extends Button
## A big on/off switch for touch, made like a wooden lever: the button's text on the left
## of a brown plank, and on the right a dark slot with a brass knob that slides to ON
## (its bulb lit) or OFF.

@export var track_size := Vector2(150, 54)

var _time := 0.0


func _init() -> void:
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _ready() -> void:
	UiKit.paint_button(self, UiKit.PAINTS.brown)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(c, UiKit.LIGHT)
	# Pressed means on, not pushed in: the same plank either way.
	add_theme_stylebox_override("pressed", UiKit.plank(UiKit.PAINTS.brown))
	add_theme_stylebox_override("hover_pressed", UiKit.plank(UiKit.PAINTS.brown, "hover"))


func _process(delta: float) -> void:
	if button_pressed:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var on := button_pressed
	var p := float(UiKit.PIXEL)
	var rect := Rect2(Vector2(size.x - track_size.x - p * 10, (size.y - track_size.y) * 0.5), track_size)
	rect = Rect2((rect.position / p).floor() * p, (rect.size / p).floor() * p)
	# The slot, cut into the wood.
	draw_rect(rect, Color("1e120a"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, p)), Color("0e0805"))
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - p), Vector2(rect.size.x, p)), Color("6a4a30"))
	var font := get_theme_font("font")
	var font_size := 22
	for side: bool in [false, true]:
		var text := "ON" if side else "OFF"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x := rect.end.x - p * 4 - width if not side else rect.position.x + p * 4
		if side != on:
			continue  # The state's name, on the side the knob isn't.
		draw_string(font, Vector2(x, rect.get_center().y + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, UiKit.BULB if on else UiKit.DIM)
	# The brass knob.
	var knob := Rect2(Vector2(rect.end.x - rect.size.y if on else rect.position.x, rect.position.y), Vector2.ONE * rect.size.y)
	knob = knob.grow(-p)
	draw_rect(knob, Color("7a5a1c"))
	draw_rect(knob.grow(-p), Color("d6a640"))
	draw_rect(Rect2(knob.position + Vector2(p * 2, p * 2), Vector2(p * 3, p)), Color("f6dc8a"))
	# Its bulb: lit when on.
	var bulb := knob.get_center() - Vector2(p, p)
	UiKit.draw_bulbs(self, bulb, bulb, 1, on, _time, 1.6)
