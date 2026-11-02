# skatelike

A portrait mobile skate game prototype made with Godot 4.7. The ground scrolls past a board
that stays at a fixed spot on screen. The board keeps its speed on flat ground; you push to
go faster, pop over steps and off
ledges, and catch every trick before landing. Everything is drawn in code with basic shapes.
The only asset is the graffiti font used for trick callouts.

Live at **https://skatelike.com** (web export, served from the servi2 infra repo).

## Controls

The bottom of the screen is a tap control panel. Pads react on touch-down and support
several fingers at once. Where you touch inside a pad often matters.

**On the ground**

| Pad | Action |
|---|---|
| TAIL POP / NOSE POP | Ollie / nollie. Touch height sets pop strength (top = full). |
| PUSH | A kick: a force pulse over 0.1–0.25 s. Touch height sets strength. Kicks add less the faster you go (see Board physics). You can't pop while pushing, and up to 2 pushes queue. |

**While balancing** (a manual, grind or slide), the pads switch to two rows. Everything is
played with the one finger still down from holding CATCH. New taps on these pads do nothing.

| Pad | Action |
|---|---|
| POP (top row) | Slide the finger up into it to pop out: the nose for nose tricks (nose manual, nosegrind, noseslide), the tail for tail tricks and 50-50s. A normal pop: catch it. |
| BALANCE (bottom row, where CATCH was) | Slide the held finger left or right to keep the balance needle (the meter above the board) up. It falling off an end slams. |
| (lift the finger) | Ends the trick cleanly: a manual puts the wheels down, a grind drops off the rail (no catch needed), a slide keeps rolling along the ledge top. |

**In the air** (after a pop or rolling off a ledge)

| Pad | Action |
|---|---|
| TRICK (top) | Four sectors. The column on the side of the pop pad you used does shuvits (top front shuvit, bottom shuvit). The opposite column does flips (top heelflip, bottom kickflip). Only after a pop, one board trick per jump. |
| CATCH (bottom) | A tap catches the board and locks its angle (touch x: left = tail down, right = nose down). **Holding** CATCH readies a manual or grind for as long as it's held, and tilts the board 12° (touch x: left = tail down, right = nose down, middle = level). |

## Board physics

Rolling follows a point-mass model along the surface, in SI units (`pixels_per_meter` = 120,
so the board is a 0.8 m deck):

```
dx/dt = v cos(a)        dy/dt = v sin(a)        (a = slope angle, positive downhill)
dv/dt = (F_push(t) - c_r m g cos(a) - c_d v²) / m + g sin(a)
```

| Term | Value | Meaning |
|---|---|---|
| m | 75 kg | rider + board (`mass`) |
| c_r | 0.003 | rolling resistance of urethane wheels on smooth concrete (`rolling_resistance`) |
| c_d | 0.2 kg/m | air drag, 0.5 × air density × Cd × frontal area (`drag`) |
| g | 9.81 m/s² | gravity along slopes (`slope_g`) |
| F_push(t) | 500–1200 N peak | a half-sine pulse per kick (`push_force`, `push_time`), scaled by (1 − v / `foot_speed`) |

- **Push limit.** A foot can only drive the board while it sweeps back faster than the
  board rolls (`foot_speed` 8 m/s). A full kick adds about 1.9 m/s at walking speed,
  1.3 m/s at the 3.3 m/s start speed and 0.4 m/s at 6.5 m/s. Nonstop pushing tops out near
  7.8 m/s (28 km/h).
- **Coasting.** Resistance is small: from 3.3 m/s the board still does about 2.8 m/s after
  10 s on flat ground.
- **Speed limit.** `max_speed` is 12 m/s (43 km/h), about where a street board starts to
  speed-wobble. Drag and the push limit keep normal riding well below it; only long hills
  get close.
- **Jumps.** Taking off splits v into horizontal and vertical parts. Touching down keeps
  the velocity's part along the new surface, so landing on a downslope gains speed. Air
  gravity (`gravity`, 3000 px/s² ≈ 2.5 g) stays game-tuned for snappy pops.
- Grinds use `rail_friction` (0) and `ledge_friction` (8) as factors on c_r. Drag still
  applies.
