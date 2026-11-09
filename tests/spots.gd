extends SceneTree
## Spots and the map (see Spots, Goal, MapView), on a save file of their own
## (SKATELIKE_SPOTS_SAVE: the player's isn't touched):
## - Bridge, the first spot's stage, can be cleared: a bot pushes, pops the gaps, the step
##   up and the kicker's lip, and catches.
## - Goals and rewards: Bridge is open, School locked; meeting Bridge's "clear" goal
##   clears it and unlocks School (coming soon: not on the map), and that's saved.
## - The map: Map is the main menu's first item; Bridge is on it, School isn't; pressing
##   Bridge rides its stage with its goals watched; reaching the flag there meets the goal
##   and the map then says what it gave; the map's scroll is saved and restored.
## - Bridge's asset group (SpotArt): its stage has its own ground, every prop and
##   obstacle a level places exists and stands on its floor, and the game's backdrop is
##   Bridge's.
## - The stage: rolling off a small step down needs no catch (a big one still does); a
##   parked car slams a board rolling into it and is cleared popping off its kicker.

const SAVE := "user://test_spots.cfg"


## Rides Bridge with a bot; returns whether it reached the flag (and the slam if not).
func ride_bridge() -> Array:
	var r := TestUtil.runner(self, Levels.get_level("bridge"))
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
	var ride := ride_bridge()
	TestUtil.check("bridge: a bot clears it", ride[0], "slam '%s'" % ride[1])
	_check_art()
	_check_stage()
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
			and given == ["School unlocked (coming soon)"], str(given))
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
	TestUtil.check("map: Bridge on it, School not", bridge_button != null and map.get_node_or_null("Spot_school") == null)
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
	_clear_save()
	quit()


func _check_art() -> void:
	var r := TestUtil.runner(self, Levels.get_level("bridge"))
	TestUtil.check("art: Bridge's ground", r.art == "bridge" and r.fill_texture == SpotArt.fill("bridge")
			and r.edge_texture == SpotArt.edge("bridge") and r.fill_texture != null)
	var placed := 0
	var blocking := 0
	for s: Runner.Seg in r._segs:
		placed += s.props.size()
		blocking += s.obstacles.size()
	var wanted: int = Levels.get_level("bridge").get("start_props", []).size()
	var wanted_blocking := 0
	for segment in Levels.get_level("bridge").segments:
		if segment is Dictionary:
			wanted += segment.get("props", []).size()
			wanted_blocking += segment.get("obstacles", []).size()
	TestUtil.check("art: Bridge's props all placed", placed == wanted and wanted > 0, "%d of %d" % [placed, wanted])
	var tops := 0
	for platform: Dictionary in r._platforms:
		if platform.get("hidden", false):
			tops += 1
	TestUtil.check("art: Bridge's obstacles placed, each with a top to land on", blocking == wanted_blocking
			and blocking > 0 and tops == blocking, "%d of %d, %d tops" % [blocking, wanted_blocking, tops])
	r.queue_free()
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
	var backdrop := SpotArt.backdrop("bridge")
	TestUtil.check("art: Bridge's backdrop", backdrop.layers.size() == 3 and not backdrop.layers.has(null))


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


func _clear_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
