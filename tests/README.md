# Tests

Headless checks of the game's behaviour, run with Godot from the command line:

```
tests/run.sh                 # all of them
tests/run.sh mirror replay   # some
GODOT=/path/to/godot tests/run.sh
```

Each test prints `PASS name` or `FAIL name: why`; `run.sh` sums them up and exits
non-zero on any failure (or a script error). Scoreboard calls go nowhere
(`SKATELIKE_API_URL` points at a closed port). The player's saves (from playing in the
editor) are copied aside before the run and put back after it, and spot progress uses a
test file of its own (`SKATELIKE_SPOTS_SAVE`). The folder is left out of exports (`exclude_filter` in `export_presets.cfg`).

| Test | What it checks |
|---|---|
| `mirror.gd` | The ground code works the same both ways: 12 features (crests, roll-offs, walls, too-steep bends, kicker lips, ledge slides, rail grinds, rolling back, a steep-lip launch) built forward and as their mirror image, ridden forward and backward with mirrored inputs, must match step for step. |
| `backward_course.gd` | The transfer's landing stance (fakie; with a 180 in the air, the original stance), and Transfer end to end: the transfer to fakie, then the lower floor ridden backward (hump hop, fakie tailslide, fakie nosegrind, the kicker popped or rolled off) to the flag. |
| `trick_names.gd` | Stance and names: regular and goofy (frontside/backside, which way the skater faces); switch after 180s; fakie tricks chaining off the tail, a nose pop or a push out of fakie to switch, manuals out of fakie as switch manuals; half cab and fakie frontside 180 back to the original stance (the skater turned around), full cab staying fakie; 360s; a late catch settling back on the 180; a twisted pop barely tipping the board. |
| `replay.gd` | Determinism for online ghosts: a seeded random bot's run replayed from its actions, from the start and from a snapshot halfway (set_state), must match every snapshot. |
| `spots.gd` | Spots and the map: a bot clears each spot's stage (Bridge, School) and each has its asset group (ground, props, obstacles with tops to land on, backdrop, icon); small drops need no catch, rolling into a parked car slams and popping off its kicker clears it; spots unlock in order, a spot added later opening for a player who cleared the one before it (older saves keep theirs); Map is the main menu's first item, Bridge and School on it (School locked); Bridge rides its stage with its goal and backdrop, its flag unlocks School, the map says so; School rides its stage and its flag clears it; the map's scroll is saved and restored. |
| `practice.gd` | Practice: the menu (Practice is Learn, then Stairs and Flat; Learn is Mechanics and Tricks; Tricks lists the four trick lessons, Mechanics the others); a practice stage has no goals and starts again at its flag; a bot rides Stairs; each trick lesson's trick lands and meets its goal (a front shuvit isn't a shuvit). |
| `game_scene.gd` | The real scene with its views and UI: the profile's stance picker (Goofy saved, the next rider goofy); a held pop slid sideways shows its aim and pops on the lift; board and skater views; flow unrestricted on free rides only; restart; balance pops (landing finger or a second finger) waiting for the lift with their aim; the menu (Map first, lists gliding after a fling). |

`test_util.gd` (class `TestUtil`) has the helpers: a runner without the scene, PASS /
FAIL lines, and where a full pop would come down.
