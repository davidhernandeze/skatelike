class_name PauseMenu
extends CanvasLayer
## The pause screen: a dim full-screen veil over the game with a hanging PAUSED sign and
## three big painted signboard buttons, Home (back to the menu), Restart (the level from the start) and Play (back
## to the game). It keeps working while the tree is paused; Main pauses and resumes the
## game around it.

signal home
signal restart
signal play

const VEIL := Color(0.05, 0.02, 0.1, 0.7)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var veil := ColorRect.new()
	veil.theme = UiKit.theme()  # A CanvasLayer: the game's theme doesn't reach here.
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
	var title := HangingSign.new()
	title.text = "PAUSED"
	title.font_size = 80
	title.paint = UiKit.PAINTS.teal
	title.chain = 120.0
	column.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	row.add_child(_button("MENU", "home", UiKit.PAINTS.red, home))
	row.add_child(_button("RESTART", "restart", UiKit.PAINTS.orange, restart))
	row.add_child(_button("PLAY", "play", UiKit.PAINTS.green, play))


func _button(text: String, icon_name: String, paint: Color, pressed: Signal) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(196, 220)
	UiKit.paint_button(button, paint, "pad")
	# The icon above its name, the two together in the middle of the pad (a Button's own
	# icon would sit on its top edge).
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var icon := TextureRect.new()
	icon.texture = UiKit.icon(icon_name, UiKit.INK, true)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", UiKit.INK)  # Burned in, as on the buttons.
	label.add_theme_constant_override("outline_size", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	# Pushed in: the content goes down a texel with the plank.
	button.button_down.connect(func() -> void: content.position.y = UiKit.PIXEL)
	button.button_up.connect(func() -> void: content.position.y = 0.0)
	button.pressed.connect(func() -> void: pressed.emit())
	return button
