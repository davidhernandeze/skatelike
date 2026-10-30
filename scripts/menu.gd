extends Control
## Menu pages: the main page (Practice, Challenges, Profile), the level lists, a
## challenge's scoreboard ("board:<level id>") and the profile editor. Level buttons are built from Levels.LIST: levels with
## `challenge = true` go under Challenges (with their best progress), the rest under Practice.

const GAME_SCENE := "res://scenes/main.tscn"
const BUTTON_SIZE := Vector2(480, 88)

## Page to show; kept so that leaving a level returns to its list.
static var page := "main"

@onready var list: VBoxContainer = $Center/Box/Levels


func _ready() -> void:
	Levels.load_progress()
	Profile.load_profile()
	Scoreboard.flush()  # Clears queued while offline.
	list.add_theme_constant_override("separation", 16)  # Room for the 8 practice levels.
	_show(page)


func _show(new_page: String) -> void:
	page = new_page
	for child in list.get_children():
		child.queue_free()
	match page:
		"practice":
			_show_levels(false)
		"challenges":
			_show_levels(true)
		"profile":
			_show_profile()
		_ when page.begins_with("board:"):
			_show_board(page.trim_prefix("board:"))
		_:
			page = "main"
			_add_label("skater " + Profile.skater_name, 32, Color(0.75, 0.78, 0.9))
			_add_button("Practice", _show.bind("practice"))
			_add_button("Challenges", _show.bind("challenges"))
			_add_button("Profile", _show.bind("profile"))


func _show_levels(challenges: bool) -> void:
	_add_label("CHALLENGES" if challenges else "PRACTICE", 36, Color(0.75, 0.78, 0.9))
	if challenges:
		_add_online_switch()
	for level in Levels.LIST:
		if level.get("challenge", false) != challenges:
			continue
		var text: String = level.name
		var best: float = Levels.best.get(level.id, 0.0)
		if challenges and best > 0.0:
			text += "   best %d%%" % floori(best * 100.0)
		var button := _add_button(text, _start.bind(level.id))
		if Levels.is_cleared(level.id):
			button.icon = Icons.check_texture(36, Color(0.5, 0.9, 0.5))
			button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if challenges and Profile.online:
			var board := _make_button("Scoreboard", Vector2(480, 60), 28)
			board.pressed.connect(_show.bind("board:" + level.id))
			list.add_child(board)
	_add_button("Back", _show.bind("main"))


## A challenge's scoreboard: who cleared it, in the order they first did.
func _show_board(id: String) -> void:
	var level := Levels.get_level(id)
	_add_label(level.name.to_upper(), 36, Color(0.75, 0.78, 0.9))
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 26)
	state.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
	list.add_child(state)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	list.add_child(rows)
	_add_button("Back", _show.bind("challenges"))
	if not Profile.online:
		state.text = "turn Online on to see who cleared it"
		return
	state.text = "loading..."
	var on_loaded := func(challenge: String, board: Dictionary) -> void:
		if challenge == id:
			_fill_board(rows, state, board)
	var on_failed := func(challenge: String) -> void:
		if challenge == id:
			state.text = "can't load the scoreboard right now"
	# A clear that just went through moves the board: load it again.
	var on_recorded := func(challenge: String, _result: Dictionary) -> void:
		if challenge == id:
			Scoreboard.fetch_board(id)
	Scoreboard.board_loaded.connect(on_loaded)
	Scoreboard.board_failed.connect(on_failed)
	Scoreboard.clear_recorded.connect(on_recorded)
	state.tree_exiting.connect(func() -> void:
		Scoreboard.board_loaded.disconnect(on_loaded)
		Scoreboard.board_failed.disconnect(on_failed)
		Scoreboard.clear_recorded.disconnect(on_recorded))
	Scoreboard.fetch_board(id)


const BOARD_ROWS := 12


