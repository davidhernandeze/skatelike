extends SceneTree
## Determinism (what online ghosts rely on): a run driven by a seeded random bot on a
## level is recorded as its actions (Runner.acted); a fresh runner of the same level
## replaying them must match it at every snapshot, and so must one restored from a
## snapshot halfway through (set_state).

func bot_step(r: Runner, rng: RandomNumberGenerator) -> void:
	if r._grounded and not r.is_pushing() and rng.randf() < 0.02:
		r.act(Runner.Act.PUSH, rng.randf_range(-1.0, 1.0))
	if r.can_pop() and rng.randf() < 0.01:
		r.act(Runner.Act.POP, 1.0 if rng.randf() < 0.3 else 0.0, rng.randf_range(0.0, 1.0))
		if rng.randf() < 0.3: r.act(Runner.Act.BODY_180, 1.0 if rng.randf() < 0.5 else -1.0)
	if r.can_board_trick() and rng.randf() < 0.05:
		r.act(Runner.Act.BOARD_TRICK, rng.randi_range(0, Runner.TRICKS.size() - 1))
	if r._in_trick and r._catches == 0 and r._velocity_y > 0.0 and rng.randf() < 0.1:
		r.act(Runner.Act.PRESS_CATCH, rng.randf_range(-0.5, 0.5)); r.act(Runner.Act.RELEASE_CATCH)

func _initialize():
	for id in ["sketchy_1", "transfer", "vert", "lesson_rails"]:
		var level := Levels.get_level(id)
		var a := TestUtil.runner(self, level)
		var actions := []
		a.acted.connect(func(t, action, x, y): actions.append([t, action, x, y]))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var states := {0: a.get_state()}
		for tick in 120 * 20:
			bot_step(a, rng)
			a.step()
			if a.tick % 120 == 0: states[a.tick] = a.get_state()
			if a._dead and a._slam_t < 0.0: break
		var last: int = a.tick
		for from in [0, (last / 240) * 120]:
			var b := TestUtil.runner(self, level)
			if from > 0:
				b.set_state(states[from])
			var i := 0
			while i < actions.size() and actions[i][0] < from: i += 1
			var checked := 0
			var bad := -1
			while b.tick < last:
				while i < actions.size() and actions[i][0] == b.tick:
					var e: Array = actions[i]
					b.act(e[1], e[2], e[3]); i += 1
				b.step()
				if states.has(b.tick):
					checked += 1
					if bad < 0 and not b.matches_state(states[b.tick]): bad = b.tick
			TestUtil.check("replay %s from tick %d (%d actions)" % [id, from, actions.size()], bad < 0 and checked > 0,
					"%d snapshots checked%s" % [checked, "" if bad < 0 else ", first mismatch at tick %d" % bad])
			b.queue_free()
		a.queue_free()
	quit()
