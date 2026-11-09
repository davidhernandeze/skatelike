class_name Pad
extends Panel
## A tappable zone in the control panel. Hit-testing is done by ControlPanel.

## What this pad does; interpreted by whoever listens to ControlPanel.pad_pressed.
@export var action: StringName
@export var color := Color.WHITE
@export var label := ""
## When set, `label` goes in the top half, this in the bottom half, with a divider between.
@export var label_bottom := ""
@export var font_size := 36
## Draws a vertical line at the center, for pads where touch position matters.
@export var center_mark := false
## Draws ▲ near the top and ▼ near the bottom (touch height matters).
@export var arrows := false
## Draws ◄ side_left and side_right ► below the middle (touch x matters); leave the
## label's second line blank for them.
@export var side_arrows := false
@export var side_left := ""
@export var side_right := ""
## Drawn between them, on the center line.
@export var side_middle := ""
## Shown faded, for pads without a function yet.
@export var dimmed := false
## How the paint shows that the touch position matters: "auto" picks from the marks
## (arrows: a gradient down, bright at the strong top; side arrows or a center mark: one
## across), "flat" one color (it doesn't matter where it's touched).
@export_enum("auto", "flat", "down", "across") var paint_mode := "auto"
## Colors of the two ends of an "across" gradient (left, right); unset: from `color`.
@export var across_colors := PackedColorArray()
## A burned-in icon (UiKit.icon, big) above the label, mirrored with `icon_flip`.
@export var icon := ""
@export var icon_flip := false

var _board: NinePatchRect
var _paint: ShaderMaterial
var _tween: Tween
var _enabled := true
## Pie indicator (e.g. push cooldown): remaining fraction, hidden at 0.
var _pie := 0.0
var _pie_queue := 0
var _label_nodes: Array[Label] = []
## While a pop is held and aimed (see set_aim): faint arrows both ways, the aimed one lit
## with its name.
var _aiming := false
var _aim := 0
var _aim_text := ""
## Bulb glow: 1 normally, up while flashing.
var _glow := 1.0
var _time := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# The signboard: a worn plank, its paint flat or a gradient (see paint_mode).
	_board = NinePatchRect.new()
	_board.texture = ImageTexture.create_from_image(UiKit.scaled(UiKit.PAD.get_image()))
	var m := UiKit.PAD_MARGIN * UiKit.PIXEL
	_board.patch_margin_left = m.x
	_board.patch_margin_top = m.y
	_board.patch_margin_right = m.z
	_board.patch_margin_bottom = m.w
	_board.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	_board.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	_board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.show_behind_parent = true
	var ends := _paint_ends()
	_paint = UiKit.paint_material(ends[0], ends[1], ends[2])
	_board.material = _paint
	add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.resized.connect(func() -> void: _paint.set_shader_parameter("size", _board.size))
	_apply_alpha()
	if label_bottom != "":
		_add_label(label, Control.PRESET_TOP_WIDE)
		_add_label(label_bottom, Control.PRESET_BOTTOM_WIDE)
	elif label != "":
		_add_label(label, Control.PRESET_FULL_RECT)
		if icon != "":
			_label_nodes[0].anchor_top = 0.24  # Under the icon and the top arrow.


