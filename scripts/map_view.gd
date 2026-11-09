class_name MapView
extends Control
## The city map, as a paper map lying on a wooden table: the first page of the menu. It
## is pixel art at the UI's pixel size (UiKit.PIXEL), made in code: the table, a clean
## paper sheet (faint fibers, no marks of use) printed with a city plan, and per spot
## (Spots.on_map()) its name on a paper tag. The plan, per section of the sheet: city
## blocks between the streets (building footprints, parks, plazas), an avenue running
## through each spot, a river under a spot by one (map.river) with bridges where avenues
## cross it, and the dotted route along the streets from the bottom through the spots in
## order. Its frame and compass rose sit on the sheet's margin. Sections stack upward,
## so the map grows up as spots are added (the menu scrolls it, from the bottom); the top
## of the last one is still being surveyed: its blocks thin out into blank paper.
##
## Each spot's icon (spot.landmark: a standalone low-res sprite, not part of the paper)
## floats over the sheet: drawn on top with its shadow cast on the paper below it, rising
## and sinking a pixel. Over it: a pointer bobbing on the spot to ride next, a check once
## cleared, a lock while locked (the icon faded). Pressing an open spot emits spot_pressed.

signal spot_pressed(id: String)

## The sheet's width and each section's height (art px). A section holds four spots
## (SLOTS), so four or more are in sight on a phone screen at once.
const ART_W := 196
const SECTION_H := 256
## Where a section's spots go (their icon's top left, art px in the section), in order
## up the route: zigzagging left and right, SECTION_H / 4 apart. Spots' `map.at`.
const SLOTS: Array[Vector2] = [Vector2(36, 200), Vector2(124, 136), Vector2(36, 72), Vector2(124, 8)]
## Table showing around the sheet (art px): at the sides, below, and above (the room the
## next sections will take).
const TABLE_SIDE := 10
const TABLE_BOTTOM := 16
const TABLE_TOP := 60
const WOOD := Color("6b4a2e")
const PAPER := Color("efe3c4")
const PAPER_EDGE := Color("c9b48a")
const RIVER := Color("9db6bf")
const ROUTE := Color("b4553f")
const INK := Color("4a3a2a")
## The printed plan: blocks (and their outline), building footprints, parks and trees,
## plazas; the streets are the paper between the blocks.
const BLOCK := Color("e4d4aa")
const BLOCK_EDGE := Color("cdb98b")
const BUILDING := Color("d6c296")
const BUILDING_SHADE := Color("bfa877")
const PARK := Color("c6cb98")
const TREE := Color("9fa86f")
const PLAZA := Color("ece0bd")
## Avenues (and the street through a spot) are this wide; side streets narrower (art px).
const AVENUE := 6
const STREET := 4
## Rows at the top of the last section where the plan fades out.
const SURVEY_FADE := 110
## The icons' shadow on the paper: how far below them (art px) and how dark.
const SHADOW_DROP := Vector2(2, 4)
const SHADOW := Color(0.2, 0.13, 0.06, 0.28)

## The spots shown (Spots.on_map() unless set before adding it, e.g. for a preview).
var spots: Array = []
var _art_h := 0
## Each spot on the map: {spot, rect (landmark, art px), center (art px)}.
var _places: Array = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	light_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if spots.is_empty():
		spots = Spots.on_map()
	_art_h = TABLE_BOTTOM + _sections() * SECTION_H + TABLE_TOP
	custom_minimum_size = Vector2(ART_W + TABLE_SIDE * 2, _art_h) * UiKit.PIXEL
	for spot: Dictionary in spots:
		var section_top := _art_h - TABLE_BOTTOM - (int(spot.map.section) + 1) * SECTION_H
		var at: Vector2 = Vector2(spot.map.at) + Vector2(TABLE_SIDE, section_top)
		var landmark: Texture2D = load(spot.landmark) if spot.landmark != "" else null
		var size := landmark.get_size() if landmark else Vector2(32, 32)
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


## How many sections the map has: up to the highest one with a spot.
func _sections() -> int:
	var top := 0
	for spot: Dictionary in spots:
		top = maxi(top, int(spot.map.section))
	return top + 1


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
		# Its name on a paper tag lying on the plan.
		var name := String(place.spot.name).to_upper()
		var width := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var tag := Rect2(Vector2(roundf((r.get_center().x * p - width * 0.5) / p) - 3, r.end.y + 1) * p,
				Vector2(ceilf(width / p) + 6, 11) * p)
		draw_rect(Rect2(tag.position + Vector2(p, p), tag.size), Color(SHADOW, 0.18))
		draw_rect(tag, PAPER)
		draw_rect(tag.grow(-p * 0.5), PAPER_EDGE, false, p)
		draw_string(font, Vector2(tag.position.x, tag.end.y - 2.5 * p), name, HORIZONTAL_ALIGNMENT_CENTER,
				tag.size.x, 30, INK)
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


