class_name MapView
extends Control
## The city map, as a paper map lying on a wooden table: the first page of the menu. It
## is pixel art at the UI's pixel size (UiKit.PIXEL), made in code: the table, a clean
## paper sheet (faint fibers, no marks of use), and per spot (Spots.on_map()) its section
## of the sheet: a river under its landmark, the dotted route leading up from the bottom
## through the spots in order, and its name. Sections stack upward, so the map grows up
## as spots are added (the menu scrolls it, from the bottom).
##
## Each spot's icon (spot.landmark: a standalone low-res sprite, not part of the paper)
## floats over the sheet: drawn on top with its shadow cast on the paper below it, rising
## and sinking a pixel. Over it: a pointer bobbing on the spot to ride next, a check once
## cleared, a lock while locked (the icon faded). Pressing an open spot emits spot_pressed.

signal spot_pressed(id: String)

## The sheet's width and each section's height (art px).
const ART_W := 196
const SECTION_H := 300
## Table showing around the sheet (art px): at the sides, below, and above (the room the
## next sections will take).
const TABLE_SIDE := 10
const TABLE_BOTTOM := 16
const TABLE_TOP := 60
const WOOD := Color("6b4a2e")
const PAPER := Color("efe3c4")
const PAPER_EDGE := Color("c9b48a")
const RIVER := Color("9db6bf")
const ROUTE := Color("a88a5c")
const INK := Color("4a3a2a")
## The icons' shadow on the paper: how far below them (art px) and how dark.
const SHADOW_DROP := Vector2(3, 6)
const SHADOW := Color(0.2, 0.13, 0.06, 0.28)

var _art_h := 0
## Each spot on the map: {spot, rect (landmark, art px), center (art px)}.
var _places: Array = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	light_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art_h = TABLE_BOTTOM + Spots.sections() * SECTION_H + TABLE_TOP
	custom_minimum_size = Vector2(ART_W + TABLE_SIDE * 2, _art_h) * UiKit.PIXEL
	for spot: Dictionary in Spots.on_map():
		var section_top := _art_h - TABLE_BOTTOM - (int(spot.map.section) + 1) * SECTION_H
		var at: Vector2 = Vector2(spot.map.at) + Vector2(TABLE_SIDE, section_top)
		var landmark: Texture2D = load(spot.landmark) if spot.landmark != "" else null
		var size := landmark.get_size() if landmark else Vector2(48, 48)
		_places.append({spot = spot, landmark = landmark, rect = Rect2(at, size), center = at + size * 0.5})
	var art := TextureRect.new()
	art.texture = ImageTexture.create_from_image(_paint())
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.show_behind_parent = true  # Under the markers (this control's _draw).
	art.light_mask = 0  # A paper map on a table: the menu's neon sign doesn't light it.
	add_child(art)
	# A button over each landmark and its name (flat: the art shows through).
	for place: Dictionary in _places:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var r: Rect2 = place.rect
		button.position = (r.position - Vector2(6, 6)) * UiKit.PIXEL
		button.size = (r.size + Vector2(12, 24)) * UiKit.PIXEL
		button.disabled = not Spots.is_unlocked(place.spot.id)
		button.name = "Spot_" + place.spot.id
		var id: String = place.spot.id
		button.pressed.connect(func() -> void: spot_pressed.emit(id))
		add_child(button)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Where a spot's landmark is (screen px in this control), for scrolling to it.
func spot_center(id: String) -> Vector2:
	for place: Dictionary in _places:
		if place.spot.id == id:
			return (place.center as Vector2) * UiKit.PIXEL
	return Vector2.ZERO


