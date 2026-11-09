class_name Spots
extends RefCounted
## The spots on the city map (the map screen, MapView): each a stage (a level of Levels,
## with `spot = true` so it isn't listed under Practice) with goals and their rewards.
## Spots unlock in order: the first is open, each next one when the one before it gives
## its `{unlock = "next"}` reward (clearing it). That holds for a spot added later too:
## a player who cleared the last spot finds the new one already open. A spot entry:
##   id, name
##   level:    the stage's level id ("" for a spot still to come)
##   map:      where it is on the map, {section (0 at the bottom, counting up; four
##             spots each), at (its icon's top left, art px in its section: one of
##             MapView.SLOTS, in order), river (a river runs under it, bridged by the
##             streets)}; empty: not on the map yet
##   landmark: its icon on the map (a standalone sprite, floating over the paper)
##   goals:    Goal entries; the "clear" goal (reach the flag) is required and clears it
## Rewards (a goal's `reward`): {unlock = "next"} (the next spot in LIST, now or once
## it's added), {unlock = spot id}. More kinds come with the profile's items.
##
## Progress (goals met, spots unlocked) and the map's scroll position are saved in
## save_file(), apart from the levels' best progress (Levels).

const LIST := [
	{id = "bridge", name = "Bridge", level = "bridge",
		map = {section = 0, at = MapView.SLOTS[0], river = true}, landmark = "res://assets/spots/bridge/icon.png",
		goals = [
			{id = "clear", clear = true, required = true, text = "Ride to the flag", reward = {unlock = "next"}},
		]},
	{id = "school", name = "School", level = "school",
		map = {section = 0, at = MapView.SLOTS[1]}, landmark = "res://assets/spots/school/icon.png",
		goals = [
			{id = "clear", clear = true, required = true, text = "Ride to the flag", reward = {unlock = "next"}},
		]},
]

const SAVE_PATH := "user://spots.cfg"
## The spot whose stage is being ridden ("" for a level started from Practice).
static var current := ""
## Goals met: "spot/goal" -> true; spots unlocked by rewards; the map's scroll (px, -1:
## never scrolled: it opens at the bottom).
static var _met := {}
static var _unlocked := {}
static var map_scroll := -1
static var _loaded := false
## What the last run gave (goals met, rewards), for the map to show; it clears them.
static var news := PackedStringArray()


static func find(id: String) -> Dictionary:
	for spot: Dictionary in LIST:
		if spot.id == id:
			return spot
	return {}


## The spots drawn on the map (those with a `map` entry), in order.
static func on_map() -> Array:
	return LIST.filter(func(spot: Dictionary) -> bool: return not spot.map.is_empty())


## How many sections the map has: up to the highest one with a spot.
static func sections() -> int:
	var top := 0
	for spot: Dictionary in on_map():
		top = maxi(top, spot.map.section)
	return top + 1


static func is_unlocked(id: String) -> bool:
	return unlocked_in(LIST, id)


## Whether spot `id` of `spots` (LIST, or another list for tests) is open: the first one,
## one a reward unlocked by id, or the one after a spot whose met goal unlocks "next".
static func unlocked_in(spots: Array, id: String) -> bool:
	load_progress()
	for i in spots.size():
		if spots[i].id != id:
			continue
		if i == 0 or _unlocked.has(id):
			return true
		var before: Dictionary = spots[i - 1]
		for goal: Dictionary in before.get("goals", []):
			if goal.get("reward", {}).get("unlock", "") == "next" and _met.has(before.id + "/" + goal.id):
				return true
	return false


static func is_met(spot_id: String, goal_id: String) -> bool:
	load_progress()
	return _met.has(spot_id + "/" + goal_id)


## Cleared: every required goal met.
static func is_cleared(spot_id: String) -> bool:
	var spot := find(spot_id)
	if spot.is_empty():
		return false
	for goal: Dictionary in spot.goals:
		if goal.get("required", false) and not is_met(spot_id, goal.id):
			return false
	return true


## Records a goal met and gives its reward (once); returns what it gave, as lines to show
## ("School unlocked"), empty if it was met before.
static func meet(spot_id: String, goal_id: String) -> PackedStringArray:
	load_progress()
	var key := spot_id + "/" + goal_id
	if _met.has(key):
		return PackedStringArray()
	_met[key] = true
	var given := PackedStringArray()
	for goal: Dictionary in find(spot_id).get("goals", []):
		if goal.id == goal_id and goal.has("reward"):
			given = reward(goal.reward, spot_id)
	save_progress()
	return given


## Gives a reward (a goal of spot `from`'s); returns what it gave, as lines to show. The
## "next" unlock needs nothing saved: it follows from the goal being met (unlocked_in).
static func reward(spec: Dictionary, from := "") -> PackedStringArray:
	var given := PackedStringArray()
	if spec.has("unlock"):
		var id: String = spec.unlock
		if id == "next":
			var i := LIST.find(find(from))
			id = LIST[i + 1].id if i >= 0 and i + 1 < LIST.size() else ""
		else:
			_unlocked[id] = true
		var spot := find(id)
		if spot.is_empty() or spot.get("map", {}).is_empty():
			given.append("Next spot coming soon" if spec.unlock == "next" else "%s unlocked (coming soon)" % spec.unlock)
		else:
			given.append("%s unlocked" % spot.name)
	return given


static func set_map_scroll(px: int) -> void:
	load_progress()
	map_scroll = px


static func load_progress() -> void:
	if _loaded:
		return
	_loaded = true
	_met.clear()
	_unlocked.clear()
	map_scroll = -1
	var file := ConfigFile.new()
	if file.load(save_file()) != OK:
		return
	for key in file.get_value("progress", "met", []):
		_met[key] = true
	for id in file.get_value("progress", "unlocked", []):
		_unlocked[id] = true
	map_scroll = file.get_value("map", "scroll", -1)


static func save_progress() -> void:
	var file := ConfigFile.new()
	file.set_value("progress", "met", _met.keys())
	file.set_value("progress", "unlocked", _unlocked.keys())
	file.set_value("map", "scroll", map_scroll)
	file.save(save_file())


## Forgets what was loaded and loads again.
static func reload() -> void:
	_loaded = false
	load_progress()


## Where progress is saved: SAVE_PATH, or SKATELIKE_SPOTS_SAVE when set (tests, so the
## player's progress isn't touched).
static func save_file() -> String:
	var override := OS.get_environment("SKATELIKE_SPOTS_SAVE")
	return override if override != "" else SAVE_PATH
