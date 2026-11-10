class_name ParallaxBackdrop
extends Control
## The Dusk Boardwalk backdrop: sky, sea and boardwalk front layers (assets/backgrounds,
## see tools/make_backgrounds.gd) that tile sideways and scroll at their own speeds
## behind whatever moves in front: the level (follow a Runner) or the menus (drifting
## by themselves, the pages floating over it). Drawn as pixel art on the world's grid.
## A spot's stage brings its own layers instead (use_art(), see SpotArt).
##
## The layers stop at their bottom edge, and each one moves up and down at its own speed
## as the camera does, so what's under a layer would show as empty: every layer but the
## front one carries on down, its bottom band (EXTEND_ROWS texels) repeated mirrored (the
## sky's glow, the sea's water). Under the front one: a flat colour (its last row), or,
## with `open_bottom` (a spot's, see SpotArt), nothing, so the layers behind show (the
## river's water under the embankment).

## Texels of a layer's bottom band repeated under it.
const EXTEND_ROWS := 48

const BOARDWALK: Array[Texture2D] = [
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

## The layers, back to front (the last one's bottom edge sits at `bottom`).
var layers: Array[Texture2D] = BOARDWALK
## Leave the front layer's bottom open (see above).
var open_bottom := false
## Per layer: its bottom band, then the same flipped, to repeat under it (null for none).
var _extensions: Array[Texture2D] = []
## The level this follows (its scrolling and camera height), if any.
var runner: Runner
## Foreground scroll (px): x along, y up (positive: the camera went up).
var scroll := Vector2.ZERO
var _cam_from := NAN
## Colors above the sky's top and below the boardwalk's bottom, for screens taller than
## the layers.
var _top_color := Color.BLACK
var _bottom_color := Color.BLACK


## Uses a spot's asset group's backdrop (SpotArt.backdrop), if it has one; call before
## adding it.
func use_art(art: String) -> void:
	var backdrop := SpotArt.backdrop(art)
	if not backdrop.is_empty():
		layers = backdrop.layers
		speeds = backdrop.speeds
		open_bottom = backdrop.get("open_bottom", false)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sky := layers[0].get_image()
	_top_color = sky.get_pixel(sky.get_width() / 2, 0)
	# Below the front layer: its lowest solid colour (a keyed layer can end see-through).
	var front := layers.back().get_image() as Image
	for y in range(front.get_height() - 1, -1, -1):
		var c := front.get_pixel(front.get_width() / 2, y)
		if c.a >= 0.5:
			_bottom_color = c
			break
	clip_contents = true
	for i in layers.size():
		_extensions.append(_extension(layers[i]) if i < layers.size() - 1 else null)


## `layer`'s bottom band flipped, then as it is: repeated under the layer it carries on
## from its last row with no seam.
static func _extension(layer: Texture2D) -> Texture2D:
	var image := layer.get_image()
	if image.is_compressed():
		image.decompress()
	var rows := mini(EXTEND_ROWS, image.get_height())
	var band := image.get_region(Rect2i(0, image.get_height() - rows, image.get_width(), rows))
	var flipped := band.duplicate() as Image
	flipped.flip_y()
	var out := Image.create(band.get_width(), rows * 2, false, band.get_format())
	out.blit_rect(flipped, Rect2i(Vector2i.ZERO, flipped.get_size()), Vector2i.ZERO)
	out.blit_rect(band, Rect2i(Vector2i.ZERO, band.get_size()), Vector2i(0, rows))
	return ImageTexture.create_from_image(out)


func _process(delta: float) -> void:
	if runner:
		# The runner's units are the world's: zoomed (its scale) on the way to the screen.
		var zoom := runner.get_global_transform().get_scale().x
		var cam: float = runner.position.y * zoom  # -camera height: grows as the camera goes up.
		if is_nan(_cam_from):
			_cam_from = cam
			var board: Vector2 = runner.get_global_transform() * (runner.board_pose()[0] as Vector2)
			bottom = (board.y - global_position.y - lift) / maxf(size.y, 1.0)
		scroll = Vector2(runner.scrolled() * zoom, cam - _cam_from)
	else:
		scroll.x += drift * delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _top_color)
	var base := size.y * bottom
	for i in layers.size():
		var texture := layers[i]
		var tile := Vector2(texture.get_size()) * pixel
		var x := -fposmod(scroll.x * speeds[i], tile.x)
		var y := base + scroll.y * speeds[i] - tile.y
		# Following a level, the layers snap to the world's pixel grid. Drifting slowly in
		# the menus, snapping makes them jump a whole texel every few frames (seconds, for the
		# sky): they glide on the screen's own pixels instead.
		if runner:
			x = roundf(x / pixel) * pixel
		y = roundf(y / pixel) * pixel
		var x0 := x
		while x < size.x:
			draw_texture_rect(texture, Rect2(Vector2(x, y), tile), false)
			x += tile.x
		if _extensions[i] and y + tile.y < size.y:
			var band := Vector2(_extensions[i].get_size()) * pixel
			var by := y + tile.y
			while by < size.y:
				x = x0
				while x < size.x:
					draw_texture_rect(_extensions[i], Rect2(Vector2(x, by), band), false)
					x += band.x
				by += band.y
		if i == layers.size() - 1 and not open_bottom and y + tile.y < size.y:
			draw_rect(Rect2(0.0, y + tile.y, size.x, size.y - y - tile.y), _bottom_color)
