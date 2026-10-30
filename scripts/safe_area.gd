extends MarginContainer
## Pads its children so UI stays clear of notches, rounded corners and home bars.

@export var base_margin := 24
@export var use_top := true
@export var use_bottom := true
@export var use_left := true
@export var use_right := true


func _ready() -> void:
	get_viewport().size_changed.connect(_update_margins)
	_update_margins()


func _update_margins() -> void:
	var window_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var view_size := get_viewport_rect().size
	if not OS.has_feature("mobile") or window_size.x <= 0 or window_size.y <= 0 or safe.size == Vector2.ZERO:
		_apply(Vector4i.ZERO)
		return
	# Convert from screen pixels to viewport units.
	var to_view := view_size / window_size
	var left := int(safe.position.x * to_view.x) if use_left else 0
	var top := int(safe.position.y * to_view.y) if use_top else 0
	var right := int((window_size.x - safe.end.x) * to_view.x) if use_right else 0
	var bottom := int((window_size.y - safe.end.y) * to_view.y) if use_bottom else 0
	_apply(Vector4i(maxi(left, 0), maxi(top, 0), maxi(right, 0), maxi(bottom, 0)))


func _apply(insets: Vector4i) -> void:
	add_theme_constant_override("margin_left", base_margin + insets.x)
	add_theme_constant_override("margin_top", base_margin + insets.y)
	add_theme_constant_override("margin_right", base_margin + insets.z)
	add_theme_constant_override("margin_bottom", base_margin + insets.w)