## The paint's two ends and whether they run across (else down), from paint_mode.
func _paint_ends() -> Array:
	var mode := paint_mode
	if mode == "auto":
		mode = "down" if arrows else ("across" if side_arrows or center_mark else "flat")
	match mode:
		"down":
			return [color.lightened(0.18), color.darkened(0.45), false]
		"across":
			if across_colors.size() == 2:
				return [across_colors[0], across_colors[1], true]
			return [color.darkened(0.35), color.lightened(0.15), true]
	return [color, color, false]


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _add_label(string: String, preset: Control.LayoutPreset) -> void:
	var text := Label.new()
	text.text = string
	# Short names in the brush font, like the signboards; long lines in the UI font.
	var brush := string.length() <= 12 and not string.contains("·")
	text.add_theme_font_override("font", UiKit.LOGO_FONT if brush else UiKit.UI_FONT)
	text.add_theme_font_size_override("font_size", roundi(font_size * 1.5) if brush else font_size)
	text.add_theme_constant_override("line_spacing", -roundi(font_size * 0.5) if brush else 0)
	text.add_theme_color_override("font_color", UiKit.LIGHT)
	text.add_theme_color_override("font_outline_color", UiKit.INK)
	text.add_theme_constant_override("outline_size", 10)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_nodes.append(text)
	text.set_anchors_and_offsets_preset(preset)
	if preset != Control.PRESET_FULL_RECT:
		text.anchor_top = 0.0 if preset == Control.PRESET_TOP_WIDE else 0.5
		text.anchor_bottom = text.anchor_top + 0.5
		text.offset_top = 0.0
		text.offset_bottom = 0.0
	add_child(text)


## Changes the (top) label's text.
func set_label(text: String) -> void:
	label = text
	if not _label_nodes.is_empty():
		_label_nodes[0].text = text


## Fades the pad when its action isn't available right now.
func set_enabled(enabled: bool) -> void:
	if enabled != _enabled:
		_enabled = enabled
		_apply_alpha()


## Shows a pie in the corner: `remaining` 0..1 of the current cycle, plus a dot per queued one.
func set_pie(remaining: float, queued: int) -> void:
	if not is_equal_approx(remaining, _pie) or queued != _pie_queue:
		_pie = remaining
		_pie_queue = queued
		queue_redraw()


## Shows a held pop's aim: `holding` draws faint side arrows; `aim` -1 / +1 lights the
## left / right one with `text` ("BS 180"); 0 none.
func set_aim(holding: bool, aim := 0, text := "") -> void:
	if holding != _aiming or aim != _aim or text != _aim_text:
		_aiming = holding
		_aim = aim
		_aim_text = text
		queue_redraw()


func _apply_alpha() -> void:
	var off := dimmed or not _enabled
	modulate.a = 0.55 if dimmed else 1.0
	if _paint:
		_paint.set_shader_parameter("faded", 1.0 if off else 0.0)
	for label_node in _label_nodes:
		label_node.modulate.a = 0.5 if off else 1.0


