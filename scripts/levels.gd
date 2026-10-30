class_name Levels
extends RefCounted
## Level definitions and the current selection (kept across scene reloads).
##
## Each level starts on a flat platform at `start_y` (fraction of play area height),
## then lays out `segments` in order: Vector3(width, step, rise), where step is the
## vertical jump at the start of that platform and rise the height change along it
## (negative = up, positive = down). Vector2(width, step) means a flat platform.
## A Dictionary {width, step, rise, rail = Vector3(start, length, height)} is a platform
## with a rail above it, parallel to its surface: starting `start` px into the platform,
## `length` px long, `height` px above the ground.
## It can also have `platform = [Vector2(x, height), ...]`: a solid-from-above figure whose
## top runs through those points (x from the start of the floor piece, height above the
## floor there), filled down to the floor, or drawn as a slab `deck` px thick. Its ends
## join floor at the same height smoothly.
## `mark = "name"` records where the segment's rail, platform or floor piece starts and
## ends (Runner.marks), for tutorial steps to trigger on. Marked segments are also
## checkpoints: after a slam the level restarts from the last one reached.
## `gap = px` leaves empty space before the floor piece: a pit to jump, grind or bridge.
## `stairs = N` draws the piece as N stairs; they can't be landed on (ollie or grind them).
## `rail` can also be [Vector2(x, height), Vector2(x, height)]: a straight rail between
## two points (height above the piece's extended surface line), e.g. sloping across a gap.
## Platform points can lie over a gap too: where there's no floor below, the platform
## is drawn as an overhang.
## `tutorial = true` runs the guided steps in tutorial.gd on the level.
## `checkpoints = false` turns checkpoints off (slams restart the level).
## `challenge = true` lists the level under Challenges (with its best progress) instead
## of Practice.
## `random` adds that many randomly generated platforms afterwards.
## A flat goal platform with the finish flag always follows the last obstacle.

const LIST := [
	# Guided tour of every mechanic; tutorial.gd freezes the game at each marked spot.
	{id = "tutorial", name = "Tutorial", start_y = 0.35, tutorial = true, segments = [
		Vector2(700, 0),
		{width = 700, step = -80, mark = "ollie"},
		{width = 700, step = 120, mark = "drop"},
		{width = 700, step = -80, mark = "nollie"},
		{width = 800, step = 260, mark = "flip"},
		{width = 600, step = -100, mark = "steps"},
		{width = 900, step = 260, mark = "late"},
		Vector2(600, -110), Vector2(600, -110),
		{width = 1600, step = 100, mark = "manual"},
		{width = 2000, rail = Vector3(300, 1300, 70), mark = "rail"},
		Vector2(400, 0),
		{width = 1800, platform = [Vector2(300, 60), Vector2(1300, 60)], mark = "ledge"},
		Vector2(600, 0),
	]},
	{id = "flat", name = "Flat", start_y = 0.7, segments = [Vector2(8000, 0)]},
	{id = "push", name = "Push", start_y = 0.7, segments = [
		Vector3(600, 0, 0),  # flat run-up
		Vector3(900, 0, -160),  # uphill
		Vector3(500, 0, 0),
		Vector3(900, 0, 200),  # downhill
		Vector3(400, 0, 0),
	]},
	{id = "single_jump", name = "Single jump", start_y = 0.7, segments = [Vector2(600, -90)]},
	{id = "drops", name = "Drops", start_y = 0.4,
			segments = [Vector2(500, 80), Vector2(500, 120), Vector2(600, 160)]},
	# Two screen-high drops (~1.1 s of air from a full pop) for catch + late flip,
	# with pop steps climbing back up between them.
	{id = "long_jump", name = "Long jump", start_y = 0.3, segments = [
		Vector2(800, 580),
		Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110),
		Vector2(800, 550),
	]},
	# Long rails to practice grinds: a straight one, then a downhill one.
	{id = "rails", name = "Rails", start_y = 0.5, segments = [
		{width = 2000, rail = Vector3(300, 1400, 70)},
		Vector2(500, 0),
		{width = 2400, rise = 2400 * tan(deg_to_rad(8.0)), rail = Vector3(300, 1800, 70)},
	]},
	# Platforms: a flat ledge, a downhill ledge running onto the floor, and a bridge over a pit.
	{id = "ledges", name = "Ledges", start_y = 0.6, segments = [
		{width = 1800, platform = [Vector2(300, 60), Vector2(1300, 60)]},
		Vector2(400, 0),
		{width = 1800, platform = [Vector2(300, 140), Vector2(1400, 0)]},
		Vector2(400, 0),
		{width = 800, step = 180, platform = [Vector2(0, 180), Vector2(800, 180)], deck = 36},
		Vector2(600, -180),
	]},
	# Survival run through every obstacle kind, no checkpoints. Heights stay inside the
	# screen (y between about 0.3 and 0.86 of the play area). Marks are for tests and bots.
	{id = "sketchy_1", name = "Sketchy #1", start_y = 0.6, checkpoints = false, challenge = true, segments = [
		Vector2(600, 0),
		{width = 700, gap = 260, mark = "gap"},
		{width = 600, step = -140, mark = "high1"},  # High ollies: near a full pop's limit.
		{width = 700, step = -130, mark = "high2"},
		# A stair set with a handrail: ollie it or grind the rail down.
		{width = 480, rise = 280, stairs = 8, rail = Vector3(-40, 520, 70), mark = "stairs1"},
		Vector2(900, 0),
		Vector3(900, 0, -230),  # Uphill to bleed off the speed from the handrail...
		Vector2(400, 0),
		Vector3(260, 0, -90),  # ...then a kicker over a gap.
		{width = 800, gap = 340, step = 60, mark = "kicker"},
		# A gap only a rail crosses.
		{width = 800, gap = 900, rail = [Vector2(-1150, 70), Vector2(150, 70)], mark = "railgap"},
		# A gap only a raised deck crosses: ollie up onto it, drop off the far end.
		{width = 700, gap = 800, platform = [Vector2(-1000, 90), Vector2(60, 90)], mark = "deckgap"},
		# A downhill rail over a gap (or a long ollie down across it).
		{width = 900, gap = 600, step = 220, rail = [Vector2(-850, 290), Vector2(80, 160)], mark = "downrail"},
		# A gap onto a downhill landing ramp: catch nose down.
		{width = 600, gap = 300, step = -40, rise = 100, mark = "ramp"},
		Vector2(400, 0),
		Vector3(1100, 0, -300),  # A long uphill.
		# Two gaps with a small island between them.
		{width = 550, gap = 280, mark = "island"},
		{width = 700, gap = 280, mark = "island2"},
		{width = 460, rise = 260, stairs = 8, rail = Vector3(-40, 500, 70), mark = "stairs2"},
		Vector2(700, 0),
		Vector3(700, 0, -120),  # Uphill: keep pushing.
		{width = 600, step = -140, mark = "high3"},
		# A box that overhangs a gap and ends short of the far side: ollie off its end.
		{width = 900, gap = 500, platform = [Vector2(-700, 60), Vector2(-250, 60)], mark = "overhang"},
		{width = 800, gap = 320, mark = "gap2"},
		# Second half: the same ideas, harder.
		{width = 700, gap = 360, step = 40, mark = "longgap"},
		# A downhill ledge bridging a gap: ollie up onto it, ride it down onto the far side.
		{width = 800, gap = 600, platform = [Vector2(-800, 100), Vector2(50, 0)], mark = "ledgebridge"},
		{width = 520, rise = 300, stairs = 9, rail = Vector3(-40, 560, 70), mark = "stairs3"},
		Vector2(800, 0),
		Vector3(1000, 0, -250),
		{width = 550, step = -120, mark = "high4"},
		# A downhill rail that ends over a gap, above a landing ramp.
		{width = 700, gap = 700, step = 160, rise = 120, rail = [Vector2(-950, 230), Vector2(-50, 130)],
				mark = "downrail2"},
		Vector2(400, 0),
		Vector3(900, 0, -220),  # Uphill.
		# Three islands in a row.
		{width = 500, gap = 260, mark = "isle_a"},
		{width = 500, gap = 260, mark = "isle_b"},
		{width = 600, gap = 260, mark = "isle_c"},
		# Finale: a high deck over a wide gap.
		{width = 800, gap = 900, platform = [Vector2(-1100, 120), Vector2(100, 120)], deck = 30, mark = "finale"},
		Vector2(500, 0),
	]},
]

