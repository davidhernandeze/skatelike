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
## `random` adds that many randomly generated platforms afterwards.
## A flat goal platform with the finish flag always follows the last obstacle.

const LIST := [
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
	{id = "long", name = "Long", start_y = 0.7, segments = [], random = 30},
]

static var current := "push"
static var last_cleared := ""


static func get_level(id: String) -> Dictionary:
	for level in LIST:
		if level.id == id:
			return level
	return LIST[0]
