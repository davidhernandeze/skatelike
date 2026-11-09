extends Control
## Menu pages: the main page (Gaps, Practice, Profile), the level lists, a
## challenge's scoreboard ("board:<level id>") and the profile editor (name and board). The title stays at
## the top; pages scroll below it and start with a Back button. Level buttons come from
## Levels.LIST: levels with `challenge = true` go in the challenges table, shown as
## "Gaps" (best progress, scoreboard), the rest under Practice.

const GAME_SCENE := "res://scenes/main.tscn"
const BUTTON_SIZE := Vector2(480, 88)
## Width of the challenges and scoreboard tables, and their column widths.
const TABLE_WIDTH := 640.0
const BEST_WIDTH := 120.0
const BOARD_WIDTH := 130.0
const HEADER_COLOR := UiKit.DIM
const CHECK_COLOR := Color("a6d96a")

## Page to show; kept so that leaving a level returns to its list.
static var page := "main"

@onready var list: VBoxContainer = $Safe/Page/Scroll/Center/Levels
@onready var scroll: ScrollContainer = $Safe/Page/Scroll

## Dragging scrolls the page from anywhere, buttons included (they'd otherwise keep the
## finger): a finger that moves more than this (px) is scrolling, not pressing.
const DRAG_START := 14.0
## The finger on the page: where it went down, the scroll then, and whether it's
## scrolling; the button it went down on is disabled meanwhile so lifting doesn't press it.
var _touch_index := -1
var _touch_from := Vector2.ZERO
var _scroll_from := 0
var _scrolling := false
var _held_button: Button
## Momentum: let go mid-drag, the page glides on at the finger's speed (px/s, smoothed
## over the drag) and slows down like a phone's lists, FLING_FRICTION per second, until
## FLING_STOP or an end of the page. A touch while it glides only catches it.
const FLING_FRICTION := 2.0
const FLING_STOP := 20.0
## Finger held still this long before lifting (s): no glide.
const FLING_HOLD := 0.08
## Fastest glide (px/s).
const FLING_MAX := 6000.0
var _fling_v := 0.0
## Scroll position as a float while gliding (the container's is whole pixels).
var _fling_pos := 0.0
## The finger's speed while dragging, and when it last moved (s).
var _drag_v := 0.0
var _drag_last := 0.0
var _drag_last_y := 0.0
var _clock := 0.0
## Buttons painted so far on this page (see _paint_next).
var _paint_turn := 0


func _ready() -> void:
	theme = UiKit.theme()
	_dress()
	Levels.load_progress()
	Profile.load_profile()
	Scoreboard.flush()  # Clears queued while offline.
	list.add_theme_constant_override("separation", 16)  # Room for the 8 practice levels.
	# Drags are scrolled by _input (from anywhere, buttons included): the container's own
	# touch dragging (empty space only) would scroll them twice. The wheel still works.
	scroll.scroll_deadzone = 1000000
	_show(page)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_touch_from = event.position
			_scroll_from = scroll.scroll_vertical
			_scrolling = false
			_drag_v = 0.0
			_drag_last = _now()
			_drag_last_y = event.position.y
			if absf(_fling_v) > FLING_STOP * 5.0:
				# Catching a glide: it stops, and the finger doesn't press what's under it.
				_hold_button(_button_at(event.position))
			_fling_v = 0.0
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			if _scrolling and _now() - _drag_last < FLING_HOLD:
				_fling_v = clampf(_drag_v, -FLING_MAX, FLING_MAX)
				_fling_pos = scroll.scroll_vertical
			if _held_button:
				# Back on after this release has gone by, so it didn't count as a press.
				_held_button.set_deferred("disabled", false)
				_held_button = null
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var dy: float = event.position.y - _touch_from.y
		if not _scrolling and absf(dy) > DRAG_START:
			_scrolling = true
			if not _held_button:
				_hold_button(_button_at(_touch_from))
		# The finger's speed, smoothed (scroll moves the other way to the finger).
		var now := _now()
		var dt := maxf(now - _drag_last, 0.001)
		var v: float = -(event.position.y - _drag_last_y) / dt
		_drag_v = lerpf(_drag_v, v, clampf(dt / 0.05, 0.2, 1.0))
		_drag_last = now
		_drag_last_y = event.position.y
		if _scrolling:
			scroll.scroll_vertical = _scroll_from - roundi(dy)


