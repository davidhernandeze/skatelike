class_name PauseMenu
extends CanvasLayer
## The pause screen: a dim full-screen veil over the game with PAUSED and three big
## buttons, Home (back to the menu), Restart (the level from the start) and Play (back
## to the game). It keeps working while the tree is paused; Main pauses and resumes the
## game around it.

signal home
signal restart
signal play

const VEIL := Color(0.03, 0.03, 0.06, 0.72)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var veil := ColorRect.new()
	veil.color = VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing reaches the game under it.
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 48)
	veil.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	column.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	row.add_child(_button("HOME", Icons.home_texture(96), home))
	row.add_child(_button("RESTART", Icons.restart_texture(96), restart))
	row.add_child(_button("PLAY", Icons.triangle_texture(Vector2.RIGHT, 96), play))


func _button(text: String, icon: Texture2D, pressed: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.expand_icon = false
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(196, 220)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(func() -> void: pressed.emit())
	return button
