extends SceneTree
## The game scene with its views and UI (a headless window): a held pop slid sideways
## shows its aim and lands a frontside 180 kickflip; the board and skater views are on;
## flow is unrestricted on free rides only; restart reloads the level; balance pops wait
## for the lift (the landing finger slid into POP, or a second finger on it) and take
## their aim; the menu puts Map first and its lists glide after a fling.

var main

func load_level(id: String) -> void:
	Levels.current = id
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10: await process_frame
	main = current_scene

func held_pop_and_flip() -> void:
	await load_level("flat")
	var r: Runner = main.runner
	var out := {landed = [], slam = ""}
	r.landed.connect(func(s): out.landed.append(s))
	r.slammed.connect(func(s): out.slam = s)
	for f in 60: await process_frame
	var pad: Pad = main.pop_pads[0]
	var cp = main.control_panel
	var start: Vector2 = pad.get_global_rect().get_center()
	cp._touches[5] = {action = &"tail_pop", pos = start}
	main._on_pad_pressed(&"tail_pop", 0, Vector2(0, -1))
	for f in 8:
		cp._touches[5].pos = start + Vector2(0.5 * pad.size.x * (f + 1) / 8.0, 0)
		await process_frame
	TestUtil.check("held pop: no pop before the lift", not r._in_trick)
	TestUtil.check("held pop: aim shown on the pad", pad._aim == 1, "aim %d" % pad._aim)
	cp._touches.erase(5)
	main._on_pad_released(&"tail_pop")
	await process_frame
	TestUtil.check("held pop: pops on the lift", r._in_trick)
	r.act(Runner.Act.BOARD_TRICK, 0)
	for f in 120:
		await process_frame
		if r._in_trick and r._catches == 0 and r._velocity_y > 0:
			r.act(Runner.Act.PRESS_CATCH, 0.0); r.act(Runner.Act.RELEASE_CATCH)
		if r._catches > 0 and not r._in_trick: break
	TestUtil.check("held pop: lands a frontside flip", out.landed.size() > 0 and String(out.landed[0]).begins_with("frontside"),
			"landed %s, slam '%s'" % [out.landed, out.slam])
	TestUtil.check("views: board and skater views on", is_instance_valid(r.board_view) and is_instance_valid(r.skater_view))
	# Seen from behind the toes are past the deck's far edge: the board draws over the
	# skater; from the front, the skater over the board.
	var goofy: bool = r._goofy
	var order := []
	for back in [false, true]:
		r._switch = back != goofy  # The back to the camera, whatever the saved stance.
		await process_frame
		await process_frame
		order.append(r.skater_view.get_index() > r.board_view.get_index())
	r._switch = false
	TestUtil.check("views: skater over the board from the front, under it from behind", order == [true, false], str(order))

func flow_and_restart() -> void:
	for id in ["flat", "sketchy_1"]:
		await load_level(id)
		var normal := Engine.time_scale
		main._on_pad_pressed(&"flow", 0, Vector2.ZERO)
		await process_frame
		var slow := Engine.time_scale < normal
		main._on_pad_pressed(&"flow", 0, Vector2.ZERO)
		await process_frame
		if id == "flat":
			TestUtil.check("flow: free ride starts it with an empty meter, a tap ends it",
					slow and Engine.time_scale == normal)
		else:
			TestUtil.check("flow: a gap needs a full meter", not slow)
	var before = main
	var restart: Button = main.get_node("Layout/PlayArea/HUD/Top/Restart")
	restart.pressed.emit()
	for i in 10: await process_frame
	TestUtil.check("restart: reloads the level", current_scene != before and Levels.current == "sketchy_1")

