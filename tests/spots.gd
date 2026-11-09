extends SceneTree
## Spots and the map (see Spots, Goal, MapView), on a save file of their own
## (SKATELIKE_SPOTS_SAVE: the player's isn't touched):
## - Each spot's stage (Bridge, School) can be cleared by a bot (it pushes, pops the gaps,
##   steps up, stairs and kicker lips, and catches), and has its asset group (SpotArt):
##   its own ground, props and obstacles placed (each obstacle with a top to land on), its
##   backdrop and map icon; every prop a level places exists.
## - The stage: rolling off a small step down needs no catch (a big one still does); a
##   parked car slams a board rolling into it and is cleared popping off its kicker.
## - Unlocking in order (_check_unlock_order): a spot added later opens for a player who
##   cleared the one before it, and older saves keep what they unlocked.
## - Goals and rewards: Bridge is open, School locked; meeting Bridge's "clear" goal
##   clears it and unlocks School, and that's saved.
## - The map: Map is the main menu's first item; Bridge and School are on it (School the
##   next slot up, locked); pressing Bridge rides its stage with its goals watched and its
##   backdrop; reaching the flag there meets the goal and the map then says what it gave;
##   School is open then, rides its stage, and its flag clears it. The map's scroll is
##   saved and restored.

const SAVE := "user://test_spots.cfg"


## Rides a spot's stage with a bot; returns whether it reached the flag (and the slam if
## not).
func ride_spot(level_id: String) -> Array:
	var r := TestUtil.runner(self, Levels.get_level(level_id))
	var out := {slam = ""}
	r.slammed.connect(func(s): out.slam = s)
	var tapped := false
	for tick in 120 * 60:
		if r._grounded and not r._in_trick and not r.is_pushing() and r._speed < 6.5 * r.pixels_per_meter \
				and not _hazard_near(r, 500.0):
			r.act(Runner.Act.PUSH, 1.0)
		if r._grounded and r.can_pop():
			var target := _pop_target(r)
			if not target.is_empty():
				var land := TestUtil.pop_landing(r, target.top)
				if not is_nan(land) and land > target.from + 40.0 and land < target.from + 260.0:
					r.act(Runner.Act.POP, 0.0, 1.0)
		if r._lip_t > 0.0 and r.can_pop():
			r.act(Runner.Act.POP, 0.0, 1.0)  # The kicker's lip: pop it.
		if r._in_trick and r._needs_catch and r._catches == 0 and r._velocity_y > 0.0 and not tapped:
			tapped = true
			r.act(Runner.Act.PRESS_CATCH, 0.0)
			r.act(Runner.Act.RELEASE_CATCH)
		if not r._in_trick:
			tapped = false
		r.step()
		if r._cleared or r._dead:
			break
	var result := [r._cleared, out.slam]
	r.queue_free()
	return result


## The floor the board must pop onto ahead, if its own ends at a gap or a step up:
## {from (x where it starts), top (its height)}.
func _pop_target(r: Runner) -> Dictionary:
	var s: Runner.Seg = r._support
	var stairs: Runner.Seg = r._continuation(s)
	if stairs != null and stairs.stairs > 0 and stairs.next != null:
		# Stairs ahead: ollie them, onto the floor at their foot.
		return {from = stairs.x1, top = stairs.next.y_at(stairs.x1 + 100.0)}
	if r._continuation(s) != null or s == r._segs.back():
		return {}
	var next: Runner.Seg = null
	for other: Runner.Seg in r._segs:
		if other != s and other.x0 >= s.x1 - 1.0 and (next == null or other.x0 < next.x0):
			next = other
	if next == null:
		return {}
	if next.y0 < s.y1 - 1.0 or next.x0 - s.x1 > 1.0:
		return {from = next.x0, top = next.y_at(next.x0 + 100.0)}
	return {}


func _hazard_near(r: Runner, dist: float) -> bool:
	var s: Runner.Seg = r._support
	return r._continuation(s) == null and s.x1 - r._pos.x < dist