static var current := "push"
## Furthest progress per level id (0..1; 1 = cleared), saved in PROGRESS_FILE. On the web,
## user:// lives in the browser's IndexedDB: Godot syncs it when a file is closed.
static var best := {}
static var _loaded := false
const PROGRESS_FILE := "user://progress.cfg"
## Mark of the last checkpoint reached in the current level ("" = from the start).
## Cleared when a level is picked or cleared.
static var checkpoint := ""


## Whether the level was ever cleared on this device or browser.
static func is_cleared(id: String) -> bool:
	load_progress()
	return best.get(id, 0.0) >= 1.0


## Records a run's progress (0..1) if it beats the best so far, and saves it.
static func record(id: String, progress: float) -> void:
	load_progress()
	if progress <= best.get(id, 0.0):
		return
	best[id] = progress
	var file := ConfigFile.new()
	for level_id in best:
		file.set_value("best", level_id, best[level_id])
	file.save(PROGRESS_FILE)


static func load_progress() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(PROGRESS_FILE) == OK and file.has_section("best"):
		for id in file.get_section_keys("best"):
			best[id] = file.get_value("best", id)


## Index of the segment with `mark` in `level`, or -1.
static func mark_index(level: Dictionary, mark: String) -> int:
	var segments: Array = level.segments
	for i in segments.size():
		if segments[i] is Dictionary and segments[i].get("mark", "") == mark:
			return i
	return -1


## A copy of `level` that starts right before the segment with `mark`, on a start
## platform at the height the level has there (`start_dy` px below `start_y`).
static func from_checkpoint(level: Dictionary, mark: String) -> Dictionary:
	var index := mark_index(level, mark)
	if index < 0:
		return level
	var resumed := level.duplicate()
	var dy := 0.0
	for i in index:
		var segment = level.segments[i]
		if segment is Dictionary:
			dy += segment.get("step", 0.0) + segment.get("rise", 0.0)
		elif segment is Vector3:
			dy += segment.y + segment.z
		else:
			dy += segment.y
	resumed.segments = level.segments.slice(index)
	resumed.start_dy = dy
	resumed.checkpoint = mark
	return resumed


static func get_level(id: String) -> Dictionary:
	for level in LIST:
		if level.id == id:
			return level
	return LIST[0]