## Into a manual on Flat (CATCH held on the tail side), then a balance pop.
func balance_pop(second_finger: bool) -> void:
	await load_level("flat")
	var r: Runner = main.runner
	var calls := []
	r.callout.connect(func(c, _b): calls.append(c))
	var cp = main.control_panel
	var bp = main.balance_pad
	for f in 30: await process_frame
	main._on_pad_pressed(&"tail_pop", 0, Vector2(0, -1)); main._on_pad_released(&"tail_pop")
	var held := false
	var bal := 0
	for f in 200:
		if not held and r._in_trick and r._velocity_y > -900.0:
			held = true
			cp._touches[6] = {action = &"lock_tilt", pos = main.trick_pad.get_global_rect().get_center()}
			main._on_pad_pressed(&"lock_tilt", 0, Vector2(-0.3, 0))
		if bp.is_active():
			bal += 1
			var half: float = bp.size.x * 0.5
			var off := clampf(-(bp.needle + bp._needle_v * 0.15), -1.0, 1.0)
			var x: float = bp.global_position.x + half if is_nan(bp._finger) else bp.global_position.x + bp._reference + off * half
			cp._touches[6].pos = Vector2(x, bp.get_global_rect().get_center().y)
			if bal == 50: break
		await process_frame
	TestUtil.check("balance pop (%s): in a manual" % ("second finger" if second_finger else "held finger"), r.is_balancing())
	var pop_pad: Pad = main.balance_pop_pad
	var start := pop_pad.get_global_rect().get_center()
	var slide := Vector2(0.4 * pop_pad.size.x, 0)
	# The finger on POP: the landing finger slid up into it, or a second finger pressed on
	# it; slid sideways for a frontside 180, held a while.
	var action := &"balance_pop" if second_finger else &"lock_tilt"
	var index := 7 if second_finger else 6
	if second_finger:
		cp._touches[7] = {action = &"balance_pop", pos = start}
		main._on_pad_pressed(&"balance_pop", 0, Vector2.ZERO)
	else:
		cp._touches[6].pos = start
	for f in 10:
		await process_frame
		cp._touches[index].pos = start + slide * (f + 1) / 10.0
	for f in 12: await process_frame
	TestUtil.check("balance pop (%s): no pop before the lift" % ("second finger" if second_finger else "held finger"), not r._in_trick)
	cp._touches.erase(index)
	main._on_pad_released(action)
	await process_frame
	TestUtil.check("balance pop (%s): pops on the lift with the 180" % ("second finger" if second_finger else "held finger"),
			r._in_trick and r._body_turn >= 0.0, "in trick %s, body turn %.2f" % [r._in_trick, r._body_turn])
	if second_finger and cp._touches.has(6):
		cp._touches.erase(6); main._on_pad_released(&"lock_tilt")

func menu() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	for i in 10: await process_frame
	var m = current_scene
	m._show("main")  # The menu reopens on the last page shown.
	await process_frame
	var first := ""
	for b in m.list.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			first = b.text; break
	TestUtil.check("menu: Map first", first == "Map", "first '%s'" % first)
	m._show("mechanics")  # A list longer than the screen.
	for i in 5: await process_frame
	var at := Vector2(270, 700)
	var e := InputEventScreenTouch.new(); e.index = 0; e.pressed = true; e.position = at
	m._input(e)
	for i in 10:
		at.y -= 25.0
		var d := InputEventScreenDrag.new(); d.index = 0; d.position = at
		m._input(d)
		await process_frame
	var lifted: int = m.scroll.scroll_vertical
	e = InputEventScreenTouch.new(); e.index = 0; e.pressed = false; e.position = at
	m._input(e)
	for i in 40: await process_frame
	TestUtil.check("menu: a fling glides on", m.scroll.scroll_vertical > lifted + 100,
			"%d at the lift, %d after" % [lifted, m.scroll.scroll_vertical])

## The profile page's stance picker: Goofy is saved and the next run's rider is goofy.
func stance_picker() -> void:
	change_scene_to_file("res://scenes/menu.tscn")
	for i in 10: await process_frame
	var m = current_scene
	m._show("profile")
	for i in 5: await process_frame
	var goofy: Button = null
	for b in m.list.find_children("*", "Button", true, false):
		if b.text == "Goofy": goofy = b
	TestUtil.check("stance picker: on the profile page", goofy != null)
	if goofy == null:
		return
	goofy.pressed.emit()
	TestUtil.check("stance picker: Goofy saved", Profile.goofy)
	await load_level("flat")
	TestUtil.check("stance picker: the rider is goofy", main.runner._goofy and not main.runner.facing_camera())
	Profile.set_goofy(false)


func _initialize():
	await stance_picker()
	await held_pop_and_flip()
	await flow_and_restart()
	await balance_pop(false)
	await balance_pop(true)
	await menu()
	quit()
