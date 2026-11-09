extends SceneTree
## Makes the wooden UI kit (assets/ui, used by UiKit) from its sources (assets/ui/source,
## see assets/ui/sources.json): crops the Sprite Fusion plank, pad, backboard and dial
## sprites, and cuts the Runway icon sheet (dark symbols on white, 6 x 3) into icon masks:
## white where the symbol is, shrunk to SIZES texels with a cubic resize and hard edges, so
## they can be drawn in any color (burned in, or lit) on the UI's pixel grid.
##
##   godot --headless --path . -s tools/make_ui_kit.gd

const SOURCE := "res://assets/ui/source/"
const OUT := "res://assets/ui/"
const SPRITES := {plank = "plank_sf", pad = "pad_sf", dial = "dial_sf", backboard = "backboard_sf"}
## The icon sheet's symbols, row by row.
const ICONS := ["pop", "push", "pop_nose", "pause", "restart", "play",
	"home", "back", "profile", "star", "gaps", "practice",
	"check", "trophy", "stats", "lock", "online", "flow"]
const COLUMNS := 6
const ROWS := 3
## Icon sizes (texels, the longer side): the small ones, and the big ones (name_big.png)
## burned into the touch pads.
const SIZES := {"": 16, "_big": 28}


func _initialize() -> void:
	for name: String in SPRITES:
		var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE + SPRITES[name] + ".png"))
		image.convert(Image.FORMAT_RGBA8)
		if name != "backboard":
			image = image.get_region(image.get_used_rect())
		image.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
		print(name, " ", image.get_size())
		if name in ["plank", "pad"]:
			_unscrewed(image).save_png(ProjectSettings.globalize_path(OUT + name + "_bare.png"))
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "icons_runway.png"))
	sheet.convert(Image.FORMAT_RGBA8)
	var cell := Vector2i(sheet.get_width() / COLUMNS, sheet.get_height() / ROWS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "icons"))
	for i in ICONS.size():
		var region := sheet.get_region(Rect2i(Vector2i(i % COLUMNS, i / COLUMNS) * cell, cell))
		var mask := Image.create(cell.x, cell.y, false, Image.FORMAT_RGBA8)
		for y in cell.y:
			for x in cell.x:
				var ink := clampf((0.8 - region.get_pixel(x, y).get_luminance()) / 0.6, 0.0, 1.0)
				mask.set_pixel(x, y, Color(ink, ink, ink, ink))  # Premultiplied white.
		var used := mask.get_used_rect().grow(4)
		var side := maxi(used.size.x, used.size.y)
		var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
		square.blit_rect(mask, used, (Vector2i(side, side) - used.size) / 2)
		for suffix: String in SIZES:
			var icon := square.duplicate() as Image
			icon.resize(SIZES[suffix], SIZES[suffix], Image.INTERPOLATE_CUBIC)
			for y in icon.get_height():
				for x in icon.get_width():
					icon.set_pixel(x, y, Color.WHITE if icon.get_pixel(x, y).a >= 0.45 else Color(1, 1, 1, 0))
			icon = icon.get_region(icon.get_used_rect())
			icon.save_png(ProjectSettings.globalize_path(OUT + "icons/" + ICONS[i] + suffix + ".png"))
	print(ICONS.size(), " icons")
	quit()


## `image` (a plank or pad) without its corner screws, for small buttons: in each corner,
## the box around the screw (its dark grey core, grown to take its rim and shadow) takes the
## paint just inside it on the same rows, where the grain runs on.
func _unscrewed(image: Image) -> Image:
	var out := image.duplicate() as Image
	var w := image.get_width()
	var h := image.get_height()
	const CORNER := 16
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var box := Rect2i()
		for y in CORNER:
			for x in CORNER:
				var at := Vector2i(w - 1 - x if corner.x else x, h - 1 - y if corner.y else y)
				var c := image.get_pixelv(at)
				if x > 2 and y > 2 and c.a > 0.5 and c.get_luminance() < 0.45 and c.s < 0.3:
					box = Rect2i(at, Vector2i.ONE) if box.size == Vector2i.ZERO else box.expand(at)
		if box.size == Vector2i.ZERO:
			continue
		box.size += Vector2i.ONE
		box = box.grow(2)
		var shift := box.size.x + 1 if corner.x == 0 else -box.size.x - 1
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				out.set_pixel(x, y, image.get_pixel(x + shift, y))
	return out
