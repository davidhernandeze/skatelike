class_name TestUtil
extends RefCounted
## Helpers for the tests in tests/ (see tests/README.md): a runner on its own (no game
## scene), and PASS / FAIL lines that tests/run.sh counts.

const AREA := Vector2(540, 676)


## A runner on `level` (a Levels entry or a level Dictionary), stepped by hand.
static func runner(tree: SceneTree, level: Dictionary) -> Runner:
	var r := Runner.new()
	r.manual = true
	r.configure(level)
	tree.root.add_child(r)
	r.setup(AREA)
	return r


## Prints PASS or FAIL for `name` (with `detail`), returns `ok`.
static func check(name: String, ok: bool, detail := "") -> bool:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, (": " + detail) if detail != "" else ""])
	return ok


## Where (x) a full pop now would come down through height `top`, or NAN.
static func pop_landing(r: Runner, top: float) -> float:
	var y: float = r._pos.y
	var vy: float = r._dir * r._speed * sin(r._ground_angle) - r.jump_velocity
	var speed: float = r._speed * cos(r._ground_angle)
	var t := 0.0
	while t < 2.0:
		var prev := y
		vy += r.gravity * Runner.STEP
		y += vy * Runner.STEP
		t += Runner.STEP
		if vy > 0.0 and prev <= top and y >= top:
			return r._pos.x + r._dir * speed * t
	return NAN