## The map's art (art px): table, sheet, the plan, route (the icons float over it: _draw).
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
	# The plan, section by section from the bottom; then the rivers and their bridges.
	var avenues_of := []
	var streets_of := []
	for section in _sections():
		var bottom := _art_h - TABLE_BOTTOM - section * SECTION_H
		var area := Rect2i(sheet.position.x + 9, bottom - SECTION_H, sheet.size.x - 18, SECTION_H)
		if section == 0:
			area.size.y -= 24  # Clear of the margin and its compass.
		var plan := _plan(area, section, rng)
		avenues_of.append(plan.avenues)
		streets_of.append(plan.streets)
		_blocks(img, area, plan, section == _sections() - 1, rng)
	for place: Dictionary in _places:
		if not place.spot.map.get("river", false):
			continue
		var center: Vector2 = place.center
		_river(img, sheet, int(center.y), rng)
		for x: int in avenues_of[int(place.spot.map.section)]:
			_bridge(img, x, int(center.y), AVENUE + 2 if x == int(center.x) else STREET + 2)
	_margin(img, sheet)
	# The route: from the bottom edge up the first spot's avenue, then from spot to spot
	# along a cross street between them (of the section it leaves from, the one nearest
	# halfway), on up toward what's still to come.
	var route_from := Vector2(img.get_width() * 0.5, sheet.end.y - 12)
	if not _places.is_empty():
		route_from.x = (_places[0].center as Vector2).x
	var from_section := 0
	for place: Dictionary in _places:
		var center: Vector2 = place.center
		var arrive := center + Vector2(0, place.rect.size.y * 0.5 + 14)
		if absf(route_from.x - arrive.x) > 1.0:
			var turn_y := (route_from.y + arrive.y) * 0.5
			var best := INF
			for y: int in streets_of[from_section]:
				if y < route_from.y - 4 and y > arrive.y and absf(y - turn_y) < best:
					best = absf(y - turn_y)
					turn_y = y
			_route(img, route_from, Vector2(route_from.x, turn_y))
			_route(img, Vector2(route_from.x, turn_y), Vector2(arrive.x, turn_y))
			route_from = Vector2(arrive.x, turn_y)
		_route(img, route_from, arrive)
		route_from = center - Vector2(0, place.rect.size.y * 0.5 + 6)
		from_section = int(place.spot.map.section)
	_route(img, route_from, Vector2(route_from.x, sheet.position.y + 12), true)
	return img


## A section's streets (art px): avenues (x of each, left to right: four spread across,
## the nearest one moved onto each of its spots) and cross streets (y of each, from the
## bottom up, 30 to 50 apart).
func _plan(area: Rect2i, section: int, rng: RandomNumberGenerator) -> Dictionary:
	var avenues: Array[int] = []
	for i in 4:
		avenues.append(area.position.x + roundi(area.size.x * (i + 0.5) / 4.0) + rng.randi_range(-4, 4))
	for place: Dictionary in _places:
		if int(place.spot.map.section) != section:
			continue
		var x := int((place.center as Vector2).x)
		var nearest := 0
		for i in avenues.size():
			if absi(avenues[i] - x) < absi(avenues[nearest] - x):
				nearest = i
		avenues[nearest] = x
	var streets: Array[int] = []
	var y := area.end.y - rng.randi_range(14, 24)
	while y > area.position.y + 12:
		streets.append(y)
		y -= rng.randi_range(30, 50)
	return {avenues = avenues, streets = streets}


