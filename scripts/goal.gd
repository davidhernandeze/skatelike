class_name Goal
extends RefCounted
## A goal of a spot's stage (see Spots), watched during a run: `reached` when it's met.
## A goal is a Dictionary:
##   id:       its name within the spot ("clear", "kickflip"...)
##   text:     how it reads ("Ride to the flag", "Land a kickflip")
##   required: clearing the spot needs it (the "clear" goal always is)
##   reward:   what meeting it gives, see Spots.reward()
## and what to do, one of:
##   clear = true                      reach the flag
##   trick = "kickflip"                land a trick named that (count = n times; match
##                                     "end" (default: the name, or ending in it, so a
##                                     "nollie kickflip" counts), "contains" or "starts")
##   line = n                          a line of n tricks (FlowButton)
##   speed = km/h                      reach that speed
## Adding a goal to a spot is adding one of these to its `goals` (with a reward).

signal reached

var spec: Dictionary
var met := false
var _landed := 0
var _runner: Runner


func _init(goal: Dictionary) -> void:
	spec = goal


## Watches `runner` (and `flow` for lines) until it's met.
func watch(runner: Runner, flow: FlowButton) -> void:
	_runner = runner
	if spec.get("clear", false):
		runner.level_cleared.connect(_reach)
	if spec.has("trick"):
		runner.line_event.connect(_on_line_event)
	if spec.has("line") and flow:
		flow.line_changed.connect(func(tricks: PackedStringArray, _ended: StringName) -> void:
			if tricks.size() >= spec.line:
				_reach())
	if spec.has("speed"):
		runner.speed_changed.connect(func(speed: float) -> void:
			if speed / runner.pixels_per_meter * 3.6 >= spec.speed:
				_reach())


func _on_line_event(air: String, balance: String, _wheels_down: bool) -> void:
	for name: String in [air, balance]:
		if name != "" and trick_matches(name, spec.trick, spec.get("match", "end")):
			_landed += 1
	if _landed >= spec.get("count", 1):
		_reach()


func _reach() -> void:
	if met:
		return
	met = true
	reached.emit()


## Whether a landed trick `name` counts as `trick`: matched by "end" (the name, or ending
## in it: "nollie 360 flip" counts as a 360 flip, a nollie isn't an ollie), "contains" or
## "starts".
static func trick_matches(name: String, trick: String, match_by := "end") -> bool:
	match match_by:
		"contains":
			return name.contains(trick)
		"starts":
			return name.begins_with(trick)
	return name == trick or name.ends_with(" " + trick)
