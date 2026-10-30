class_name TrickPad
extends Pad
## Air pad for board tricks, split into four sectors. The column on the side of the
## pop pad that was used does shuvits; the opposite column does flips.
## Top row: front shuvit / heelflip. Bottom row: shuvit / kickflip.

var _nose_pop := false
var _labels: Array[Label] = []


func _ready() -> void:
	super()
	for i in 4:
		var text := Label.new()
		text.add_theme_font_size_override("font_size", font_size)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.anchor_left = 0.5 * (i % 2)
		text.anchor_right = text.anchor_left + 0.5
		text.anchor_top = 0.5 * (i / 2)
		text.anchor_bottom = text.anchor_top + 0.5
		add_child(text)
		_labels.append(text)
	set_pop_side(false)


## Which pop pad started the jump: nose (right) or tail (left).
func set_pop_side(nose: bool) -> void:
	_nose_pop = nose
	for i in 4:
		_labels[i].text = String(trick_at(Vector2(1.0 if i % 2 else -1.0, 1.0 if i >= 2 else -1.0))) \
				.to_upper().replace(" ", "\n")


## The trick for a touch at local_pos (-1..1 on each axis).
func trick_at(local_pos: Vector2) -> StringName:
	var top := local_pos.y < 0.0
	var pop_side := (local_pos.x > 0.0) == _nose_pop
	if pop_side:
		return &"front shuvit" if top else &"shuvit"
	return &"heelflip" if top else &"kickflip"


func _draw() -> void:
	super()
	var line := Color(color, 0.6)
	draw_line(Vector2(12.0, size.y * 0.5), Vector2(size.x - 12.0, size.y * 0.5), line, 3.0)
	draw_line(Vector2(size.x * 0.5, 12.0), Vector2(size.x * 0.5, size.y - 12.0), line, 3.0)
