class_name Toggle
extends Button
## A big on/off switch for touch: the button's text on the left and a pill-shaped
## switch on the right, green with "ON" or muted red with "OFF".

@export var on_color := Color(0.3, 0.75, 0.4)
@export var off_color := Color(0.55, 0.22, 0.25)
@export var track_size := Vector2(130, 60)


func _init() -> void:
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var on := button_pressed
	var rect := Rect2(Vector2(size.x - track_size.x - 18.0, (size.y - track_size.y) * 0.5), track_size)
	var radius := rect.size.y * 0.5
	var track := StyleBoxFlat.new()
	track.bg_color = on_color if on else off_color
	track.set_corner_radius_all(int(radius))
	draw_style_box(track, rect)
	# The knob slides to the side of the switch it's set to; the label sits on the other.
	var knob_x := rect.end.x - radius if on else rect.position.x + radius
	draw_circle(Vector2(knob_x, rect.get_center().y), radius - 6.0, Color(0.95, 0.95, 0.97))
	var font := get_theme_font("font")
	var text := "ON" if on else "OFF"
	var font_size := 24
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_center := rect.position.x + radius + 4.0 if on else rect.end.x - radius - 4.0
	draw_string(font, Vector2(label_center - width * 0.5, rect.get_center().y + font_size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
