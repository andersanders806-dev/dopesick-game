# The sea and the Night Boat — design

Date: 2026-10-28. Status: approved in conversation ("all of it, write the doc and build it").

## Intent

At the edge of the open-world block the player walks into black nothing.
The player wants the world to end in **open sea to the horizon** instead,
and **exactly one harbour pier** the player can walk out on. Out on the
pier something should happen that belongs to Dope Sick's story (addiction,
theft, the pusher) — new, not copied from another game, and "fucking
badass".

The pitch the player approved, "The Night Boat":

- The third-person camera becomes an over-the-shoulder camera like
  Resident Evil 4 (the player: "over the shoulder like RE4") — for the
  whole story game, not just the harbour (see "The camera").
- The block is an island. Open black water all round, a lighthouse
  blinking far out.
- One old wooden pier. By day: a quiet old fisherman; fishing with him pays
  a little and the withdrawal bites softer — the only calm place in the
  game.
- At 3 AM on some nights: a dark boat drifts in and hands bags to the
  pusher's crew under the pier lamp. This is where the block's dope comes
  from. Found by being out there at the wrong hour, or the fisherman hints
  at it once he trusts you.
- Three choices, all of which the player wants:
  1. **Rip a bag** — huge stash, then a chase down a dead-end pier: hide
     under the boards or go into the freezing water and swim for the
     seawall; the crew hunts you on the block for days.
  2. **Tip the cops** — reward, the boat stops, the block dries up: prices
     climb, everyone gets sicker, you too.
  3. **Get on the boat** — trade something big, ride out at dawn, never come
     back. A new ending, different from recovery.

## Goals

- No visible void anywhere from any camera on the block, day or night:
  seawall, water, horizon, sky.
- One pier you walk out on (no second pier, no other docks).
- The fisherman, fishing, the boat night, and all three choices playable
  in a normal story run.
- Stays inside the open-world perf gate: Low on the UHD 620, 60 FPS,
  GPU <= 13 ms, no frame > 25 ms while walking, City3D load <= 2.5 s.

## Non-goals

- No boats to drive, no sailing, no second island, no underwater.
- No swimming anywhere you like: water is only entered from the pier.
- No change to Main Street's existing positions (open-world constraint).

## Anti-goals (a failure even if it works)

- Water that looks like a flat blue plastic sheet or a bright cartoon sea.
  It's a cold, dirty city harbour at night: black-green, low swell,
  lamp reflections, fog toward the horizon.
- Stutter. The sea must not bring back walking hitches (the player's #1
  complaint).
- The boat night as a cutscene you watch. The player acts in it.
- The boat ending reading as a happy ending. You're still sick, just
  somewhere else.

## The camera (over the shoulder, like RE4)

- The story game's third-person view becomes an RE4-style
  over-the-shoulder camera: close behind and to the right of the player,
  shoulder height, the player off-centre left; mouse / right stick orbit
  it freely around the player (yaw all the way round, pitch clamped);
  shoulder swap on a button; pulls in on walls (the Task 2 R2-I3
  pull-in) instead of clipping; the cutaway still dithers walls between
  camera and player. First person stays as it is.
- One rig, `player/ShoulderCam.gd`, shared with zombie mode: zombie Task
  Z5 adds aim, laser sight and combat on top of it instead of building its
  own. No aiming in story mode.
- Stealth must still read: the existing detection cues (guards' sight,
  heat) stay visible from behind the shoulder.
- Because the camera now turns all the way round, every edge of the block
  is seen: the sea, seawall and horizon must look right in all four
  directions, and the open-world perf gate must be re-run with the new
  camera (more of the block is in view than with the old north-facing
  camera).
- Built as its own task before the harbour, since the harbour's views
  are framed for it.

## Where it goes

- Sea on all four sides of the block, beyond a seawall that bounds the
  block. Between the outer frontages and the seawall: a strip of quay /
  pavement wide enough that the camera never looks over the edge into
  nothing. Seawall has a railing and collision; the player can't climb it.
