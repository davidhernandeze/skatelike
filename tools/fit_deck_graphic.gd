extends SceneTree
## Fits a generated deck underside (a Sprite Fusion image of the deck seen from below,
## nose to tail left to right) to the deck graphic BoardView maps under the board:
## trims the empty margin and the drawn outline (the board view draws its own), then
## scales it to SIZE with nearest-neighbour sampling, keeping the pixels hard.
##
##   godot --headless --path . -s tools/fit_deck_graphic.gd -- in.png out.png [preview.png]
##
## SIZE is the texels the deck covers at BoardView's default pixel (3): 32 x 8.
##
## The optional preview is the result 8x bigger, to look at.

const SIZE := Vector2i(32, 8)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- in.png out.png [preview.png]")
		quit(1)
		return
	var image := Image.load_from_file(args[0])
	if image == null or image.is_empty():
		printerr("can't read ", args[0])
		quit(1)
		return
	image.convert(Image.FORMAT_RGBA8)
	image = image.get_region(image.get_used_rect())
	image = _strip_outline(image)
	image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_NEAREST)
	_fill_transparent(image)
	image.save_png(args[1])
	if args.size() > 2:
		var preview := image.duplicate() as Image
		preview.resize(SIZE.x * 8, SIZE.y * 8, Image.INTERPOLATE_NEAREST)
		preview.save_png(args[2])
	print("%s -> %s (%dx%d)" % [args[0], args[1], SIZE.x, SIZE.y])
	quit()


## Drops the outermost ring of pixels when it's the outline (dark, around the deck).
func _strip_outline(image: Image) -> Image:
	var size := image.get_size()
	if size.x < 8 or size.y < 6:
		return image
	var dark := 0
	var total := 0
	for x in size.x:
		for y in [0, size.y - 1]:
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				total += 1
				dark += 1 if c.get_luminance() < 0.15 else 0
	if total > 0 and dark > total * 0.6:
		return image.get_region(Rect2i(1, 1, size.x - 2, size.y - 2))
	return image


## The rounded ends leave transparent corners: give them the nearest opaque color in
## the row, so nothing shows through where the mesh's own rounding differs.
func _fill_transparent(image: Image) -> void:
	for y in image.get_height():
		var row: Array[Color] = []
		for x in image.get_width():
			row.append(image.get_pixel(x, y))
		for x in image.get_width():
			if row[x].a >= 0.5:
				continue
			for d in image.get_width():
				for nx in [x - d, x + d]:
					if nx >= 0 and nx < image.get_width() and row[nx].a >= 0.5:
						image.set_pixel(x, y, Color(row[nx], 1.0))
						break
				if image.get_pixel(x, y).a >= 0.5:
					break
