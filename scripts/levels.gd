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
## ends (Runner.marks), for tests and bots. A slam always restarts the level from the start.
## `gap = px` leaves empty space before the floor piece: a pit to jump, grind or bridge.
## `stairs = N` draws the piece as N stairs; they can't be landed on (ollie or grind them).
## `rail` can also be [Vector2(x, height), Vector2(x, height)]: a straight rail between
## two points (height above the piece's extended surface line), e.g. sloping across a gap.
## Platform points can lie over a gap too: where there's no floor below, the platform
## is drawn as an overhang.
## `challenge = true` lists the level under Gaps (with its best progress) instead of
## Practice.
## `max_fall = px` sets the hardest landing (Runner.max_fall; 0 = no limit).
## `lesson = {title, text, demo, goal}` makes it a practice lesson (see Lesson): listed
## first under Practice, with an explanation panel and a goal it needs to clear.
## `at = Vector2(x, y)` starts a new stretch of floor there instead of after the last
## piece (x from the end of the start platform, y down from its height), so a floor can
## run under one laid already (drawn as a slab, Runner.floor_slab); the pieces after it
## carry on from it. `goal = px` puts the finish flag that far into the piece instead of
## after the last one: reached rolling past it either way, on that floor.
## `random` adds that many randomly generated platforms afterwards.
## A flat goal platform with the finish flag always follows the last obstacle.

