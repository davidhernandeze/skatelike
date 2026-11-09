extends SceneTree
## The Transfer level end to end: down the drop and the U, the 75° lip, fakie down the
## wall, then the obstacles ridden backward on the lower floor: the hump (a crest hop), a
## tailslide on the box, a nosegrind on the rail, and the kicker (popped at the lip, or
## rolled off and caught), to the flag. Checks the names (fakie) and the clear.

func ride(kicker: String) -> Dictionary:
	var r := TestUtil.runner(self, Levels.get_level("transfer"))
	var out := {landed = [], slam = "", cleared = false, hops = 0}
	r.landed.connect(func(s): out.landed.append(s))
	r.slammed.connect(func(s): out.slam = s)
	r.level_cleared.connect(func(): out.cleared = true)
	r.dropped.connect(func(): if r._dir < 0.0 and r._pos.y > r._segs[0].y0 + 600.0 and not r._needs_catch: out.hops += 1)
	var done := {}
	var popped_for := ""
	var tapped := false
	var lower := false
	for tick in 120 * 40:
		# On the lower floor, rolling backward (from then on: a pop off the kicker goes
		# higher than the floor's height test).
		lower = lower or (r._pos.y > r._segs[0].y0 + 600.0 and r._dir < 0.0)
		if lower and r._grounded and r._rail == null and r.is_balancing():
			r.act(Runner.Act.END_BALANCE)  # Out of a manual, for a full pop.
		if lower and r._grounded and r.can_pop() and popped_for == "":
			for target in ["back_ledge", "back_rail"]:
				if done.has(target) or not r.marks.has(target):
					continue
				var span: Vector2 = r.marks[target]
				var mid := (span.x + span.y) * 0.5
				var top := NAN
				for s in r._rails + r._ledges:
					if mid >= s.x0 and mid <= s.x1: top = s.y_at(mid)
				var land := TestUtil.pop_landing(r, top)
				var near: float = span.x if r._dir > 0.0 else span.y
				if not is_nan(land) and (land - (near + 60.0 * r._dir)) * r._dir > 0.0 and (mid - land) * r._dir > 0.0:
					done[target] = true
					popped_for = target
					r.act(Runner.Act.POP, 1.0, 1.0)
					break
		if popped_for.begins_with("back_") and r._in_trick and r._catches == 0 and r._velocity_y > -250.0:
			r.act(Runner.Act.PRESS_CATCH, -0.3 if popped_for == "back_ledge" else 0.3)
		if popped_for != "" and not r._in_trick and r._rail == null:
			r.act(Runner.Act.RELEASE_CATCH)
			if r._grounded: popped_for = ""
		if lower and kicker == "pop" and r._lip_t > 0.0 and r.can_pop() and absf(r._pos.x - r.marks.back_kicker.x) < 200.0:
			r.act(Runner.Act.POP, 1.0, 1.0); popped_for = "kicker"
		# Catch the kicker's air early: a pop off it turns the board fast (past upright, a
		# catch only turns it back slowly); a roll-off when it starts coming down.
		var catch_at := -500.0 if popped_for == "kicker" else 0.0
		if lower and r._in_trick and r._needs_catch and r._catches == 0 and r._velocity_y > catch_at and not tapped \
				and not popped_for.begins_with("back_"):
			tapped = true; r.act(Runner.Act.PRESS_CATCH, 0.0); r.act(Runner.Act.RELEASE_CATCH)
		if not r._in_trick: tapped = false
		r.step()
		if r._dead or r._cleared: break
	r.queue_free()
	return out

func _initialize():
	for kicker in ["pop", "roll"]:
		var out := ride(kicker)
		var names: Array = out.landed
		TestUtil.check("backward course (kicker %s) cleared" % kicker, out.cleared, "slam '%s', landed %s" % [out.slam, names])
		TestUtil.check("backward course (kicker %s) tailslide named fakie" % kicker, names.has("fakie tailslide"), str(names))
		TestUtil.check("backward course (kicker %s) nosegrind named fakie" % kicker, names.has("fakie nosegrind"), str(names))
		TestUtil.check("backward course (kicker %s) hop over the hump" % kicker, names.has("roll"), str(names))
	quit()