func _initialize():
	OS.set_environment("SKATELIKE_SPOTS_SAVE", SAVE)  # Not the player's progress.
	_clear_save()
	Spots.reload()
	# The stage.
	for spot: Dictionary in Spots.LIST:
		if spot.level != "":
			var ride := ride_spot(spot.level)
			TestUtil.check("%s: a bot clears it" % spot.id, ride[0], "slam '%s'" % ride[1])
			_check_art(spot)
	_check_props_exist()
	_check_stage()
	await _check_unlock_order()
	_clear_save()
	Spots.reload()
	# Goals and rewards.
	TestUtil.check("progress: Bridge open, School locked", Spots.is_unlocked("bridge") and not Spots.is_unlocked("school"))
	var r := TestUtil.runner(self, Levels.get_level("bridge"))
	var goal := Goal.new(Spots.find("bridge").goals[0])
	goal.watch(r, null)
	var given := []  # Filled by the lambda (it can't assign the variable itself).
	goal.reached.connect(func() -> void: given.append_array(Spots.meet("bridge", "clear")))
	r.level_cleared.emit()
	r.queue_free()
	TestUtil.check("goals: reaching the flag meets 'clear'", goal.met and Spots.is_met("bridge", "clear"))
	TestUtil.check("rewards: clearing Bridge unlocks School", Spots.is_cleared("bridge") and Spots.is_unlocked("school")
			and given == ["School unlocked"], str(given))
	TestUtil.check("rewards: given once", Spots.meet("bridge", "clear").is_empty())
	Spots.reload()
	TestUtil.check("progress: saved", Spots.is_cleared("bridge") and Spots.is_unlocked("school"))
	TestUtil.check("goals: a trick goal's matching", Goal.trick_matches("nollie kickflip", "kickflip")
			and not Goal.trick_matches("kickflip", "flip") and Goal.trick_matches("frontside flip", "side flip", "contains"))
	# The map, from a fresh save.
	_clear_save()
	Spots.reload()
	change_scene_to_file("res://scenes/menu.tscn")
	for i in 10: await process_frame
	var m = current_scene
	m._show("main")
	await process_frame
	var first := ""
	for b in m.list.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			first = b.text
			break
	TestUtil.check("menu: Map first", first == "Map", "first '%s'" % first)
	m._show("map")
	for i in 5: await process_frame
	var map: MapView = m.list.find_children("*", "MapView", true, false)[0] if not m.list.find_children("*", "MapView", true, false).is_empty() else null
	var bridge_button: Button = map.get_node_or_null("Spot_bridge") if map else null
	var school_button: Button = map.get_node_or_null("Spot_school") if map else null
	TestUtil.check("map: Bridge and School on it, School locked", bridge_button != null and not bridge_button.disabled
			and school_button != null and school_button.disabled)
	TestUtil.check("map: School next up the route, close by", map.spot_center("school").y < map.spot_center("bridge").y
			and map.spot_center("bridge").y - map.spot_center("school").y <= MapView.SECTION_H / 4 * UiKit.PIXEL)
	TestUtil.check("map: opens at the bottom", m.scroll.scroll_vertical > 0
			and m.scroll.scroll_vertical >= int(m.scroll.get_v_scroll_bar().max_value - m.scroll.get_v_scroll_bar().page) - 1)
	m.scroll.scroll_vertical = 40
	await process_frame
	m._show("main")  # Leaving the map saves where it was.
	# Read from the file itself: a static variable read straight from this script can be
	# stale (a Godot quirk with -s scripts).
	var saved := ConfigFile.new()
	saved.load(SAVE)
	TestUtil.check("map: scroll saved", saved.get_value("map", "scroll", -1) == 40, str(saved.get_value("map", "scroll", -1)))
	m._show("map")
	for i in 5: await process_frame
	TestUtil.check("map: opens where it was left", m.scroll.scroll_vertical == 40, str(m.scroll.scroll_vertical))
	map = m.list.find_children("*", "MapView", true, false)[0]
	map.get_node("Spot_bridge").pressed.emit()
	for i in 10: await process_frame
	var game = current_scene
	TestUtil.check("map: Bridge rides its stage", game.has_method("pause") and Levels.current == "bridge"
			and Spots.current == "bridge" and game._goals.size() == 1)
	var backdrops: Array = game.find_children("*", "ParallaxBackdrop", true, false)
	TestUtil.check("stage: Bridge's backdrop behind it", backdrops.size() == 1
			and backdrops[0].layers == SpotArt.backdrop("bridge").layers)
	game.runner.level_cleared.emit()  # The flag.
	await process_frame
	TestUtil.check("stage: the flag meets the goal", Spots.is_cleared("bridge") and Spots.is_unlocked("school"))
	for i in 120: await process_frame  # Back to the menu.
	m = current_scene
	var news := false
	for label in m.list.find_children("*", "Label", true, false):
		if label.text.contains("School unlocked"): news = true
	TestUtil.check("map: says what the run gave", m.page == "map" and news, "page '%s'" % m.page)
	# Then School: open now, ridden from the map, cleared at its flag.
	await process_frame
	map = m.list.find_children("*", "MapView", true, false)[0]
	school_button = map.get_node("Spot_school")
	TestUtil.check("map: School open after Bridge", not school_button.disabled)
	school_button.pressed.emit()
	for i in 10: await process_frame
	game = current_scene
	TestUtil.check("map: School rides its stage", game.has_method("pause") and Levels.current == "school"
			and Spots.current == "school" and game._goals.size() == 1)
	game.runner.level_cleared.emit()
	await process_frame
	TestUtil.check("stage: School's flag clears it", Spots.is_cleared("school"))
	_clear_save()
	quit()


