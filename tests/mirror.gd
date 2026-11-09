extends SceneTree
## Mirror test: for each feature, a forward level (the feature to the right of the start)
## and its mirror image (to the left, laid out with `at`), ridden forward and backward
## from the same speed with mirrored inputs (pop the trailing end, catch offsets
## flipped). The ground code is written once for both ways, so the runs must match step
## for step: heights, speeds, airborne steps and events (names compared without their
## stance and with nose and tail swapped), board angles mirrored.
const LEAD := 358.0  # Forward: start end to feature = backward: board to start platform end.
const MIRROR_C := -830.0  # x -> MIRROR_C - x maps the forward feature onto the backward one.

func flat(w: float) -> Dictionary: return {width = w}
func slope(w: float, deg: float) -> Dictionary: return {width = w, rise = -w * tan(deg_to_rad(deg))}

func features() -> Array:
	var kicker_drop := 100 * tan(deg_to_rad(20.0)) + 80
	return [
		["crest hop (7° hump)", 9.0, [flat(400), slope(150, 7), slope(150, -7), flat(800)], {}],
		["crest launch (12° hump, catch)", 11.0, [flat(400), slope(200, 12), slope(200, -12), flat(1500)], {tap = true}],
		["roll off a step down (catch)", 6.0, [flat(400), {width = 1200, step = 120}], {tap = true}],
		["wall (step up)", 5.0, [flat(400), {width = 600, step = -60}], {}],
		["too steep (40° bend)", 5.0, [flat(400), slope(100, 40), flat(600)], {}],
		["kicker lip pop", 7.0, [flat(400), slope(100, 20), {width = 1500, step = kicker_drop}], {lip_pop = true, tap = true}],
		["kicker roll off (catch)", 7.0, [flat(400), slope(100, 20), {width = 1500, step = kicker_drop}], {tap = true}],
		["ledge slide", 7.0, [flat(400), {width = 1400, platform = [Vector2(700, 50), Vector2(1000, 50)]}, flat(400)], {target = "ledge", offset = -0.3}],
		["rail grind", 7.0, [flat(400), {width = 1400, rail = Vector3(700, 300, 45)}, flat(400)], {target = "rail", offset = 0.3}],
		["50-50 on a rail", 7.0, [flat(400), {width = 1400, rail = Vector3(700, 300, 45)}, flat(400)], {target = "rail", offset = 0.0}],
		["roll back down an uphill", 3.0, [flat(400), slope(600, 10), flat(400)], {}],
		["steep lip (transfer launch)", 11.0, [flat(400), slope(60, 20), slope(60, 40), slope(60, 60), slope(150, 70), {width = 1500, step = 400}], {}],
	]

## The mirror image of a forward piece list, as backward-level segments.
func mirror(specs: Array) -> Array:
	var x := LEAD
	var y := 0.0
	var ends := []
	for p: Dictionary in specs:
		x += p.get("gap", 0.0)
		y += p.get("step", 0.0)
		var start := Vector2(x, y)
		x += p.width
		y += p.get("rise", 0.0)
		ends.append([start, Vector2(x, y)])
	var out := []
	for k in range(specs.size() - 1, -1, -1):
		var p: Dictionary = specs[k]
		var m := {width = p.width, rise = -p.get("rise", 0.0)}
		if k == specs.size() - 1:
			var e: Vector2 = ends[k][1]
			m.at = Vector2(MIRROR_C - e.x, e.y)
		else:
			var after: Dictionary = specs[k + 1]
			if after.has("step"): m.step = -after.step
			if after.has("gap"): m.gap = after.gap
		if p.has("rail"):
			var r: Vector3 = p.rail
			m.rail = Vector3(p.width - r.x - r.y, r.y, r.z)
		if p.has("platform"):
			var pts := []
			for v: Vector2 in p.platform:
				pts.push_front(Vector2(p.width - v.x, v.y))
			m.platform = pts
		out.append(m)
	return out

func make(segments: Array, dir: float, speed: float, name: String) -> Runner:
	var r := TestUtil.runner(self, {id = name, start_y = 0.5, segments = segments})
	r._set_dir(dir)  # Backward: rolling fakie.
	r._speed = speed * r.pixels_per_meter
	return r