func _draw() -> void:
	var p := float(UiKit.PIXEL)
	var lit := _enabled and not dimmed
	# The bulb strip along the top edge, lit while the pad can be used.
	var bulbs := maxi(3, int(size.x / (p * 12.0)))
	UiKit.draw_bulbs(self, Vector2(p * 9, p * 4), Vector2(size.x - p * 9, p * 4), bulbs, lit, _time, _glow)
	var ink := Color(UiKit.INK, 0.85)
	if label_bottom != "":
		var y := roundf(size.y * 0.5 / p) * p
		draw_rect(Rect2(p * 6, y - p * 0.5, size.x - p * 12, p), ink)
	if center_mark:
		var x := roundf(size.x * 0.5 / p) * p
		draw_rect(Rect2(x - p * 0.5, p * 9, p, size.y - p * 15), ink)
	if icon != "":
		var texture := UiKit.icon(icon, ink, true)
		var at := (Vector2(size.x * 0.5, size.y * 0.2) - texture.get_size() * 0.5) / p
		var rect := Rect2(at.floor() * p, texture.get_size())
		if icon_flip:
			draw_set_transform(Vector2(rect.position.x * 2 + rect.size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect(texture, rect, false)
		draw_set_transform(Vector2.ZERO)
	if _aiming:
		# A held pop: slide sideways to aim it into a 180 (drawn, not text arrows).
		var y := size.y * 0.5
		for side: int in [-1, 1]:
			var on: bool = side == _aim
			var tip := Vector2(size.x * (0.5 + 0.38 * side), y)
			_draw_arrow(tip, Vector2(side, 0), 34.0 if on else 24.0, Color(UiKit.LIGHT, 0.95 if on else 0.35))
		if _aim != 0:
			_draw_text(Vector2(0.0, size.y * 0.3), _aim_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, UiKit.BULB)
	# Symbols are shapes, not text: the web build's font has no arrow glyphs.
	var arrow := font_size * 0.8
	if arrows:
		var top := 0.36 if icon != "" else 0.18
		_draw_arrow(Vector2(size.x * 0.5, size.y * top), Vector2.UP, arrow, UiKit.LIGHT)
		_draw_arrow(Vector2(size.x * 0.5, size.y * 0.86), Vector2.DOWN, arrow, UiKit.LIGHT)
	if side_arrows:
		var y := size.y * 0.5 + font_size * 0.68
		var left := Vector2(size.x * 0.12, y)
		var right := Vector2(size.x * 0.88, y)
		_draw_arrow(left, Vector2.LEFT, arrow, UiKit.LIGHT)
		_draw_arrow(right, Vector2.RIGHT, arrow, UiKit.LIGHT)
		var font := get_theme_default_font()
		var baseline := y + font_size * 0.35
		_draw_text(Vector2(left.x + arrow, baseline), side_left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiKit.LIGHT)
		var width := font.get_string_size(side_right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_draw_text(Vector2(right.x - arrow - width, baseline), side_right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				UiKit.LIGHT)
		if side_middle != "":
			var middle := font.get_string_size(side_middle, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var box := Rect2(Vector2(size.x * 0.5 - middle.x * 0.5 - 8.0, y - middle.y * 0.5), middle + Vector2(16.0, 0.0))
			draw_rect(box, UiKit.INK)  # A burned patch over the center line, behind the text.
			_draw_text(Vector2(size.x * 0.5 - middle.x * 0.5, baseline), side_middle, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_size, UiKit.LIGHT)
	if _pie > 0.0 or _pie_queue > 0:
		# Push cooldown: a little brass dial in the corner, queued kicks as bulbs under it.
		var radius := 8.0 * p
		var center := (Vector2(size.x - radius - p * 8, radius + p * 9) / p).floor() * p
		draw_circle(center, radius + p, Color("6a4a1a"))
		draw_circle(center, radius, Color("e8d8b0"))
		if _pie > 0.0:
			var points := PackedVector2Array([center])
			var steps := maxi(2, ceili(_pie * 32.0))
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * _pie * float(i) / steps
				points.append(center + Vector2(cos(a), sin(a)) * (radius - p))
			draw_colored_polygon(points, Color(UiKit.INK, 0.8))
		for i in _pie_queue:
			var at := center + Vector2(-p, radius + p * 4 + i * p * 6)
			UiKit.draw_bulbs(self, at, at, 1, true, _time + i, 1.5)


## A light triangle with a burned dark edge.
func _draw_arrow(tip: Vector2, dir: Vector2, arrow: float, fill: Color) -> void:
	draw_colored_polygon(Icons.triangle(tip, dir, arrow + 8.0), Color(UiKit.INK, fill.a))
	draw_colored_polygon(Icons.triangle(tip, dir, arrow), fill)


## Light lettering with a dark edge, in the UI font.
func _draw_text(at: Vector2, text: String, align: HorizontalAlignment, width: float, text_size: int,
		fill: Color) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, at, text, align, width, text_size, 8, UiKit.INK)
	draw_string(font, at, text, align, width, text_size, fill)


func flash() -> void:
	if _tween:
		_tween.kill()
	_paint.set_shader_parameter("flash", 1.0)
	_glow = 2.5
	_tween = create_tween().set_parallel()
	_tween.tween_method(func(v: float) -> void: _paint.set_shader_parameter("flash", v), 1.0, 0.0, 0.2)
	_tween.tween_property(self, "_glow", 1.0, 0.3)