- **Fixed steps.** The physics runs in fixed steps of 1/120 s (`Runner.STEP_RATE`), whatever
  the frame rate, and the drawing blends the last two steps. So a run plays out the same on
  every device (a 144 Hz phone used to jump about 8% higher than a 30 fps one), and it can
  be replayed exactly from the player's actions (ghosts). Everything the player does goes
  through `Runner.act()`, stamped with the step it applies before.
- The stats show speed in km/h.

## Trick rules

- **Catch or slam.** Every pop, and every roll-off of a floor ledge (the nose tips down),
  must be caught before landing, and the board angle must match the ground within
  `land_tolerance` (15°). Rolling off a platform and hopping over a crest need no catch,
  but the landing rules still hold: the board keeps the angle it left at, so if that's
  more than 15° off the ground it lands on, catch to fix it. Leaving a grind (off the end
  of a rail or slide, or lifting the finger) needs nothing: the board levels out to the
  ground below by itself. You can still catch for a manual. Hopping off a rail with a pop
  does need a catch.
- **Manuals and grinds: hold CATCH.** Holding CATCH readies the balance (the board tilts
  12° toward the held side) for as long as it's held. Whatever the board touches down on
  meanwhile decides the trick: a rail grinds, a platform top slides, the floor is a manual.
  - The press that catches the board has to be held for `hold_delay` (0.15 s) before it
    counts, so quick catches stay plain catches. Any later press, once the board is caught,
    readies it at once.
  - Letting go before touchdown just cancels it: no slam. So over a rail you can let the
    rail pass, then press and hold again to land a manual on the floor under it.
- **Balancing** is one long press, from holding CATCH in the air to lifting the finger:
  slide it left or right to balance, up into POP to pop out, or lift it to finish. In a
  manual, a tap on POP with another finger pops out too.
  - A **meter above the board** shows the balance needle, so the eyes stay on the board.
    The needle tips away from the middle by itself, faster the further it's gone, with a
    little random drift, and gets slowly harder the longer it's held (`ramp`). The finger
    leans it back: finger left pushes it left. Off either end: a slam.
  - It starts **settling**: the steering reference glides from where the finger landed to
    the pad's middle while the needle is held up, so you slide the finger to the middle
    wherever it landed and have room both ways. Once it's there (or after 1 s) the needle
    goes live, steered from the middle. The pad shows the reference line and the finger.
  - The needle runs only on the player's device; what's recorded for ghosts is the
    outcome (losing the balance), like any other action.
- **Flips and shuvits.** The board keeps spinning until it's caught: a flip one full turn
  per `trick_time` (0.4 s), a shuvit half a turn per `shuvit_spin_time` (0.2 s). The catch
  counts the turns, rounded, at least one: kickflip, double kickflip, triple kickflip;
  shuvit, 360 shuvit, 540 shuvit (heelflips and front shuvits alike). So a double needs
  about 0.6 s of spin before the catch: a big pop or a drop.
  - pop → trick → catch = kickflip / heelflip / shuvit / front shuvit (or more turns)
  - pop → catch → trick → catch = late trick
  - Landing still spinning slams.
- **Combos.** Each trick tapped opens (or keeps open) a window of `combo_unit` (0.2 s) more,
  and tricks tapped while it's open join the combo: flips add flip turns, shuvits add half
  turns. The board spins the whole combo in one loop, both ways at once, and loops it until
  caught; the catch counts the loops. The first flip and the first shuvit tapped set which
  way each goes. Combos still need the catch.

  | Taps | Trick |
  |---|---|
  | shuvit + kickflip | varial kickflip |
  | shuvit ×2 + kickflip | 360 flip |
  | front shuvit + kickflip | hardflip |
  | front shuvit + heelflip | varial heelflip |
  | shuvit + heelflip | inward heelflip |
  | front shuvit ×2 + heelflip | laser flip |
  | anything else | built from its parts: "540 shuvit kickflip", "double kickflip" |

  A named combo looped twice is a "double 360 flip". Flow counts each flip turn and shuvit
  half turn, so a 360 flip earns three times a kickflip's bonus.
