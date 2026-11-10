# skatelike

A portrait mobile skate game prototype made with Godot 4.7. The ground scrolls past a board
that stays at a fixed spot on screen. The board keeps its speed on flat ground; you push to
go faster, pop over steps and off ledges, and catch every trick before landing. It's pixel
art in a "Dusk Boardwalk" look (see Look): a cutout-rig skater you can dress, a 3D board
drawn as pixel art, wooden signboard pads and menus. Sprites come from Sprite Fusion,
backgrounds from Runway, fonts and sounds from open sources (see Credits).

Live at **https://skatelike.com** (web export, served from the servi2 infra repo).

## Controls

The bottom of the screen is a tap control panel. Pads react on touch-down and support
several fingers at once. Where you touch inside a pad often matters.

**On the ground**

| Pad | Action |
|---|---|
| TAIL POP / NOSE POP | Ollie / nollie, when the finger lifts (hold as long as you like). Where it went down sets pop strength (top = full); sliding it sideways meanwhile aims a body 180 (shown on the pad). |
| PUSH | A kick: a force pulse over 0.1–0.25 s. Touch height sets strength. Kicks add less the faster you go (see Board physics). You can't pop while pushing, and up to 2 pushes queue. |

**While balancing** (a manual, grind or slide), the pads switch to two rows. Everything is
played with the one finger still down from holding CATCH. New taps on these pads do nothing.

| Pad | Action |
|---|---|
| POP (top row) | Slide the finger up into it, then lift, to pop out: the nose for nose tricks (nose manual, nosegrind, noseslide), the tail for tail tricks and 50-50s. Sliding sideways on it before lifting aims a 180. A normal pop: catch it. In a manual, a second finger on POP does the same. |
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

### Transfers and fakie

- **Rolling backward.** The board has a direction (`Runner._dir`): +1 rolling right, -1
  rolling left (fakie). Rolling to a stop going up a slope, it rolls back down backward.
  There's no "stopped" slam: on flat ground the board just stands until the next push.
  Pushes always drive the board forward, so rolling backward they brake it first. The far
  end of the start platform (which reaches a screen back) stops a board rolling back to
  it. The view pans (`pan_rate`) to show more of the way it's going.
- **Mirrored ground code.** Everything about riding the ground works both ways: handing
  over between pieces, spanning bends, crest hops and launches, walls and too-steep
  bends, lips and roll-offs (the leading end tips down: the tail rolling backward),
  grinds and slides, ledges running onto the floor, and the camera's look-ahead. It's
  written once, for rolling forward, through direction helpers (`_ahead_end()`,
  `_beyond()`, `_linked_ahead()`, `_rel()`, `_gap()`, `_joint(a, b, direction)`); floor
  pieces link both ways (`Seg.next`, `Seg.prev`). Rolling forward they reduce to the old
  code exactly, so forward riding is unchanged; rolling backward a level's mirror image
  plays out the same, step for step (the mirror test).
- A board that slides off the end of a ledge doesn't land back on it with its trailing
  wheel (that used to give a second touchdown, and a slam after a tilted slide).
- **Transfers.** Leaving a ramp steeper than `transfer_angle` (60°) going up, off its lip
  or with a pop, the board keeps its angle (no catch needed) and flies almost straight
  up. Catches and the pop's spin limit are measured from the ramp's angle (`_air_base`),
  so a centered catch keeps it there. Pop at the lip (`lip_pop_time`) for height and
  tricks. Coming down onto a wall that faces back the way it came, it touches down tail
  first and rolls down it backward: fakie.
