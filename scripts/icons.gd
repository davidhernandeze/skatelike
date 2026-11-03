class_name Icons
extends RefCounted
## Small UI symbols drawn as shapes, for glyphs the built-in font lacks (▲ ▼ ◄ ► ≡ ✓).
## Desktop builds borrow them from system fonts, but web builds have none and show boxes.


## Points of a triangle pointing `dir` (Vector2.UP, DOWN, LEFT or RIGHT), `size` px
## across, centered on `center`.
static func triangle(center: Vector2, dir: Vector2, size: float) -> PackedVector2Array:
	var half := size * 0.5
	var side := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		center + dir * half, center - dir * half + side * half, center - dir * half - side * half,
	])


static func triangle_texture(dir: Vector2, size: int, color := Color.WHITE) -> ImageTexture:
	return _rasterize(size, size, [triangle(Vector2(size, size) * 0.5, dir, size * 0.8)], color)


## Three horizontal bars: the menu symbol.
static func menu_texture(size: int, color := Color.WHITE) -> ImageTexture:
	var bar := maxf(2.0, size * 0.14)
	var shapes := []
	for i in 3:
		var y := size * (0.2 + 0.3 * i) - bar * 0.5
		shapes.append(PackedVector2Array([
			Vector2(size * 0.1, y), Vector2(size * 0.9, y), Vector2(size * 0.9, y + bar), Vector2(size * 0.1, y + bar),
		]))
	return _rasterize(size, size, shapes, color)


## Two vertical bars: the pause symbol.
static func pause_texture(size: int, color := Color.WHITE) -> ImageTexture:
	var s := float(size)
	var shapes := []
	for x in [0.2, 0.6]:
		shapes.append(PackedVector2Array([
			Vector2(x, 0.12) * s, Vector2(x + 0.2, 0.12) * s, Vector2(x + 0.2, 0.88) * s, Vector2(x, 0.88) * s,
		]))
	return _rasterize(size, size, shapes, color)


## A house: the home symbol.
static func home_texture(size: int, color := Color.WHITE) -> ImageTexture:
	var s := float(size)
	var roof := PackedVector2Array([Vector2(0.5, 0.08) * s, Vector2(0.95, 0.5) * s, Vector2(0.05, 0.5) * s])
	var walls := PackedVector2Array([
		Vector2(0.18, 0.46) * s, Vector2(0.82, 0.46) * s, Vector2(0.82, 0.92) * s, Vector2(0.58, 0.92) * s,
		Vector2(0.58, 0.66) * s, Vector2(0.42, 0.66) * s, Vector2(0.42, 0.92) * s, Vector2(0.18, 0.92) * s,
	])
	return _rasterize(size, size, [roof, walls], color)


## A circular arrow: the restart symbol. A ring, open at the top right, with an arrowhead
## on its end pointing round clockwise.
static func restart_texture(size: int, color := Color.WHITE) -> ImageTexture:
	var s := float(size)
	var center := Vector2(s, s) * 0.5
	var outer := s * 0.4
	var inner := s * 0.27
	var ring := PackedVector2Array()
	var from := deg_to_rad(-60.0)
	var to := deg_to_rad(230.0)  # Clockwise on screen from upper right round to the top.
	for i in 25:
		ring.append(center + Vector2.from_angle(lerpf(from, to, i / 24.0)) * outer)
	for i in 25:
		ring.append(center + Vector2.from_angle(lerpf(to, from, i / 24.0)) * inner)
	# Arrowhead at the ring's start (upper right), pointing back along it (clockwise).
	var tip_dir := Vector2.from_angle(from - PI * 0.5)
	var base := center + Vector2.from_angle(from) * (outer + inner) * 0.5
	var across := Vector2.from_angle(from) * s * 0.2
	var head := PackedVector2Array([base + across, base - across, base + tip_dir * s * 0.22])
	return _rasterize(size, size, [ring, head], color)


## A check mark.
static func check_texture(size: int, color := Color.WHITE) -> ImageTexture:
	var s := float(size)
	var shape := PackedVector2Array([
		Vector2(0.08, 0.52) * s, Vector2(0.22, 0.38) * s, Vector2(0.4, 0.56) * s, Vector2(0.78, 0.16) * s,
		Vector2(0.92, 0.3) * s, Vector2(0.4, 0.84) * s,
	])
	return _rasterize(size, size, [shape], color)


## A checkbox: a square outline, with a check mark inside when `checked`.
static func box_texture(size: int, checked: bool, color := Color.WHITE) -> ImageTexture:
	var s := float(size)
	var t := maxf(s * 0.1, 2.0)  # Outline thickness.
	var shapes := [
		PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, t), Vector2(0, t)]),
		PackedVector2Array([Vector2(0, s - t), Vector2(s, s - t), Vector2(s, s), Vector2(0, s)]),
		PackedVector2Array([Vector2(0, 0), Vector2(t, 0), Vector2(t, s), Vector2(0, s)]),
		PackedVector2Array([Vector2(s - t, 0), Vector2(s, 0), Vector2(s, s), Vector2(s - t, s)]),
	]
	if checked:
		shapes.append(PackedVector2Array([
			Vector2(0.2, 0.52) * s, Vector2(0.32, 0.4) * s, Vector2(0.44, 0.54) * s, Vector2(0.7, 0.24) * s,
			Vector2(0.82, 0.36) * s, Vector2(0.44, 0.78) * s,
		]))
	return _rasterize(size, size, shapes, color)


## Fills polygons into a texture, 4x4 supersampled for smooth edges.
static func _rasterize(width: int, height: int, shapes: Array, color: Color) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var hits := 0
			for sy in 4:
				for sx in 4:
					var p := Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0)
					for shape: PackedVector2Array in shapes:
						if Geometry2D.is_point_in_polygon(p, shape):
							hits += 1
							break
			image.set_pixel(x, y, Color(color, color.a * hits / 16.0))
	return ImageTexture.create_from_image(image)