func _fill_board(rows: VBoxContainer, state: Label, board: Dictionary) -> void:
	for child in rows.get_children():
		child.queue_free()
	var clears: Array = board.get("clears", [])
	var total: int = board.get("total", clears.size())
	if total == 0:
		state.text = "nobody has cleared it yet: be the first!"
		return
	state.text = "%d skater%s cleared it, first clears first" % [total, "" if total == 1 else "s"]
	var mine := -1
	for i in clears.size():
		if clears[i].get("skater", "") == Profile.skater_name:
			mine = i
	for i in mini(clears.size(), BOARD_ROWS):
		rows.add_child(_board_row(i + 1, clears[i], i == mine))
	if mine >= BOARD_ROWS:
		rows.add_child(_board_row(mine + 1, clears[mine], true))
	elif total > BOARD_ROWS:
		var more := Label.new()
		more.text = "and %d more" % (total - BOARD_ROWS)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.add_theme_font_size_override("font_size", 24)
		more.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
		rows.add_child(more)


## "3.  ABC01   x2": position, skater and how often they cleared it; yours in yellow.
func _board_row(position: int, clear: Dictionary, mine: bool) -> Label:
	var row := Label.new()
	var times: int = clear.get("clears", 1)
	row.text = "%2d.  %s%s" % [position, clear.get("skater", "?????"), "   x%d" % times if times > 1 else ""]
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_theme_font_size_override("font_size", 34)
	row.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if mine else Color(0.9, 0.9, 0.95))
	return row


## Online switch: ghosts of other skaters on the same challenge, and the scoreboards.
func _add_online_switch() -> void:
	var switch := Toggle.new()
	switch.text = "  Online"
	switch.button_pressed = Profile.online
	switch.custom_minimum_size = BUTTON_SIZE
	switch.add_theme_font_size_override("font_size", 36)
	list.add_child(switch)
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 24)
	list.add_child(state)
	var show_status := func(status: StringName) -> void:
		state.text = {&"off": "offline: riding alone, no scoreboards", &"connecting": "connecting...",
				&"online": "online: ghosts and scoreboards",
				&"offline": "scoreboards on, ghost server unreachable (retrying)"}.get(status, "")
		state.add_theme_color_override("font_color",
				Color(0.5, 0.9, 0.5) if status == &"online" else Color(0.6, 0.62, 0.72))
	switch.toggled.connect(func(on: bool) -> void:
		Profile.set_online(on)
		Online.refresh()
		Scoreboard.flush()
		_show(page))  # Shows or hides the Scoreboard buttons.
	Online.status_changed.connect(show_status)
	state.tree_exiting.connect(func() -> void: Online.status_changed.disconnect(show_status))
	Online.refresh()
	show_status.call(Online.status)


## Skater name editor: a column per character, with buttons to step through its charset.
func _show_profile() -> void:
	_add_label("SKATER NAME", 36, Color(0.75, 0.78, 0.9))
	_add_label("3 letters + 2 numbers", 26, Color(0.6, 0.62, 0.72))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	list.add_child(row)
	for i in 5:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		row.add_child(column)
		var up := _make_button("", Vector2(84, 84), 36)
		up.icon = Icons.triangle_texture(Vector2.UP, 36)
		up.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var letter := Label.new()
		letter.text = Profile.skater_name[i]
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 72)
		letter.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		var down := _make_button("", Vector2(84, 84), 36)
		down.icon = Icons.triangle_texture(Vector2.DOWN, 36)
		down.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		up.pressed.connect(_step_char.bind(i, 1, letter))
		down.pressed.connect(_step_char.bind(i, -1, letter))
		column.add_child(up)
		column.add_child(letter)
		column.add_child(down)
	_add_button("Back", _show.bind("main"))


## Moves character i of the name by `step` through its charset, wrapping, and saves.
func _step_char(i: int, step: int, letter: Label) -> void:
	var chars := Profile.charset(i)
	var skater := Profile.skater_name
	var next := chars[posmod(chars.find(skater[i]) + step, chars.length())]
	Profile.set_skater_name(skater.substr(0, i) + next + skater.substr(i + 1))
	letter.text = next


func _add_label(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	list.add_child(label)


func _add_button(text: String, action: Callable) -> Button:
	var button := _make_button(text, BUTTON_SIZE, 40)
	button.pressed.connect(action)
	list.add_child(button)
	return button


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _start(id: String) -> void:
	Levels.current = id
	Levels.checkpoint = ""
	get_tree().change_scene_to_file(GAME_SCENE)