- **Stance** (`Runner.stance_name()`, shown bottom left as SWITCH or FAKIE):
  - **Regular or goofy**, picked on the profile page: a regular rider shows the camera
    their chest riding normal, a goofy one their back (`Runner._goofy`).
  - **Switch:** riding the other way round to normal, facing the other way (after a 180).
  - **Fakie:** rolling backward, facing as your stance does, ready to pop the tail. The
    rider has a heading (`Runner._heading`, the way it faces along the track) apart from
    the way the board rolls: fakie is rolling against it. Only the board turning around
    gets you there: landing on a wall that faces back (Transfer) or rolling back down a
    slope; rolling the other way again out of fakie is normal.
  - **Fakie tricks chain:** a tail pop is a fakie trick ("fakie ollie", "fakie
    kickflip") and lands fakie, ready for the next.
  - **Out of fakie to switch:** a nose pop is a switch trick ("switch ollie") and lands
    switch; a push puts you in switch; a manual or grind landed out of fakie is a switch
    one ("fakie kickflip switch 5-0 grind", "switch manual") and leaves you switch.
  - **180s** take normal to switch and switch to normal. Out of fakie a 180 turns the
    rider to face the way it rolls: your original stance (a half cab). So does a 180 in
    the air into a transfer to fakie: you land in your original stance. A 360 leaves the
    stance as it was.
  - Manuals, grinds and slides carry the stance they're ridden in ("switch nose
    manual"), and the pop's when it differs.
- **Half cab.** A fakie pop (off the tail) with a backside 180: "half cab", with board
  tricks "half cab flip", "half cab heelflip", "half cab 360 shuvit"; it lands in your
  original stance. A backside 360 is a "full cab" ("full cab flip") and stays fakie. Fakie
  with a frontside 180 is "fakie frontside 180" ("fakie frontside flip"), also back to
  your original stance; off the nose, "switch backside 180".
- **Floors over floors.** A level can start a new stretch of floor anywhere (`at`), so
  one can run under another. The floor under the board is the highest one at or below
  it (`_seg_at(x, y)`). A floor with another under it is drawn as a slab (`floor_slab`,
  40 px) mitred at the bends. A step more than `WALL_REACH` (150 px) above the board is
  overhead, not a wall. There's no ceiling: an ollie under a floor goes through it.
- **Flags anywhere.** `goal = px` puts the flag on a given piece, reached rolling past it
  either way on that floor. A level's own pieces are all laid out at the start, so a
  floor underneath exists before the one above is drawn, and a level with `at` keeps all
  of them (others drop what's 3000 px behind the view, `PRUNE_BEHIND`); pieces off
  screen aren't drawn. The endless floor after a level carries on from its rightmost
  piece.
- The distance score never goes down.

## Trick rules

- **Pop spin.** A tail pop turns the board nose up, a nose pop nose down, both at
  `jump_spin` (2.5 rad/s, about 143°/s at full strength) without slowing down, until the
  catch or `pop_spin_cap` (120°). A board caught past 90° turns back slowly
  (`catch_slow_turn`, 180°/s), so catch a full pop within about 0.6 s, or time a late
  catch to meet a steep wall (Vert).
  - Popping out of a manual or grind is smaller: it goes `balance_pop_height` (60%) as
    high as a normal pop and spins at `balance_pop_spin` (60%).
- **Catch or slam.** Every pop, and every roll-off of a floor ledge (the nose tips down),
  must be caught before landing, and the board angle must match the ground within
  `land_tolerance` (15°). Rolling off a platform, off a small step down (`small_drop`,
  90 px or less, onto floor right past the edge: the board drops flat, and pushing off it
  just ends the push) and hopping over a crest need no catch,
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
  manual, pressing POP with another finger pops out too.
  - **Popping out** works like TAIL/NOSE POP: the pop goes when the finger on POP lifts,
    however long it's held. Sliding it sideways BODY_SWIPE pad widths first aims a
    frontside or backside 180 (shown on the pad). Held up on POP by the landing finger,
    the needle keeps the last steer; slid back down, it's balancing again, no pop.
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
  - Kicking a trick works against the pop's spin: each tap turns the board's pitch spin
    around at half its speed (`trick_counter_spin`), so a kickflip off an ollie brings
    the nose back down, and a nollie's nose down; after the kick the spin dies out.
- **Body 180.** A pop goes when the finger lifts, however long it was held. While holding,
  slide the finger sideways at least a third of the pad's width to aim the pop: the pad
  shows faint arrows both ways while held, and lights the aimed one with its name ("FS 180",
  "BS 180"). Lifting then pops with a body 180: the skater turns around with the board,
  half a turn every `body_turn_time` (0.35 s). A plain tap (or a small wiggle) is a normal
  pop. Pausing while holding calls the pop off. It adds one board trick's worth of flow.
  - **Twisted pops barely tip:** a pop with a body turn keeps only `twist_pop_spin` (0.1)
    of the pop's nose-up or nose-down spin (under 10° on a full pop).
  - **360s and more:** like board tricks, the body keeps turning until it's caught. The
    catch settles it on the nearest half turn, or back on one it passed by no more than
    `body_catch_slack` (0.15 of a half turn): caught early it finishes the 180, caught
    around 0.55-0.65 s it's a 360 ("frontside 360", "backside 360 kickflip"). Landing
    before it has settled slams ("landed mid-frontside 360"). An even number of half
    turns leaves you in the stance you were in.
  - **Frontside or backside:** turning the chest toward the way the board rolls is
    frontside (`Runner.swipe_is_frontside()`): for a regular rider riding normal a swipe
    to the right; riding switch, goofy, or fakie, the sides swap accordingly.
  - **Switch:** landing a 180 (or 540) puts you in switch (shown bottom left), another one
    back; a 360 doesn't.
    Tricks popped switch say so: "switch ollie", "switch nollie", "switch kickflip", and so
    do manuals, grinds and slides landed switch: "switch 5-0 grind", "switch kickflip
    noseslide". Rolling backward it's fakie (see Stance). A slam restarts you in your
    normal stance.
  - **Names:** "frontside 180", "nollie backside 180"; with board tricks, their own names
    where they have one:

    | 180 | Board trick | Trick |
    |---|---|---|
    | frontside / backside | kickflip | frontside flip / backside flip |
    | frontside / backside | heelflip | frontside heelflip / backside heelflip |
    | backside | 360 shuvit | bigspin |
    | frontside | 360 front shuvit | frontside bigspin |
    | backside | 360 flip | bigspin flip |
    | frontside | laser flip | frontside bigspin heelflip |

    and otherwise built from the parts: "frontside 180 hardflip", "backside 180 double
    kickflip".
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
- **Callouts.** Landed tricks pop up next to the board in the sign font (Knewave): "ollie!",
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
  (`scripts/flow_button.gd`). On free ride levels (not lessons or gaps) flow has no
  restrictions (`FlowButton.unlimited`): the button is always full, a tap turns slow motion
  on for as long as you like, and another tap turns it off.
- **Stats.** The STATS button next to the menu button shows the speed and a log of recent
  inputs (pop strength, catches, landings, slam reasons). Hidden by default; the choice is
  kept across restarts.
- **Slams.** Other causes: hitting a wall, a transition that's too steep, rolling off a ledge
  while pushing, running into an obstacle (a parked car, see Spots and the map), or
  stopping.
  - On a slam the board goes loose for `slam_duration` (1 s) before the restart: it keeps
    the velocity it had (on a landing, the speed it came down at), tumbles, bounces off
    and slides along surfaces, and stops against steps. The view follows it.
- **View.** The view follows the floor under the board up and down, keeping it inside
  `camera_band`, with a look-ahead that stops at lips and gaps. In the air it frames the
  board instead (`camera_air_band`). It moves on a critically damped spring
  (`camera_follow`), and it takes on the board's speed as the board nears an edge of the
  screen, so long falls and fast rides stay in view without jolts.

## Lessons

Levels that teach one thing each, under **Practice > Learn**, in two lists: **Mechanics**
(the game's mechanics, in order; they replaced the old guided tutorial) and **Tricks**
(one board trick each). A lesson is a level with a `lesson` entry (`scripts/levels.gd`,
run by `scripts/lesson.gd`; its `group` is "mechanics", the default, or "tricks"):

- An **explanation panel** at the top of the play area: the mechanic's text, the goal and
  how it's going, and a miniature control panel where a finger loops the input to make
  (the lesson's `demo` steps: taps at a spot on a pad, holds, slides while pressed, waits,
  and which pad layout).
  It never takes touches. The **Tips** checkbox in the top bar hides it (remembered).
- A **goal** to clear it: reach a speed (`{speed = km/h}`) or land a trick, n times
  (`{trick = "360 flip", count = n}`): a trick of a line named that, or ending in it
  ("nollie 360 flip" counts as a 360 flip; a nollie isn't an ollie, a front shuvit isn't a
  shuvit). Reaching the flag without it says what's missing and restarts the lesson.
- Each list is numbered, with a check once cleared.

**Tricks**, each an ollie off a high floor (a 420 px drop to a lower one, `max_fall`
900), so there's time to do it and catch: Kickflip, Heelflip, Shuvit and FS Shuvit (front
shuvit), each with its demo tapping the right quarter of the TRICK pad; the goal is to
land that trick.

**Mechanics:**

| # | Lesson | Goal |
|---|---|---|
| 1 | Pushing: tap PUSH, higher kicks harder, taps line up during a kick, no pops while pushing. Flat ground, then two uphills too steep to coast | reach 25 km/h |
| 2 | Ollie & catch: TAIL POP (higher pops higher), the board turns nose up until caught, CATCH (middle = level) before landing. Pits 120, 160 and 200 px wide | land 3 ollies |
| 3 | Pop height: low or full pops; step ups of 40 to 130 px need a full pop, early | reach the flag |
| 4 | Drops: rolling off a ledge tips the nose down (catch it); pop off for more air | reach the flag |
| 5 | Nollie: NOSE POP, the board turns nose down; the Ollie lesson's pits | land 3 nollies |
| 6 | Catch angle: CATCH's side tilts the board; gaps onto 23° landing ramps a level catch can't land | reach the flag |
| 7 | Crests & lips: hops off a ramp's crest, then a kicker over a 340 px gap | reach the flag |
| 8 | Flip tricks: TRICK after a pop (pop side's column shuvits, the other flips), catch to stop the spin. Long Jump's drops | land a kickflip |
| 9 | Doubles: the catch counts the turns | land a double kickflip |
| 10 | Late tricks: catch, trick, catch | land a late trick |
| 11 | Combo tricks: quick taps join (two shuvits and a kickflip) | land a 360 flip |
| 12 | Manuals: hold CATCH on a side onto flat, balance the needle, lift to finish | land a manual |
| 13 | Manual pops: slide into POP or press it with another finger, and lift (slide sideways first for a 180); that's a line | a line of 3 tricks |
| 14 | Rails: hold CATCH onto a rail (50-50, 5-0, nosegrind), balance, pop out or ride off. The Rails level | land 2 grinds |
| 15 | Ledges: slides on platform tops, lift to roll on. The Ledges level | land a slide |
| 16 | Double grinds: two rails 150 px apart, pop off the first onto the second | land a double grind |
| 17 | Lines & flow: chain tricks for x2, x3...; FLOW and slow motion | a line of 4 tricks |
| 18 | 180s & switch: hold the pop and slide sideways for a frontside/backside 180, land switch, add a kickflip. Long Jump's drops | land a frontside or backside flip |
| 19 | Vert: the Vert challenge's ramp, explained | reach the flag |

While the panel shows, the camera keeps the ground (with room for a pop) and the board
below it, so they never hide behind it; hiding it with TIPS restores the normal framing.

## Pause

The pause button (top left) stops the game under a dim full-screen veil with **Home**
(back to the menu), **Restart** (the level from the start) and **Play** (resume). Next to
the pause button, on every level, the **restart** button (a circular arrow) starts the
level over at once. A restart counts the run so far for best progress, like a slam. The game also pauses by itself whenever it loses
focus: another window on desktop, another tab or app on the web, the app going to the
background on mobile. It never resumes by itself.

Pausing stops everything under `Layout` (the world, sounds, ghosts, the pads) and the
flow button, whose real-time slow motion is held; Main and the pause screen keep running,
so the ghost room still gets (empty) action batches and doesn't drop a paused rider.
Fingers on the pads are let go when it pauses. `scripts/pause_menu.gd`.

## Restarts

There are no checkpoints: a slam or a fall always restarts the level from the start.

## Levels

Defined in `scripts/levels.gd` (the format is documented at the top of the file):

| Level | What it's for |
|---|---|
| Bridge | The first spot (from the map): beginner gaps, a step up, a drop, a rail, a kicker over a gap, a box |
| Downhill cruise | 30,000 px at 0.7°, where gravity about makes up for rolling resistance and drag: speed holds (3.3 to about 5 m/s over the minute), so you can manual the whole way |
| Flat | Pushing and riding |
| Push | Uphill and downhill slopes |
| Single jump | One step up to pop onto |
| Drops | Three ledges |
| Long jump | Screen-high drops with enough air for late flips |
| Rails | A long straight rail and a long downhill rail |
| Ledges | A flat ledge, a downhill ledge that runs onto the floor, and a bridge over a pit |
| Sketchy #1 | A long survival run through every obstacle kind (see below) |
| Sketchy #2 | Rail yard: gaps only rails cross (one 1200 px), stair rails, downhill rails over drops |
| Sketchy #3 | Rooftops: decks and boxes over gaps, islands at different heights, a kicker, high ollies; no rails |
| Sketchy #4 | Bomb hill: downhills, rail-less stair sets to clear in one ollie, landing ramps, islands, long uphills to push |
| Transfer | Drop into a U whose far side goes up to a 75° lip: the board flies almost straight up, drifts onto a tall 72° wall facing back, comes down it fakie and rolls back left on a lower floor under the U, through obstacles ridden backward: a hump (crest hop), a box to slide, a rail to grind, a kicker up to a drop (pop the lip, or catch the roll-off), to the flag. Pop at the transfer lip for a bigger air higher up the wall |
| Vert | Drop into a 3400 px near-vertical wall with a nollie timed to meet it, then a 40° kicker out of the bottom over a 1050 px pit: pop at its lip |

## Menu

The main menu has these pages, in order:

- **Map:** the city map (see Spots and the map below).
- **Practice:** **Learn** (a page with **Mechanics** and **Tricks**, each a list of
  lessons, see Lessons), then the **Obstacles** to practice on: levels with
  `practice = true`, so far **Stairs** (4, 6 and 8 stairs at 35° with handrails, after a
  run-up) and **Flat**. A practice stage has no goals, and reaching its flag starts it
  again: only the menu (pause) leaves it. The other old free-ride levels are out of the
  menu, kept for tests.
- **Profile:** your skater name, 3 letters and 2 numbers (default SKT01), set with the
  ▲/▼ buttons over each character; your stance (Regular or Goofy); your skater (a preview riding in place, and a picker
  per outfit slot); your board (a spinning preview, and pickers for the deck graphic,
  grip and wheels). It's all saved in `user://profile.cfg`.

The title stays at the top, and pages scroll below it. Each page starts with an outlined
**Back** button. Leaving a level returns to the page it was started from.

Pages scroll by dragging from anywhere, buttons included (a finger that moves more than
14 px is scrolling, and doesn't press the button it started on). Let go mid-drag and the
page glides on at the finger's speed, slowing down like a phone's lists (`FLING_FRICTION`
2/s, stopping at the top or bottom); a touch during the glide catches it without pressing
anything. Holding the finger still before lifting doesn't glide.

Cleared levels get a green check, and challenges show their best progress. **Progress**
is counted in marks: `Runner.progress_marks` (20) spread evenly along the level's own floor
pieces, and how many the board has crossed, either way, on the floor under it (a floor
running above or below doesn't count), so it works on levels ridden backward too. The flag
makes it 100%. Both are saved
in `user://progress.cfg`: on a phone or desktop that's the app's data folder; in the
browser it's the page's IndexedDB (`/userfs`), which Godot syncs whenever a file is
written. They survive restarts and page reloads, but not clearing site data or a private
window.

## Spots and the map

The game is moving to a map of spots, each a stage with goals and rewards
(`scripts/spots.gd`). The old challenges (Gaps: Sketchy #1 to #4, Vert) are out of the
menu, kept as levels for testing until spots replace them.

- **The map** (`MapView`) is a paper map lying on a wooden table, pixel art made in
  code: a clean sheet printed with a city plan (blocks with building footprints, parks
  and plazas between the streets, an avenue through each spot, a river under each spot
  with bridges where the avenues cross it, riverside parks, for a spot with `river`), a double rule and a compass
  rose on its margin, and a dotted red route along the streets through the spots in
  order. Each section holds four spots, zigzagging up the route 64 art px apart
  (`MapView.SLOTS`), so four or more are in sight on a phone screen; their icons are
  32 px sprites. The top of the last section is still being surveyed: the blocks thin out
  into blank paper where the next spots will go. Names sit on small paper tags. Each spot's icon is a standalone low-res sprite (it reads on its own,
  not drawn to match the paper) that floats over the sheet: drawn on top, with its shadow
  on the paper and a slow one-pixel rise and fall. Sections stack upward as spots are
  added, so the map grows up. It opens where it was last scrolled to (the bottom, at
  first), with what the last run gave under it; Back stays pinned above the map.
- **Spots** unlock in order: the first is open, each next one once the spot before it gives
  its `{unlock = "next"}` reward (its required goal). It follows from that goal being met,
  not saved, so a spot added in an update is already open for a player who cleared the
  one before it. On the map: a bobbing pointer on the spot to ride next, a check once
  cleared, a lock while locked. A spot entry has its stage (a level with `spot = true`, not listed under
  Practice), its place on the map (section and position) and icon (`landmark`), and its goals.
- **Goals** (`Goal`) are watched during a spot's run: `clear` (reach the flag; required,
  it clears the spot), `trick` (land one, by name), `line` (a line of n tricks), `speed`.
  Each can carry a **reward**; the only kind so far is unlocking (`{unlock = "next"}`, or
  `{unlock = spot id}`). Adding "land a kickflip" with a reward is one entry in the
  spot's `goals`.
- **Bridge** is the first spot: beginner jumps and obstacles (gaps, a step up, a drop, a
  rail, a kicker over a gap, a box, a car and a van after kickers). Clearing it unlocks
  **School**, the second, next up the route on the map: a step up, still clearable with ollies
  (a gap, a planter ledge, four stairs down with a handrail, the school bus after a
  kicker, a gap up to a higher yard). Clearing School unlocks the next spot in advance
  ("Next spot coming soon").
- **Each spot has its own look**, an asset group (`SpotArt`, `assets/spots/<spot>/`) its
  level picks with `art`: the ground's fill and edge strip, a parallax backdrop matching
  its name, and props standing on the floor, drawn at the world's pixel size behind the
  skater:
  - **scenery** (`props` on a floor piece, `start_props`: lamps, benches) is only drawn,
    a little see-through (`prop_alpha`) so it reads as not in the way;
  - **obstacles** (`obstacles` on a floor piece: parked cars) are solid. Their outline
    (the top of each pixel column of the sprite) is a hitbox: the board running into it
    slams. Their top (hood, roof, trunk) is a platform to land on, ride and grind, off
    the end of which the board drops with no catch. A level puts a kicker before each.
  Ramps, rails and boxes stay drawn by the runner, stretched to fit. Bridge's:
  sandstone bridge masonry with a stone curb, a riverside old town at dusk (an arched
  bridge across the river, embankment houses, a cafe), iron lamps, benches, and two
  parked cars after kickers (a small car, then a van) to jump or ride over. School's:
  red brick with a concrete coping and a yellow line, a red brick high school with a
  clock and a flagpole before the distant city and its water tower, basketball hoops,
  bike racks, and the school bus. The art is generated (Sprite Fusion for the tiles
  and props, with the base skater as the style reference; Runway for the backdrop) and
  processed by `tools/make_spot_assets.gd` (tiles mended to wrap, props trimmed to stand
  on their bottom row, a dusk tint, from the set's `make.json`) and
  `tools/make_backgrounds.gd` (the backdrop layers); the map icon comes from the same
  set. Sources and prompts: each `sources.json`.
- Progress (goals met, spots unlocked) and the map's scroll are saved in
  `user://spots.cfg` (`SKATELIKE_SPOTS_SAVE` overrides it, for tests).
- Online scoreboards and ghosts aren't on spots yet: they still belong to the old
  challenges.

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

With the switch on, everyone riding the same challenge shows up as a faded, tinted skater
(the same rig, in the default outfit: outfits aren't sent online) with their skater name. Your own board gets a name tag too. It's purely visual: no competition
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

About a minute of riding. A slam or a fall restarts from the start, and
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
overhangs) and `challenge = true`.

The random terrain generator (steps and slopes) still exists. Give a level `random = N` to use it.

## Look

Art direction "Dusk Boardwalk": a pixel-art beach boardwalk at blue-hour dusk, with
wooden surf-shop signboards for the controls and menus. The world is drawn at
`Runner.PIXEL` (3) world px per art pixel; the skater at `Runner.skater_pixel` (5), so
they stand about 1.8 boards tall. In the game the world is drawn zoomed out
(`Main.world_zoom`, 2/3: the World node's scale, the runner laying out a bigger area), so
the skater is smaller on screen and obstacles are in sight earlier; the world's art pixels
are then 2 screen px, the backdrop's too. Text in the world (callouts, ghost name tags)
keeps its screen size. The level's own area is the play area's lower part, near the pads
(`Main.world_top`: the top 40% is left to the backdrop, and to whatever flies up into
it); levels' `start_y` and the camera bands are fractions of that area.

- **The board** (`BoardView`) is a small 3D model rendered into a low-res viewport and
  drawn back as pixel art (stepped toon shading, 1 texel outline). Flips, shuvits, body
  turns and slides are real 3D turns from `Runner.board_motion()`, so the grip shows on
  top and the deck graphic underneath; the wheels roll with the speed and keep spinning
  in the air. `Runner.board_pose()` is the same pose seen flat, for anything drawn
  without the view.
- **The skater** (`SkaterView`) is a 2D cutout rig: the Sprite Fusion base sprite
  (`assets/characters/skater.png`) cut into 10 pieces by a label map and joints
  (`tools/make_skater_rig.gd`, `assets/characters/rig/`), posed every frame from
  `Runner.skater_pose()`: the hip drops and the torso leans with the crouch, the legs
  reach the feet with two-bone IK, the arms come up for balance, and the whole rig turns
  with the body (narrowing through a 180). Turned pieces are drawn RotSprite style, so
  they stay hard pixel art.
- **Front and back.** The rig has two views of the same figure, both facing right: the
  front (chest to the camera) and the back (`skater_back.png`, a Sprite Fusion edit of
  the base, lined up with it pixel for pixel, cut by `tools/make_skater_rig.gd --back`).
  The pose says which, and whether it's mirrored to face left (`back`, `mirror` from
  `Runner.skater_pose()`): a regular rider riding normal shows the front facing right,
  switch the back facing right (looking ahead), fakie the front facing right while
  rolling left (riding backward), and after a half cab the back facing left; goofy
  swaps front and back. A body turn spins the figure: it narrows edge-on and the other
  side comes round facing the other way, so a 360 goes front, back facing left, front.
  A 180 that should end looking ahead (switch: the back, facing right) finishes with a
  quick turn of the head (`Runner.view_flip_time`, 0.12 s) once the turn has settled; a
  half cab already ends the way it rides on (the back, facing left).
  Seen from behind, the toes are past the deck's far edge, so the board is drawn over
  the skater (SkaterView reorders itself under the board; ghosts draw their boards over
  their figures); from the front, the skater over the board. The back view wears the front views of the outfit items for now
  (hair, hats, hoodie, long sleeve: they line up, but show front details).
- **Outfits** (`Outfits`, saved in `Profile`): skin, hair, hat, shirt, pants and shoe
  slots. Items have the base's shape, so every pose works with no new animation: a layer
  recolored by a [dark, mid, light] color ramp. Hair, hats, the hoodie and the long sleeve
  are cut from Sprite Fusion edits of the base (`tools/sf_item.sh`,
  `tools/extract_item.gd`).
- **Board parts** (`Boards`): deck graphics (`assets/boards`, fitted with
  `tools/fit_deck_graphic.gd`), grip and wheel colors.
- **The ground** is tiled with boardwalk concrete (`assets/tiles`: a fill inside the
  ground and an edge strip along its surface), or a spot's own tiles (see Spots and the
  map). A floor with another floor under it is a
  slab instead (see Floors over floors).
- **The backdrop** (`ParallaxBackdrop`): sky, sea and town layers (`assets/backgrounds`,
  made with Runway, `tools/make_backgrounds.gd`) scrolling at their own speeds behind the
  level, and drifting by themselves behind the menus. A spot's stage has its own layers.
  Each layer moves up and down at its own speed with the camera, so every layer but the
  front one carries on below its bottom edge (its bottom band repeated mirrored: sky
  glow, water); on the spots the front one's bottom is open, so what's behind carries on
  in pits and below the yard (Bridge's river, School's distant city).
- **The UI** (`UiKit`, its theme on every screen): clean old cream-painted planks
  repainted per color (on the CPU, or `scripts/paint.gdshader` for the pads), small
  screwless planks for small buttons, dark backboards behind panels, burned-in (INK) or
  lit icons (`assets/ui/icons`), strips of warm bulbs. The pads follow one rule: a
  gradient where the touch position matters (pop and push: bright top = strong; catch:
  tail red to nose orange across), flat paint otherwise. FLOW is a brass dial whose
  needle fills with the meter; the Online switch is a wooden lever. The logo is a neon
  sign (`NeonSign`, glowing and flickering on), and the pause title a hanging sign
  (`HangingSign`). `tools/make_ui_kit.gd` rebuilds the UI sprites from their sources.
- **Fonts:** Lilita One for the interface, Knewave for signs, titles, pad lettering and
  callouts, Tilt Neon for the neon sign.
- Where every generated asset came from (prompts, tools, edits) is in the `sources.json`
  next to it; the raw sources sit in `source/` folders that Godot ignores (`.gdignore`).

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
                     (the ground; the board and skater poses the views draw, with a flat
                     board and a stick figure as fallbacks)
  board_view.gd      the board as a 3D model drawn as pixel art (BoardView)
  skater_view.gd     the skater as a cutout rig drawn as pixel art (SkaterView)
  outfits.gd         outfit items per slot, recolored by ramps (Outfits)
  boards.gd          board parts: deck graphics, grips, wheels (Boards)
  skater_preview.gd  the profile page's skater, riding in place
  board_spinner.gd   the profile page's board, turning and flipping
  ui_kit.gd          the wooden UI: planks, paints, backboards, icons, bulbs, theme (UiKit)
  paint.gdshader     repaints a plank's cream on the pads (flat or a gradient)
  parallax_backdrop.gd  sky, sea and town layers behind the level and the menus
  neon_sign.gd       the logo as a neon sign
  hanging_sign.gd    a wooden sign hanging on chains (the pause title)
  main.gd            wires control pads → runner, HUD messages, level flow
  control_panel.gd   multi-touch hit testing, ground/air pad layouts
  pad.gd             a tappable pad: painted signboard, bulbs, icon, arrows, aim, push dial
  trick_pad.gd       four-sector trick pad that follows the pop side
  callouts.gd        trick onomatopoeias next to the board
  flow_button.gd     flow meter, lines and slow-motion flow state
  line_label.gd      the line in progress, under the score
  balance_meter.gd   the balance needle drawn above the board
  sfx.gd             board sounds: pops, catches, landings, slams, rolling and grinding loops
  lesson.gd          a lesson's explanation panel, input demo and goal
  pause_menu.gd      the pause screen (Home / Restart / Play)
  icons.gd           UI symbols (arrows, menu bars, check) drawn as shapes: the web build's
                     font has no glyphs for them and no system fonts to fall back on
  balance_pad.gd     the balance needle for manuals and grinds, steered by the held finger
  levels.gd          level definitions
  spots.gd           the map's spots: stages, goals, rewards, unlocks, saved progress (Spots)
  goal.gd            a spot's goal watched during a run (Goal)
  map_view.gd        the city map: a paper map on a table, spots and their markers (MapView)
  spot_art.gd        a spot's asset group: ground tiles, props, backdrop layers (SpotArt)
  menu.gd            menu pages: main, Map, Practice, Profile, Credits
  toggle.gd          a wooden lever on/off switch (the Online ghosts switch)
  profile.gd         skater name, online switch, outfit and board, saved on the device
  online.gd          online ghosts: WebSocket client and headless relay server (autoload)
  scoreboard.gd      challenge scoreboards from the server/ API, with an offline queue (autoload)
  ghosts.gd          draws other riders' skaters, boards and the name tags
  safe_area.gd       keeps UI clear of notches and home indicators
assets/
  characters/        the base skater, its rig (label map, joints), outfit items, sources
  boards/            deck graphics
  spots/             per spot: its map icon and asset group (fill, edge, props/, backdrop/);
                     source/ holds the generated originals (not exported)
  tiles/             ground fill and edge
  backgrounds/       sky, sea and town layers
  ui/                planks, pads, backboard, dial, icons
  fonts/             Lilita One, Knewave, Tilt Neon (with their OFL licenses)
  sfx/               sound effects
docs/
  online.md          online server handoff: running, TLS/URL, protocol
server/              scoreboard API (Node + Postgres), see server/README.md
tools/
  android-release.sh build (and upload) the signed APK
  make_skater_rig.gd cut the base skater into the rig's pieces (label map, joints)
  sf_item.sh         ask Sprite Fusion for an outfit item drawn on the base
  extract_item.gd    cut an item out of a Sprite Fusion edit, aligned to the rig
  fit_deck_graphic.gd fit a generated deck underside to the board's deck graphic
  make_ui_kit.gd     build the UI planks, pads and icons from their sources
  make_backgrounds.gd build the backdrop layers from their sources (the boardwalk's, or a spot's)
  make_spot_assets.gd build a spot's tiles and props from its generated set (make.json)
tests/               headless tests of the game's behaviour (see tests/README.md)
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

Tests (headless, about two minutes; see `tests/README.md`):

```sh
tests/run.sh
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

## Credits

Sound effects are cut from ["Skateboarding Tricks"](https://freesound.org/people/SoundBiterSFX/sounds/746602/)
by SoundBiterSFX, licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The
clips in `assets/sfx/` (pop, landings, catch, slam, and the rolling and grinding loops,
crossfaded to repeat) are trimmed, faded, mixed to mono and normalized from it.

Fonts, all under the [SIL Open Font License 1.1](https://openfontlicense.org) (license
files in `assets/fonts/`): Lilita One by Juan Montoreano (interface), Knewave by Tyler
Finck (signs and callouts), Tilt Neon by Andy Clymer (the neon sign).

Art: backgrounds and mockups made with Runway, sprites (skater, outfit items, deck
graphics, tiles, UI planks) with Sprite Fusion; provenance in each `sources.json`. The
menu's Credits page lists all of these.
