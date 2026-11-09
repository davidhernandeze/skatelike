# Tests

Headless checks of the game's behaviour, run with Godot from the command line:

```
tests/run.sh                 # all of them
tests/run.sh mirror replay   # some
GODOT=/path/to/godot tests/run.sh
```

Each test prints `PASS name` or `FAIL name: why`; `run.sh` sums them up and exits
non-zero on any failure (or a script error). Scoreboard calls go nowhere
(`SKATELIKE_API_URL` points at a closed port), and the saves the runs leave behind are
deleted. The folder is left out of exports (`exclude_filter` in `export_presets.cfg`).

| Test | What it checks |
|---|---|
| `mirror.gd` | The ground code works the same both ways: 12 features (crests, roll-offs, walls, too-steep bends, kicker lips, ledge slides, rail grinds, rolling back, a steep-lip launch) built forward and as their mirror image, ridden forward and backward with mirrored inputs, must match step for step. |
| `backward_course.gd` | Transfer end to end: the transfer to fakie, then the lower floor ridden backward (hump hop, fakie tailslide, fakie nosegrind, the kicker popped or rolled off) to the flag. |
| `trick_names.gd` | Names by stance: ollie / nollie / switch forward; fakie ollie, switch ollie (off the tail), half cab, full cab, fakie frontside 180 rolling backward; 360s; a late catch settling back on the 180; a twisted pop barely tipping the board. |
| `replay.gd` | Determinism for online ghosts: a seeded random bot's run replayed from its actions, from the start and from a snapshot halfway (set_state), must match every snapshot. |
| `game_scene.gd` | The real scene with its views and UI: a held pop slid sideways shows its aim and pops on the lift; board and skater views; flow unrestricted on free rides only; restart; balance pops (landing finger or a second finger) waiting for the lift with their aim; the menu (Gaps first, lists gliding after a fling). |

`test_util.gd` (class `TestUtil`) has the helpers: a runner without the scene, PASS /
FAIL lines, and where a full pop would come down.
