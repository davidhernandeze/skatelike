extends SceneTree
## Cuts an outfit item out of a Sprite Fusion edit of the base skater (tools/sf_item.sh):
## lines the edit up with the base on the rig canvas (by the body the item doesn't
## touch), keeps the item's pixels and saves them on the canvas, in the rest pose, as
## Outfits items are (assets/characters/items).
##
##   godot --headless --path . -s tools/extract_item.gd -- <edit.png> <slot> <out.png> [preview.png]
##   godot --headless --path . -s tools/extract_item.gd -- --base <out.png>
##
## slot: "hat" or "hair" (the new grey pixels above the neck) or "shirt" (the whole top:
## every grey pixel from the neck to the waist). Ask for items in plain light grey. --base saves the base on
## the canvas (the edit's input). The optional preview shows base, edit, item and the
## base wearing it, 8x bigger.

const SPRITE := "res://assets/characters/skater.png"
const RIG := "res://assets/characters/rig/base.json"
## How different a pixel must be from the base's to count as changed (RGB distance).
const CHANGED := 0.16
const OUTLINE_V := 0.22
## Smaller parts of the item are noise from the redraw.
const MIN_PART := 4
const AROUND: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1)]

var canvas: Vector2i
var offset: Vector2i
var joints: Dictionary


func _initialize() -> void:
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIG))
	canvas = Vector2i(rig.canvas[0], rig.canvas[1])
	offset = Vector2i(rig.offset[0], rig.offset[1])
	joints = rig.joints
	var args := OS.get_cmdline_user_args()
	var base := _base()
	if args.size() >= 2 and args[0] == "--base":
		base.save_png(args[1])
		quit()
		return
	if args.size() < 3:
		push_error("usage: <edit.png> <slot> <out.png> [preview.png]")
		quit(1)
		return
	var edit := Image.load_from_file(args[0])
	edit.convert(Image.FORMAT_RGBA8)
	if edit.get_width() > canvas.x or edit.get_height() > canvas.y:
		push_error("edit is %dx%d, bigger than the canvas: redrawn at another scale, use the other result"
			% [edit.get_width(), edit.get_height()])
		quit(1)
		return
	var slot := args[1]
	var neck := int(joints.neck[1])
	var waist := int(joints.hip[1]) + 1
	# Line up by the rows the item leaves alone.
	var rows := Vector2i(neck + 2, canvas.y) if slot in ["hat", "hair"] else Vector2i(waist + 1, canvas.y)
	var at := _align(base, edit, rows)
	print("edit %dx%d placed at %s, %.0f%% of the untouched body matches" % [edit.get_width(), edit.get_height(),
		at, 100.0 * _score(base, edit, at, rows, true)])
	var placed := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	placed.blit_rect(edit, Rect2i(Vector2i.ZERO, edit.get_size()), at)
	var item := _cut(base, placed, slot, neck, waist)
	item.save_png(args[2])
	print("item -> ", args[2])
	if args.size() > 3:
		_save_preview(base, placed, item, args[3])
	quit()


## The base skater on the rig canvas.
func _base() -> Image:
	var sprite := Image.load_from_file(ProjectSettings.globalize_path(SPRITE))
	sprite.convert(Image.FORMAT_RGBA8)
	var image := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	image.blit_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), offset)
	return image


