class_name UiKit
extends RefCounted
## The game's look outside the world: worn, painted wooden surf-shop signs with warm bulb
## strips (art direction: Dusk Boardwalk, the touch pads' signboards). Everything here is
## pixel art on one grid (PIXEL screen px per texel) built from a few sprites
## (assets/ui, tools/make_ui_kit.gd):
##   plank, pad: cream-painted planks; paint() repaints the cream (any color, flat or a
##     gradient) and leaves the bare wood, the outline and the screws as they are.
##   backboard: dark stained boards behind panels.
##   icons: masks drawn in any color, burned in (INK) or lit.
## theme() puts the same look on every Button, Label, panel and scroll bar.

const PIXEL := 3
const UI_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const LOGO_FONT: Font = preload("res://assets/fonts/Knewave-Regular.ttf")
const PLANK: Texture2D = preload("res://assets/ui/plank.png")
const PAD: Texture2D = preload("res://assets/ui/pad.png")
## The same without their screws, for small buttons.
const PLANK_BARE: Texture2D = preload("res://assets/ui/plank_bare.png")
const PAD_BARE: Texture2D = preload("res://assets/ui/pad_bare.png")
const BACKBOARD: Texture2D = preload("res://assets/ui/backboard.png")
const DIAL: Texture2D = preload("res://assets/ui/dial.png")

## Sign paints (sun-faded, like the pads in the mockups).
const PAINTS := {
	red = Color("c4513e"), orange = Color("d99a36"), teal = Color("3f8ca2"), green = Color("6e9440"),
	blue = Color("4a6fb0"), purple = Color("7d55a0"), cream = Color("eadcbc"), brown = Color("8a5a36"),
}
## Buttons in a list take these in turn.
const ROTATION: Array[String] = ["orange", "teal", "red", "green"]
## Burned-in lettering and icons, and light lettering on dark wood.
const INK := Color("2b1a10")
const LIGHT := Color("fbe9c8")
const DIM := Color("cdb58e")
## Warm bulb light.
const BULB := Color("ffd27a")

## Plank margins (texels) that don't stretch: the screws and the worn ends.
const PLANK_MARGIN := Vector4i(10, 9, 10, 10)  # left, top, right, bottom
const PAD_MARGIN := Vector4i(13, 13, 13, 13)
## Without screws, only the worn ends and edges (and the pad's clipped corners) stay.
const MARGINS := {
	plank = PLANK_MARGIN, pad = PAD_MARGIN,
	plank_bare = Vector4i(5, 4, 5, 5), pad_bare = Vector4i(8, 8, 8, 8),
}

static var _theme: Theme
static var _styles := {}
static var _icons := {}
static var _paint_shader: Shader


## Whether a pixel of a plank sprite is paint (light, not saturated: the cream) and how
## much (0..1), against the bare wood, the outline and the screws.
static func paint_amount(c: Color) -> float:
	if c.a < 0.5:
		return 0.0
	return clampf((0.34 - c.s) / 0.12, 0.0, 1.0) * clampf((c.v - 0.5) / 0.15, 0.0, 1.0)


## `image` (a plank sprite) with its cream paint repainted `top` .. `bottom` (a gradient
## down it, or across it if `across`), shaded as the cream was.
static func paint(image: Image, top: Color, bottom := top, across := false) -> Image:
	var out := image.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	var w := out.get_width()
	var h := out.get_height()
	for y in h:
		for x in w:
			var c := out.get_pixel(x, y)
			var amount := paint_amount(c)
			if amount <= 0.0:
				continue
			var t := (x + 0.5) / w if across else (y + 0.5) / h
			var color := top.lerp(bottom, t)
			var shade := c.get_luminance() / 0.86  # The cream's own light and dark.
			out.set_pixel(x, y, c.lerp(Color(color.r * shade, color.g * shade, color.b * shade, c.a), amount))
	return out


## `image` PIXEL times bigger, hard pixels.
static func scaled(image: Image, factor := PIXEL) -> Image:
	var out := image.duplicate() as Image
	out.resize(out.get_width() * factor, out.get_height() * factor, Image.INTERPOLATE_NEAREST)
	return out


## A plank (or `pad`, or either `_bare`: without screws, for small buttons) painted
## `color`, as a style box that tiles its middle and keeps its screws and ends: `state` "pressed" is darker and pushes the content down a texel,
## "hover" lighter, "disabled" faded and dirty.
static func plank(color: Color, state := "normal", sprite := "plank") -> StyleBoxTexture:
	var key := "%s/%s/%s" % [sprite, color.to_html(), state]
	if _styles.has(key):
		return _styles[key]
	var paint_color := color
	match state:
		"pressed":
			paint_color = color.darkened(0.22)
		"hover":
			paint_color = color.lightened(0.08)
		"disabled":
			paint_color = color.lerp(Color("6a5a48"), 0.65)
	var source: Image = {plank = PLANK, pad = PAD, plank_bare = PLANK_BARE, pad_bare = PAD_BARE}[sprite].get_image()
	var image := paint(source, paint_color)
	if state == "disabled":
		image.adjust_bcs(0.7, 1.0, 0.6)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(scaled(image))
	var m: Vector4i = MARGINS[sprite]
	style.texture_margin_left = m.x * PIXEL
	style.texture_margin_top = m.y * PIXEL
	style.texture_margin_right = m.z * PIXEL
	style.texture_margin_bottom = m.w * PIXEL
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	var side := 4 if sprite.ends_with("_bare") else 10  # Clear of the screws.
	style.content_margin_left = side * PIXEL
	style.content_margin_right = side * PIXEL
	style.content_margin_top = (3 if state == "pressed" else 2) * PIXEL
	style.content_margin_bottom = (1 if state == "pressed" else 2) * PIXEL
	_styles[key] = style
	return style


