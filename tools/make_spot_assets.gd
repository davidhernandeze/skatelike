extends SceneTree
## Turns a spot's generated art (Sprite Fusion, under assets/spots/source/<set>/) into its
## asset group (assets/spots/<spot>/), as its make.json says:
##
##   {"out": "res://assets/spots/bridge/",
##    "tint": [r, g, b],                         (optional, multiplies the tiles: the
##                                               spot's light, e.g. dusk)
##    "prop_tint": [r, g, b],                    (the same for the props)
##    "fill": {"from": "fill/result_0.png"},     -> fill.png: tiled inside the ground
##    "edge": {"from": "edge/result_0.png", "rows": [0, 10]}
##                                            -> edge.png: the strip along the surface
##    "props": {"lamp": {"from": "lamp/result_3.png"}, ...}
##                                            -> props/<name>.png: trimmed to the sprite;
##                                               "scale": 0.6 shrinks one drawn too big
##                                               (cubic, then hard alpha)
##    "icon": {"from": "icon/result_0.png"}    -> icon.png: the spot's map icon, as is}
##
## Tiles are mended to wrap (see _wrapping). Props are cut to their opaque bounds (the bottom
## row is where they stand) and stray magenta pixels (generation noise) are painted over
## with their neighbours. The backdrop layers go through tools/make_backgrounds.gd.
##
##   godot --headless --path . -s tools/make_spot_assets.gd -- assets/spots/source/bridge_set

var _tint := Color.WHITE
var _prop_tint := Color.WHITE


func _initialize() -> void:
	var dir: String = OS.get_cmdline_user_args()[0].trim_suffix("/")
	var source := ProjectSettings.globalize_path("res://" + dir.trim_prefix("res://")) + "/"
	var make: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source + "make.json"))
	var out := ProjectSettings.globalize_path(make.out)
	DirAccess.make_dir_recursive_absolute(out + "props")
	if make.has("tint"):
		_tint = Color(make.tint[0], make.tint[1], make.tint[2])
	if make.has("prop_tint"):
		_prop_tint = Color(make.prop_tint[0], make.prop_tint[1], make.prop_tint[2])
	if make.has("fill"):
		var fill := _wrapping(_load(source + make.fill.from))
		_save(_tinted(fill), out + "fill.png")
	if make.has("edge"):
		var edge := _wrapping(_load(source + make.edge.from), true)
		var rows: Array = make.edge.get("rows", [0, edge.get_height()])
		edge = edge.get_region(Rect2i(0, rows[0], edge.get_width(), rows[1] - rows[0]))
		_save(_tinted(edge), out + "edge.png")
	if make.has("icon"):
		_save(_load(source + make.icon.from), out + "icon.png")
	for name: String in make.get("props", {}):
		var prop := _load(source + make.props[name].from)
		_clean_magenta(prop)
		prop = prop.get_region(_opaque_rect(prop))
		var scale: float = make.props[name].get("scale", 1.0)
		if scale != 1.0:
			prop = _shrunk(prop, scale)
		_save(_tinted(prop, _prop_tint), out + "props/" + name + ".png")
	quit()


## `image` resized by `scale` (cubic, colours premultiplied so see-through pixels don't
## bleed), every pixel then solid or clear: hard pixel-art edges.
func _shrunk(image: Image, scale: float) -> Image:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
	image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)),
			Image.INTERPOLATE_CUBIC)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a >= 0.5:
				image.set_pixel(x, y, Color(minf(c.r / c.a, 1.0), minf(c.g / c.a, 1.0), minf(c.b / c.a, 1.0), 1.0))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image.get_region(_opaque_rect(image))


func _load(path: String) -> Image:
	var image := Image.load_from_file(path)
	image.convert(Image.FORMAT_RGBA8)
	return image


func _save(image: Image, path: String) -> void:
	image.save_png(path)
	print(path.get_file(), " ", image.get_size())


## `image` mended so it repeats (`x_only`: only sideways, an edge strip). Generated
## "seamless" tiles come with a border of sorts: a see-through last row, and shading
## down the first column where the last one already has it. The see-through rows go
## (in a fill, the last one becomes a mortar row, a copy of the darkest full row); where
## a row's first and last pixels are both the same shade, a brick runs across the wrap
## and the first takes its neighbour's colour (the brick face).
func _wrapping(image: Image, x_only := false) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	if not x_only and _row_clear(image, h - 1):
		var mortar := 0
		for y in h - 1:
			if _row_luminance(image, y) < _row_luminance(image, mortar):
				mortar = y
		for x in w:
			image.set_pixel(x, h - 1, image.get_pixel(x, mortar))
	image = image.get_region(_opaque_rect(image))
	w = image.get_width()
	h = image.get_height()
	for y in h:
		var first := image.get_pixel(0, y)
		var last := image.get_pixel(w - 1, y)
		var face := image.get_pixel(1, y)
		# Shade, not mortar (much darker), on both sides of the wrap.
		var shade := face.get_luminance() - 0.05
		if first.get_luminance() < shade and last.get_luminance() < shade \
				and absf(first.get_luminance() - last.get_luminance()) < 0.06 and first.get_luminance() > 0.45:
			image.set_pixel(0, y, face)
	return image


func _row_clear(image: Image, y: int) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, y).a >= 0.5:
			return false
	return true


func _row_luminance(image: Image, y: int) -> float:
	var sum := 0.0
	for x in image.get_width():
		var c := image.get_pixel(x, y)
		sum += c.get_luminance() if c.a >= 0.5 else 1.0
	return sum / image.get_width()


func _opaque_rect(image: Image) -> Rect2i:
	var lo := Vector2i(image.get_width(), image.get_height())
	var hi := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.5:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _clean_magenta(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5 or minf(c.r, c.b) - c.g < 0.35:
				continue
			# The most common solid, non-magenta colour around it.
			var counts := {}
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
					Vector2i(-2, 0), Vector2i(2, 0)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height():
					continue
				var n := image.get_pixelv(p)
				if n.a >= 0.5 and minf(n.r, n.b) - n.g < 0.35:
					counts[n] = counts.get(n, 0) + 1
			var best = null
			for n: Color in counts:
				if best == null or counts[n] > counts[best]:
					best = n
			image.set_pixel(x, y, best if best != null else Color(0, 0, 0, 0))


func _tinted(image: Image, tint := _tint) -> Image:
	if tint == Color.WHITE:
		return image
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	return image