- **Crests keep momentum.** Where a ramp goes flat (or flat ground tips downhill) the board
  flies on if its speed across the new surface, `v sin(bend)`, would lift it `launch_min`
  (6 px) or more. Slower, it rolls over.
  - Hops up to `hop_max` (40 px) need no catch, but the board keeps the angle it left
    the ramp at. Small ones (up to `hop_level_free`, 20 px) land at any angle. Higher, one
    off a ramp steeper than 15° onto flat needs a catch to land. The
    pads switch to the air layout (with CATCH) once the lip-pop window is over. A hop
    rolled through counts as a plain roll. A manual rides over them.
  - Higher launches tip like a roll-off ledge and have to be caught.
  - For `lip_pop_time` (0.12 s) after leaving a lip (a crest, a bend too sharp to
    follow, or the end of a kicker) you can still pop: the pop adds to the launch, so
    popping right at the lip goes highest. A push still going is cut short.
- **Platforms** (ledges, boxes, bridges) are only solid from above. You land on or ride along
  their top and pass through their sides.
  - A platform's end drops you off unless it meets floor at the same height. That lets a
    downhill ledge run onto the floor, or a bridge carry you over a pit.
- **Grinds.** Rails are only solid for a board coming down on them with CATCH held (the
  balance ready). Otherwise you pass through and land on the floor. The same hold onto a
  platform top is a slide.
  - **The trick is named from how the board meets the surface,** not from where CATCH
    was held (that only tilts the board on the way down). At touchdown, the board's angle
    against the rail, ledge or floor decides:

    | Angle against it | Rail | Ledge | Floor |
    |---|---|---|---|
    | within `fifty_band` (6°) of level | 50-50 | 50-50 | plain landing |
    | nose down, up to the limit | nosegrind | noseslide | nose manual |
    | tail down, up to the limit | 5-0 | tailslide | manual |
    | past the limit (`grind_max_angle` 27°, floor `manual_max_angle` 20°) | slam | slam | nose/tail strike |

    The board keeps the angle it touched down at. A 50-50 uses the normal (manual)
    balance and either pop ollies off it. A level catch with a middle hold on a
    flat rail is a 50-50. A slightly tail-down catch with a nose-side hold on an 8°
    downhill rail ends up level with it: also a 50-50.
  - A grind is a manual on the rail or edge, with harder balance settings. On rails it's a
    5-0 (tail) or nosegrind. On ledges it's a tailslide or noseslide: the board swings across
    the ledge and rests on its tail or nose, with the trucks hanging over the edge.
  - Rails have no friction (`rail_friction` factor 0). Slides drag 8× rolling friction.
  - POP ollies out of a grind from the end you ride (a nollie off a nosegrind), and it needs a catch.
  - Reaching the end of a rail or ledge drops you off, no catch needed. A ledge that runs down onto the floor turns the
    slide into a manual.
  - Grinding again before touching the floor counts as a double grind.
- **Callouts.** Landed tricks pop up next to the board in the graffiti font: "ollie!",
  "nollie!", "kickflip!", "nollie heelflip!". Manuals, grinds and slides ("5-0 grind!", "tailslide!") stay up and
  shake for as long as they last. Slams show a red "slam!" on the spot where the rider fell.
- **Flow.** The round FLOW button above the pads is a meter. Landed tricks fill it, and
  harder tricks fill it more:

  | Trick | Meter |
  |---|---|
  | ollie / nollie | 3% |
  | flip or shuvit | +7% per flip turn or shuvit half turn (late: +3% more) |
  | manual | 5%, then 3% per second balanced |
  | grind or slide | 7% (double: +5%), then 5% per second balanced |

  **Lines.** Tricks chained without the wheels coming down make a line: each air trick (a
  board trick, or an ollie/nollie) and each manual, grind or slide landed into joins it,
  and the n-th one scores n times its value (up to x10), as does balancing meanwhile. So
  kickflip onto a nosegrind, heelflip out into a nose manual, nollie out is "kickflip, x2
  nosegrind, x3 heelflip, x4 nose manual, x5 nollie", shown under the score, with the
  multiplier on the button. A clean landing (or lifting out of a manual or slide) adds its
  trick and ends the line; a slam loses it (shown in red). When the meter is full, tap the button for flow state: 5 real seconds at 35%
  game speed, with the ring counting down. Everything slows, including trick and balance
  timers, so you can make inputs more slowly. Tuning is on `FlowButton`
  (`scripts/flow_button.gd`).
- **Stats.** The STATS button next to the menu button shows the speed and a log of recent
  inputs (pop strength, catches, landings, slam reasons). Hidden by default; the choice is
  kept across restarts.
- **Slams.** Other causes: hitting a wall, a transition that's too steep, rolling off a ledge
  while pushing, or stopping.
  - On a slam the board goes loose for `slam_duration` (1 s) before the restart: it keeps
    the velocity it had (on a landing, the speed it came down at), tumbles, bounces off
    and slides along surfaces, and stops against steps. The view follows it.
- **View.** The view follows the floor under the board up and down, keeping it inside
  `camera_band`, with a look-ahead that stops at lips and gaps. In the air it frames the
  board instead (`camera_air_band`). It moves on a critically damped spring
  (`camera_follow`), and it takes on the board's speed as the board nears an edge of the
  screen, so long falls and fast rides stay in view without jolts.

## Tutorial

The first entry in the level menu. Lessons go from riding to balancing to tricks, each one
building on the last:

1. **Riding:** push, ollie and catch, rolling off a ledge, nollie.
2. **Manual:** catch, hold CATCH, slide the finger to the middle and balance the needle,
   lift it to finish. This is the first balance lesson because it's on flat ground.
3. **Board tricks:** flip or shuvit, the step ups on your own, a late trick.
4. **Rail:** hold onto the rail (level is a 50-50), balance like the manual, slide up into
   POP to ollie out, catch.
5. **Ledge:** hold on a side to tailslide or noseslide, lift to end it, roll off the end.
6. **Flow state** (the meter is filled for you there).

At each spot the game freezes, shows the instruction and highlights the pad to use. For
the hold lessons you press and keep holding CATCH. The game resumes after 0.35 s with your
finger still down, and "Keep holding" shows if you let go sooner. Balance steps wait for
the held finger to slide to the pad's middle, into POP, or to lift. Lifting early just ends that
balance and skips the rest of its lesson.

**No slams.** The tutorial runs the Runner in `forgiving` mode: a missed catch, an expired
point, a wall and so on put the rider back on the ground under the board, with a hint,
instead of ending the run. The tap that resumes it is applied at the frozen
moment, so the timing is always right. A wrong pad or a weak tap shows a hint instead (for
example "tap higher" for a pop, or "tap near the middle line" for a flat catch). A few
stretches in between, such as the step ups after the first flip, are left to the player.
Steps the player already did on their own are skipped.

**Checkpoints** (any level with marked segments; the tutorial no longer slams, so there
they only matter if that's turned off). A slam doesn't send you back to the start. Each lesson begins at a
checkpoint (the ollie step, the drop, the rail, the ledge and so on). After a slam the level
restarts just before the last checkpoint you reached, at the same height, and the tutorial
picks up at that lesson. A checkpoint counts as reached once you're riding calmly within
600 px of it: on the ground and not in a manual or grind. Picking a level from the menu,
or clearing it, starts the next run from the beginning.

The freeze pauses the scene tree. Main processes always, while the world and the balance
needle are pausable, so the pads keep taking input. Steps live in `scripts/tutorial.gd` and
trigger on spots marked in the level (`mark = "name"`, see `Runner.marks`; any level's
marked segments are also its checkpoints) and on board
state (near the apex, mid-trick, balancing).

## Levels

Defined in `scripts/levels.gd` (the format is documented at the top of the file):

| Level | What it's for |
|---|---|
| Tutorial | Every mechanic, with guided freezes |
| Flat | Pushing and riding |
| Push | Uphill and downhill slopes |
| Single jump | One step up to pop onto |
| Drops | Three ledges |
| Long jump | Screen-high drops with enough air for late flips |
| Rails | A long straight rail and a long downhill rail |
| Ledges | A flat ledge, a downhill ledge that runs onto the floor, and a bridge over a pit |
| Sketchy #1 | A long survival run through every obstacle kind, no checkpoints (see below) |
| Sketchy #2 | Rail yard: gaps only rails cross (one 1200 px), stair rails, downhill rails over drops |
| Sketchy #3 | Rooftops: decks and boxes over gaps, islands at different heights, a kicker, high ollies; no rails |
| Sketchy #4 | Bomb hill: downhills, rail-less stair sets to clear in one ollie, landing ramps, islands, long uphills to push |
| Vert | Drop into a 3400 px near-vertical wall with a nollie timed to meet it, then a 40° kicker out of the bottom over a 1050 px pit: pop at its lip |

## Menu

The main menu has three pages:

- **Practice:** every level without `challenge = true`, the tutorial first.
- **Challenges:** the **Online** switch (see below), then a table of the levels with
  `challenge = true` (Sketchy #1 to #4). Each row has the play button, your best progress
  (a check once cleared), and **Top**, the challenge's scoreboard (only with Online on).
- **Profile:** your skater name, 3 letters and 2 numbers (default SKT01). Set it with the
  ▲/▼ buttons over each character. It's saved in `user://profile.cfg` and shown on the main
  page.

The title stays at the top, and pages scroll below it. Each page starts with an outlined
**Back** button. Leaving a level returns to the page it was started from.

Cleared levels get a green check, and challenges show their best progress. Both are saved
in `user://progress.cfg`: on a phone or desktop that's the app's data folder; in the
browser it's the page's IndexedDB (`/userfs`), which Godot syncs whenever a file is
written. They survive restarts and page reloads, but not clearing site data or a private
window.

## Online: scoreboards

With the Online switch on, clearing a challenge records you on its scoreboard, and you land
on the board when you're back on the menu. The board lists the skaters who cleared it in
the order they first did. It shows the first 12, plus your own row (in yellow) if you're
further down.

- The API lives in `server/` (Fastify + Postgres, served at `https://skatelike.com/api`).
  `scripts/scoreboard.gd` (autoload `Scoreboard`) calls `POST /scoreboards/<id>/clears`
  and `GET /scoreboards/<id>`.
- Clears are queued in `user://scoreboard.cfg` before sending. A clear made offline, or
  while the API is down, goes out later: on the menu, on the next clear, or every 30 s.
  Rejected ones (bad name, unknown challenge) are dropped.
- API URL: `--api-url=`, then `SKATELIKE_API_URL`, then the project setting
  `skatelike/api/url`, then (web) `/api` on the page's own origin, then
  `https://skatelike.com/api`.
- With the switch off, the game makes no network calls.

## Online: ghosts

With the switch on, everyone riding the same challenge shows up as a faded blue board with
their skater name. Your own board gets a name tag too. It's purely visual: no competition
or collisions. Under the switch, the menu shows the connection state (connecting, online,
or retrying).

- `scripts/online.gd` (autoload `Online`) is both the WebSocket client and the server. Run
  with `-- --server [--port=8910]`, or export the "Linux Server" preset, for a headless
  relay with one room per challenge.
- Each client sends what the rider does rather than where they are: their actions
  (`Runner.act`), stamped with the physics step, in batches 10 times a second, and a
  snapshot of their state (`Runner.get_state`) every second. `scripts/ghosts.gd` runs each
  ghost as a hidden `Runner` of the same level, started from a snapshot and fed the actions
  about 0.25 s behind, so it rides exactly like the rider did (flips, catches, slams). When
  it reaches a later snapshot's step it checks it, and restarts from it if it drifted.
- Deployment notes, URL selection (same host `/online` on the web), TLS and the protocol
  are in [`docs/online.md`](docs/online.md).

### Sketchy #1 (challenge)

About a minute of riding with no checkpoints. A slam or a fall restarts from the start, and
the menu shows your best progress, saved in `user://progress.cfg`. Obstacles, in order:

- gaps to ollie and high step ups (130–140 px, near a full pop's limit)
- stair sets with handrails: ollie the whole set or grind the rail down (landing on the
  stairs slams)
- a kicker ramp that launches you over a gap
- a gap only a rail crosses, and a gap only a raised deck crosses
- a downhill rail over a gap (or a long ollie down across it), onto a landing ramp
- islands between gaps, where a fast board needs a weaker pop to avoid overshooting
- a box that overhangs a gap and ends short of the far side, so you ollie off its end
- a downhill ledge bridging a gap, and a high deck over a wide gap as the finale

Uphills after each big descent bleed off the speed that rails and slopes add, since the
board has no brake. Riders still reach 9–12 m/s in the second half.

New level keys used here (documented in `scripts/levels.gd`): `gap`, `stairs`, point rails
(`rail = [Vector2(x, height), Vector2(x, height)]`), platforms over gaps (drawn as
overhangs), `checkpoints = false` and `challenge = true`.

The random terrain generator (steps and slopes) still exists. Give a level `random = N` to use it.

## Project layout

```
project.godot        720x1280 portrait, canvas_items stretch with keep_width aspect (wide
                     screens and desktop browsers get a portrait column with side bars;
                     taller phones extend the play area), touch emulated from mouse
export_presets.cfg   "Web" preset (single-threaded, no COOP/COEP headers needed), "Android", "Linux Server"
scenes/
  menu.tscn          level select (main scene)
  main.tscn          play area + HUD + control panel
scripts/
  runner.gd          the game: terrain, platforms, rails, board physics, tricks, drawing
  main.gd            wires control pads → runner, HUD messages, level flow
  control_panel.gd   multi-touch hit testing, ground/air pad layouts
  pad.gd             a tappable pad (flash, dimming, pie indicator, split label)
  trick_pad.gd       four-sector trick pad that follows the pop side
  callouts.gd        trick onomatopoeias next to the board
  flow_button.gd     flow meter, lines and slow-motion flow state
  line_label.gd      the line in progress, under the score
  balance_meter.gd   the balance needle drawn above the board
  icons.gd           UI symbols (arrows, menu bars, check) drawn as shapes: the web build's
                     font has no glyphs for them and no system fonts to fall back on
  tutorial.gd        tutorial steps: freezes, instructions, pad highlights
  balance_pad.gd     balance points for manuals and grinds
  levels.gd          level definitions
  menu.gd            menu pages: main, Practice, Challenges, Profile
  toggle.gd          big on/off switch (the Online ghosts switch)
  profile.gd         skater name (3 letters + 2 numbers) and the online switch, saved on the device
  online.gd          online ghosts: WebSocket client and headless relay server (autoload)
  scoreboard.gd      challenge scoreboards from the server/ API, with an offline queue (autoload)
  ghosts.gd          draws other riders' boards and the name tags
  safe_area.gd       keeps UI clear of notches and home indicators
assets/fonts/
  BubblezGraffiti-Regular.ttf   callout font by GGBotNet
  BubblezGraffiti-OFL.txt       its license (SIL Open Font License 1.1; keep it with the font)
docs/
  online.md          online server handoff: running, TLS/URL, protocol
server/              scoreboard API (Node + Postgres), see server/README.md
tools/
  android-release.sh build (and upload) the signed APK
skatepark.blend      unused 3D sketch
```

Almost all tuning lives in exported variables on the **Runner** node: pop and spin, catch
angles, the physics constants and push force, terrain generation, trick time, rail
and ledge friction factors, colors. Balance difficulty (normal and hard) is on the **Balance** pad, and the
global time scale (`game_speed`) is on **Main**.

## Running

Open the folder in Godot 4.7 and press Play. The window is a 405x720 portrait preview, and
mouse clicks act as touches.

From the command line:

```sh
godot --path .
```

## Web export and deploy

Requires the Godot 4.7.2 web export templates.

```sh
godot --headless --path . --export-release Web build/web/index.html
```

`build/` is git-ignored. Put an empty `build/.gdignore` in it so Godot doesn't import the
exported PNGs as project resources (that creates stray `.import` files in the build).
Deploy steps for skatelike.com (rsync to the server, permissions, precompression) are in
`docs/skatelike.md` in the infra repo.

## Android export and deploy

Requires the Godot 4.7.2 Android export templates, the Android SDK (platform-tools and
build-tools) and a JDK, all set in Godot's editor settings. The release keystore lives in
`~/.config/skatelike/` (outside the repo). Back it up, because a different key can't update
installed copies.

```sh
tools/android-release.sh               # signed APK + version.json in build/android-site/
tools/android-release.sh <server>      # same, then rsync to android.skatelike.com's webroot
```

The script sets a fresh `version/code` for each build, so every APK installs over the
previous one. It restores `export_presets.cfg` when it's done. Server-side steps are in
`docs/skatelike.md` in the infra repo.