## Disables `button` (if any) until the finger lifts, so that lift doesn't press it.
func _hold_button(button: Button) -> void:
	if button and not button.disabled:
		button.disabled = true
		_held_button = button


## Frame time so far (s): the finger's speed and the glide run on the same clock.
func _now() -> float:
	return _clock


## The glide after a fling: slows down until it stops or reaches an end of the page.
func _process(delta: float) -> void:
	_clock += delta
	if _fling_v == 0.0 or _touch_index >= 0:
		return
	_fling_pos += _fling_v * delta
	_fling_v *= exp(-FLING_FRICTION * delta)
	scroll.scroll_vertical = roundi(_fling_pos)
	if absf(_fling_v) < FLING_STOP or scroll.scroll_vertical != roundi(_fling_pos):
		_fling_v = 0.0  # Slowed to a stop, or ran into the top or bottom.


## The enabled button on the page at a screen position, if any.
func _button_at(at: Vector2) -> Button:
	for node in scroll.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(at):
			return button
	return null


func _show(new_page: String) -> void:
	page = new_page
	_fling_v = 0.0
	_paint_turn = 0
	for child in list.get_children():
		child.queue_free()
	match page:
		"practice":
			_show_levels(false)
		"challenges":
			_show_levels(true)
		"profile":
			_show_profile()
		"credits":
			_show_credits()
		_ when page.begins_with("board:"):
			_show_board(page.trim_prefix("board:"))
		_:
			page = "main"
			_add_label("skater " + Profile.skater_name, 32, UiKit.LIGHT)
			for entry in [["Gaps", "gaps", "challenges"], ["Practice", "practice", "practice"],
					["Profile", "profile", "profile"], ["Credits", "star", "credits"]]:
				var button := _add_button(entry[0], _show.bind(entry[2]))
				button.icon = UiKit.icon(entry[1])
				button.custom_minimum_size = Vector2(480, 104)
				button.add_theme_font_size_override("font_size", 48)


func _show_levels(challenges: bool) -> void:
	_add_back("main")
	_add_label("GAPS" if challenges else "PRACTICE", 36, UiKit.LIGHT)
	if challenges:
		_add_online_switch()
		_show_challenge_table()
		return
	# Lessons first, in order, then free practice.
	for lessons in [true, false]:
		_add_label("Lessons" if lessons else "Free ride", 26, HEADER_COLOR)
		var n := 0
		for level in Levels.LIST:
			if level.get("challenge", false) or level.has("lesson") != lessons:
				continue
			n += 1
			var button := _add_button(("%d. %s" % [n, level.name]) if lessons else level.name, _start.bind(level.id))
			if Levels.is_cleared(level.id):
				button.icon = UiKit.icon("check")
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
		UiKit.paint_button(play, UiKit.PAINTS.teal)
		var best: float = Levels.best.get(level.id, 0.0)
		var best_cell: Control
		if Levels.is_cleared(level.id):
			var check := TextureRect.new()
			check.texture = UiKit.icon("check", CHECK_COLOR)
			check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			check.custom_minimum_size = Vector2(BEST_WIDTH, 0)
			best_cell = check
		else:
			best_cell = _cell("%d%%" % floori(best * 100.0) if best > 0.0 else "-", BEST_WIDTH, 32,
					UiKit.LIGHT if best > 0.0 else HEADER_COLOR)
		var board := _make_button("Top", Vector2(BOARD_WIDTH, 84), 28)
		board.icon = UiKit.icon("trophy")
		UiKit.paint_button(board, UiKit.PAINTS.orange, "plank_bare")
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


## The Back button: a small red plank with a left arrow, at the top left of the page.
func _add_back(target: String) -> void:
	var back := _make_button("Back", Vector2(200, 72), 32)
	back.icon = UiKit.icon("back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiKit.paint_button(back, UiKit.PAINTS.red)
	back.pressed.connect(_show.bind(target))
	list.add_child(back)


## A challenge's scoreboard: who cleared it, in the order they first did.
func _show_board(id: String) -> void:
	_add_back("challenges")
	var level := Levels.get_level(id)
	_add_label(level.name.to_upper(), 36, UiKit.LIGHT)
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_theme_font_size_override("font_size", 26)
	state.add_theme_color_override("font_color", UiKit.DIM)
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
		more.add_theme_color_override("font_color", UiKit.DIM)
		rows.add_child(more)


## A board row: position, skater and how often they cleared it; yours in yellow.
func _board_row(position: int, clear: Dictionary, mine: bool) -> HBoxContainer:
	var color := UiKit.BULB if mine else UiKit.LIGHT
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
				CHECK_COLOR if status == &"online" else UiKit.DIM)
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
## The assets the game uses and their licenses (CC BY 4.0 asks for the sounds' credit).
func _show_credits() -> void:
	_add_back("main")
	_add_label("Credits", 40, UiKit.BULB)
	for credit in [
		["Sounds", "\"Skateboarding Tricks\" by SoundBiterSFX\nfreesound.org/s/746602\nCC BY 4.0, cut and mixed for the game"],
		["Neon sign font", "Tilt Neon by Andy Clymer\nSIL Open Font License 1.1"],
		["Sign font", "Knewave by Tyler Finck\nSIL Open Font License 1.1"],
		["Interface font", "Lilita One by Juan Montoreano\nSIL Open Font License 1.1"],
		["Art", "backgrounds and mockups made with Runway,\nsprites made with Sprite Fusion"],
		["Engine", "Godot Engine\nMIT license"],
	]:
		_add_label(credit[0], 26, UiKit.LIGHT)
		_add_label(credit[1], 18, UiKit.DIM)


func _show_profile() -> void:
	_add_back("main")
	_add_label("SKATER NAME", 36, UiKit.LIGHT)
	_add_label("3 letters + 2 numbers", 26, UiKit.DIM)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	list.add_child(row)
	for i in 5:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		row.add_child(column)
		var up := _make_button("", Vector2(84, 84), 36)
		up.icon = Icons.triangle_texture(Vector2.UP, 36, UiKit.LIGHT)
		_style_stepper(up)
		up.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# A wooden tile of a combination lock.
		var letter := Label.new()
		letter.text = Profile.skater_name[i]
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.add_theme_font_override("font", UiKit.LOGO_FONT)
		letter.add_theme_font_size_override("font_size", 64)
		letter.add_theme_color_override("font_color", UiKit.INK)
		letter.add_theme_constant_override("outline_size", 0)
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", UiKit.plank(UiKit.PAINTS.orange, "normal", "pad_bare"))
		tile.custom_minimum_size = Vector2(84, 100)
		tile.add_child(letter)
		var down := _make_button("", Vector2(84, 84), 36)
		down.icon = Icons.triangle_texture(Vector2.DOWN, 36, UiKit.LIGHT)
		_style_stepper(down)
		down.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		up.pressed.connect(_step_char.bind(i, 1, letter))
		down.pressed.connect(_step_char.bind(i, -1, letter))
		column.add_child(up)
		column.add_child(tile)
		column.add_child(down)
	_add_stance_picker()
	_add_skater_picker()
	_add_board_picker()


## Regular or goofy: whether the skater faces the camera riding normal (regular) or
## shows the back (goofy). The picked one stays pressed.
func _add_stance_picker() -> void:
	_add_label("STANCE", 36, UiKit.LIGHT)
	_add_label("regular faces the camera, goofy turns its back", 22, UiKit.DIM)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	list.add_child(row)
	var group := ButtonGroup.new()
	for goofy in [false, true]:
		var button := _make_button("Goofy" if goofy else "Regular", Vector2(220, 80), 30)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = Profile.goofy == goofy
		_style_picked(button)
		button.pressed.connect(func() -> void: Profile.set_goofy(goofy))  # The preview follows it.
		row.add_child(button)


## Colors that stand for the base character's own layers, for item chips with no ramp.
const BASE_SWATCH := {skin = Color("d08a50"), shirt = Color("eee8dc"), pants = Color("3c5a8c"),
	shoes = Color("e8e8e4")}
const SLOT_TITLES := {skin = "SKIN", hair = "HAIR", hat = "HAT", shirt = "SHIRT", pants = "PANTS",
	shoes = "SHOES"}


## The skater: riding in the middle wearing the outfit, with a row of chips per slot under
## it; the picked one's name shows by the slot's title.
func _add_skater_picker() -> void:
	_add_label("SKATER", 36, UiKit.LIGHT)
	var preview := SkaterPreview.new()
	preview.custom_minimum_size = Vector2(TABLE_WIDTH, 340)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_stage(preview))
	for slot in Outfits.SLOTS:
		_add_outfit_row(slot, preview)


## A slot's title (with the picked item's name) and one chip per item; the picked one
## stays pressed.
func _add_outfit_row(slot: String, preview: SkaterPreview) -> void:
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiKit.DIM)
	list.add_child(title)
	var name_of := func(id: String) -> String:
		return "%s  ·  %s" % [SLOT_TITLES[slot], Outfits.find(slot, id).name.to_upper()]
	title.text = name_of.call(Profile.outfit[slot])
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	row.custom_minimum_size = Vector2(TABLE_WIDTH, 0)
	list.add_child(row)
	var group := ButtonGroup.new()
	for item: Dictionary in Outfits.ITEMS[slot]:
		var button := _make_button("", Vector2(96, 80), 24)
		button.icon = _item_chip(slot, item)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = item.id == Profile.outfit[slot]
		_style_picked(button)
		var id: String = item.id
		button.pressed.connect(func() -> void:
			Profile.set_outfit_part(slot, id)
			title.text = name_of.call(id)
			preview.refresh())
		row.add_child(button)


## An item's chip: the item itself (hair, hats, shirts with their own image), its color
## (the base's own layers), or a crossed-out chip for nothing (no hat, bald).
func _item_chip(slot: String, item: Dictionary) -> Texture2D:
	var chip := 40
	var image := Outfits.icon(item, 56)
	if image:
		return ImageTexture.create_from_image(image)
	image = Image.create(chip, chip, false, Image.FORMAT_RGBA8)
	if item.layer == null:
		image.fill(Color(0.3, 0.31, 0.38))
		for i in chip:
			for t in 3:
				image.set_pixel(clampi(i + t - 1, 0, chip - 1), chip - 1 - i, Color(0.75, 0.3, 0.3))
	else:
		image.fill(Outfits.swatch(item, BASE_SWATCH.get(slot, Color.WHITE)))
	return ImageTexture.create_from_image(image)


## A name stepper: a small dark plank (its light arrow is the icon).
func _style_stepper(button: Button) -> void:
	UiKit.paint_button(button, UiKit.PAINTS.brown, "plank_bare")


## `content` in a shop window: dark wooden boards behind it.
func _stage(content: Control) -> PanelContainer:
	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel", UiKit.backboard(0.55))
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(content)
	return stage


## A picker button: a small dark wooden token, and picked, lit up all around like a
## bulb strip.
func _style_picked(button: Button) -> void:
	UiKit.paint_button(button, UiKit.PAINTS.brown, "plank_bare")
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(c, UiKit.LIGHT)
	for state in ["pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("6a4428")
		style.border_color = UiKit.BULB
		style.set_border_width_all(UiKit.PIXEL * 2)
		style.set_corner_radius_all(UiKit.PIXEL * 2)
		style.shadow_color = Color(UiKit.BULB, 0.55)
		style.shadow_size = UiKit.PIXEL * 4
		style.set_content_margin_all(12)
		button.add_theme_stylebox_override(state, style)


## The board: spinning in the middle, with a row of choices for each part under it.
func _add_board_picker() -> void:
	_add_label("BOARD", 36, UiKit.LIGHT)
	var spinner := BoardSpinner.new()
	spinner.custom_minimum_size = Vector2(TABLE_WIDTH, 300)
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(_stage(spinner))
	var graphics := []
	for g: Dictionary in Boards.GRAPHICS:
		graphics.append({id = g.id, name = g.name, icon = _graphic_icon(g.id)})
	_add_part_row("GRAPHIC", "graphic", graphics, Profile.board_graphic, spinner)
	var grips := []
	for g: Dictionary in Boards.GRIPS:
		grips.append({id = g.id, name = g.name, icon = _swatch([g.color])})
	_add_part_row("GRIP", "grip", grips, Profile.board_grip, spinner)
	var wheels := []
	for w: Dictionary in Boards.WHEELS:
		wheels.append({id = w.id, name = w.name, icon = _swatch([w.color, w.core])})
	_add_part_row("WHEELS", "wheels", wheels, Profile.board_wheels, spinner)


## A title and one button per option of a board part; the picked one stays pressed.
func _add_part_row(title: String, part: String, options: Array, picked: String, spinner: BoardSpinner) -> void:
	_add_label(title, 26, UiKit.DIM)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	list.add_child(row)
	var group := ButtonGroup.new()
	for option: Dictionary in options:
		var button := _make_button(option.name, Vector2(280, 88), 28)
		button.icon = option.icon
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = option.id == picked
		_style_picked(button)
		button.pressed.connect(func() -> void:
			Profile.set_board_part(part, option.id)
			spinner.refresh())
		row.add_child(button)


## A deck graphic as a button icon, at the game's pixel size.
func _graphic_icon(id: String) -> Texture2D:
	var image := Boards.graphic_texture(id).get_image()
	image.resize(image.get_width() * Runner.PIXEL, image.get_height() * Runner.PIXEL, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


## Color chips side by side, as a button icon.
func _swatch(colors: Array) -> Texture2D:
	var chip := 32
	var image := Image.create(chip * colors.size(), chip, false, Image.FORMAT_RGBA8)
	for i in colors.size():
		image.fill_rect(Rect2i(i * chip, 0, chip, chip), colors[i])
	return ImageTexture.create_from_image(image)


## Moves character i of the name by `step` through its charset, wrapping, and saves.
func _step_char(i: int, step: int, letter: Label) -> void:
	var chars := Profile.charset(i)
	var skater := Profile.skater_name
	var next := chars[posmod(chars.find(skater[i]) + step, chars.length())]
	Profile.set_skater_name(skater.substr(0, i) + next + skater.substr(i + 1))
	letter.text = next


## A line of text on the page; big ones (36 and up) are titles: a red plank tag with the
## logo font.
func _add_label(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_size < 36:
		list.add_child(label)
		return
	label.add_theme_font_override("font", UiKit.LOGO_FONT)
	label.add_theme_color_override("font_color", UiKit.LIGHT)
	label.add_theme_constant_override("outline_size", 10)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiKit.plank(UiKit.PAINTS.red))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.custom_minimum_size = Vector2(300, 0)
	tag.add_child(label)
	list.add_child(tag)


func _add_button(text: String, action: Callable) -> Button:
	var button := _make_button(text, BUTTON_SIZE, 40)
	button.pressed.connect(action)
	_paint_next(button)
	list.add_child(button)
	return button


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	return button


## Paints `button` the next color of UiKit.ROTATION (starting over on each page).
func _paint_next(button: Button) -> void:
	UiKit.paint_button(button, UiKit.PAINTS[UiKit.ROTATION[_paint_turn % UiKit.ROTATION.size()]])
	_paint_turn += 1


## The menu's set: the Dusk Boardwalk drifting by behind the pages (dimmed so they read),
## and the name on a neon sign lighting it up.
func _dress() -> void:
	var dim: ColorRect = $Background
	dim.color = Color(0.05, 0.02, 0.1, 0.45)
	var backdrop := ParallaxBackdrop.new()
	backdrop.drift = 18.0
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title: Label = $Safe/Page/Title
	var sign := NeonSign.new()
	sign.text = title.text
	title.get_parent().add_child(sign)
	title.get_parent().move_child(sign, title.get_index())
	title.queue_free()


func _start(id: String) -> void:
	Levels.current = id
	get_tree().change_scene_to_file(GAME_SCENE)
