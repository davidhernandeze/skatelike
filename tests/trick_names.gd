extends SceneTree
## Trick names by stance: jumps on a long floor rolling forward or backward (popped off a
## given end, with a body turn, a board trick, caught at a given time), checking each
## callout and the stance after it. Also how little a twisted pop tips the board.

## Rides `jumps` ([pop end "n"/"t", swipe, trick, catch time s]) rolling `dir`; returns
## [[callout, stance after, max tip deg], ...].
func ride(dir: float, jumps: Array) -> Array:
	var r := TestUtil.runner(self, {id = "names", start_y = 0.5,
			segments = [Vector2(9000, 0), {at = Vector2(-10200, 0), width = 9000}]})
	r._dir = dir
	r._speed = 5.0 * r.pixels_per_meter
	var calls := []
	r.callout.connect(func(c, _b): calls.append(c))
	r.slammed.connect(func(s): calls.append("SLAM " + s))
	var out := []
	for jump: Array in jumps:
		for i in 40: r.step()
		r.act(Runner.Act.POP, 1.0 if jump[0] == "n" else 0.0, 1.0)
		if jump[1] != 0: r.act(Runner.Act.BODY_180, jump[1])
		if jump[2] != "": r.act(Runner.Act.BOARD_TRICK, Runner.TRICKS.find(StringName(jump[2])))
		var t := 0.0
		var caught := false
		var tip := 0.0
		while r._in_trick and not r._dead and t < 3.0:
			if not caught and t >= jump[3]:
				caught = true; r.act(Runner.Act.PRESS_CATCH, 0.0); r.act(Runner.Act.RELEASE_CATCH)
			r.step(); t += Runner.STEP
			tip = maxf(tip, absf(rad_to_deg(r._angle)))
		out.append([calls.back() if not calls.is_empty() else "", r.stance_name(), tip])
		if r._dead: break
	r.queue_free()
	return out

func expect(label: String, dir: float, jumps: Array, want: Array) -> void:
	var got := ride(dir, jumps)
	for i in want.size():
		var g: Array = got[i] if i < got.size() else ["(none)", "", 0.0]
		var ok: bool = g[0] == want[i][0] and g[1] == want[i][1]
		TestUtil.check("%s #%d: %s" % [label, i + 1, want[i][0]], ok, "" if ok else "got '%s', riding '%s'" % [g[0], g[1]])

func _initialize():
	expect("forward", 1.0, [["t", 0, "", 0.2], ["t", 0, "kickflip", 0.4], ["n", 0, "", 0.2], ["t", 1, "", 0.2],
			["t", 0, "kickflip", 0.4], ["t", -1, "", 0.2], ["t", 0, "", 0.2]],
		[["ollie", ""], ["kickflip", ""], ["nollie", ""], ["frontside 180", "switch"], ["switch kickflip", "switch"],
			["switch frontside 180", ""], ["ollie", ""]])
	expect("fakie", -1.0, [["n", 0, "", 0.2], ["n", 0, "kickflip", 0.4], ["t", 0, "", 0.2], ["t", 0, "kickflip", 0.4]],
		[["fakie ollie", "fakie"], ["fakie kickflip", "fakie"], ["switch ollie", "fakie"], ["switch kickflip", "fakie"]])
	expect("half cab", -1.0, [["n", 1, "", 0.2]], [["half cab", ""]])
	expect("half cab flip", -1.0, [["n", 1, "kickflip", 0.2]], [["half cab flip", ""]])
	expect("full cab", -1.0, [["n", 1, "", 0.6]], [["full cab", "fakie"]])
	expect("fakie frontside", -1.0, [["n", -1, "", 0.2]], [["fakie frontside 180", ""]])
	expect("switch backside off the tail", -1.0, [["t", 1, "", 0.2]], [["switch backside 180", ""]])
	expect("360", 1.0, [["t", 1, "", 0.6], ["t", -1, "", 0.6]], [["frontside 360", ""], ["backside 360", ""]])
	expect("late catch settles back on the 180", 1.0, [["t", 1, "", 0.4]], [["frontside 180", "switch"]])
	# A twisted pop barely tips the board; a plain one tips well over.
	var plain: Array = ride(1.0, [["t", 0, "", 0.3]])[0]
	var twisted: Array = ride(1.0, [["t", 1, "", 0.6]])[0]
	TestUtil.check("twisted pop tips under 15°", twisted[2] < 15.0, "%.0f°" % twisted[2])
	TestUtil.check("plain pop tips over 30°", plain[2] > 30.0, "%.0f°" % plain[2])
	quit()
