# Open world: the block — design

Date: 2026-10-18. Status: approved in conversation ("just go on").

## Intent

Dope Sick's city is one 59 m street; every place off it is a separate scene
behind a fade. The player wants it to feel like an open world: a whole
block to walk around, people with somewhere to be, things to find, and a
way to get around faster. AA-quality look and feel, and it must stay
smooth on the target laptop (Intel UHD 620, 1600x900, 60 Hz): walking
stutter was just fixed and must not come back.

Decisions the player made:
- Size: one full block, about 140 x 90 m (option "one full block").
- Walk-in (no fade): convenience store, liquor store, pawn shop, music
  store. Pharmacy, supermarket, electronics, bar, shelter, kart center,
  jail and the apartment keep their doors.
- Getting round: a bike.
- Loading: the whole block is resident, split into cells that sleep when
  far (approach A). Nothing loads while walking.

## Layout

```
          Back Street (north): stoops, the projects entrance, bus shelter
   +--------------------------------------------------------------------+
 W | park / court        |  back alley loop     |  lot + underpass camp  | E
 A | (gate locks 22:00)  |  (dumpsters, fire    |  (tents; the pusher's  | A
 v |                     |   escapes, back      |   new spot; fence hole)| v
 e |                     |   doors of shops)    |                        | e
   +--------------------------------------------------------------------+
          Main Street (south): today's street, unchanged in the middle
```

- World axes as today: x east, z south, buildings on Main Street's north
  side face south (+z); the camera sits south of the player looking north.
- Main Street keeps today's x in [-29, 29] exactly as built (shops, doors,
  markers, NPC positions, mailbox, police station, the pusher's alleys) and
  is extended to x in [-70, 70] with new frontage.
- West Ave (x ~ -70) and East Ave (x ~ +70) run north to Back Street
  (z ~ -90). The block interior is z in (-85, -6).
- One back alley loop: from the alleys at x = 14 / 21 north to an
  east-west service lane behind the shops, out to Back Street. The
  backyard gate (Backyard3D) stays a door.
- Landmarks: a tall neon pharmacy sign at the west end, the elevated
  overpass at the east end. Bends/buildings keep any sightline under
  ~50 m. No dead ends.
- Built in `dev-tools/build_rooms_3d.gd` (the generator for City3D.tscn)
  with the existing kit (Facades.gd pieces, Poly Haven / ambientCG
  textures, Rocketbox cast). New builder code goes in focused helper files
  `dev-tools/city/*.gd` called from `_build_city()`, one per area, so the
  generator doesn't become one giant function.

## Cells (residency without loading)

- `world/BlockCells.gd` (child of City3D): five cells — Main, West, East,
  Back, Interior (alley/park/lot). Each is a Node3D root in City3D.tscn.
- A cell is *awake* if the player is in it or within 25 m of its bounds;
  otherwise *asleep*: `process_mode = DISABLED`, visible = false for
  non-landmark geometry, lights off. Landmarks stay visible.
- Switching is incremental: at most one cell changes state per frame.
- Static occluders: one OccluderInstance3D box per building, baked by the
  generator; occlusion culling enabled in project settings only if it
  measures as a win on the UHD 620 (gpu_probe.gd), otherwise left off.
- Repeated props (bins, bollards, litter, windows) as MultiMeshInstance3D
  per cell.
- Navigation: one NavigationRegion3D per cell baked at build time, edges
  matching so they connect; no runtime baking.

## Seeing the player

- Walls/roofs between camera and player dither out (alpha-scissor style
  `discard` in a spatial shader, no alpha blending), driven by a global
  shader uniform with the player's position. Applies to building meshes
  in the block via a shared material override pass in the generator.

## Walk-in shops

- Convenience, liquor, pawn and music store interiors are built inside
  their buildings in City3D (same fixtures/guards/items logic as the
  separate scenes, reusing the builder helpers), with glass shopfronts.
- The interior is part of its building's cell. Entering (an Area3D at the
  door) raises the interior lights and hides that building's roof/upper
  floor; leaving reverses it. Store3D logic (theft, guards, prices) is
  reused by attaching the same script to the in-street interior root.
- The old separate scenes stay in the repo until the walk-in versions pass
  the smoke test, then their doors are removed.

## People with somewhere to be

- `autoload/Schedules.gd`: per-character schedule resources: list of
  `{from_minute, place_id, activity}`; places are named markers in the
  block (`Place_*`). Midnight wrap handled.
- Three tiers: visible (full NPC), awake cell but off-screen (moves along
  its path at 4 Hz, no animation), asleep cell (pure data: position is a
  function of the schedule and the clock; snapped to the navmesh when the
  cell wakes).
- Scheduled: the postman, the beat cop's patrol loop round the block,
  the pusher (corner by day, underpass by night), Ray, shopkeepers
  opening/closing, 8-12 named regulars (park, bus stop, stoops). Generic
  passers-by keep today's lane walkers, on all four streets.
- Avoidance only for agents within 10 m of the player; repath at most
  every 0.75 s.

## Exploration and the bike

- Each area gets one secret that changes a route: a fire-escape ladder
  you kick down from a roof (shortcut alley -> Back Street), a fence hole
  (lot -> underpass), the park gate's broken lock, back doors of the
  walk-in shops (alley access), a rooftop run between two buildings.
- Stashes: 10-15 hand-placed hiding spots that refill on a schedule with
  survival items, some tied to schedules (only reachable while the
  guard is gone). Found places are recorded in the notebook.
- Bike: a beat-up bike, found/stolen at a rack; ~3x walking speed (about
  5.5 m/s, a bike's planted-feet problem doesn't apply — pedalling clip
  or a sitting pose with cranks animated). Left at racks to go inside;
  can be stolen if left unlocked. Not usable indoors or in the alley's
  narrow spots.

## Performance budget (UHD 620, Low)

- 60 FPS walking anywhere on the block, GPU <= 13 ms at the lean scale,
  no frame > 25 ms while walking (perf.log / hitch_probe), measured on
  all four streets day and night.
- Startup of City3D behind the fade: <= 2.5 s.

## Testing

- Smoke test (dev-tools/smoke_test_3d.gd) sections per feature: layout
  (every street reachable via navmesh, no dead ends), cells (sleep/wake),
  walk-in shops (theft/guards work without a scene change), schedules
  (people are where their schedule says at given times, across midnight),
  stashes and secrets, the bike.
- Probes: walking loop of the whole block with hitch_probe-style timing
  and the char_jitter check; gpu_probe on each street.

## Out of scope

- Streaming beyond the block, more blocks, cars you drive, a full
  interior for the bigger stores.
