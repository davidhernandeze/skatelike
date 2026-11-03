class_name Sfx
extends Node
## Board sounds, played from the Runner's signals and state: pops, catches, landings
## (heavier the harder the board comes down), slams, and two loops faded in and out every
## frame, rolling (louder and higher the faster the board goes) and grinding (on rails
## and ledges). A child of the Runner, so it pauses with the game. In flow state's slow
## motion the sounds slow down too.
##
## Clips cut from "Skateboarding Tricks" by SoundBiterSFX (freesound.org/s/746602),
## CC BY 4.0.

const POP := preload("res://assets/sfx/pop.wav")
const LAND := preload("res://assets/sfx/land.wav")
const LAND_HEAVY := preload("res://assets/sfx/land_heavy.wav")
const CATCH := preload("res://assets/sfx/catch.wav")
const SLAM := preload("res://assets/sfx/slam.wav")
const ROLL := preload("res://assets/sfx/roll_loop.wav")
const GRIND := preload("res://assets/sfx/grind_loop.wav")

## Speed into the surface at touchdown (px/s) for the loudest landing, and from which a
## landing uses the heavy hit.
@export var hard_landing := 1500.0
@export var heavy_landing := 1300.0
## Rolling is loudest from this speed (m/s), and pitched up this much per m/s.
@export var loud_speed := 8.0
@export var roll_pitch_per_speed := 0.04
## How fast the loops fade in and out (volume fraction per second).
@export var loop_fade := 6.0
@export var volume_db := -2.0

var runner: Runner
var _roll: AudioStreamPlayer
var _grind: AudioStreamPlayer
var _shots: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_roll = _player(ROLL)
	_grind = _player(GRIND)
	for i in 6:
		_shots.append(_player(null))
	runner.popped.connect(func(_nose: bool, strength: float) -> void:
		_play(POP, lerpf(-6.0, 0.0, clampf((strength - runner.min_pop) / (1.0 - runner.min_pop), 0.0, 1.0))))
	runner.caught.connect(func(catch_index: int, _angle: float, _apex: int) -> void:
		if catch_index == 1:
			_play(CATCH, -4.0))
	runner.landed.connect(_on_landed)
	runner.slammed.connect(func(_reason: String) -> void:
		_play(SLAM, 0.0))


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	if stream != null:
		player.volume_db = -80.0
		player.play()  # Loops run all the time, faded in and out.
	return player


## Plays a one-shot on a free player (or the one that's been going longest).
func _play(stream: AudioStream, db: float, pitch := 1.0) -> void:
	var player := _shots[0]
	for candidate in _shots:
		if not candidate.playing:
			player = candidate
			break
	_shots.erase(player)
	_shots.append(player)
	player.stream = stream
	player.volume_db = volume_db + db
	player.pitch_scale = pitch * Engine.time_scale
	player.play()


func _on_landed(style: String) -> void:
	if style == "to manual":
		return  # Rolling off a ledge into a manual: no touchdown.
	var into := absf(runner._impact.y)  # Vertical speed at touchdown.
	var k := clampf(into / hard_landing, 0.0, 1.0)
	var db := lerpf(-14.0, 0.0, k)
	if style.contains("grind") or style.contains("slide"):
		db -= 3.0  # Onto a rail or ledge: the grind loop carries it.
	_play(LAND_HEAVY if into >= heavy_landing else LAND, db, randf_range(0.95, 1.05))


func _process(delta: float) -> void:
	var alive := not runner._dead
	var grinding := alive and runner.is_grinding()
	var rolling := alive and runner.is_grounded() and not grinding
	var speed := runner._speed / runner.pixels_per_meter
	var loud := clampf(speed / loud_speed, 0.15, 1.0)
	_fade(_roll, loud if rolling else 0.0, delta)
	_fade(_grind, loud if grinding else 0.0, delta)
	_roll.pitch_scale = maxf(0.7 + roll_pitch_per_speed * speed, 0.5) * Engine.time_scale
	_grind.pitch_scale = maxf(0.85 + roll_pitch_per_speed * 0.5 * speed, 0.5) * Engine.time_scale


## Moves a loop's volume toward `level` (0..1).
func _fade(player: AudioStreamPlayer, level: float, delta: float) -> void:
	var now := db_to_linear(player.volume_db - volume_db) if player.volume_db > -79.0 else 0.0
	now = move_toward(now, level, loop_fade * delta)
	player.volume_db = volume_db + linear_to_db(now) if now > 0.001 else -80.0