## One step of the mirrored bot.
func drive(r: Runner, opts: Dictionary, st: Dictionary) -> void:
	var d: float = r._dir
	var trailing := 0.0 if d > 0.0 else 1.0  # Tail going forward, nose going backward.
	if opts.get("lip_pop", false) and not st.popped and r._lip_t > 0.0 and r.can_pop():
		st.popped = true; r.act(Runner.Act.POP, trailing, 1.0)
	if opts.has("target") and not st.popped and r._grounded and r.can_pop():
		var spans: Array = r._ledges if opts.target == "ledge" else r._rails
		for s in spans:
			var near: float = s.x0 if d > 0.0 else s.x1
			var mid: float = (s.x0 + s.x1) * 0.5
			var land := TestUtil.pop_landing(r, s.y_at(mid))
			if not is_nan(land) and (land - (near + 60.0 * d)) * d > 0.0 and (mid - land) * d > 0.0:
				st.popped = true; r.act(Runner.Act.POP, trailing, 1.0)
				break
	if opts.has("target") and st.popped and not st.held and r._in_trick and r._velocity_y > -250.0:
		st.held = true; r.act(Runner.Act.PRESS_CATCH, opts.offset * d)
	if st.held and not r._in_trick and r._rail == null:
		st.held = false; r.act(Runner.Act.RELEASE_CATCH)
	if opts.get("tap", false) and r._in_trick and r._needs_catch and r._catches == 0 and r._velocity_y > 0.0:
		r.act(Runner.Act.PRESS_CATCH, 0.0); r.act(Runner.Act.RELEASE_CATCH)

func swap_ends(s: String) -> String:
	s = s.replace("fakie ", "").replace("switch ", "")  # The stance names differ by design.
	var map := {"nosegrind": "5-0 grind", "5-0 grind": "nosegrind", "noseslide": "tailslide", "tailslide": "noseslide",
		"nose manual": "manual", "manual": "nose manual", "nose strike": "tail strike", "tail strike": "nose strike"}
	for k in map:
		if s.ends_with(k) and not (k == "manual" and s.ends_with("nose manual")):
			return s.trim_suffix(k) + map[k]
	return s

func _initialize():
	for f in features():
		var name: String = f[0]
		var speed: float = f[1]
		var specs: Array = f[2] + [flat(4000)]  # A long runout both ways.
		var opts: Dictionary = f[3]
		var a := make([Vector2(LEAD, 0)] + specs.map(func(p): return p.duplicate()), 1.0, speed, "mirror_f")
		var b := make(mirror(specs), -1.0, speed, "mirror_b")
		var ev := [[], []]
		var runs := [a, b]
		for i in 2:
			var r: Runner = runs[i]
			var list: Array = ev[i]
			r.landed.connect(func(s): list.append("%d landed %s" % [r.tick, swap_ends(s) if i == 1 else s]))
			r.slammed.connect(func(s): list.append("%d slam %s" % [r.tick, swap_ends(s) if i == 1 else s]))
			r.dropped.connect(func(): list.append("%d off the ground" % r.tick))
		var sa := {popped = false, held = false}
		var sb := {popped = false, held = false}
		var first := -1
		var flips := [0, 0]
		var dirs := [a._dir, b._dir]
		for tick in 120 * 6:
			drive(a, opts, sa)
			drive(b, opts, sb)
			a.step(); b.step()
			for i in 2:
				if runs[i]._dir != dirs[i]: dirs[i] = runs[i]._dir; flips[i] += 1
			var e := absf(a._pos.y - b._pos.y)
			var ea := absf(wrapf(a._angle + b._angle, -PI, PI))
			var ev2 := absf(a._speed - b._speed)
			if first < 0 and (e > 0.05 or ea > 0.002 or ev2 > 0.05 or a._grounded != b._grounded or a._dead != b._dead):
				first = tick
			if a._dead and b._dead:
				break
		var ok: bool = first < 0 and ev[0] == ev[1] and flips[0] == flips[1]
		TestUtil.check("mirror: " + name, ok, "" if ok else "diverged at step %d; forward %s, backward %s" % [first, ev[0], ev[1]])
		a.queue_free(); b.queue_free()
	quit()
