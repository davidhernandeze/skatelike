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