- The pier leaves the island from **Back Street (north)**, toward the east
  end near the lot and underpass camp (the pusher's crew is already
  there). The camera looks north, so walking out on the pier you look over
  the water to the horizon and the lighthouse. Builder picks the exact x
  through a gap in Back Street's north frontage. ~35-45 m long, ~4 m wide,
  wooden boards on piles, a T or L end with a bollard and one weak lamp.
- Lighthouse: far out to the north, a landmark (group `landmark`), slow
  sweeping beam visible at night.
- In Dead Block (zombie mode) the sea and pier exist (same City3D) but no
  fisherman, no boat, no fishing.

## The sea (look and cost)

- One large water surface (plus a far horizon ring or the fog doing that
  job) with a cheap custom spatial shader: scrolling normal maps, low
  vertex swell near the shore only, depth/fresnel tint, specular from the
  street lamps and moon. No SSR, no refraction pass, no transparency
  sorting over the whole sea. Fog blends it into the sky at the horizon.
- Its own cell or part of `Cell_Back` — builder's call — but the water and
  lighthouse are landmarks and never hidden.
- Sound: waves slapping the seawall and piles, a far foghorn now and then,
  gulls by day; quieter inland.

## The fisherman (Sal — name is the controller's call)

- New Rocketbox body via `CharacterCast` (role `fisherman`): an old man in
  a heavy coat and watch cap. Schedule (Task 4 `Schedules.gd`): at the pier
  end roughly 06:00-19:00, home otherwise. Never present on boat nights
  after 01:00.
- Talk to him: short lines, dry, kind. He lends a rod.
- **Fishing**: sit at the pier edge, cast, wait, a bite cue (rod tip +
  sound + controller rumble), a timed press/hold to land it. Misses happen.
  Catches are small fish, sometimes junk (a boot, a phone, once in a while
  something useful). Sal buys fish for a few dollars (order of $2-5; the
  economy's numbers are the builder's to tune against `balance_sim`).
- While fishing, withdrawal is softer: craving decay and the sickness
  screen effects are reduced (e.g. half) for as long as you sit there.
  Leaving ends it.
- **Trust**: fishing with him on separate days raises trust. At a trust
  threshold (about three days) he says, once, that you should not be out
  here on a given night, and names it. The notebook notes the night.

## The boat night

- Boat nights: not every night (every few nights — builder tunes; a fixed,
  save-stable rule, so the hint can name the next one). The next boat
  night is known to the game in advance so Sal can name it.
- ~03:00: the boat (no lights, engine cut) drifts to the pier end. Two
  boat men, plus the pusher's crew (two; the pusher himself may stand at
  the pier head). Bags go from the boat into a stack under the pier lamp,
  then off the pier into the block. The whole thing lasts about 20-30 game
  minutes, then the boat leaves.
- The crew uses the existing guard/cop sight model (vision cones,
  flashlights). Being seen near the stack is trouble: they rough you up
  (existing beating cost) and throw you off the pier — into the water.
- Witnessing it (being within sight of the stack during the drop, unseen)
  sets "saw the boat" — the notebook records it, and it unlocks choices 2
  and 3.

### Choice 1: rip a bag

- Grab one bag from the stack while no one is looking (stealth). The bag
  is a big stash of the block's main street drug (order of 10 doses) —
  usable, sellable through the existing fence, or stashable (Task 5
  stashes).
- They notice within seconds. The pier is a dead end: crew with
  flashlights come down it. Two escapes:
  - **Under the boards**: a ladder at the pier side to a crossbeam under
    the deck. Hide there until they give up (search, then leave). Being
    found there = beaten, bag taken.
  - **The water**: drop off the side, swim slowly to a ladder in the
    seawall. Swimming drains warmth very fast (Survival), slow movement,
    no running. Too long in the water → you go under (health ending path,
    as other deaths do). The bag survives the swim.
- Aftermath ("hunted"): for several days an enforcer from the crew walks
  the block looking for you (a scheduled/hunting NPC). Spotted = chased;
  caught = beaten and stash taken. The pusher's prices for you go up
  while hunted.

### Choice 2: tip the cops

- After witnessing a boat night, tell the police (the desk at the police
  station or a patrol cop). Cash reward.
- The next boat night is a raid: blue lights at the pier, the boat doesn't
  come, crew arrested. Boat nights stop for the rest of the run.