## A spot's stage has its asset group: ground, props and obstacles placed (each obstacle
## with a top), backdrop, map icon.
func _check_art(spot: Dictionary) -> void:
	var level := Levels.get_level(spot.level)
	var art: String = level.get("art", "")
	var r := TestUtil.runner(self, level)
	TestUtil.check("art: %s's ground" % spot.id, art != "" and r.art == art and r.fill_texture == SpotArt.fill(art)
			and r.edge_texture == SpotArt.edge(art) and r.fill_texture != null)
	var placed := 0
	var blocking := 0
	for s: Runner.Seg in r._segs:
		placed += s.props.size()
		blocking += s.obstacles.size()
	var wanted: int = level.get("start_props", []).size()
	var wanted_blocking := 0
	for segment in level.segments:
		if segment is Dictionary:
			wanted += segment.get("props", []).size()
			wanted_blocking += segment.get("obstacles", []).size()
	TestUtil.check("art: %s's props all placed" % spot.id, placed == wanted and wanted > 0, "%d of %d" % [placed, wanted])
	var tops := 0
	for platform: Dictionary in r._platforms:
		if platform.get("hidden", false):
			tops += 1
	TestUtil.check("art: %s's obstacles placed, each with a top to land on" % spot.id, blocking == wanted_blocking
			and blocking > 0 and tops == blocking, "%d of %d, %d tops" % [blocking, wanted_blocking, tops])
	r.queue_free()
	var backdrop := SpotArt.backdrop(art)
	TestUtil.check("art: %s's backdrop and icon" % spot.id, backdrop.layers.size() == 3 and not backdrop.layers.has(null)
			and ResourceLoader.exists(spot.landmark))


func _check_props_exist() -> void:
	var missing := []
	for level: Dictionary in Levels.LIST:
		var props: Array = level.get("start_props", []).duplicate()
		for segment in level.segments:
			if segment is Dictionary:
				props.append_array(segment.get("props", []))
				props.append_array(segment.get("obstacles", []))
		for prop: Array in props:
			if not ResourceLoader.exists(SpotArt.DIR % level.get("art", "") + "props/%s.png" % prop[0]):
				missing.append("%s: %s" % [level.id, prop[0]])
	TestUtil.check("art: every prop a level places exists", missing.is_empty(), str(missing))