## The blocks between a section's streets: each one buildings (one to three footprints),
## a park (trees) or a plaza (a fountain); the ones the river runs through are riverside
## parks. In the last section (`last`) they thin out toward its top: the survey isn't
## done there.
func _blocks(img: Image, area: Rect2i, plan: Dictionary, last: bool, rng: RandomNumberGenerator) -> void:
	var xs: Array = [area.position.x] + plan.avenues + [area.end.x]
	var ys: Array = [area.end.y] + plan.streets + [area.position.y]
	for j in ys.size() - 1:
		for i in xs.size() - 1:
			var left: int = xs[i] + (0 if i == 0 else AVENUE / 2 + 1)
			var right: int = xs[i + 1] - (0 if i == xs.size() - 2 else AVENUE / 2 + 1)
			var bottom: int = ys[j] - (0 if j == 0 else STREET / 2 + 1)
			var top: int = ys[j + 1] + (0 if j == ys.size() - 2 else STREET / 2 + 1)
			if right - left < 6 or bottom - top < 6:
				continue
			if last and top < area.position.y + SURVEY_FADE:
				var k := float(area.position.y + SURVEY_FADE - top) / SURVEY_FADE
				if rng.randf() < k * 1.2:
					continue
			var block := Rect2i(left, top, right - left, bottom - top)
			var kind := rng.randf()
			var riverside := false
			for place: Dictionary in _places:
				var river_y := int((place.center as Vector2).y)
				riverside = riverside or (place.spot.map.get("river", false)
						and top < river_y + 20 and bottom > river_y - 20)
			if kind < 0.16 or riverside:
				_park(img, block, rng)
			elif kind < 0.24:
				_fill(img, block, PLAZA)
				_frame(img, block, BLOCK_EDGE)
				_fill(img, Rect2i(block.get_center() - Vector2i(1, 1), Vector2i(3, 3)), RIVER)  # A fountain.
			else:
				_fill(img, block, BLOCK)
				_frame(img, block, BLOCK_EDGE)
				_buildings(img, block.grow(-2), rng)


## One to three building footprints side by side in `lot`, each with a shaded edge.
func _buildings(img: Image, lot: Rect2i, rng: RandomNumberGenerator) -> void:
	if lot.size.x < 3 or lot.size.y < 3:
		return
	var count := clampi(lot.size.x / 14, 1, 3)
	var x := lot.position.x
	for i in count:
		var w := (lot.end.x - x) if i == count - 1 else maxi(3, lot.size.x / count + rng.randi_range(-3, 3))
		var h := lot.size.y - rng.randi_range(0, lot.size.y / 3)
		var footprint := Rect2i(x, lot.end.y - h, w - 1, h)
		_fill(img, footprint, BUILDING.darkened(rng.randf_range(-0.03, 0.05)))
		_fill(img, Rect2i(footprint.position.x, footprint.end.y - 1, footprint.size.x, 1), BUILDING_SHADE)
		_fill(img, Rect2i(footprint.end.x - 1, footprint.position.y, 1, footprint.size.y), BUILDING_SHADE)
		x += w


## A park: green, with trees dotted over it.
func _park(img: Image, block: Rect2i, rng: RandomNumberGenerator) -> void:
	_fill(img, block, PARK)
	_frame(img, block, TREE)
	for i in block.get_area() / 40:
		var at := Vector2i(rng.randi_range(block.position.x + 2, block.end.x - 4),
				rng.randi_range(block.position.y + 2, block.end.y - 4))
		_fill(img, Rect2i(at, Vector2i(2, 2)), TREE)


## A bridge carrying a street `width` wide at x across the river around row `y` (see
## _river): the street's paper over the water, a parapet line along each side, reaching
## a pixel onto each bank.
func _bridge(img: Image, x: int, y: int, width: int) -> void:
	var half := width / 2
	var rows: Array[int] = []
	for row in range(y - 24, y + 25):
		if _is_water(img.get_pixel(x, row)):
			rows.append(row)
	if rows.is_empty():
		return
	for row in range(rows.front() - 1, rows.back() + 2):
		for dx in range(-half, half + 1):
			if absi(dx) == half:
				img.set_pixel(x + dx, row, INK.lightened(0.35))
			elif _is_water(img.get_pixel(x + dx, row)):
				img.set_pixel(x + dx, row, PAPER)


static func _is_water(c: Color) -> bool:
	return c.b > c.r + 0.05


## The sheet's margin: a double rule around the plan and a compass rose in its corner.
func _margin(img: Image, sheet: Rect2i) -> void:
	var rule := sheet.grow(-5)
	_frame(img, rule, INK.lightened(0.45))
	_frame(img, rule.grow(-2), INK.lightened(0.6))
	# The compass, bottom right: four points, north dark.
	var c := Vector2i(rule.end.x - 14, rule.end.y - 11)
	_fill(img, Rect2i(c - Vector2i(6, 6), Vector2i(13, 13)), PAPER)
	_frame(img, Rect2i(c - Vector2i(6, 6), Vector2i(13, 13)), INK.lightened(0.6))
	for d in range(1, 6):
		var w := 3 if d < 3 else 1
		_fill(img, Rect2i(c.x - w / 2, c.y - d, w, 1), INK)  # North.
		_fill(img, Rect2i(c.x - w / 2, c.y + d, w, 1), INK.lightened(0.5))
		_fill(img, Rect2i(c.x + d, c.y - w / 2, 1, w), INK.lightened(0.5))
		_fill(img, Rect2i(c.x - d, c.y - w / 2, 1, w), INK.lightened(0.5))
	img.set_pixelv(c, PAPER)


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
