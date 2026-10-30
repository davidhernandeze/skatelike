extends Control
## Level selector. Buttons are built from Levels.LIST.

const GAME_SCENE := "res://scenes/main.tscn"

@onready var list: VBoxContainer = $Center/Box/Levels


func _ready() -> void:
	for level in Levels.LIST:
		var button := Button.new()
		button.text = level.name + ("  ✓" if level.id == Levels.last_cleared else "")
		button.custom_minimum_size = Vector2(480, 120)
		button.add_theme_font_size_override("font_size", 40)
		button.pressed.connect(_start.bind(level.id))
		list.add_child(button)


func _start(id: String) -> void:
	Levels.current = id
	get_tree().change_scene_to_file(GAME_SCENE)
