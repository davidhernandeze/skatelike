class_name Profile
extends RefCounted
## The player's profile, saved in FILE: a skater name of 3 letters and 2 digits
## (e.g. "DHZ07"), whether challenges show online ghosts, the board picked from
## Boards (graphic, grip and wheels ids) and the outfit picked from Outfits.

const FILE := "user://profile.cfg"
const DEFAULT_NAME := "SKT01"
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS := "0123456789"

static var skater_name := DEFAULT_NAME
## The Challenges page's online switch.
static var online := false
## The board: ids from Boards.GRAPHICS, Boards.GRIPS and Boards.WHEELS.
static var board_graphic: String = Boards.GRAPHICS[0].id
static var board_grip: String = Boards.GRIPS[0].id
static var board_wheels: String = Boards.WHEELS[0].id
## The outfit: slot -> Outfits item id (Outfits.SLOTS).
static var outfit: Dictionary = Outfits.default_outfit()
static var _loaded := false


static func is_valid(skater: String) -> bool:
	if skater.length() != 5:
		return false
	for i in 5:
		if not (LETTERS if i < 3 else DIGITS).contains(skater[i]):
			return false
	return true


## Characters allowed at position i of the name.
static func charset(i: int) -> String:
	return LETTERS if i < 3 else DIGITS


static func set_skater_name(skater: String) -> void:
	if not is_valid(skater):
		return
	skater_name = skater
	_save()


static func set_online(on: bool) -> void:
	online = on
	_save()


## Picks a board part: `part` is "graphic", "grip" or "wheels", `id` one of its ids.
static func set_board_part(part: String, id: String) -> void:
	match part:
		"graphic":
			board_graphic = Boards.find(Boards.GRAPHICS, id).id
		"grip":
			board_grip = Boards.find(Boards.GRIPS, id).id
		"wheels":
			board_wheels = Boards.find(Boards.WHEELS, id).id
	_save()


## Puts on an item: `slot` one of Outfits.SLOTS, `id` one of its items.
static func set_outfit_part(slot: String, id: String) -> void:
	if not Outfits.SLOTS.has(slot):
		return
	outfit[slot] = Outfits.find(slot, id).id
	_save()


static func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("profile", "name", skater_name)
	file.set_value("profile", "online", online)
	file.set_value("board", "graphic", board_graphic)
	file.set_value("board", "grip", board_grip)
	file.set_value("board", "wheels", board_wheels)
	for slot in Outfits.SLOTS:
		file.set_value("outfit", slot, outfit[slot])
	file.save(FILE)


static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(FILE) == OK:
		var saved: String = file.get_value("profile", "name", DEFAULT_NAME)
		if is_valid(saved):
			skater_name = saved
		online = file.get_value("profile", "online", false)
		# Unknown ids (a part since removed) fall back to the default.
		board_graphic = Boards.find(Boards.GRAPHICS, file.get_value("board", "graphic", "")).id
		board_grip = Boards.find(Boards.GRIPS, file.get_value("board", "grip", "")).id
		board_wheels = Boards.find(Boards.WHEELS, file.get_value("board", "wheels", "")).id
		for slot in Outfits.SLOTS:
			outfit[slot] = Outfits.find(slot, file.get_value("outfit", slot, "")).id
