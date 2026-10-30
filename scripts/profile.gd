class_name Profile
extends RefCounted
## The player's profile, saved in FILE: a skater name of 3 letters and 2 digits
## (e.g. "DHZ07") and whether challenges show online ghosts.

const FILE := "user://profile.cfg"
const DEFAULT_NAME := "SKT01"
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS := "0123456789"

static var skater_name := DEFAULT_NAME
## The Challenges page's online switch.
static var online := false
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


static func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("profile", "name", skater_name)
	file.set_value("profile", "online", online)
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