## The icons (with their shadows), names and markers, over the art.
func _draw() -> void:
	var p := float(UiKit.PIXEL)
	var font := UiKit.UI_FONT
	var next_found := false
	for i in _places.size():
		var place: Dictionary = _places[i]
		var id: String = place.spot.id
		var r: Rect2 = place.rect
		var open := Spots.is_unlocked(id)
		# Floating: up and down a pixel (each spot on its own beat); the shadow stays.
		var lift := Vector2(0, -roundf(sin(_time * 1.6 + i * 1.3) * 0.5 + 0.5))
		if place.landmark:
			var texture: Texture2D = place.landmark
			var shadow := SHADOW if open else Color(SHADOW, SHADOW.a * 0.5)
			draw_texture_rect(texture, Rect2((r.position + SHADOW_DROP) * p, r.size * p), false, shadow)
			draw_texture_rect(texture, Rect2((r.position + lift) * p, r.size * p), false,
					Color.WHITE if open else Color(1, 1, 1, 0.45))  # Faded: not open yet.
		var top := Vector2(r.get_center().x, r.position.y + lift.y) * p
		var name_at := Vector2(r.position.x - 20, r.end.y + 9) * p
		draw_string(font, name_at, String(place.spot.name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
				(r.size.x + 40) * p, 30, INK)
		if not open:
			_draw_icon("lock", r.get_center() * p)
		elif Spots.is_cleared(id):
			_draw_icon("check", top + Vector2(0, -10 * p))
		elif not next_found:
			# The spot to ride next: a pointer bobbing over it.
			next_found = true
			var bob := roundf(sin(_time * 4.0) * 2.0) * p
			var tip := top + Vector2(0, -4 * p + bob)
			draw_colored_polygon(Icons.triangle(tip - Vector2(0, 7 * p), Vector2.DOWN, 16 * p), INK)
			draw_colored_polygon(Icons.triangle(tip - Vector2(0, 8 * p), Vector2.DOWN, 11 * p), UiKit.BULB)


func _draw_icon(icon: String, center: Vector2) -> void:
	var texture := UiKit.icon(icon, INK, true)
	draw_texture(texture, (center - texture.get_size() * 0.5).round())


## The map's art (art px): table, sheet, rivers, route (the icons float over it: _draw).
func _paint() -> Image:
	var img := Image.create(ART_W + TABLE_SIDE * 2, _art_h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# The table: planks across, a seam every 26 px, a little grain.
	for y in img.get_height():
		for x in img.get_width():
			var c := WOOD.darkened(rng.randf_range(0.0, 0.08))
			if y % 26 == 0:
				c = WOOD.darkened(0.35)
			elif (x * 7 + y * 3 + int(y / 26.0) * 11) % 53 == 0:
				c = WOOD.darkened(0.18)
			img.set_pixel(x, y, c)
	# The sheet, with its shadow on the table.
	var sheet := Rect2i(TABLE_SIDE, TABLE_TOP - 20, ART_W, _art_h - TABLE_TOP + 20 - TABLE_BOTTOM)
	_fill(img, Rect2i(sheet.position + Vector2i(2, 3), sheet.size), Color(0, 0, 0, 0.35), true)
	for y in range(sheet.position.y, sheet.end.y):
		for x in range(sheet.position.x, sheet.end.x):
			var c := PAPER.darkened(rng.randf_range(0.0, 0.025))
			if rng.randf() < 0.012:
				c = PAPER.darkened(0.06)  # A fiber.
			img.set_pixel(x, y, c)
	_frame(img, sheet, PAPER_EDGE)
	# Per spot: a river across the sheet under its landmark, and the route up to it.
	var route_from := Vector2(img.get_width() * 0.5, sheet.end.y - 4)
	for place: Dictionary in _places:
		var center: Vector2 = place.center
		_river(img, sheet, int(center.y), rng)
		_route(img, route_from, center + Vector2(0, place.rect.size.y * 0.5 + 14))
		route_from = center - Vector2(0, place.rect.size.y * 0.5 + 6)
	# On up toward what's still to come, fading out.
	_route(img, route_from, Vector2(route_from.x, sheet.position.y + 6), true)
	return img


## A river across the sheet around row `y`: a gently winding band with light ripples.
func _river(img: Image, sheet: Rect2i, y: int, rng: RandomNumberGenerator) -> void:
	for x in range(sheet.position.x + 1, sheet.end.x - 1):
		var mid := y + roundi(sin(x * 0.045) * 6.0)
		var half := 11 + roundi(sin(x * 0.11 + 1.0) * 1.5)
		for dy in range(-half, half + 1):
			var c := RIVER
			if absf(dy) >= half - 1:
				c = RIVER.darkened(0.15)  # Banks.
			elif rng.randf() < 0.05:
				c = RIVER.lightened(0.25)
			img.set_pixel(x, mid + dy, c)


## A dotted route from `a` to `b` (art px); `fade` thins it out toward `b`.
func _route(img: Image, a: Vector2, b: Vector2, fade := false) -> void:
	var length := a.distance_to(b)
	var steps := int(length / 2.0)
	for i in steps:
		if i % 3 == 2:
			continue
		var k := float(i) / maxf(steps, 1)
		if fade and k > 0.3 and (i * 7) % 10 < int(k * 10.0):
			continue
		var q := Vector2i(a.lerp(b, k).round())
		var wobble := roundi(sin(k * 9.0) * 2.0) if not fade else 0
		for d in [Vector2i(0, 0), Vector2i(1, 0)]:
			img.set_pixelv(q + d + Vector2i(wobble, 0), ROUTE)


static func _fill(img: Image, rect: Rect2i, color: Color, blend := false) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			img.set_pixel(x, y, img.get_pixel(x, y).blend(color) if blend else color)


static func _frame(img: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.end.x):
		img.set_pixel(x, rect.position.y, color)
		img.set_pixel(x, rect.end.y - 1, color)
	for y in range(rect.position.y, rect.end.y):
		img.set_pixel(rect.position.x, y, color)
		img.set_pixel(rect.end.x - 1, y, color)