- Drought: street prices roughly double and the pusher has shorter hours /
  limited stock for several days; regulars on the block look sicker (Ray
  included). Withdrawal pressure on the player rises because dope is
  harder to get.
- Risk: the pusher may suspect you — he won't front you, or sells only at
  a markup, for the rest of the run (builder's call how likely).

### Choice 3: get on the boat (new ending)

- After witnessing, at a later boat night, walk up to the boat men openly.
  They take you only for something big: a lot of cash (order of $200) or
  mom's ring (the existing `belongings["ring"]`) — the player chooses
  which to give up. Not the ripped bag (that gets you killed — a beating
  and thrown in at minimum; builder may make it a death).
- You ride out at dawn: short cutscene, the block shrinking, the
  lighthouse passing, the sea. New ending cause `"boat"` through
  `GameState.end_run`, with an `ending_line` that depends on Mia/Ray state
  like the others ("You never went back. Mia never heard from you again."
  tone — you're gone, still sick). New MetaProgress unlock for it.

## Save, schedules and other systems

- Everything above survives save/load mid-day and mid-boat-night (stash,
  hunted days, drought days, trust, next boat night, the ending
  requirements).
- Pusher hours already differ by branch (Task 4 changed them); the boat
  night must work with whatever `PUSHER_HOURS` / schedules say on the
  merged branch.
- Credits/LICENSES: any new asset (water normal maps, boat, pier props,
  sounds) recorded with licence and author. Non-commercial assets are fine;
  EU-excluded tools are not.

## Tests (project convention)

- `_harbour_checks(gs)` in `dev-tools/smoke_test_3d.gd` plus
  `dev-tools/smoke_harbour.gd`: no void (rays from cameras at every
  block edge hit seawall/water/sky), pier walkable and navmeshed, only one
  pier, fisherman on schedule, fishing awards money and softens
  withdrawal, trust → hint, boat night timing, each of the three choices
  end to end, swim warmth drain + ladder out, hunted / drought timers,
  save/load during a boat night, Dead Block has none of the events.
- Perf gate in a window on Low, walking the full loop and the pier, day
  and night (with `--no-sick`, never in the real game).
- Renders: the pier at dusk looking north, the sea from each block edge,
  the boat night under the lamp.

## Order of work

The open-world block Tasks 2-4 are in flight on separate branches and all
touch `City3D.gd`, the builder and the smoke test. This work starts after
those merge into `zombie-mode`, as a new open-world task (before Task 7's
art pass, which may restyle the pier with real models).

## Settled after the builder check (controller's calls)

- Builds after open-world Tasks 2-4 merge; `Schedules.gd`, the Task 4
  pusher hours and the walk-in work exist then. Task 5 stashes don't yet:
  the ripped bag goes into the inventory; a stash hook follows when Task 5
  lands.
- Fishing's softer withdrawal is a transient multiplier on craving decay
  and the sickness screen effects, not saved; loading a save made while
  fishing stands you up.
- Drowning is `Survival.die()` → `end_run("health")` like other deaths.
  Being thrown in by the crew drops you near a seawall ladder: survivable
  if you swim straight for it. The rip-escape swim is lethal only if you
  linger.
- The existing pusher walks to the pier head for the drop (a boat-night
  schedule entry around 02:45-03:45) and goes back to his normal hours.
  The two crew and two boat men are new bodies from a pool built during
  the title warm-up — nothing loads while walking.
- Drought, hunted and "boat stopped" are per run; only the ending unlock
  carries over (MetaProgress).
- Sal and the cop tip extend the existing NPC talk interactions; the
  notebook uses `GameState.log_event` / `ui/Notebook.gd`.
- The boat ending uses the existing `Cutscene` autoload (stills or a
  short graded clip plus captions), new scene id `"boat"`, not a live
  camera sequence.

## Left to the builder

Exact pier x, length and shape; sea shader details; boat model
(Sketchfab/Poly Haven/CC0 or built); numbers (fish prices, boat-night
cadence, reward, drought length, hunted length, cost to board, swim
time); the fishing input feel; the enforcer's patrol; whether the pusher's
suspicion after a tip is a chance or certain.
