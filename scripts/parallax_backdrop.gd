class_name ParallaxBackdrop
extends Control
## The Dusk Boardwalk backdrop: sky, sea and boardwalk front layers (assets/backgrounds,
## see tools/make_backgrounds.gd) that tile sideways and scroll at their own speeds
## behind whatever moves in front: the level (follow a Runner) or the menus (drifting
## by themselves, the pages floating over it). Drawn as pixel art on the world's grid.

const LAYERS: Array[Texture2D] = [
	preload("res://assets/backgrounds/sky.png"),
	preload("res://assets/backgrounds/sea.png"),
	preload("res://assets/backgrounds/town.png"),
]

## Screen px per texel (the world's, Runner.PIXEL).
@export var pixel := Runner.PIXEL
## How far each layer moves for one px of the foreground (sky, sea, town).
@export var speeds := PackedFloat32Array([0.04, 0.12, 0.35])
## Drifting sideways by itself (px/s of foreground), for the menus.
@export var drift := 0.0
## Where the layers' bottom edge (the boardwalk railing) is, as a share of the height
## (1 = the bottom), when nothing has scrolled up or down. Following a runner: on the
## ground under the board at the start, raised by `lift` px.
@export var bottom := 1.0
@export var lift := 0.0

## The level this follows (its scrolling and camera height), if any.
var runner: Runner
## Foreground scroll (px): x along, y up (positive: the camera went up).
var scroll := Vector2.ZERO
var _cam_from := NAN
## Colors above the sky's top and below the boardwalk's bottom, for screens taller than
## the layers.
var _top_color := Color.BLACK
var _bottom_color := Color.BLACK


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sky := LAYERS[0].get_image()
	_top_color = sky.get_pixel(sky.get_width() / 2, 0)
	var town := LAYERS[2].get_image()
	_bottom_color = town.get_pixel(town.get_width() / 2, town.get_height() - 1)
	clip_contents = true


func _process(delta: float) -> void:
	if runner:
		var cam: float = runner.position.y  # -camera height: grows as the camera goes up.
		if is_nan(_cam_from):
			_cam_from = cam
			var board: Vector2 = runner.board_pose()[0]
			bottom = (board.y + cam - lift) / maxf(size.y, 1.0)
		scroll = Vector2(runner.scrolled(), cam - _cam_from)
	else:
		scroll.x += drift * delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _top_color)
	var base := size.y * bottom
	for i in LAYERS.size():
		var texture := LAYERS[i]
		var tile := Vector2(texture.get_size()) * pixel
		var x := -fposmod(scroll.x * speeds[i], tile.x)
		var y := base + scroll.y * speeds[i] - tile.y
		# Following a level, the layers snap to the world's pixel grid. Drifting slowly in
		# the menus, snapping makes them jump a whole texel every few frames (seconds, for the
		# sky): they glide on the screen's own pixels instead.
		if runner:
			x = roundf(x / pixel) * pixel
		y = roundf(y / pixel) * pixel
		while x < size.x:
			draw_texture_rect(texture, Rect2(Vector2(x, y), tile), false)
			x += tile.x
		if i == LAYERS.size() - 1 and y + tile.y < size.y:
			draw_rect(Rect2(0.0, y + tile.y, size.x, size.y - y - tile.y), _bottom_color)