## Rolls `level` from its start, pushing up to `speed` (m/s) but not near `mark` (that
## far before it), popping at a kicker's lip if `pop` (and catching); returns {slam, cleared, past
## (whether it got past `mark`'s end)}.
func _roll(level: Dictionary, speed: float, pop := false, mark := "") -> Dictionary:
	var r := TestUtil.runner(self, level)
	var out := {slam = "", cleared = false, past = false}
	r.slammed.connect(func(s): out.slam = s)
	for tick in 120 * 20:
		var near: bool = mark != "" and r.marks.has(mark) and r.marks[mark].x - r._pos.x < 300.0
		if r._grounded and not r.is_pushing() and r._speed < speed * r.pixels_per_meter and not near:
			r.act(Runner.Act.PUSH, 1.0)
		if pop and r._lip_t > 0.0 and r.can_pop():
			r.act(Runner.Act.POP, 0.0, 1.0)
		if pop and r._in_trick and r._needs_catch and r._catches == 0 and r._velocity_y > 0.0:
			r.act(Runner.Act.PRESS_CATCH, 0.0)  # Catch it on the way down.
			r.act(Runner.Act.RELEASE_CATCH)
		r.step()
		if mark != "" and r.marks.has(mark) and r._pos.x > r.marks[mark].y and r._grounded:
			out.past = true
		if r._dead or r._cleared or out.past:
			break
	out.cleared = r._cleared
	r.queue_free()
	return out


func _check_stage() -> void:
	for drop in [40.0, 80.0, 160.0]:
		var level := {id = "drop", segments = [Vector2(800, 0), {width = 800, step = drop, mark = "low"},
			Vector2(800, 0)]}
		var ride := _roll(level, 4.0, false, "")
		if drop <= 90.0:
			TestUtil.check("stage: a %d px drop rolled off, no catch needed" % drop, ride.cleared, ride.slam)
		else:
			TestUtil.check("stage: a %d px drop still needs a catch" % drop, ride.slam == "no catch", ride.slam)
	# From the car's kicker on.
	var bridge := Levels.get_level("bridge")
	var from := 0
	for i in bridge.segments.size():
		if bridge.segments[i] is Dictionary and bridge.segments[i].get("mark", "") == "car_kicker":
			from = i - 2
	var level := {id = "car", art = "bridge", segments = [Vector2(300, 0)] + bridge.segments.slice(from)}
	var hit := _roll(level, 6.5, false, "car")
	TestUtil.check("stage: rolling into the car slams", hit.slam == "hit an obstacle", hit.slam)
	var jump := _roll(level, 6.5, true, "car")
	TestUtil.check("stage: popping off the kicker clears the car", jump.past and jump.slam == "", jump.slam)


## Spots unlock in order, a new spot opening for a player who cleared the one before it:
## - Bridge cleared before School existed (that save has only "bridge/clear" met):
##   School is open once it's added, on the map too.
## - A save from when Bridge unlocked School by id: still open.
## - A spot added after School: open for a player who cleared School, not before.
func _check_unlock_order() -> void:
	_write_save(["bridge/clear"], [])
	Spots.reload()
	TestUtil.check("unlock: School open for a player who cleared Bridge before School existed",
			Spots.is_unlocked("school") and not Spots.is_cleared("school"))
	var map := MapView.new()
	root.add_child(map)
	await process_frame
	TestUtil.check("unlock: ...and its map button works", not map.get_node("Spot_school").disabled)
	map.queue_free()
	_write_save(["bridge/clear"], ["school"])
	Spots.reload()
	TestUtil.check("unlock: an older save (School unlocked by id) keeps it open", Spots.is_unlocked("school"))
	var later: Array = Spots.LIST + [{id = "plaza", name = "Plaza", level = "", map = {}, landmark = "", goals = []}]
	TestUtil.check("unlock: a spot added later is locked until School is cleared", not Spots.unlocked_in(later, "plaza"))
	var next := Array(Spots.meet("school", "clear"))
	TestUtil.check("unlock: clearing the last spot says the next is coming", next == ["Next spot coming soon"], str(next))
	TestUtil.check("unlock: a spot added later is open for a player who cleared School", Spots.unlocked_in(later, "plaza"))
	_write_save([], [])
	Spots.reload()
	TestUtil.check("unlock: a fresh save has only Bridge open", Spots.is_unlocked("bridge")
			and not Spots.is_unlocked("school") and not Spots.unlocked_in(later, "plaza"))


## A spots save file with these goals met and spots unlocked, as any version wrote it.
func _write_save(met: Array, unlocked: Array) -> void:
	var file := ConfigFile.new()
	file.set_value("progress", "met", met)
	file.set_value("progress", "unlocked", unlocked)
	file.save(SAVE)


func _clear_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