## Where to put `edit`'s top left on the canvas so `rows` match the base best.
func _align(base: Image, edit: Image, rows: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_score := -INF
	for dy in range(-edit.get_height(), canvas.y):
		for dx in range(-edit.get_width(), canvas.x):
			var s := _score(base, edit, Vector2i(dx, dy), rows, false)
			if s > best_score:
				best_score = s
				best = Vector2i(dx, dy)
	return best


## How well `edit` at `at` matches the base in `rows`: matching opaque pixels minus
## pixels only one of them has (or, `fraction`, the share of the base's pixels matched).
func _score(base: Image, edit: Image, at: Vector2i, rows: Vector2i, fraction: bool) -> float:
	var good := 0.0
	var bad := 0.0
	var total := 0.0
	for y in range(rows.x, rows.y):
		for x in canvas.x:
			var b := base.get_pixel(x, y)
			var e := Color(0, 0, 0, 0)
			var p := Vector2i(x, y) - at
			if p.x >= 0 and p.y >= 0 and p.x < edit.get_width() and p.y < edit.get_height():
				e = edit.get_pixelv(p)
			if b.a >= 0.5:
				total += 1.0
			if b.a >= 0.5 and e.a >= 0.5:
				if _distance(b, e) <= CHANGED:
					good += 1.0
				else:
					bad += 0.5
			elif b.a >= 0.5 or e.a >= 0.5:
				bad += 1.0
	return good / maxf(total, 1.0) if fraction else good - bad


func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## The item in the lined-up edit: its fill is the neutral grey pixels (items are drawn
## grey, to be recolored by Outfits' ramps) of the slot's rows that the base doesn't have
## there (for "shirt", every one: the whole top), in parts of at least MIN_PART pixels
## (the rest is redraw noise); its outline is the dark pixels touching the fill.
func _cut(base: Image, placed: Image, slot: String, neck: int, waist: int) -> Image:
	var rows := Vector2i(0, neck) if slot in ["hat", "hair"] else Vector2i(neck - 1, waist)
	var fill := {}
	for y in range(rows.x, rows.y + 1):
		for x in canvas.x:
			var c := placed.get_pixel(x, y)
			var b := base.get_pixel(x, y)
			if c.a < 0.5 or c.v < OUTLINE_V or c.s >= 0.2:
				continue
			if slot == "shirt" or b.a < 0.5 or _distance(b, c) > CHANGED:
				fill[Vector2i(x, y)] = true
	# Small parts are noise unless they're next to a big one, past the base's edge (a cap's
	# brim, beyond its outline).
	var parts := _parts(fill)
	var big := {}
	for part in parts:
		if part.size() >= MIN_PART:
			for p: Vector2i in part:
				big[p] = true
	for part in parts:
		if part.size() >= MIN_PART:
			continue
		var near := false
		for p: Vector2i in part:
			if base.get_pixelv(p).a >= 0.5:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					near = near or big.has(p + Vector2i(dx, dy))
		if not near:
			for p: Vector2i in part:
				fill.erase(p)
	var item := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	for p: Vector2i in fill:
		item.set_pixelv(p, Color(placed.get_pixelv(p), 1.0))
	for p: Vector2i in fill:
		for d in AROUND:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= canvas.x or q.y >= canvas.y or q.y > rows.y + 1 or fill.has(q):
				continue
			var c := placed.get_pixelv(q)
			if c.a >= 0.5 and c.v < OUTLINE_V:
				item.set_pixelv(q, Color(c, 1.0))
	return item


## `pixels`' 8-connected parts.
func _parts(pixels: Dictionary) -> Array[Array]:
	var parts: Array[Array] = []
	var seen := {}
	for start: Vector2i in pixels:
		if seen.has(start):
			continue
		var part: Array[Vector2i] = []
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			part.append(p)
			for d in AROUND:
				var q: Vector2i = p + d
				if pixels.has(q) and not seen.has(q):
					seen[q] = true
					stack.append(q)
		parts.append(part)
	return parts


func _save_preview(base: Image, placed: Image, item: Image, path: String) -> void:
	var worn := base.duplicate() as Image
	worn.blend_rect(item, Rect2i(Vector2i.ZERO, canvas), Vector2i.ZERO)
	var sheet := Image.create(canvas.x * 4 + 6, canvas.y + 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.42, 0.45, 0.52))
	var i := 0
	for image: Image in [base, placed, item, worn]:
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, canvas), Vector2i(1 + i * (canvas.x + 1), 1))
		i += 1
	sheet.resize(sheet.get_width() * 8, sheet.get_height() * 8, Image.INTERPOLATE_NEAREST)
	sheet.save_png(path)
