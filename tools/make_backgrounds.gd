extends SceneTree
## Turns the Runway background layers (assets/backgrounds/source, see sources.json) into
## the parallax layers ParallaxBackdrop draws: keys out the flat magenta of the sea and
## town layers, makes each one tile horizontally (cross-fading a band where it wraps) and
## shrinks it to the world's pixel grid (one texel per Runner.PIXEL screen px) with a
## cubic resize, the look the skaters have.
##
##   godot --headless --path . -s tools/make_backgrounds.gd [-- <source dir> <out dir> <layer>[:key] ...]
##
## With no arguments: the Dusk Boardwalk (sky, sea:key, town:key). A spot's backdrop
## (see Spots.backdrop) passes its own folders and layers, back to front; `:key` keys out
## the flat magenta.

const SOURCE := "res://assets/backgrounds/source/"
const OUT := "res://assets/backgrounds/"
## Texels tall: a 1280 px portrait screen at Runner.PIXEL.
const HEIGHT := 427
## Share of the width cross-faded where a layer wraps.
const SEAM := 0.08
const LAYERS := {sky = false, sea = true, town = true}


func _initialize() -> void:
	var source := SOURCE
	var out := OUT
	var layers := LAYERS
	var args := OS.get_cmdline_user_args()
	if args.size() >= 3:
		source = "res://" + args[0].trim_prefix("res://").trim_suffix("/") + "/"
		out = "res://" + args[1].trim_prefix("res://").trim_suffix("/") + "/"
		layers = {}
		for layer in args.slice(2):
			layers[layer.trim_suffix(":key")] = layer.ends_with(":key")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for name: String in layers:
		var image := Image.load_from_file(ProjectSettings.globalize_path(source + name + ".png"))
		image.convert(Image.FORMAT_RGBA8)
		if layers[name]:
			_key(image)
		image = _tiled(image)
		_premultiply(image, true)
		var width := roundi(image.get_width() * float(HEIGHT) / image.get_height())
		image.resize(width, HEIGHT, Image.INTERPOLATE_CUBIC)
		_premultiply(image, false)
		image.save_png(ProjectSettings.globalize_path(out + name + ".png"))
		print(name, " ", image.get_size())
	quit()


## Clears the flat magenta (#FF00FF) and takes the magenta glow off the edges next to it.
func _key(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var magenta := minf(c.r, c.b) - c.g  # 1 for pure magenta, about 0 for the rest.
			if magenta > 0.55:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif magenta > 0.3:
				# Edge pixels blended with the key: pull the magenta out, partly see-through.
				var a := clampf((0.55 - magenta) / 0.25, 0.0, 1.0)
				var spill := minf(c.r, c.b) - maxf(c.g, 0.0)
				image.set_pixel(x, y, Color(c.r - spill * 0.5, c.g, c.b - spill * 0.5, a))


## `image` with its last SEAM of columns cross-faded into its first, and cut there, so its
## right edge runs into its left.
func _tiled(image: Image) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var band := roundi(w * SEAM)
	var out := image.get_region(Rect2i(0, 0, w - band, h))
	for x in band:
		var t := float(x) / band
		for y in h:
			var a := image.get_pixel(w - band + x, y)
			var b := image.get_pixel(x, y)
			# Blend premultiplied so see-through pixels don't darken the other side.
			var pa := Color(a.r * a.a, a.g * a.a, a.b * a.a, a.a)
			var pb := Color(b.r * b.a, b.g * b.a, b.b * b.a, b.a)
			var c := pa.lerp(pb, t)
			out.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a) if c.a > 0.001 else Color(0, 0, 0, 0))
	return out


## Multiplies the colors by alpha (`on`) or divides them back and makes every pixel
## solid or clear, around a resize, so see-through pixels don't bleed dark edges.
func _premultiply(image: Image, on: bool) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if on:
				image.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
			elif c.a >= 0.5:  # Hard edges, like the rest of the pixel art.
				image.set_pixel(x, y, Color(minf(c.r / c.a, 1.0), minf(c.g / c.a, 1.0), minf(c.b / c.a, 1.0), 1.0))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
