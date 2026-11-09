class_name NeonSign
extends Control
## The game's name as a neon sign: glass tubes bent into letters (Tilt Neon), glowing on a
## clear acrylic panel hung on two wires, lighting up what's around it (a PointLight2D in
## the tubes' color). Drawn at the UI's pixel size (UiKit.PIXEL) so it sits with the
## pixel art; it flickers on when shown, and now and then a letter buzzes.

const FONT: Font = preload("res://assets/fonts/TiltNeon.ttf")

@export var text := "skatelike":
	set(value):
		text = value
		update_minimum_size()
@export var font_size := 132
## The gas's color, lit.
@export var tube := Color("ff3a7a")
## Wire length above the panel (px).
@export var wire := 48.0
## Room around the letters on the panel (px).
@export var padding := Vector2(42, 18)
## How much it lights its surroundings.
@export var light_energy := 1.8

var _view: SubViewport
var _tubes: Node2D
var _light: PointLight2D
var _core_font: FontVariation
var _bloom: Texture2D
var _haze: TextureRect
var _time := 0.0
## 0..1: how lit the sign is (all of it), and one letter's buzz.
var _power := 0.0
var _buzz_letter := -1
var _buzz_until := 0.0
var _next_buzz := 4.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	light_mask = 0  # Its own light doesn't wash it out.
	# Light adds up: the tubes and their glow brighten what's behind them, as neon does
	# (a Light2D alone only multiplies, and does little on a dark sky).
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	# The thin white-hot core inside each tube.
	_core_font = FontVariation.new()
	_core_font.base_font = FONT
	_core_font.variation_embolden = -0.55
	_view = SubViewport.new()
	_view.transparent_bg = true
	_view.disable_3d = true
	_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_tubes = Node2D.new()
	_tubes.draw.connect(_draw_sign)
	_view.add_child(_tubes)
	_light = PointLight2D.new()
	_light.texture = _light_texture()
	_bloom = _light.texture
	_light.color = tube
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.texture_scale = 3.6
	add_child(_light)
	# The haze it lights in the air around it, behind the panel.
	_haze = TextureRect.new()
	_haze.texture = _light.texture
	_haze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_haze.stretch_mode = TextureRect.STRETCH_SCALE
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.show_behind_parent = true
	_haze.material = add
	_haze.light_mask = 0
	add_child(_haze)
	resized.connect(_fit)
	_fit()


func _get_minimum_size() -> Vector2:
	var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(text_size.x, FONT.get_height(font_size) * 0.82) + padding * 2.0 + Vector2(0, wire)


func _fit() -> void:
	var p := float(UiKit.PIXEL)
	_view.size = Vector2i(ceili(size.x / p), ceili(size.y / p))
	_light.position = Vector2(size.x * 0.5, wire + (size.y - wire) * 0.5)
	var haze := Vector2(size.x * 1.3, (size.y - wire) * 2.6)
	_haze.position = _light.position - haze * 0.5
	_haze.size = haze


func _process(delta: float) -> void:
	_time += delta
	# Switched on: a few stutters, then steady.
	var on := [0.0, 0.08, 0.14, 0.32, 0.4, 0.62]
	var lit := true
	for i in on.size():
		if _time >= on[i]:
			lit = i % 2 == 1
	_power = 1.0 if _time > 0.7 else (0.9 if lit else 0.08)
	if _time > _next_buzz:
		_buzz_letter = randi() % text.length()
		_buzz_until = _time + randf_range(0.25, 0.6)
		_next_buzz = _time + randf_range(3.5, 8.0)
	if _time > _buzz_until:
		_buzz_letter = -1
	var hum := 0.96 + 0.04 * sin(_time * 37.0) * sin(_time * 5.3)
	var glow := _power * hum * (0.85 if _buzz_letter >= 0 else 1.0)
	_light.energy = light_energy * glow
	_haze.modulate = Color(tube, 0.45 * glow)
	_tubes.queue_redraw()
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(_view.get_texture(), Rect2(Vector2.ZERO, Vector2(_view.size) * UiKit.PIXEL), false)


