extends SceneTree
## Trick names by stance (see Runner.stance_name()): jumps on a long floor, riding normal
## or fakie (rolling backward), regular or goofy, each popped off an end, with a body turn,
## a board trick, caught at a given time, maybe held into a manual; checks each callout
## and the stance after it. Also how little a twisted pop tips the board.

## Rides `jumps` ([pop end "n"/"t", swipe, trick, catch time s, "manual" or ""]) starting
## fakie if `fakie`; returns [[callout, stance after, max tip deg], ...].
func ride(fakie: bool, jumps: Array, goofy := false, push_first := false) -> Array:
	var r := TestUtil.runner(self, {id = "names", start_y = 0.5,
			segments = [Vector2(9000, 0), {at = Vector2(-10200, 0), width = 9000}]})
	r._goofy = goofy
	r._speed = 5.0 * r.pixels_per_meter
	if fakie:
		r._set_dir(-1.0)
	if push_first:
		r.act(Runner.Act.PUSH, 0.0)
	var calls := []
	r.callout.connect(func(c, _b): calls.append(c))
	r.slammed.connect(func(s): calls.append("SLAM " + s))
	var out := []
	for jump: Array in jumps:
		for i in 40: r.step()
		r.act(Runner.Act.POP, 1.0 if jump[0] == "n" else 0.0, 1.0)
		if jump[1] != 0: r.act(Runner.Act.BODY_180, jump[1])
		if jump[2] != "": r.act(Runner.Act.BOARD_TRICK, Runner.TRICKS.find(StringName(jump[2])))
		var manual: bool = jump.size() > 4 and jump[4] == "manual"
		var t := 0.0
		var caught := false
		var tip := 0.0
		while r._in_trick and not r._dead and t < 3.0:
			if not caught and t >= jump[3]:
				caught = true
				r.act(Runner.Act.PRESS_CATCH, -0.3 if manual else 0.0)
				if not manual: r.act(Runner.Act.RELEASE_CATCH)
			r.step(); t += Runner.STEP
			tip = maxf(tip, absf(rad_to_deg(r._angle)))
		out.append([calls.back() if not calls.is_empty() else "", r.stance_name(), tip])
		if manual:
			r.act(Runner.Act.RELEASE_CATCH)
			r.act(Runner.Act.END_BALANCE)
		if r._dead: break
	if jumps.is_empty():
		for i in 40: r.step()
		out.append(["", r.stance_name(), 0.0])
	r.queue_free()
	return out

## The views a tail pop with a body turn `swipe` caught at `catch_t` shows in the air,
## repeats collapsed ("front-right", "back-left"...), starting fakie if `fakie`.
func turn_views(fakie: bool, swipe: float, catch_t: float) -> Array:
	var r := TestUtil.runner(self, {id = "spin", start_y = 0.5,
			segments = [Vector2(9000, 0), {at = Vector2(-10200, 0), width = 9000}]})
	r._speed = 5.0 * r.pixels_per_meter
	if fakie:
		r._set_dir(-1.0)
	for i in 40: r.step()
	r.act(Runner.Act.POP, 0.0, 1.0)
	r.act(Runner.Act.BODY_180, swipe)
	var seq := []
	var t := 0.0
	var caught := false
	while r._in_trick and t < 3.0:
		if not caught and t >= catch_t:
			caught = true; r.act(Runner.Act.PRESS_CATCH, 0.0); r.act(Runner.Act.RELEASE_CATCH)
		r.step(); t += Runner.STEP
		if not r._in_trick: break
		var pose := r.skater_pose()
		var v := ("back" if pose.back else "front") + ("-left" if pose.mirror else "-right")
		if seq.is_empty() or seq.back() != v: seq.append(v)
	r.queue_free()
	return seq


func expect(label: String, fakie: bool, jumps: Array, want: Array, goofy := false, push_first := false) -> void:
	var got := ride(fakie, jumps, goofy, push_first)
	for i in want.size():
		var g: Array = got[i] if i < got.size() else ["(none)", "", 0.0]
		var ok: bool = g[0] == want[i][0] and g[1] == want[i][1]
		TestUtil.check("%s #%d: '%s', then %s" % [label, i + 1, want[i][0], want[i][1] if want[i][1] != "" else "normal"],
				ok, "" if ok else "got '%s', riding '%s'" % [g[0], g[1]])

