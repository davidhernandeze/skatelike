extends Control
## Menu pages: the main page (Practice, Challenges, Profile), the level lists, a
## challenge's scoreboard ("board:<level id>") and the profile editor. The title stays at
## the top; pages scroll below it and start with a Back button. Level buttons come from
## Levels.LIST: levels with `challenge = true` go in the Challenges table (best progress,
## scoreboard), the rest under Practice.

const GAME_SCENE := "res://scenes/main.tscn"
const BUTTON_SIZE := Vector2(480, 88)
## Width of the challenges and scoreboard tables, and their column widths.
const TABLE_WIDTH := 640.0
const BEST_WIDTH := 120.0
const BOARD_WIDTH := 130.0
const HEADER_COLOR := Color(0.6, 0.62, 0.72)
const BACK_COLOR := Color(0.55, 0.62, 0.85)

## Page to show; kept so that leaving a level returns to its list.
static var page := "main"

@onready var list: VBoxContainer = $Safe/Page/Scroll/Center/Levels


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
	_add_back("main")
	_add_label("CHALLENGES" if challenges else "PRACTICE", 36, Color(0.75, 0.78, 0.9))
	if challenges:
		_add_online_switch()
		_show_challenge_table()
		return
	for level in Levels.LIST:
		if level.get("challenge", false):
			continue
		var button := _add_button(level.name, _start.bind(level.id))
		if Levels.is_cleared(level.id):
			button.icon = Icons.check_texture(36, Color(0.5, 0.9, 0.5))
			button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## One row per challenge: play button, your best progress, and its scoreboard.
func _show_challenge_table() -> void:
	list.add_child(_table_row([_cell("CHALLENGE", 0.0, 24, HEADER_COLOR, HORIZONTAL_ALIGNMENT_LEFT),
			_cell("BEST", BEST_WIDTH, 24, HEADER_COLOR), _cell("BOARD", BOARD_WIDTH, 24, HEADER_COLOR)]))
	for level in Levels.LIST:
		if not level.get("challenge", false):
			continue
		var play := _make_button("  " + level.name, Vector2(0, 84), 36)
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.pressed.connect(_start.bind(level.id))
		var best: float = Levels.best.get(level.id, 0.0)
		var best_cell: Control
		if Levels.is_cleared(level.id):
			var check := TextureRect.new()
			check.texture = Icons.check_texture(40, Color(0.5, 0.9, 0.5))
			check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			check.custom_minimum_size = Vector2(BEST_WIDTH, 0)
			best_cell = check
		else:
			best_cell = _cell("%d%%" % floori(best * 100.0) if best > 0.0 else "-", BEST_WIDTH, 32,
					Color(0.9, 0.9, 0.95) if best > 0.0 else HEADER_COLOR)
		var board := _make_button("Top", Vector2(BOARD_WIDTH, 84), 28)
		board.disabled = not Profile.online  # The boards come from the server.
		board.pressed.connect(_show.bind("board:" + level.id))
		list.add_child(_table_row([play, best_cell, board]))
	if not Profile.online:
		_add_label("turn Online on for the scoreboards", 24, HEADER_COLOR)


func _table_row(cells: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(TABLE_WIDTH, 0)
	row.add_theme_constant_override("separation", 10)
	for cell in cells:
		row.add_child(cell)
	return row


## A table cell: a label `width` px wide, or filling the row's spare width when 0.
func _cell(text: String, width: float, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if width > 0.0:
		label.custom_minimum_size = Vector2(width, 0)
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## The Back button: outlined in BACK_COLOR with a left arrow, at the top left of the page.
func _add_back(target: String) -> void:
	var back := _make_button("Back", Vector2(200, 72), 32)
	back.icon = Icons.triangle_texture(Vector2.LEFT, 28, BACK_COLOR)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.add_theme_color_override("font_color", BACK_COLOR)
	back.add_theme_color_override("font_hover_color", BACK_COLOR.lightened(0.3))
	back.add_theme_color_override("font_pressed_color", BACK_COLOR.lightened(0.3))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(BACK_COLOR, 0.18 if state == "pressed" else (0.1 if state == "hover" else 0.0))
		style.border_color = BACK_COLOR
		style.set_border_width_all(3)
		style.set_corner_radius_all(36)
		style.content_margin_left = 18
		style.content_margin_right = 24
		back.add_theme_stylebox_override(state, style)
	back.pressed.connect(_show.bind(target))
	list.add_child(back)


## A challenge's scoreboard: who cleared it, in the order they first did.
func _show_board(id: String) -> void:
	_add_back("challenges")
	var level := Levels.get_level(id)
	_add_label(level.name.to_upper(), 36, Color(0.75, 0.78, 0.9))
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_theme_font_size_override("font_size", 26)
	state.add_theme_color_override("font_color", Color(0.6, 0.62, 0.72))
	list.add_child(state)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	list.add_child(rows)
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
	rows.add_child(_table_row([_cell("#", 90.0, 24, HEADER_COLOR), _cell("SKATER", 0.0, 24, HEADER_COLOR),
			_cell("CLEARS", 150.0, 24, HEADER_COLOR)]))
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


## A board row: position, skater and how often they cleared it; yours in yellow.
func _board_row(position: int, clear: Dictionary, mine: bool) -> HBoxContainer:
	var color := Color(1, 0.85, 0.3) if mine else Color(0.9, 0.9, 0.95)
	return _table_row([_cell(str(position), 90.0, 34, color), _cell(clear.get("skater", "?????"), 0.0, 34, color),
			_cell(str(int(clear.get("clears", 1))), 150.0, 34, color)])  # JSON numbers are floats.


## Online switch: ghosts of other skaters on the same challenge, and the scoreboards.
func _add_online_switch() -> void:
	var switch := Toggle.new()
	switch.text = "  Online"
	switch.button_pressed = Profile.online
	switch.custom_minimum_size = Vector2(TABLE_WIDTH, BUTTON_SIZE.y)
	switch.add_theme_font_size_override("font_size", 36)
	list.add_child(switch)
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Wrap instead of widening the menu.
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
		_show(page))  # Turns the scoreboard buttons on or off.
	Online.status_changed.connect(show_status)
	state.tree_exiting.connect(func() -> void: Online.status_changed.disconnect(show_status))
	Online.refresh()
	show_status.call(Online.status)


## Skater name editor: a column per character, with buttons to step through its charset.
func _show_profile() -> void:
	_add_back("main")
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
