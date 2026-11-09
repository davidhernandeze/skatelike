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
| `spots.gd` | Spots and the map: a bot clears Bridge; its "clear" goal unlocks School (coming soon) and is saved; Map is the main menu's first item; Bridge is on the map, School isn't; pressing Bridge rides its stage with its goal watched; the flag meets it and the map says what it gave; the map's scroll is saved and restored. Bridge's asset group: its own ground, every prop a level places exists and is placed, its backdrop behind its stage; obstacles placed with tops to land on. The stage: small drops need no catch (big ones still do); rolling into a parked car slams, popping off its kicker clears it. |
| `game_scene.gd` | The real scene with its views and UI: the profile's stance picker (Goofy saved, the next rider goofy); a held pop slid sideways shows its aim and pops on the lift; board and skater views; flow unrestricted on free rides only; restart; balance pops (landing finger or a second finger) waiting for the lift with their aim; the menu (Map first, lists gliding after a fling). |

`test_util.gd` (class `TestUtil`) has the helpers: a runner without the scene, PASS /
FAIL lines, and where a full pop would come down.