## Dark stained boards, tiled, behind panels; `shade` < 1 darker.
static func backboard(shade := 0.7) -> StyleBoxTexture:
	var key := "backboard/%.2f" % shade
	if _styles.has(key):
		return _styles[key]
	var image := BACKBOARD.get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.adjust_bcs(shade, 1.0, 1.0)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(scaled(image))
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.set_content_margin_all(4 * PIXEL)
	_styles[key] = style
	return style


## An icon (assets/ui/icons, see tools/make_ui_kit.gd) in `color`, at the UI's pixel size;
## `big` the pads' size.
static func icon(name: String, color := INK, big := false) -> Texture2D:
	var key := "%s/%s/%s" % [name, color.to_html(), big]
	if _icons.has(key):
		return _icons[key]
	var image := (load("res://assets/ui/icons/%s%s.png" % [name, "_big" if big else ""]) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a
			image.set_pixel(x, y, Color(color, a * color.a))
	var texture := ImageTexture.create_from_image(scaled(image))
	_icons[key] = texture
	return texture


## A row of `count` small bulbs from `from` to `to` on `canvas`: warm and glowing (each
## flickering a little, `time` in seconds) when `lit`, dull glass when not.
static func draw_bulbs(canvas: CanvasItem, from: Vector2, to: Vector2, count: int, lit: bool, time := 0.0,
		glow := 1.0) -> void:
	var p := float(PIXEL)
	for i in count:
		var at := from.lerp(to, (i + 0.5) / count)
		at = (at / p).floor() * p
		if lit:
			var flicker := 0.85 + 0.15 * sin(time * (5.0 + (i * 7) % 5) + i * 1.7)
			var halo := Color(BULB, 0.2 * glow * flicker)
			canvas.draw_rect(Rect2(at - Vector2(p * 3, p * 3), Vector2(p * 9, p * 9)), Color(halo, halo.a * 0.45))
			canvas.draw_rect(Rect2(at - Vector2(p * 2, p * 2), Vector2(p * 7, p * 7)), halo)
			canvas.draw_rect(Rect2(at - Vector2(p, p), Vector2(p * 5, p * 5)), halo)
			canvas.draw_rect(Rect2(at, Vector2(p * 3, p * 3)), BULB.lerp(Color.WHITE, 0.25 * flicker))
			canvas.draw_rect(Rect2(at, Vector2(p, p)), Color.WHITE)
		else:
			canvas.draw_rect(Rect2(at, Vector2(p * 3, p * 3)), Color("5e4e34"))
			canvas.draw_rect(Rect2(at, Vector2(p, p)), Color("8c7a52"))


## A hanging chain from `from` down to `to`: alternating links, on the pixel grid.
static func draw_chain(canvas: CanvasItem, from: Vector2, to: Vector2) -> void:
	var p := float(PIXEL)
	var steps := int(from.distance_to(to) / (p * 4.0))
	for i in steps:
		var at := (from.lerp(to, float(i) / maxf(steps, 1)) / p).floor() * p
		if i % 2 == 0:  # A link seen face on: a ring.
			canvas.draw_rect(Rect2(at - Vector2(p, 0), Vector2(p * 3, p * 5)), Color("2e2a26"))
			canvas.draw_rect(Rect2(at + Vector2(-p, p), Vector2(p, p * 3)), Color("9a9088"))
			canvas.draw_rect(Rect2(at + Vector2(p, p), Vector2(p, p * 3)), Color("6a625a"))
		else:  # Edge on: a bar.
			canvas.draw_rect(Rect2(at, Vector2(p, p * 5)), Color("7a7068"))


## The shader that paints a plank's cream in a Control's local space (flat, or a gradient
## along `direction`): for pads whose size isn't known up front.
static func paint_material(top: Color, bottom: Color, across := false) -> ShaderMaterial:
	if _paint_shader == null:
		_paint_shader = load("res://scripts/paint.gdshader")
	var material := ShaderMaterial.new()
	material.shader = _paint_shader
	material.set_shader_parameter("top", top)
	material.set_shader_parameter("bottom", bottom)
	material.set_shader_parameter("across", across)
	return material


## The theme every screen uses: the UI font, light lettering with a dark edge on the dark
## wood, burned-in lettering on cream planks for buttons (Buttons in a list are painted in
## turn by their owners), wooden scroll grabbers.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = UI_FONT
	t.default_font_size = 30
	t.set_color("font_color", "Label", LIGHT)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 8)
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "Button", plank(PAINTS.cream, state))
	t.set_stylebox("hover_pressed", "Button", plank(PAINTS.cream, "pressed"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.55))
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_constant("h_separation", "Button", 4 * PIXEL)
	t.set_constant("outline_size", "Button", 0)
	t.set_stylebox("panel", "PanelContainer", backboard())
	t.set_stylebox("panel", "Panel", backboard())
	var grabber := plank(PAINTS.cream)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.45)
	track.set_corner_radius_all(PIXEL * 2)
	track.content_margin_left = PIXEL * 3
	track.content_margin_right = PIXEL * 3
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, grabber)
		t.set_stylebox("grabber_highlight", bar, grabber)
		t.set_stylebox("grabber_pressed", bar, plank(PAINTS.cream, "pressed"))
	_theme = t
	return t


## Paints `button` `color` (one of PAINTS) in every state.
static func paint_button(button: Button, color: Color, sprite := "plank") -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, plank(color, state, sprite))
	button.add_theme_stylebox_override("hover_pressed", plank(color, "pressed", sprite))