func _initialize():
	expect("regular", false, [["t", 0, "", 0.2], ["t", 0, "kickflip", 0.4], ["n", 0, "", 0.2], ["t", 1, "", 0.2],
			["t", 0, "kickflip", 0.4], ["n", 0, "", 0.2], ["t", -1, "", 0.2], ["t", 0, "", 0.2]],
		[["ollie", ""], ["kickflip", ""], ["nollie", ""], ["frontside 180", "switch"], ["switch kickflip", "switch"],
			["switch nollie", "switch"], ["switch frontside 180", ""], ["ollie", ""]])
	# Goofy faces away riding normal: the same swipe is the other side.
	expect("goofy", false, [["t", 1, "", 0.2], ["t", -1, "", 0.2]],
		[["backside 180", "switch"], ["switch backside 180", ""]], true)
	# Fakie: tail pops chain fakie tricks; a nose pop is a switch trick and lands switch.
	expect("fakie chain", true, [["t", 0, "", 0.2], ["t", 0, "kickflip", 0.4], ["n", 0, "", 0.2], ["n", 0, "", 0.2]],
		[["fakie ollie", "fakie"], ["fakie kickflip", "fakie"], ["switch ollie", "switch"], ["switch nollie", "switch"]])
	expect("push out of fakie", true, [], [["", "switch"]], false, true)
	# Manuals out of fakie are switch manuals, and leave you switch.
	expect("fakie into a manual", true, [["t", 0, "", 0.2, "manual"]], [["switch manual", "switch"]])
	expect("fakie kickflip into a manual", true, [["t", 0, "kickflip", 0.4, "manual"]],
		[["fakie kickflip switch manual", "switch"]])
	# 180s: normal <-> switch; out of fakie the rider turns to face the way it rolls: back
	# to normal (a half cab), and the next tail pop is a plain ollie.
	expect("half cab", true, [["t", 1, "", 0.2], ["t", 0, "", 0.2]], [["half cab", ""], ["ollie", ""]])
	expect("half cab flip", true, [["t", 1, "kickflip", 0.2]], [["half cab flip", ""]])
	expect("full cab", true, [["t", 1, "", 0.6]], [["full cab", "fakie"]])
	expect("fakie frontside", true, [["t", -1, "", 0.2]], [["fakie frontside 180", ""]])
	expect("nose pop 180 out of fakie", true, [["n", 1, "", 0.2]], [["switch backside 180", ""]])
	expect("360", false, [["t", 1, "", 0.6], ["t", -1, "", 0.6]], [["frontside 360", ""], ["backside 360", ""]])
	expect("late catch settles back on the 180", false, [["t", 1, "", 0.4]], [["frontside 180", "switch"]])
	# Facing: regular shows the chest riding normal (to the right) and fakie, the back
	# riding switch; goofy the other way round. A half cab turns it around.
	for goofy in [false, true]:
		var r := TestUtil.runner(self, {id = "facing", start_y = 0.5, segments = [Vector2(3000, 0)]})
		r._goofy = goofy
		var normal: float = r.skater_pose().face
		r._switch = true
		var switch: float = r.skater_pose().face
		r._switch = false
		r._set_dir(-1.0)
		var fakie: float = r.skater_pose().face
		var want := -1.0 if goofy else 1.0
		TestUtil.check("facing (%s): normal and fakie %s, switch the other way" % ["goofy" if goofy else "regular",
				"back" if goofy else "chest"], normal == want and fakie == want and switch == -want,
				"normal %d, switch %d, fakie %d" % [normal, switch, fakie])
		r._heading = -1.0  # After a half cab: riding normal to the left, turned around.
		TestUtil.check("facing (%s): turned around after a half cab" % ("goofy" if goofy else "regular"),
				r.skater_pose().face == -want and r.stance_name() == "")
		# The view the rig draws: front or back, facing left (mirrored) or right.
		var views := []
		r._heading = 1.0
		r._set_dir(1.0)
		for setup in [[false, 1.0, 1.0], [true, 1.0, 1.0], [false, 1.0, -1.0], [false, -1.0, -1.0]]:
			r._switch = setup[0]
			r._heading = setup[1]
			r._set_dir(setup[2])
			var pose := r.skater_pose()
			views.append(("back" if pose.back else "front") + ("-left" if pose.mirror else "-right"))
		var want_views := ["back-right", "front-right", "back-right", "front-left"] if goofy \
				else ["front-right", "back-right", "front-right", "back-left"]
		TestUtil.check("views (%s): normal, switch, fakie, after a half cab" % ("goofy" if goofy else "regular"),
				views == want_views, str(views))
		r.queue_free()
	# The view through a body turn, step by step (repeats collapsed): a spin that comes
	# round, a 180 that ends looking ahead.
	var spins := [
		["360", false, 1.0, 0.6, ["front-right", "back-left", "front-right"]],
		["180 to switch", false, 1.0, 0.2, ["front-right", "back-left", "back-right"]],
		["half cab", true, 1.0, 0.2, ["front-right", "back-left"]],
	]
	for spin in spins:
		var seq := turn_views(spin[1], spin[2], spin[3])
		TestUtil.check("spin view (%s)" % spin[0], seq == spin[4], str(seq))
	# A twisted pop barely tips the board; a plain one tips well over.
	var plain: Array = ride(false, [["t", 0, "", 0.3]])[0]
	var twisted: Array = ride(false, [["t", 1, "", 0.6]])[0]
	TestUtil.check("twisted pop tips under 15°", twisted[2] < 15.0, "%.0f°" % twisted[2])
	TestUtil.check("plain pop tips over 30°", plain[2] > 30.0, "%.0f°" % plain[2])
	quit()