## The sign at 1/PIXEL scale, in the SubViewport.
func _draw_sign() -> void:
	var p := float(UiKit.PIXEL)
	var fs := roundi(font_size / p)
	var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var panel_size := Vector2(text_size.x + padding.x * 2.0 / p, FONT.get_height(fs) * 0.82 + padding.y * 2.0 / p).round()
	var panel := Rect2(Vector2(roundf((_view.size.x - panel_size.x) * 0.5), roundf(wire / p)), panel_size)
	# The wires, and the panel: clear acrylic, its edges catching the light.
	for x in [panel.position.x + panel.size.x * 0.2, panel.end.x - panel.size.x * 0.2]:
		_tubes.draw_line(Vector2(roundf(x) + 0.5, 0), Vector2(roundf(x) + 0.5, panel.position.y), Color("9a9aa4"), 1.0)
	var glass := Color(0.75, 0.9, 1.0)
	_tubes.draw_rect(panel, Color(glass, 0.07))
	_tubes.draw_rect(panel.grow(-0.5), Color(glass, 0.32), false, 1.0)
	_tubes.draw_line(panel.position + Vector2(2, 1.5), Vector2(panel.end.x - 2, panel.position.y + 1.5), Color(1, 1, 1, 0.3), 1.0)
	var lit_edge := Color(tube.lerp(Color.WHITE, 0.5), 0.35 * _power)
	_tubes.draw_line(Vector2(panel.position.x + 2, panel.end.y - 0.5), Vector2(panel.end.x - 2, panel.end.y - 0.5), lit_edge, 1.0)
	# A clear standoff at each corner, holding the panel off the wall.
	for corner in [panel.position + Vector2(3, 3), Vector2(panel.end.x - 4, panel.position.y + 3),
			Vector2(panel.position.x + 3, panel.end.y - 4), panel.end - Vector2(4, 4)]:
		_tubes.draw_rect(Rect2(corner, Vector2(2, 2)), Color(1, 1, 1, 0.35))
	# The bloom the tubes throw on the panel and the air around them.
	var bloom := Rect2(panel.position - Vector2(panel.size.x * 0.12, panel.size.y * 0.3),
			panel.size * Vector2(1.24, 1.6))
	_tubes.draw_texture_rect(_bloom, bloom, false, Color(tube, 0.38 * _power))
	# The letters, each its own tube.
	var baseline := Vector2(roundf(panel.get_center().x - text_size.x * 0.5),
			roundf(panel.get_center().y + FONT.get_ascent(fs) * 0.36))
	var x := 0.0
	for i in text.length():
		var letter := text[i]
		var at := baseline + Vector2(x, 0)
		x += FONT.get_char_size(letter.unicode_at(0), fs).x
		var power := _power
		if i == _buzz_letter:
			power *= 0.25 if fmod(_time * 23.0, 1.0) < 0.5 else 0.8
		_draw_tube(letter, at, fs, power)


## One letter's tube: the glow around it, the colored glass and the bright core (all
## light, added to what's behind). Unlit, faint glass.
func _draw_tube(letter: String, at: Vector2, fs: int, power: float) -> void:
	if power > 0.0:
		for halo: Vector2 in [Vector2(18, 0.1), Vector2(11, 0.16), Vector2(6, 0.28), Vector2(3, 0.5)]:
			_tubes.draw_string_outline(FONT, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(halo.x),
					Color(tube, halo.y * power))
	var dark := Color(tube.darkened(0.55), 0.75)
	_tubes.draw_string(FONT, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dark.lerp(tube.lightened(0.15), power))
	_tubes.draw_string(_core_font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(tube.lerp(Color.WHITE, 0.8), power))


## A soft round light: bright in the middle, fading to nothing.
static func _light_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture
