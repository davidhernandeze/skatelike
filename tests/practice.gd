extends SceneTree
## Practice:
## - The menu: Practice has Learn first, then the obstacles (Stairs, Flat) and nothing
##   else; Learn has Mechanics and Tricks; Tricks lists the four trick lessons, Mechanics
##   the other lessons (none of the trick ones).
## - A practice stage has no goals and starts again at its flag (not back to the menu).
## - Stairs can be ridden through: a bot ollies the three sets.
## - Each trick lesson's trick, done off its drop, lands as that trick: its goal is met
##   (and a shuvit lesson isn't met by a front shuvit).

const TRICK_LESSONS := {lesson_kickflip = &"kickflip", lesson_heelflip = &"heelflip",
	lesson_shuvit = &"shuvit", lesson_front_shuvit = &"front shuvit"}


func _initialize() -> void:
	_check_lessons()
	TestUtil.check("goals: a front shuvit isn't a shuvit", not Goal.trick_matches("front shuvit", "shuvit")
			and Goal.trick_matches("360 shuvit", "shuvit") and Goal.trick_matches("360 front shuvit", "front shuvit")
			and Goal.trick_matches("fakie kickflip", "kickflip"))
	var ride := _ride_stairs()
	TestUtil.check("stairs: a bot rides through", ride.cleared, "slam '%s'" % ride.slam)
	await _check_menu()
	await _check_restart()
	quit()


func _buttons(m) -> PackedStringArray:
	var out := PackedStringArray()
	for b in m.list.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.text != "Back":
			out.append(b.text)
	return out


func _check_menu() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	for i in 10: await process_frame
	var m = current_scene
	m._show("practice")
	await process_frame
	var shown := _buttons(m)
	TestUtil.check("menu: Practice is Learn, then Stairs and Flat", Array(shown) == ["Learn", "Flat", "Stairs"]
			or Array(shown) == ["Learn", "Stairs", "Flat"], str(shown))
	m._show("learn")
	await process_frame
	shown = _buttons(m)
	TestUtil.check("menu: Learn is Mechanics and Tricks", Array(shown) == ["Mechanics", "Tricks"], str(shown))
	m._show("tricks")
	await process_frame
	shown = _buttons(m)
	TestUtil.check("menu: Tricks lists the four tricks", Array(shown) == ["1. Kickflip", "2. Heelflip", "3. Shuvit",
			"4. FS Shuvit"], str(shown))
	m._show("mechanics")
	await process_frame
	shown = _buttons(m)
	var tricks_there := false
	for text in shown:
		tricks_there = tricks_there or text.ends_with("Kickflip") or text.ends_with("Shuvit")
	TestUtil.check("menu: Mechanics lists the other lessons", shown.size() >= 10 and not tricks_there
			and shown[0] == "1. Pushing", "%d: %s" % [shown.size(), shown[0] if shown.size() > 0 else ""])


func _check_restart() -> void:
	Levels.current = "stairs"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10: await process_frame
	var game = current_scene
	TestUtil.check("practice stage: no goals", game._goals.is_empty() and (game.lesson == null or not game.lesson.visible))
	game.runner.level_cleared.emit()  # The flag.
	for i in 90: await process_frame
	var again = current_scene
	TestUtil.check("practice stage: the flag starts it again", again != null and again.has_method("pause")
			and again != game and Levels.current == "stairs")


## Rides Stairs: pushes to a steady speed, ollies each set (popping before it, catching
## on the way down).
func _ride_stairs() -> Dictionary:
	var r := TestUtil.runner(self, Levels.get_level("stairs"))
	var out := {slam = "", cleared = false}
	r.slammed.connect(func(s): out.slam = s)
	var tapped := false
	for tick in 120 * 40:
		if r._grounded and not r._in_trick and not r.is_pushing() and r._speed < 4.5 * r.pixels_per_meter:
			var ahead: Runner.Seg = r._support.next
			if ahead == null or ahead.stairs == 0 or ahead.x0 - r._pos.x > 700.0:
				r.act(Runner.Act.PUSH, 1.0)
		var stairs: Runner.Seg = r._support.next
		if r._grounded and r.can_pop() and stairs != null and stairs.stairs > 0 and stairs.x0 - r._pos.x < 40.0:
			r.act(Runner.Act.POP, 0.0, 1.0)
		if r._in_trick and r._needs_catch and r._catches == 0 and r._velocity_y > 0.0 and not tapped:
			tapped = true
			r.act(Runner.Act.PRESS_CATCH, 0.0)
			r.act(Runner.Act.RELEASE_CATCH)
		if not r._in_trick:
			tapped = false
		r.step()
		if r._dead or r._cleared:
			break
	out.cleared = r._cleared
	r.queue_free()
	return out


## Each trick lesson: pop at the edge of its high floor, do the trick, catch it coming
## down; the landing's name meets the lesson's goal.
func _check_lessons() -> void:
	for id: String in TRICK_LESSONS:
		var level := Levels.get_level(id)
		var trick: StringName = TRICK_LESSONS[id]
		var r := TestUtil.runner(self, level)
		var out := {landed = "", slam = ""}
		r.landed.connect(func(s): out.landed = s)
		r.slammed.connect(func(s): out.slam = s)
		var state := 0
		for tick in 120 * 15:
			if state == 0 and r._grounded and r._speed < 4.0 * r.pixels_per_meter and not r.is_pushing() \
					and r._support.x1 - r._pos.x > 300.0:
				r.act(Runner.Act.PUSH, 1.0)
			if state == 0 and r._grounded and r.can_pop() and r._support.x1 - r._pos.x < 60.0:
				r.act(Runner.Act.POP, 0.0, 1.0)
				state = 1
			elif state == 1 and not r._grounded:
				r.act(Runner.Act.BOARD_TRICK, Runner.TRICKS.find(trick))
				state = 2
			elif state == 2 and r._velocity_y > 300.0:
				r.act(Runner.Act.PRESS_CATCH, 0.0)
				r.act(Runner.Act.RELEASE_CATCH)
				state = 3
			r.step()
			if out.landed != "" or r._dead:
				break
		r.queue_free()
		var name: String = out.landed.trim_suffix(" clean").trim_suffix("clean").strip_edges()
		TestUtil.check("%s: the trick lands and meets the goal" % id, out.slam == ""
				and Goal.trick_matches(name, level.lesson.goal.trick), "landed '%s', slam '%s'" % [out.landed, out.slam])
