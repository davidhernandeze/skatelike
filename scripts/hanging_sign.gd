class_name HangingSign
extends Control
## A painted wooden sign hanging on two chains from the top of its rect, with a strip of
## warm bulbs along its top edge and its text in the logo font: the menu's logo, the pause
## screen's title.

@export var text := "skatelike":
	set(value):
		text = value
		update_minimum_size()
		queue_redraw()
@export var font_size := 96
@export var paint := UiKit.PAINTS.orange
## Chain length above the sign (px).
@export var chain := 54.0
@export var bulbs := 9
## Room around the text on the plank (px).
@export var padding := Vector2(54, 30)

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	var text_size := UiKit.LOGO_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(text_size.x, UiKit.LOGO_FONT.get_height(font_size) * 0.8) + padding * 2.0 + Vector2(0, chain)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var board_size := _get_minimum_size() - Vector2(0, chain)
	var p := float(UiKit.PIXEL)
	var board := Rect2(((Vector2((size.x - board_size.x) * 0.5, chain)) / p).floor() * p, (board_size / p).floor() * p)
	for x in [board.position.x + board.size.x * 0.18, board.end.x - board.size.x * 0.18]:
		UiKit.draw_chain(self, Vector2(x, 0), Vector2(x, board.position.y + p * 3))
	draw_style_box(UiKit.plank(paint), board)
	UiKit.draw_bulbs(self, board.position + Vector2(p * 10, p * 3), Vector2(board.end.x - p * 10, board.position.y + p * 3),
			bulbs, true, _time)
	var font := UiKit.LOGO_FONT
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := board.get_center().y + font.get_ascent(font_size) * 0.42 + p * 2
	var at := Vector2(board.get_center().x - width * 0.5, baseline)
	draw_string(font, at + Vector2(0, p), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(UiKit.LIGHT, 0.35))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiKit.INK)