const LIST := [
	# Lessons: one mechanic each, in order.
	{id = "lesson_push", name = "Pushing", start_y = 0.8, lesson = {
		title = "1. Pushing",
		text = "Tap PUSH to kick. Higher on the pad kicks harder. Tap again while a kick is going to line up to two more. No pops while pushing.",
		# Two quick hard kicks (the second lines up), then a long pause before it loops.
		demo = [
			{pad = &"push", at = Vector2(0.0, -0.7), hold = 0.12}, {wait = 0.1},
			{pad = &"push", at = Vector2(0.0, -0.7), hold = 0.12}, {wait = 2.0},
		],
		goal = {speed = 25.0},
	}, segments = [
		Vector2(3000, 0),  # Flat: get going.
		Vector3(900, 0, -110),  # Uphills too steep to coast up: keep pushing.
		Vector2(500, 0),
		Vector3(900, 0, -170),
		Vector2(600, 0),
	]},
	{id = "lesson_ollie", name = "Ollie & catch", start_y = 0.75, lesson = {
		title = "2. Ollie & catch",
		text = "Tap TAIL POP to ollie: higher on the pad pops higher. The board turns nose up until you catch it: tap CATCH (the middle keeps it level) before you land, or you slam.",
		# Pop high, the pads switch to the air ones, catch in the middle, a long pause.
		demo = [
			{layout = &"ground"}, {wait = 0.4},
			{pad = &"tail_pop", at = Vector2(0.0, -0.7), hold = 0.12},
			{layout = &"air"}, {wait = 0.25},
			{pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12}, {wait = 0.6},
			{layout = &"ground"}, {wait = 1.6},
		],
		goal = {trick = "ollie", count = 3},
	}, segments = [
		Vector2(1400, 0),  # Room to try a few.
		# Pits to ollie over, wider and wider: all clear at the start speed with a full
		# pop up to about 60 px before the edge (more with speed).
		{width = 900, gap = 120},
		{width = 900, gap = 160},
		{width = 1000, gap = 200},
	]},
	{id = "lesson_pop", name = "Pop height", start_y = 0.82, lesson = {
		title = "3. Pop height",
		text = "Low on TAIL POP pops a little, the top pops full. Step ups need a full pop, early: the nose has to clear the edge. Catch before the board passes upright.",
		demo = [
			{layout = &"ground"}, {wait = 0.4}, {pad = &"tail_pop", at = Vector2(0.0, 0.6), hold = 0.12},
			{layout = &"air"}, {wait = 0.15}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{layout = &"ground"}, {wait = 0.9}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{layout = &"ground"}, {wait = 1.6},
		],
	}, segments = [
		Vector2(900, 0),
		# Step ups, higher and higher: the last ones need a full pop.
		{width = 700, step = -40},
		{width = 700, step = -80},
		{width = 800, step = -110},
		{width = 800, step = -130},
		Vector2(500, 0),
	]},
	{id = "lesson_drops", name = "Drops", start_y = 0.35, lesson = {
		title = "4. Drops",
		text = "Rolling off a ledge tips the nose down: catch it before you land. Pop off the edge instead for more air. Don't push right at an edge.",
		demo = [
			{layout = &"ground"}, {wait = 0.8}, {layout = &"air"}, {wait = 0.3},
			{pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12}, {wait = 0.6},
			{layout = &"ground"}, {wait = 1.4},
		],
	}, segments = [
		Vector2(900, 100),  # Drops, deeper and deeper.
		Vector2(700, 160),
		Vector2(800, 220),
		Vector2(600, 0),
	]},
	{id = "lesson_nollie", name = "Nollie", start_y = 0.75, lesson = {
		title = "5. Nollie",
		text = "NOSE POP pops off the front: a nollie. The board turns nose down until you catch it, so catch it early.",
		demo = [
			{layout = &"ground"}, {wait = 0.4}, {pad = &"nose_pop", at = Vector2(0.0, -0.7), hold = 0.12},
			{layout = &"air"}, {wait = 0.25}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.6}, {layout = &"ground"}, {wait = 1.6},
		],
		goal = {trick = "nollie", count = 3},
	}, segments = [
		Vector2(1400, 0),
		{width = 900, gap = 120},
		{width = 900, gap = 160},
		{width = 1000, gap = 200},
	]},
	{id = "lesson_angle", name = "Catch angle", start_y = 0.4, lesson = {
		title = "6. Catch angle",
		text = "Where you tap CATCH tilts the board: left lifts the nose, right drops it. Landing on a downhill? Catch on the right to match it.",
		demo = [
			{layout = &"ground"}, {wait = 0.4}, {pad = &"tail_pop", at = Vector2(0.0, -0.7), hold = 0.12},
			{layout = &"air"}, {wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.75, 0.1), hold = 0.12},
			{wait = 0.6}, {layout = &"ground"}, {wait = 1.6},
		],
	}, segments = [
		Vector2(900, 0),
		# Gaps onto steep landing ramps (about 23°, under the 25° the board can ride off
		# onto flat): a level catch slams.
		{width = 600, gap = 200, step = 60, rise = 250},
		Vector2(300, 0),
		Vector3(700, 0, -150),  # Uphill: bleeds off the speed from the ramp.
		{width = 900, gap = 200, step = 40, rise = 380},
		Vector2(700, 0),
	]},
	{id = "lesson_crests", name = "Crests & lips", start_y = 0.78, lesson = {
		title = "7. Crests & lips",
		text = "Ramps throw you on with your speed: small hops land by themselves. At a kicker, pop right at the lip to fly further. Push for speed first.",
		demo = [
			{layout = &"ground"}, {pad = &"push", at = Vector2(0.0, -0.7), hold = 0.12}, {wait = 0.1},
			{pad = &"push", at = Vector2(0.0, -0.7), hold = 0.12}, {wait = 0.8},
			{pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.6}, {layout = &"ground"}, {wait = 1.4},
		],
	}, segments = [
		Vector2(1400, 0),
		Vector3(400, 0, -120),  # A ramp onto flat: crest it fast for a hop.
		Vector2(1000, 0),
		Vector3(260, 0, -90),  # A kicker over a gap: pop at its lip.
		{width = 800, gap = 340, step = 60},
		Vector2(500, 0),
	]},
	{id = "lesson_flip", name = "Flip tricks", start_y = 0.3, max_fall = 900, lesson = {
		title = "8. Flip tricks",
		text = "After a pop, tap TRICK: the column on your pop's side does shuvits, the other flips. The board spins until you CATCH it. Big drops give time.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"trick", at = Vector2(0.55, 0.5), hold = 0.12},
			{wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.6}, {layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "kickflip"},
	}, segments = [
		Vector2(800, 580),  # Screen-high drops, with pop steps back up between them.
		Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110),
		Vector2(800, 550),
	]},
	{id = "lesson_doubles", name = "Doubles", start_y = 0.3, max_fall = 900, lesson = {
		title = "9. Doubles",
		text = "The catch counts the turns: wait for two full flips before you CATCH for a double kickflip. Leave time to land.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"trick", at = Vector2(0.55, 0.5), hold = 0.12},
			{wait = 0.8}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.5}, {layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "double kickflip"},
	}, segments = [
		Vector2(800, 580),
		Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110),
		Vector2(800, 550),
	]},
	{id = "lesson_late", name = "Late tricks", start_y = 0.3, max_fall = 900, lesson = {
		title = "10. Late tricks",
		text = "Catch first, then tap TRICK, then CATCH again: a late trick, worth more.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.25}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.2}, {pad = &"trick", at = Vector2(0.55, 0.5), hold = 0.12},
			{wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.5}, {layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "late", match = "starts", text = "land a late trick"},
	}, segments = [
		Vector2(800, 580),
		Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110),
		Vector2(800, 550),
	]},
	{id = "lesson_combo", name = "Combo tricks", start_y = 0.3, max_fall = 900, lesson = {
		title = "11. Combo tricks",
		text = "Tricks tapped quickly join into one: two shuvits and a kickflip make a 360 flip. Then catch it.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.15}, {pad = &"trick", at = Vector2(-0.55, 0.5), hold = 0.08},
			{pad = &"trick", at = Vector2(-0.55, 0.5), hold = 0.08}, {pad = &"trick", at = Vector2(0.55, 0.5), hold = 0.08},
			{wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.5}, {layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "360 flip"},
	}, segments = [
		Vector2(800, 580),
		Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110),
		Vector2(800, 550),
	]},
	{id = "lesson_manual", name = "Manuals", start_y = 0.55, lesson = {
		title = "12. Manuals",
		text = "Catch, then HOLD CATCH on a side as you land: left for a manual, right for a nose manual. Slide that finger to keep the needle up; lift it to finish.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.7), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"lock_tilt", at = Vector2(-0.6, 0.1), hold = 0.5},
			{layout = &"balance"}, {pad = &"balance", at = Vector2(-0.3, 0.0), hold = 0.4},
			{pad = &"balance", at = Vector2(0.3, 0.0), hold = 0.4}, {pad = &"balance", at = Vector2(0.0, 0.0), hold = 0.4},
			{layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "manual"},
	}, segments = [
		Vector2(800, 0),
		{width = 1800, step = 100},  # Drops onto long flats: land a manual and ride it.
		{width = 1800, step = 100},
		Vector2(600, 0),
	]},
	{id = "lesson_manual_pop", name = "Manual pops", start_y = 0.55, lesson = {
		title = "13. Manual pops",
		text = "Pop out of a manual: slide the held finger up into POP, or press POP with another finger (smaller pops). It pops when you lift; slide sideways on POP first for a 180. Tricks chained like this make a line.",
		demo = [
			{layout = &"balance"}, {pad = &"balance", at = Vector2(-0.2, 0.0), hold = 0.5},
			{pad = &"balance", at = Vector2(0.2, 0.0), hold = 0.5}, {pad = &"balance_pop", at = Vector2(0.0, 0.0), hold = 0.12},
			{layout = &"air"}, {wait = 0.25}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.5}, {layout = &"ground"}, {wait = 1.4},
		],
		goal = {line = 3},
	}, segments = [
		Vector2(800, 0),
		{width = 2000, step = 100},  # Manual, then pop out (and up the small step).
		{width = 900, step = -40},
		{width = 1800, step = 100},
		Vector2(600, 0),
	]},
	{id = "lesson_rails", name = "Rails", start_y = 0.5, lesson = {
		title = "14. Rails",
		text = "Ollie over a rail and HOLD CATCH coming down onto it: level is a 50-50, tail down a 5-0, nose down a nosegrind. Balance; pop out or ride off the end.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.5},
			{layout = &"balance"}, {pad = &"balance", at = Vector2(-0.2, 0.0), hold = 0.4},
			{pad = &"balance", at = Vector2(0.2, 0.0), hold = 0.4},
			{layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "grind", count = 2},
	}, segments = [
		{width = 2000, rail = Vector3(300, 1400, 70)},
		Vector2(500, 0),
		{width = 2400, rise = 2400 * tan(deg_to_rad(8.0)), rail = Vector3(300, 1800, 70)},
		Vector2(500, 0),
	]},
	{id = "lesson_ledges", name = "Ledges", start_y = 0.6, lesson = {
		title = "15. Ledges",
		text = "Ledges work like rails: hold CATCH on a side onto one for a tailslide or noseslide. Lift to roll on along the top, or slide off the end.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"lock_tilt", at = Vector2(-0.6, 0.1), hold = 0.5},
			{layout = &"balance"}, {pad = &"balance", at = Vector2(-0.2, 0.0), hold = 0.4},
			{pad = &"balance", at = Vector2(0.2, 0.0), hold = 0.4},
			{layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "slide", match = "contains", text = "land a slide"},
	}, segments = [
		{width = 1800, platform = [Vector2(300, 60), Vector2(1300, 60)]},
		Vector2(400, 0),
		{width = 1800, platform = [Vector2(300, 140), Vector2(1400, 0)]},
		Vector2(500, 0),
	]},
	{id = "lesson_double_grind", name = "Double grinds", start_y = 0.55, lesson = {
		title = "16. Double grinds",
		text = "Pop off a rail and grab the next one before touching the floor: a double grind. The pop out is small, so the rails are close.",
		demo = [
			{layout = &"balance"}, {pad = &"balance", at = Vector2(0.0, 0.0), hold = 0.5},
			{pad = &"balance_pop", at = Vector2(0.0, 0.0), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.5},
			{layout = &"balance"}, {pad = &"balance", at = Vector2(0.0, 0.0), hold = 0.5},
			{layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "double", match = "starts", text = "land a double grind"},
	}, segments = [
		Vector2(400, 0),
		{width = 1400, rail = Vector3(300, 1000, 70)},  # Two rails in a row, 150 px apart.
		{width = 1400, rail = Vector3(50, 1000, 70)},
		Vector2(500, 0),
	]},
	{id = "lesson_lines", name = "Lines & flow", start_y = 0.5, lesson = {
		title = "17. Lines & flow",
		text = "Chain tricks without putting the wheels down: each one scores x2, x3 more. Tricks fill FLOW: tap it when full for slow motion.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"tail_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 0.2}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.5},
			{layout = &"balance"}, {pad = &"balance", at = Vector2(0.0, 0.0), hold = 0.5},
			{pad = &"balance_pop", at = Vector2(0.0, 0.0), hold = 0.12},
			{layout = &"air"}, {wait = 0.25}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{layout = &"ground"}, {wait = 1.4},
		],
		goal = {line = 4},
	}, segments = [
		{width = 2000, rail = Vector3(300, 1400, 70)},  # Rail, pop out, manual, pop out...
		{width = 1800, step = 80},
		{width = 2000, rail = Vector3(300, 1400, 70)},
		Vector2(600, 0),
	]},
	{id = "lesson_180", name = "180s & switch", start_y = 0.3, max_fall = 900, lesson = {
		title = "18. 180s & switch",
		text = "Keep holding the pop and slide sideways before lifting: the skater turns 180 (right is frontside, left backside). You land switch; another 180 turns back. Add a kickflip for a frontside or backside flip.",
		demo = [
			{layout = &"ground"}, {wait = 0.3},
			{pad = &"tail_pop", at = Vector2(0.0, -0.6), to = Vector2(-0.9, -0.6), hold = 0.3},
			{layout = &"air"}, {wait = 0.1}, {pad = &"trick", at = Vector2(0.55, 0.5), hold = 0.12},
			{wait = 0.3}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.5}, {layout = &"ground"}, {wait = 1.4},
		],
		goal = {trick = "side flip", match = "contains", text = "land a frontside or backside flip"},
	}, segments = [
		Vector2(800, 580),  # Long Jump's drops: time for a 180 and a flip.
		Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110), Vector2(400, -110),
		Vector2(800, 550),
	]},
	{id = "lesson_vert", name = "Vert", start_y = 0.43, max_fall = 650, lesson = {
		title = "19. Vert",
		text = "A nollie keeps turning nose down. Pop just before the edge, wait, and catch late: past upright the board turns back slowly, to meet the wall. Then pop at the kicker's lip.",
		demo = [
			{layout = &"ground"}, {wait = 0.3}, {pad = &"nose_pop", at = Vector2(0.0, -0.8), hold = 0.12},
			{layout = &"air"}, {wait = 1.2}, {pad = &"lock_tilt", at = Vector2(0.0, 0.1), hold = 0.12},
			{wait = 0.8}, {layout = &"ground"}, {wait = 1.4},
		],
	}, segments = [
		Vector2(300, 0),
		Vector3(350, 0, -55),
		{width = 3400 / tan(deg_to_rad(85.0)), rise = 3400, mark = "vert"},
		Vector3(40, 0, 40 * tan(deg_to_rad(65.0))),
		Vector3(50, 0, 50 * tan(deg_to_rad(45.0))),
		Vector3(60, 0, 60 * tan(deg_to_rad(25.0))),
		Vector3(70, 0, 70 * tan(deg_to_rad(5.0))),
		Vector2(1000, 0),
		# Kicker out of the bottom: 40° jumps furthest at the 12 m/s the drop gives (steeper
		# loses too much speed climbing it). Rolling off it falls short: pop at the lip.
		Vector3(20, 0, -20 * tan(deg_to_rad(15.0))),
		Vector3(20, 0, -20 * tan(deg_to_rad(30.0))),
		{width = 20, rise = -20 * tan(deg_to_rad(40.0)), mark = "kicker"},
		# Landing: gently downhill to soften the impact, still landable caught level.
		{width = 900, gap = 1050, rise = 900 * tan(deg_to_rad(14.0))},
		Vector2(400, 0),
	]},
	# A very gentle downhill (0.7°): gravity about makes up for rolling resistance and drag
	# at riding speed, so you can manual all the way, about a minute.
	{id = "cruise", name = "Downhill cruise", start_y = 0.6, segments = [
		Vector3(30000, 0, 30000 * tan(deg_to_rad(0.7))),
	]},
	# Transfer to fakie: drop into a U whose far side goes up to a 75° lip, which throws
	# the board almost straight up (Runner.transfer_angle): it drifts over onto a tall
	# 72° wall facing back, comes down it backward (fakie), and rolls back left along a
	# lower floor that runs under the U, through obstacles ridden backward, to the flag. A pop at the lip goes higher and
	# meets the wall further up. Not enough speed: it rolls back into the U (push).
	{id = "transfer", name = "Transfer", start_y = 0.2, max_fall = 900, segments = [
		Vector2(80, 0),
		# The drop: 10° steps down to 80° (small enough not to fly off them at speed), then
		# back round to the bottom (508 px down).
		Vector3(30 * cos(deg_to_rad(10.0)), 0, 30 * sin(deg_to_rad(10.0))),
		Vector3(30 * cos(deg_to_rad(20.0)), 0, 30 * sin(deg_to_rad(20.0))),
		Vector3(30 * cos(deg_to_rad(30.0)), 0, 30 * sin(deg_to_rad(30.0))),
		Vector3(30 * cos(deg_to_rad(40.0)), 0, 30 * sin(deg_to_rad(40.0))),
		Vector3(30 * cos(deg_to_rad(50.0)), 0, 30 * sin(deg_to_rad(50.0))),
		Vector3(30 * cos(deg_to_rad(60.0)), 0, 30 * sin(deg_to_rad(60.0))),
		Vector3(30 * cos(deg_to_rad(70.0)), 0, 30 * sin(deg_to_rad(70.0))),
		Vector3(273.9 * cos(deg_to_rad(80.0)), 0, 273.9 * sin(deg_to_rad(80.0))),
		Vector3(60 * cos(deg_to_rad(60.0)), 0, 60 * sin(deg_to_rad(60.0))),
		Vector3(60 * cos(deg_to_rad(40.0)), 0, 60 * sin(deg_to_rad(40.0))),
		Vector3(60 * cos(deg_to_rad(20.0)), 0, 60 * sin(deg_to_rad(20.0))),
		Vector2(150, 0),
		# Up the far side to the lip, 380 px up (128 px below the start).
		Vector3(60 * cos(deg_to_rad(20.0)), 0, -60 * sin(deg_to_rad(20.0))),
		Vector3(60 * cos(deg_to_rad(40.0)), 0, -60 * sin(deg_to_rad(40.0))),
		Vector3(60 * cos(deg_to_rad(60.0)), 0, -60 * sin(deg_to_rad(60.0))),
		# Nothing past it up here: a slow board drifts out over the drop to the wall.
		{width = 278.5 * cos(deg_to_rad(75.0)), rise = -278.5 * sin(deg_to_rad(75.0)), mark = "lip"},
		# The lower floor, 820 px down, from far left to under the U, ridden backward
		# (right to left) after the wall. Laid out left to right, so met in reverse: a
		# hump (a crest launch), a box ledge to slide, a rail to grind, then a kicker up to
		# a 120 px drop (a lip to pop, or a roll-off to catch) onto the flag's floor, long
		# enough for a full pop off it at top speed.
		{at = Vector2(-5700, 900), width = 2000, goal = 500},
		{width = 150, step = -120, rise = 40, mark = "back_kicker"},
		{width = 1600, rail = Vector3(300, 300, 45), mark = "back_rail"},
		{width = 1600, platform = [Vector2(300, 50), Vector2(600, 50)], mark = "back_ledge"},
		Vector3(150, 0, -150 * tan(deg_to_rad(7.0))),
		{width = 150, rise = 150 * tan(deg_to_rad(7.0)), mark = "back_hump"},
		Vector2(605.1, 0),
		# Round and up the 72° wall, to 450 px above the start: out of reach even of a full
		# pop off the lip at top speed (it comes down on the wall, not past it on the deck).
		Vector3(60 * cos(deg_to_rad(20.0)), 0, -60 * sin(deg_to_rad(20.0))),
		Vector3(60 * cos(deg_to_rad(40.0)), 0, -60 * sin(deg_to_rad(40.0))),
		Vector3(60 * cos(deg_to_rad(60.0)), 0, -60 * sin(deg_to_rad(60.0))),
		{width = 1218.6 * cos(deg_to_rad(72.0)), rise = -1218.6 * sin(deg_to_rad(72.0)), mark = "wall"},
		Vector2(300, 0),
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
	{id = "long_jump", name = "Long jump", start_y = 0.3, max_fall = 900, segments = [
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
	# Survival run through every obstacle kind. Heights stay inside the
	# screen (y between about 0.3 and 0.86 of the play area). Marks are for tests and bots.
	{id = "sketchy_1", name = "Sketchy #1", start_y = 0.6, challenge = true, segments = [
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
	# Rail yard: gaps that only rails cross, stair rails, downhill rails over drops.
	# Uphills after each descent bleed off the speed the frictionless rails add.
	{id = "sketchy_2", name = "Sketchy #2", start_y = 0.55, challenge = true, segments = [
		Vector2(600, 0),
		{width = 900, gap = 700, rail = [Vector2(-950, 70), Vector2(100, 70)], mark = "r1"},
		{width = 480, rise = 260, stairs = 8, rail = Vector3(-40, 520, 70), mark = "r2"},
		Vector2(700, 0),
		Vector3(1000, 0, -260),
		{width = 900, gap = 600, step = 180, rail = [Vector2(-850, 250), Vector2(80, 130)], mark = "r3"},
		Vector3(900, 0, -220),
		# The long one: a rail over a gap no ollie clears.
		{width = 900, gap = 1200, rail = [Vector2(-1450, 80), Vector2(150, 80)], mark = "r4"},
		{width = 600, step = -130, mark = "r5"},
		{width = 800, gap = 500, step = 120, rail = [Vector2(-750, 190), Vector2(100, 70)], mark = "r6"},
		{width = 460, rise = 260, stairs = 8, rail = Vector3(-40, 500, 70), mark = "r7"},
		Vector2(600, 0),
		Vector3(900, 0, -220),
		{width = 700, gap = 800, rail = [Vector2(-1050, 90), Vector2(100, 90)], mark = "r8"},
		Vector2(500, 0),
	]},
	# Rooftops: decks and boxes over gaps, islands at different heights, a kicker, high
	# ollies. No rails.
	{id = "sketchy_3", name = "Sketchy #3", start_y = 0.5, challenge = true, segments = [
		Vector2(600, 0),
		{width = 600, gap = 300, step = -60, mark = "a1"},
		{width = 700, gap = 700, platform = [Vector2(-900, 80), Vector2(80, 80)], deck = 30, mark = "a2"},
		{width = 800, gap = 450, platform = [Vector2(-650, 50), Vector2(-200, 50)], mark = "a3"},
		{width = 450, gap = 260, step = 40, mark = "a4"},
		{width = 450, gap = 260, step = -60, mark = "a5"},
		{width = 600, gap = 260, step = 40, mark = "a6"},
		{width = 600, step = -130, mark = "a7"},
		{width = 800, gap = 600, platform = [Vector2(-800, 100), Vector2(50, 0)], mark = "a8"},
		{width = 700, gap = 400, step = 200, mark = "a9"},
		Vector2(300, 0),
		Vector3(260, 0, -90),  # Kicker.
		{width = 700, gap = 380, step = 40, mark = "a10"},
		{width = 800, gap = 900, platform = [Vector2(-1100, 120), Vector2(100, 120)], deck = 30, mark = "a11"},
		Vector2(500, 0),
	]},
	# Bomb hill: downhills for speed, stair sets with no rail (clear them in one ollie),
	# landing ramps and islands where a fast board needs a softer pop.
	{id = "sketchy_4", name = "Sketchy #4", start_y = 0.3, challenge = true, segments = [
		Vector2(500, 0),
		Vector3(900, 0, 160),
		{width = 700, gap = 360, step = 30, mark = "b1"},
		{width = 500, rise = 280, stairs = 9, mark = "b2"},
		Vector2(700, 0),
		Vector3(1400, 0, -250),  # A long, gentle uphill: push.
		{width = 600, gap = 300, step = -40, rise = 120, mark = "b3"},
		Vector2(300, 0),
		{width = 500, gap = 260, mark = "b4"},
		{width = 500, gap = 260, mark = "b5"},
		Vector3(900, 0, -220),
		Vector3(800, 0, 150),
		{width = 450, rise = 240, stairs = 8, mark = "b6"},
		Vector2(600, 0),
		Vector3(1600, 0, -260),
		{width = 700, gap = 300, mark = "b7"},
		Vector2(500, 0),
	]},
	# Experimental: a vert ramp to drop into. An uphill bleeds the speed off, so the
	# board leaves the coping almost without horizontal speed and falls along a
	# near-vertical wall (rolling on just launches off it). A nollie keeps turning nose
	# down up to pop_spin_cap while the wall is still below; once a board passes 90°
	# the catch turns it back slowly (catch_slow_turn), so the catch is timed for it to
	# meet the wall's angle as it touches down. Then a kicker out of the bottom, over a
	# pit only a pop at its lip clears (about 10 frames, from just before it to
	# lip_pop_time after), landing on a gentle downhill. max_fall is raised so the
	# highest of those pops can land.
	{id = "vert", name = "Vert", start_y = 0.43, challenge = true, max_fall = 650, segments = [
		Vector2(300, 0),
		Vector3(350, 0, -55),
		{width = 3400 / tan(deg_to_rad(85.0)), rise = 3400, mark = "vert"},
		Vector3(40, 0, 40 * tan(deg_to_rad(65.0))),
		Vector3(50, 0, 50 * tan(deg_to_rad(45.0))),
		Vector3(60, 0, 60 * tan(deg_to_rad(25.0))),
		Vector3(70, 0, 70 * tan(deg_to_rad(5.0))),
		Vector2(1000, 0),
		# Kicker out of the bottom: 40° jumps furthest at the 12 m/s the drop gives (steeper
		# loses too much speed climbing it). Rolling off it falls short: pop at the lip.
		Vector3(20, 0, -20 * tan(deg_to_rad(15.0))),
		Vector3(20, 0, -20 * tan(deg_to_rad(30.0))),
		{width = 20, rise = -20 * tan(deg_to_rad(40.0)), mark = "kicker"},
		# Landing: gently downhill to soften the impact, still landable caught level.
		{width = 900, gap = 1050, rise = 900 * tan(deg_to_rad(14.0))},
		Vector2(400, 0),
	]},
]

static var current := "push"
## Furthest progress per level id (0..1; 1 = cleared), saved in PROGRESS_FILE. On the web,
## user:// lives in the browser's IndexedDB: Godot syncs it when a file is closed.
static var best := {}
static var _loaded := false
const PROGRESS_FILE := "user://progress.cfg"

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


static func get_level(id: String) -> Dictionary:
	for level in LIST:
		if level.id == id:
			return level
	return LIST[0]
