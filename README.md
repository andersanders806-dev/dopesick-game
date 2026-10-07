# Dope Sick

A dark, low-budget top-down stealth game about addiction, theft, and getting by.

## 3D version (current main scene)

The game is being ported from 2D to 3D. The 3D version is now the main
scene (`world/Apartment3D.tscn`). The original 2D scenes are still in place
alongside it.

**The 3D loop:** wake up in the Apartment and head out onto the City block
(56 m, eight buildings: police station, apartments, pharmacy, Dive Bar,
corner shop, liquor store, supermarket, electronics store). In the Dive Bar a
patron asks for something and tells you which store has it. Steal it without
a guard seeing, bring it back, get paid, and buy from the pusher in person at
the dark end of the block. Get caught and you wake up in a jail cell.

- **Art:** real places, not a toy kit -- see **Real places** below. The
  buildings are Poly Haven's CC0 modular facade kits, the props mostly Poly
  Haven models (`assets/polyhaven/`), the surfaces ambientCG and Poly Haven
  PBR materials (`assets/pbr/`); Kenney's CC0 kits are left for small
  clutter and the traffic. *People* are Microsoft Rocketbox avatars
  (`assets/rocketbox/`, MIT) -- see **Characters** below.
- **Real places.** The street is a row of brick fronts built at load by
  `world/Facades.gd` from the kits' 3 x 3 m modules (apartment blocks for
  the shops, the factory kit for the tall fillers), with framed shop glass
  lit from inside while a place is open and a roller shutter down while
  it's closed; fire escapes, air-con units and cameras on the walls,
  cast-iron street lamps, cars under tarps, worn asphalt with a faded
  centre line, paving slabs and a curb. The apartment has an iron bed
  frame, a worn sofa, real boxes and a metal bin; the Dive Bar a dark
  varnished counter and back bar, real bottles, stools and pendants; the
  stores steel shelving, tube fittings and tiled floors. Colliders, zones
  and the navmesh didn't move. `dev-tools/fetch_polyhaven_models.py` and
  `fetch_ambientcg.py` fetch the assets. Measured on a UHD 620 (GPU ms,
  Medium, A/B against the old art): City 20.6 -> 23.0, Dive Bar 16.7 ->
  16.7, supermarket 15.8 -> 16.3; Low unchanged. The fronts cast no
  shadows (the lamps hang in front of them), use coarse LODs and opaque
  window glass, and the mesh LOD threshold is 4 px below High.
- **Characters: realistic people.** The whole cast -- you, the pusher,
  Tasha, the cops and guards, every clerk, the bartender, the Dive Bar
  regulars, Ray, the passers-by: 43 people -- are Microsoft Rocketbox
  avatars (MIT licence, `assets/rocketbox/LICENSE.md`): real faces, hair,
  hands and textured clothes, rigged by professionals, made for research
  and VR. They replaced Quaternius' CC0 low-poly humans, which had the
  right proportions but no textures and simple faces. Each is a different
  avatar matched to the part (the pusher is an ordinary guy in a grey
  hoodie, hood up; Ray is a weathered older man in work clothes, greyed),
  so nobody is recoloured. `dev-tools/fetch_rocketbox.py` downloads and
  converts them: `rocketbox_to_glb.py` (Blender) retargets the library's
  animations onto each avatar's own skeleton -- baking world-space
  rotations, because the animation files' rest pose isn't the avatars' --
  and shrinks the textures to 1024/512 px; `slim_glb.py` then drops the
  animation channels that never move. In withdrawal you walk with the
  library's bruised, hunched walk and fidget when you stand still. They
  have no fall, so a body in the alley is laid down.
- **One cast list.** `npc/CharacterCast.gd` maps a *role* ("player",
  "pusher", "bartender", "clerk_liquor", "security_guard", each Dive Bar
  regular by name) to a body; nothing else in the game hardcodes a model
  path, and `CharacterCast.dress()` even swaps out a body a scene has built
  in if it isn't the role's. `npc/CharacterLook.gd` cuts the Rocketbox hair
  and lashes out with alpha scissor (blended, they sort wrong and the hair
  turns see-through) and applies an optional whole-body tint.
- **Patrons keep their faces.** A Dive Bar regular's body now comes from
  their name, not from a pool shuffled per visit. Big Eddie used to come
  back as somebody else entirely, and since the pool was all *female*
  models, four of the six male-named regulars were wearing the wrong body.
- **Clip names are resolved, not hardcoded.** `npc/CharacterAnimator.gd`
  takes logical clips ("idle", "walk", "sprint", "sit", "pick-up",
  "interact") and resolves each against whatever the loaded model actually
  ships, so the same call sites drive Kenney's `walk`, Quaternius'
  `HumanArmature|Female_Walk` and the Rocketbox clips baked in as `walk`. It also has `play_once_timed()`, which
  stretches a one-shot to a requested duration: source clips differ wildly
  between packs (Kenney's grab is 0.33 s, the Quaternius stand-in 0.917 s),
  so the old fixed speed multiplier tuned against Kenney turned the grab
  into a 3.3-second freeze against the new bodies. Timing-critical callers
  (the player's grab, the pusher's stash crouch and handoff) now ask for
  seconds and get seconds.
- **Rendering.** All five rooms share one `_environment()` in
  `dev-tools/build_rooms_3d.gd`. It uses **AgX** rather than ACES (ACES
  clips the neon signs and the police beacon to a white blob; AgX
  desaturates gracefully so a red tube still reads red at its core),
  **SSIL** on top of SSAO so light bounces colour -- the bar's red neon
  spills onto the panelling, the TV's flicker lands on the apartment floor
  -- plus screen-space reflections, volumetric fog for real light shafts,
  a mild far-field depth of field (blur starts at 16 m, past everything you
  need to see), and a contrast/saturation grade to put the bite back into
  AgX's deliberately flat output. `project.godot` backs this with 1280x720,
  4x MSAA, TAA, 4096 shadow atlas, and high SSAO/SSIL quality.
- **PBR surfaces:** floors and walls (asphalt, sidewalk, brick, wood
  floor, concrete, linoleum, store tiles, cinder block, bar panelling,
  boarded-window planks) are Poly Haven CC0 sets with albedo, normal, and
  roughness maps in `assets/pbr/`, fetched by
  `python3 dev-tools/fetch_polyhaven.py` and applied at true real-world
  scale by `_pbr_mat()` in `build_rooms_3d.gd`. The older albedo-only
  textures map onto them through `PBR_FOR`, so old call sites upgrade
  unchanged.
- **Cutscenes.** `autoload/Cutscene.gd` plays short illustrated scenes at
  the moments the game used to jump straight past: the first morning of a
  run (the Apartment), an ordinary bust (before the cell), a final bust
  ("sent away") and an overdose (both before the run-end screen, which then
  keeps the last still dimmed behind its numbers). Each scene is a few
  stills under letterbox bars, slowly drifting (Ken Burns), with film grain
  and a vignette to match the in-game grade and a caption typed out below.
  Any key finishes the caption and then advances; Escape skips the scene;
  the game is paused throughout. `await Cutscene.play("busted")` is the
  whole API, and scenes are plain data in `Cutscene.SCENES`. The stills
  (`assets/cutscenes/`, 1280x720) are painted by
  `dev-tools/gen_cutscenes.py` from the prompts in
  `dev-tools/cutscene_prompts.json`, through AI Horde
  (stablehorde.net) -- a free, volunteer-run Stable Diffusion network with a
  public API. A missing still falls back to a dark gradient, so a scene
  still plays, text only. Two other routes were tried first: Perchance's
  AI image generator gave the right look (its "Cinematic" style) but draws
  into a sandboxed frame with no way to save full-size files from a
  script, and Pollinations, which `gen_portraits.py` used, now answers
  `402 Payment Required`.
- **Recorded sound:** footsteps, doors, stealing (cloth rustle), and cash
  (coins) use Kenney's CC0 Impact Sounds / RPG Audio recordings
  (`assets/sfx/kenney/`), several takes each picked at random. Footsteps
  follow the floor: wood in the Apartment and Dive Bar, concrete
  everywhere else (`SFX.ROOM_SURFACE`), for the player and police alike.
- **First person or third.** New run asks which: through your own eyes
  (mouse or right stick to look, walking goes where you face), or the
  camera up over the room as before. Settings switches it any time
  (`Graphics.first_person`). The rooms were built to be seen from above,
  with no lid and a cut-down front wall, so in first person
  `world/FirstPersonRoom.gd` gives each one a ceiling and its front wall
  back. The street and the lot stay open to the sky.
- **PS5 controller, laid out like Call of Duty** (`GameState.PAD`). Left
  stick moves, right stick is the camera, L3 sprints (click and go, until
  you stop), square is use, circle backs out, options pauses, the touchpad
  is the notebook, triangle is the tapes and the d-pad skips one. R2 fires:
  a dart, the cue (hold and let go), the kart's gas. L2 steadies your
  breath at the board, fine-aims the cue, and brakes. Every binding is on
  any pad, not just joypad 0, and hints name the pad's buttons while
  you're on it. `dev-tools/smoke_controller.gd` and `smoke_view.gd` run
  just these checks.
- **Graphics presets (F3) and FPS counter (F4):** `autoload/Graphics.gd`.
  The rooms are built with the full look (SSIL, SSR, volumetric fog, TAA,
  far DOF); that's "High", which runs at ~12 FPS in the City on an Intel
  UHD 620. "Medium" (~25-35 FPS there) and "Low" (~42-59 FPS) drop the
  expensive passes and fake the haze with depth fog. Integrated GPUs start
  on Low. Edges: SMAA at every preset, and on High TAA too, upscaled with
  FSR 1 from 67-85%. High used FSR 2 from ~59%, which on a UHD 620 left
  edges crawling at 20-25 FPS, and measured slower than this. FSR 2 is
  now the PS5 preset's, for a desktop GPU. Shadows run on a budget: only
  the lamps nearest you cast them (2 on Medium, 3 on High, all on PS5).
  Below High the moon drops its shadow after dark (faint, and ~3.5 ms on
  the street), and Low drops the glow pass (a fixed ~3.5 ms). An
  integrated GPU left on High or PS5 is moved to Medium once, with a toast
  saying F3 puts it back. And if High still runs under 24 FPS for 5 s on
  laptop graphics, it drops to Medium once a session, saying why; pick
  High again with F3 and it stays. The colour grade -- a 3D LUT built in code (teal shadows, amber
  highlights, an S-curve) plus saturation 1.18 -- applies at every preset.
  The withdrawal tint only appears once you're actually getting sick; it
  used to sit at ~20% green over everything.
- **Room changes fade instead of freezing** (`autoload/SceneLoader.gd`).
  Going through a door used to freeze the game for 3.6-5.3 s on a UHD 620:
  the street re-read both facade kits (1.5 s) and the extras' character
  models (~1 s) and its fire escapes, cameras and shutters (0.6 s) on
  every visit. Those now stay loaded for the session (`Facades.gd`,
  `CharacterCast.scene_for`), every room you've been in stays loaded, the
  street and its facade kits load on a background thread from the first
  room you're in, and walking within 4 m of a door starts loading the room
  behind it. Measured on the UHD 620 (longest frame, all of it behind the
  black): first time onto the street 2.1 s (was 3.4-5.3), back onto it
  0.5-0.6 s, into the bar or a store 0.2-0.3 s. The change itself is a fade through
  black (0.25 s out, 0.35 s in, the world holding still until you can see
  it), then a card under the HUD: "THE DIVE BAR · 20:14". Doors, arrests,
  the station door and Continue all go through it.
- **Interaction prompts** (`ui/Prompts.gd`, `ui/InteractPrompt.gd`): the
  thing E / Square would use has a few words floating over it -- "E  Enter
  the Dive Bar", "Square  Talk to Ray", "E  Steal a bottle of vodka",
  "Sleep", "Your guitar". Under the crosshair in first person; hidden in
  dialogue, menus and fades.
- **Cutscenes are real footage, 3 s each** (`autoload/Cutscene.gd`,
  `assets/cutscenes/video/`). The opening, the bust, being sent away, the
  first score, release, each new day, temptation, relapse, walking past it,
  recovery and the overdose are each one clip of graded real footage
  (Mixkit, free licence, credits in the folder) with one line under it,
  over in three seconds; any key skips. `dev-tools/make_cutscene_video.py`
  rebuilds them. The painted stills are still the fallback and the
  run-end backdrops.
- **Every place sounds like itself.** A real CC0 field recording loops
  under each of the 14 rooms (`world/PlaceAmbience.gd`): distant
  late-night LA traffic on the street, bar chatter in the Dive Bar, a
  supermarket's tills and announcements, a convenience store's fridges, a
  jail's echo, an empty shop's air conditioning in the pawnshop, a
  cafeteria at the shelter, go-karts through the office wall. All from
  Freesound, cut to seamless loops (4 s crossfade) and levelled to
  -26 LUFS; see `assets/sfx/places/CREDITS.txt`. The rooms' positional
  sounds (bulb, cooler, TV, jukebox) still play on top.
- **Voices:** `autoload/Voice.gd` speaks the quoted part of every dialogue
  line in the character's own voice, using Piper
  (github.com/rhasspy/piper, MIT) with the LibriTTS-R model's 904 voices,
  cast by measured pitch. Piper lives in `tools/piper/` (gitignored, ~100
  MB); lines are generated on first use on a background thread and cached
  as .wav in `assets/voice/`. `dev-tools/bake_voices.gd` pre-generates all
  NPC small talk.
- **Music and mix:** OpenGameArt tracks in `assets/music/` (see
  CREDITS.txt; one is CC-BY 4.0 and needs its credit kept) -- lo-fi on the
  street by day, trap at night, lo-fi in the apartment, the jukebox plays a
  real record, and a chase gets its own track. `SFX.gd` builds Music / SFX /
  Voice / Ambience buses into a compressed, limited master, and the SFX and
  Voice reverb follows the room.
- **Poly Haven models:** 18 CC0 low-poly props (`assets/polyhaven/`, from
  `dev-tools/fetch_polyhaven_models.py`, placed with `_ph()`): trash bags,
  rats running the wall line, manhole covers, utility boxes, a tyre, cash
  registers, the dartboard, the apartment TV, the backyard's fire barrel,
  roller shutter and junk, the shelter's desk and chair.
- **Honest work.** `autoload/Jobs.gd`, for less than stealing pays and
  with nobody chasing you: unload the supermarket's delivery truck in the
  lot out back (6-10, five boxes truck to pallet -- you carry them, a
  little slower -- $12, once a day); take the flyer job off the shelter's
  noticeboard and pin five up at the glowing spots on the block ($8); and
  pick bottles out of the gutter (five a day) for the machine inside the
  supermarket's door, $1 a three. Job zones are placed on the nearest
  walkable spot once a room's navmesh is baked, and kept off the pusher's
  corner and the doors.
- **Temptation.** `world/Temptation.gd`, only while you're in the
  program, once a day each: the pusher calls you over when you pass on his
  shift ("First one's on me"), and when the withdrawal's biting a flash of
  his corner plays and your feet start turning that way. Holding on hurts
  (craving down); giving in is using, so that day won't count. Both have
  their own narrated panel, and both go in the diary.
- **The notebook (J).** `ui/Notebook.gd`, biro on lined paper, and the
  game waits while it's out: who wants what and from where, every opening
  hour with "open now", a map of the block with you and the pusher on it,
  and notes on the run so far. Also on the pause menu.
- **Word on the block: a different day, every day** (`autoload/Headlines.gd`).
  Each day rolls one event, announced in a strip under the HUD when you're
  up and noted at the top of the notebook: *crackdown* (staff x1.25, the
  beat cop sees 35% further and comes back sooner, pusher +25%), *delivery
  strike* (supermarket shut, no truck or dock job), *pool tournament* ($20
  in, $80 pot, once), *storm* (rain all day, fewer people, sleepier staff),
  *payday* (orders pay x1.4, busier street), *dry spell* (6-8 kinds at the
  pusher, +50%), *Speedway Cup* (karts open at noon, triple prizes), *track
  shut* (the day after a carburetor goes missing), or a quiet day. Day one
  is always quiet. It saves with the run; tests pin it with
  `Headlines.forced`.
- **The regulars remember you** (`GameState.rep`, -5..5 by name). Deliver
  what they asked for and they like you more, and pay $3 a point extra.
  At 2+ they tip you off once a day about a store's staff (that clerk
  watches x0.7 for the day). Sell their order to the bartender or the
  pawnshop instead and they hear about it; at -2 they won't give you work,
  and they have a word with the clerk where you'd steal it (x1.3 for two
  days). The notebook lists who feels what.
- **The kart hustle.** Big Eddie hangs around the kart office
  (`npc/KartHustler3D.gd`) and pays $30 for a thrown race: 4th or worse,
  within 8 s of the kart ahead and without driving the wrong way, or it's
  "too obvious" and he doesn't pay. Take the podium after shaking on it and
  he's burned (-2), and stops showing up. When the pusher's on shift his
  runner takes $10 on yourself; a podium pays $25. The spares box behind
  the desk has a carburetor ($30 at the pawnshop): get seen (35%) and
  you're thrown out for the day; don't, and the track's shut tomorrow.
- **Losing the police.** Two hiding spots on the block (behind pallets in
  the alley mouth at x = 14, and the far end of the dumpster), plus the
  one in the lot out back. Walking among passersby, a cop more than 5 m
  off loses you in the crowd. And officers search now: one who saw you
  walks to where he lost you and checks the hiding spots within 4.5 m of
  it, so ducking in right in front of him gets you found -- break line of
  sight first, then hide. One who never saw you (called in by a clerk)
  gives up after 4 s, as before.
- **Withdrawal you can see.** As the meter bottoms out the room's colour
  drains (saturation down to 30%, a harder contrast), every neon sign on
  the block starts to stutter, people react to how you look, and in the
  notebook your own handwriting swims -- letters swap in item and store
  names. All of it comes back as you do.
- **Your own things.** Five things in the apartment are yours to sell: the
  TV ($24), the old radio ($8), your guitar ($30), your winter coat ($10)
  and your mother's ring ($45) (`interactables/Belonging3D.gd`,
  `GameState.belongings`). Take one and its prop is gone from the room;
  three gone and the room echoes. They're yours, not stolen: a bust leaves
  them in your pockets, the bartender won't fence them, and the beat cop
  doesn't look twice. The pawnshop pays full value and writes a ticket: buy
  it back for 1.5x within four days, or it's sold. Carry it back through
  the door and it goes where it lives.
- **Rent.** $35 every five days, through the envelope slot by the door.
  Miss it and there's a final notice ($10 late fee) and one more day; miss
  that and the lock's changed -- the City door turns you away until you
  buzz the landlord (08-22) and pay it all plus $20 for the locksmith. If
  you're home when it happens, he shows you out. The shelter's cots are
  where you sleep in the meantime.
- **Court.** A bust that doesn't end the run puts you in front of a judge
  two days later, 09-12, at the police station's door
  (`interactables/PoliceDoor3D.gd`). In the program, it's drug court and a
  strike comes off. Otherwise it's three days' probation: check in at the
  same door 09-17, and the test fails on anything off the street in the
  last 24 game hours (a strike, and the cell). Miss court or a check-in
  and there's a warrant: the beat cop recognises you on sight. Turn
  yourself in at the door for a night in the cell and a fresh date, no
  strike. The HUD shows whichever of rent, court, probation or a warrant
  is most pressing, and the notebook's notes page lists them all with any
  pawn tickets. `dev-tools/smoke_batch1.gd` runs just these checks.
- **The street gets dangerous.** Three things that happen on the block
  whether you're ready or not. `dev-tools/smoke_batch2.gd` runs just these
  checks.
  - *Bad batch.* Some days the word on the block is that what's going
    around is cut. On those days 40% of the opioids the pusher sells are
    contaminated, at three times the overdose risk. Nothing tells you,
    except a test strip: the outreach worker hands out two a visit, once a
    day. With a strip in your pocket the pusher's handoff lets you test
    first, then take it all, take a little at a time, or bin it. Esc just
    takes it, so a dose you paid for never vanishes by accident.
  - *Someone goes over in the alley* (`world/AlleyOverdose.gd`). About one
    night in four, every bad-batch night, never day 1: one of the Dive Bar
    regulars goes down beside the dumpster some time after 18:00. You get
    90 real seconds on the block to find them. Naloxone saves them (rep
    +3). Running for the payphone saves them too (rep +2), but a cop comes
    with the ambulance. You can go through their pockets ($8-20; they die).
    Walk on and two times in three nobody else stops. The dead don't come
    back to the bar. The day after there are candles and their name on the
    wall, and the pusher charges 10% less. The alley
    stops taking regulars when four are left, so the bar still fills.
  - *Tasha* (`world/Booster.gd`). A rival booster, out about two days in
    five, 10-20, never on a vigil day. Each hour she cases a store and
    then hits it, and its staff are jumpy (x1.3) for the rest of the day,
    whether or not you're out there to see it. The notebook's map marks
    her with a T and what she's hit with an x. Team up and she works one
    clerk for you (x0.6) for the day, for half your next order. Or give
    her up to the beat cop: she's gone for good, her heat goes with her,
    and so does your warrant. But Ray stops trusting you and every regular
    thinks a little less of you.
- **Southside Speedway: go-karts, $5 a ride.** The KARTS door on the
  block (x = -14, open 14:00-24:00) leads to the front office
  (`world/KartCenter3D.gd`): a chequered floor, a marshal at the sign-up
  desk, a kart on a display stand, loaner helmets, the lap record on the
  board. Pay $5 and you race three laps against five of the Dive Bar
  regulars in `ui/KartRace.gd`, a floodlit night track in an old
  industrial lot, built entirely in code inside its own SubViewport world.
  - *The track* is a closed Catmull-Rom spline (`CIRCUIT`) resampled every
    metre into points, tangents, normals and signed curvature, and
    everything reads those samples: the asphalt and gravel ribbons, painted
    edge lines, red-and-white kerbs on every bend under ~40 m radius (one
    vertex-coloured mesh), tyre walls (a MultiMesh of ~3000 tyres, spaced
    evenly along the wall rather than the centre line), floodlight masts
    with real spotlights, a grandstand with a MultiMesh crowd, a pit
    building, sponsor boards from businesses on the block, cones at the
    apexes, a start gantry with five working start lights, a chequered
    grid, and a skyline of lit towers past the fence. The layout was
    checked for no bend tighter than 9 m (the walls sit 7 m out) and 30 m+
    between separate parts of the track.
  - *Karts* are arcade, not a physics engine: speed along the nose, slip
    across it that grip bleeds off, a yaw rate from the wheel. Collisions
    are against the track itself (distance from the centre line), so a wall
    hit is exact and never snags: it bounces you back in and costs pace.
    The gravel slows you; karts bump each other. Each kart is modelled from
    primitives (nose, pods, seat, engine, exhaust, number board, slicks
    that spin and steer, a steering wheel that turns) with the driver's
    actual character model seated in it, wearing a helmet.
  - *Drifting* follows the Mario Kart mini-turbo (researched from public
    Godot kart write-ups): hold Shift or Space while steering at speed and
    the kart hops into a drift. In a drift the wheel sets an *arc*, from
    7 m at full lock to 30 m at full counter-steer, so it's controllable at
    any speed. Hold ~1 s for blue sparks, ~2 s for orange; let go for a
    blue (0.8 s) or orange (1.4 s) turbo, up to 35% over top speed, with
    exhaust flame, a wider FOV and a whoosh. Drifts and hard braking lay
    rubber on the asphalt (a ring-buffered MultiMesh of skid marks).
  - *The AI* chases a point ahead on the line ("chase the rabbit"), shifted
    into a lane toward the apex and around slower karts, brakes for the
    curvature coming up (v = sqrt(a / curvature)), drifts the long bends,
    and gets a mild rubber band so a race stays close. Skill sets top speed
    and cornering.
  - *Race flow:* a slow camera swing round the grid, five red lights, GO,
    a chase cam that swings wide in a drift and shakes on a hit, lap and
    "FINAL LAP" banners, wrong-way warning, then an orbiting victory camera
    and a results board. The HUD has position, lap, lap/best/total times,
    the running order with gaps, a minimap, a speedometer, and the drift
    and turbo meter. E races again for $5; Esc leaves (mid-race it asks
    first, and the $5 stays spent).
  - *Sound* is synthesised: a two-stroke engine generated live from your
    speed and throttle, the pack as a drone that swells when they're close,
    tyre squeal while drifting, start beeps, thuds, the turbo whoosh, and a
    crowd cheer at the flag.
  - *Stakes:* the day's first race pays the podium $15 / $8 / $5; after
    that you're racing for the board. The world waits while you race (like
    pool), it goes in the run diary, and finishing takes the edge off the
    craving a little.
  - *Frame rate:* the race renders like the rooms, below native and
    upscaled with FSR at whatever scale Graphics' governor has settled on,
    so it runs ~55 FPS on the UHD 620 that does ~45 on the block; the moon
    shadow is High-only and the tyres don't cast shadows.
  - *Tests:* the smoke test sells a ride, runs a whole race on
    `autopilot`, checks prize money (once a day), that the clock waited,
    and that a drift held through the track's longest bend charges a blue
    and then an orange turbo.
- **The camera follows you.** The rig floats free of the player and eases
  after them, keeping the character centred on screen, at the same
  distance in every room so a room's size reads as its size. (It used to
  clamp to each room's walls and zoom in on small rooms, which left you
  walking off-centre and made rooms jump in scale through a door.) The
  scroll wheel moves it in and out.
- **The run, told back.** `GameState.log_event()` records the run's
  moments -- waking up, the walkman, orders delivered, scores, busts,
  games won and lost, jobs, the program's days, temptation -- each with the
  cutscene still that matches. The notebook's notes page shows them, and
  the run-end screen opens on "How it went": the whole run, newest first,
  with thumbnails, beside the numbers and the upgrades.
- **Getting out: the recovery ending.** The outreach worker at the
  shelter enrolls you in the program with your first clinic dose. Every
  night you sleep, the day counts if you took that day's clinic dose and
  nothing off the street (cannabis aside); a slip resets the count, not the
  program. `GameState.RECOVERY_DAYS` (5) in a row ends the run as "YOU GOT
  OUT", with its own cutscene and 15 days' worth of extra Know-How. The HUD
  shows "clean n/5" next to the day while you're in it.
- **Overdose that works like the real thing.** Tolerance used to protect
  every dose on its own, so forty doses back to back were forty separate
  small risks. Now each opioid or benzo adds to a respiratory load that
  fades over about 100 game minutes, and the chance of going over climbs
  with what's already on board -- redosing is what kills. Tolerance
  softens that load only down to 70%, and fades by half in a day and a half
  without use, so the first dose after a night in jail or a few days in
  treatment is the dangerous one (the jail tells you so on the way out).
  `dev-tools/drug_sim.gd` now passes real time between doses and has
  binge and relapse strategies: over two weeks, clinic bupe ~3% go over,
  steady heroin ~19%, fentanyl ~27%, opioid + benzo ~31%, a four-dose
  fentanyl binge 100%.
- **A narrator.** Cutscene captions are read aloud by their own Piper
  voice (LibriTTS-R, a low, unhurried reader), and each panel holds until
  the reading's done. `dev-tools/bake_voices.gd` now bakes every caption
  too, so it's all there without Piper installed. Cached lines also load as
  imported resources, which is what an exported build will need -- the old
  code only read loose .wav files from disk.
- **The block's regulars.** `world/StreetScenes.gd`: a smoker in the
  liquor store's doorway (10-23, ember and smoke), Dee and Marcus arguing
  outside the bar after dark (walk close and pieces of it float over
  them), and Carl asleep on the apartment steps until morning. The three
  are the shelter's dinner regulars, same bodies and clothes, at the other
  end of their day. In the rain, passersby duck under the awnings and wait
  it out.
- **Title screen, pause, settings, saves.** The game opens on
  `ui/TitleScreen.tscn`: a cutscene still drifting behind the name, a punk
  tape playing, Continue / New run / Settings / Quit. Esc in play opens
  `ui/PauseMenu.gd` (resume, settings, save and quit to title) -- it closes
  an open line of dialogue first. `ui/SettingsMenu.gd` has the graphics
  preset, fullscreen, the frame counter and a volume slider per mix bus
  (scaling each bus from SFX's base level, so the mix survives), all kept
  in user://settings.cfg by Graphics. `autoload/SaveGame.gd` keeps one run
  in user://save.json: written on walking into any room and on sleeping,
  never while wanted or in custody (no quitting out of a chase), restored
  by Continue into the same room and spot, and deleted when the run ends.
- **More cutscenes, one face.** Every still with the protagonist in it is
  painted from one description matching the 3D player (grey-green t-shirt,
  blue-grey jeans, short brown hair) and one seed, so he's recognisably the
  same man from the mattress to the courtroom. New scenes: the first score
  of a run (Pusher3D, before the handoff), walking out of the cell
  (Jail3D.release), and a one-panel day card when you sleep (Bed3D).
  `dev-tools/horde.py` is the AI Horde client both painters share.
- **Portraits in the same film look.** `dev-tools/gen_portraits.py` now
  paints through AI Horde too (Pollinations went paid): 35mm head and
  shoulders, each person in their own place -- behind the bar, on the
  corner, at the pharmacy counter.
- **Darts.** The Dive Bar's board is playable for money (`ui/DartsGame.gd`):
  three rounds of three darts, high total wins. Your aim sways, worse the
  sicker you are; hold right mouse or Shift to hold your breath and steady
  it while it lasts. Real board proportions and scoring (trebles, doubles,
  bull). Three opponents, $5 to $20. Pool and darts both pause the day and
  the craving while you play, and both open on a one-time how-to.
- **Pool opponents that play their level.** Weaker regulars don't always
  see the easiest shot, wobble more on aim and pace, and sometimes just
  fluff one; the Shark still barely misses.
- **Street grit.** `world/StreetDressing.gd` dresses the block with decals
  generated by `dev-tools/gen_street_decals.py` (procedural, nothing to
  license): spray tags with overspray and drips, torn flyers (a lost dog,
  a gig, "we buy gold", the harm-reduction number), grime running down the
  shop fronts, stains, cracks and litter on the sidewalk, oil in the road,
  and puddles that turn glossy in the rain. Decals are near free, so every
  preset gets them. Wall decals project from -5.55 to -4.45 m: the shop
  fronts step back in panels, and the box stops before anyone walking by.
- **Walkman (T, N):** it's at the foot of the mattress when you wake,
  and after the opening cutscene the game points you at it. The shoebox
  starts with fifteen tapes, five of them punk (CC0 from OpenGameArt: Pro
  Sensory, madworldgames, annandistance, Tsorthan Grove), listed first.
  T opens it; "Shuffle the shoebox" plays every tape you own in random
  order instead of looping one, and N skips to the next (starting a
  shuffle if one tape was looping). The tape plays through the "Walkman"
  bus (thin foam-headphone EQ, a little tape wow) in every room -- area
  music drops out and the room ambience sinks 6 dB -- and a little
  cassette in the bottom-left corner shows what's in, reels turning (pink
  label for punk). `autoload/Walkman.gd` holds the 35-tape catalogue
  (`assets/tapes/`, `assets/music/`, see the CREDITS files). A 3xBlast
  pop-punk pack was considered and left out: it's CC0 but its readme asks
  that it not be re-uploaded as-is, which a public repo would do.
- **Tape Deck:** the music store between the pharmacy and the bar (open
  10-21). Its racks hold tapes you don't own yet -- lift one (it goes
  straight into the shoebox; the clerk watches like any store's staff) or
  buy at the counter. `world/MusicStore3D.gd`. The counter never worked
  until now: the room builder named its trigger "Counter", the same as
  the counter body beside it, and Godot quietly renamed the trigger to
  `@Area3D@32`, so the script's name check never matched. It's
  `CounterZone` now.
- **Pool for money:** walk up to the Dive Bar's table and pick a stake;
  the bigger the bet, the better the regular who takes it ($5 Old Sailor up
  to $50 The Shark). `ui/PoolGame.gd` is proper eight-ball: you break,
  groups are decided by the first legal pot, fouls (scratch, no contact,
  wrong ball first) give ball in hand, and the 8 wins or loses the pot.
  Cushions end in angled pocket jaws, so balls rattle; W/S put follow or
  draw on the cue ball, A/D side spin that bites off the rails. Balls are a
  sphere shader that really rolls (stripes turn over, numbers come and
  go), on shader-drawn worn felt and mahogany rails under a lamp, with a
  tapered cue, aim guides, a swinging power meter and a spin dial. The
  opponent plays the same physics: ghost-ball shots it can make, power
  worked out backwards from the friction model, a miss sized by its skill,
  safeties when there's nothing on, and it picks a good spot with ball in
  hand -- and you watch it line up. Written after reading the open-source
  Godot pool games on GitHub (danielKlmr/BreakoutShot, MIT, for its rules
  flow; tailuge/billiards is GPL, so only its ideas); none of their code
  or assets are used. Sounds are synthesized (`dev-tools/gen_pool_sfx.py`).
- **Full playthrough:** `dev-tools/full_playthrough.gd` plays the whole
  game through real input -- cutscene, walkman, an order, a game of pool,
  stealing and delivering, the pusher, Tape Deck, sleep, an arrest and the
  cell, and an overdose to the run-end screen -- with chapter titles on
  screen, meant for `--write-movie`.
- **The stash:** 21 drugs in `Drugs.CATALOGUE` now (tar, tranq dope,
  morphine, hydromorphone, hydrocodone, lean, tramadol, etizolam,
  gabapentin, cocaine, amphetamine, weed on top of the originals), and the
  pusher holds 12-17 of them a night. Not yet re-balanced with
  `dev-tools/drug_sim.gd`.
- **Street life:** `world/StreetLife.gd` -- traffic (Kenney Car Kit, CC0)
  on the one-way lane by the curb, with headlights at night, stopping and
  honking for you; steam from the manholes; hourly weather rolls (rain
  streaks, a rain loop, the street going wet and shiny, a darker sky); and
  two shop signs that flicker.
- **Camera:** a fixed-angle follow camera on the player looking north, so
  every room keeps its south wall low and puts doors on the side walls.
- **Room generation:** every 3D room (Apartment, City, Dive Bar, the five
  stores, and the Jail) is *generated*
  by `dev-tools/build_rooms_3d.gd`, not hand-edited. Change the layout
  there and rebuild with
  `godot --headless --path . res://dev-tools/BuildRooms3D.tscn`. It runs
  as a scene rather than via `-s` because the room scripts reference the
  `GameState`/`SFX` autoloads, which don't exist yet when a `-s` script's
  variables are initialised.
- **Per-visit variety:** every store picks one of its fixture layouts and
  shuffles its stock, but always keeps at least one of every item it sells on
  the shelves (`Store3D._ensure_every_item_stocked()`). Parked cars get random
  paint, and the Apartment picks one of 3 clutter layouts.
- **Orders stick until delivered:** the Dive Bar's patrons, their seats, and
  what they asked for live in `GameState.bar_patrons`, so the person who gave
  you an order is still there, asking for the same thing, after you leave,
  get busted, or sleep. Once you deliver, that patron goes home, and next
  visit a newcomer takes the seat with a fresh order. Newcomers never share a
  name, body, or order with anyone in the bar, or with the patron who just
  left. Previously everyone was reshuffled on every visit, so an order was
  often gone by the time you came back with the goods.
  Navmeshes are baked at runtime after furniture moves, the same as 2D.
- **Apartment look:** based on details that recur in documentary and news
  photos of drug houses: windows boarded over (thin slivers of cold
  streetlight through the planks, a pale shaft on the floor) or taped over
  with foil; a single bare bulb on a cord that browns out now and then; a
  stained mattress on the floor instead of a bed; a sagging couch with a
  cushion on the floor; an overturned chair and a knocked-over lamp; a
  punched hole in the drywall with crumbs below; water-damage and grime
  stains (`Decal`s) on the walls and floor; and piles of cans, bottles,
  takeaway boxes, paper, and burnt foil scraps. Its textures (stains, mattress,
  couch fabric, weathered planks, the drywall hole) are procedural, from
  `dev-tools/gen_env3d_textures.py`. The mattress, couch, radio crate,
  TV, overturned chair, and box stack all have collision, and the navmesh
  routes around them.
- **Stores and what gets stolen:** the item catalogue
  (`GameState.REQUEST_POOL`, 20 items across five stores) is drawn from lists
  of what gets shoplifted to fund a habit, and the CRAVED "hot products"
  research (Concealable, Removable, Available, Valuable, Enjoyable,
  Disposable). The **pharmacy** has razors (in a locked, glass-fronted
  case), whitening strips, cold medicine, baby formula, and makeup, watched
  by a pharmacist from a raised back counter. The **supermarket** has steaks
  and cheese in an open cooler (packaged meat famously has little security),
  plus detergent, which is traded almost like cash; its one bored cashier is
  far from the aisles, so it's the easy store. The **corner shop** has
  cigarettes, chargers, batteries, energy drinks, and sunglasses. The
  **liquor store** has whiskey, vodka, and cognac, and a clerk behind
  plexiglass with a convex security mirror and a clear view. The
  **electronics store** has headphones, games, watches, and phones in low
  glass cases that hide nothing, with a TV wall, anti-theft gates, and a
  security guard at the door as well as a clerk: the most valuable, and the
  hardest. All five share one script (`world/Store3D.gd`). Each item's 3D
  model is built from primitives (`items/ItemModels.gd`), and the HUD icons
  are rendered from those same models (`dev-tools/render_item_icons.gd`).
  Patrons say which store to try.
- **The pusher:** buying happens in person on the street, not over the
  phone (the Apartment's phone is gone). He's modelled on how street-level
  selling is described in policing guides (Police Magazine, ASU Center for
  Problem-Oriented Policing). He works a fixed, badly lit spot with no
  streetlights, at the mouth of an alley. He keeps nothing on him: you pay,
  he tells you to wait, walks to a stash behind the dumpster at the next
  alley, crouches to fetch it, and comes back for a quick hand-to-hand. He
  keeps glancing up and down the street. A **lookout** posted down the
  block toward the police station whistles the moment you're wanted, and
  the pusher slips down his alley out of sight until the heat is off. A sale
  already paid for is still honoured when he comes back. He looks like an
  ordinary guy in a grey hoodie, not a movie villain (the sources stress
  that appearance isn't what gives dealing away).
- **Dive Bar:** rebuilt from write-ups of what makes a "true" dive bar. It
  has old neon beer signs dimmed with age at different heights, Christmas
  lights left up all year with a few bulbs dead, wood-panelled walls, and a
  sticky linoleum floor. There are red vinyl booths patched with duct tape
  and ripped stools, a worn bar top with a brass foot rail, beer taps and
  pretzel bowls, and a back bar with a mirror. A small TV glows blue-green in
  the corner, a pool table with faded felt sits under a stained-glass lamp,
  and a jukebox has burnt-out bulbs. There are also darts, an ATM at the
  back, a CASH ONLY card, the restroom door, and the one unboarded window,
  whose OPEN sign reads backwards from inside. Sign text is generic, never
  real brands. Patrons in booths sit, using the body's sitting clip.
- **Jail:** getting busted now books you into a holding cell instead of
  sending you home. The cell follows first-hand accounts and news photos of
  police holding cells. It has painted beige concrete-block walls, a
  concrete bench with a blue plastic-covered mattress, and a seatless steel
  toilet with the sink set into the wall above it. There's a small barred
  window of reinforced glass, a caged light, and an intercom reading "PRESS
  FOR MEDICAL ATTENTION". A CCTV dome, a floor drain, and a steel door with
  an observation slot complete it. Outside are the booking desk and officer,
  a mugshot height chart, and bagged property. Knock, press the intercom,
  or wait it out on the bench (hours pass and the withdrawal gets worse),
  or just sit tight until the officer comes. Then the door slides open and
  you walk out onto the street by the police station.
- **Who wears which model:** all of it lives in `npc/CharacterCast.gd` --
  see **One cast list** above. Nothing else in the game names a model file.
  Historical note, from when the cast was Kenney's: `male-c` was the only
  cop-uniformed model, and it had been sitting at the bar as a patron while
  the police wore a civilian body.
- **Shopkeeper vision:** the line-of-sight ray starts at eye height (1.5 m),
  above the 1.05 m counter, so the counter doesn't blind them. The 2.2 m
  shelves still fully block sight.
- **Stealth: suspicion, not a coin flip.** Guards used to bust you the
  instant they saw you inside the 0.6 s grab window, and do nothing at any
  other moment. That made the whole stealth layer one unreadable dice roll:
  nothing you did before or after the grab mattered, and there was no way
  to tell how much trouble you were in. `npc/Guard3D.gd` now carries a
  0..1 **suspicion** meter. Grabbing something in plain sight fills it in
  about a third of a second (so a careless steal is caught about as fast as
  before), while loitering in view holding stolen goods, or sprinting past,
  fills it slowly -- and standing right next to a guard makes all of it
  worse. Out of sight it drains, but more slowly once they've clocked you,
  so repeated exposure adds up. Browsing empty-handed is never suspicious,
  or shopping would be impossible. The vision cone tracks the meter
  continuously (calm blue to amber to red), which is the player's only read
  on where they stand. Guards also now turn their body to follow their own
  sweep, instead of staring through their shoulder.
- **Sprint (Shift).** The risk/reward half of the above: faster, and the
  loudest thing you can do in front of a guard. Withdrawal takes it away,
  which is exactly when you most want it.
- **Runs, strikes, and Know-How.** A run now *ends*: three busts (four with
  the right upgrade) and you're gone, with the strikes shown next to the
  day counter. This is the standard roguelite structure, and the reason for
  it is the one every write-up on the genre lands on -- failure has to buy
  something permanent, or repeated failure just wears people down. Before,
  a bust cost a fine and nothing else, and a run had no end and no memory:
  tolerance climbed until the numbers stopped working and there was nothing
  to do but keep going or quit. Every finished run now pays **Know-How**
  (`autoload/MetaProgress.gd`, saved to `user://progress.cfg`), scaled by
  days survived, orders delivered, and cash earned -- but never zero. It
  buys six tiered upgrades that change *how you can play* rather than just
  handing over bigger numbers: Steady Hands (shorter grabs), Light Touch
  (slower suspicion), Deep Pockets (starting cash), Clean Stretch (slower
  withdrawal), A Known Face (better payouts), Someone To Call (smaller
  fines, and a fourth strike at max tier). `ui/RunEndScreen.gd` shows the
  run summary and the shop; it's built in code, so adding an upgrade to
  `MetaProgress.UPGRADES` makes a row appear with no scene editing.
- **What you buy, and what it does to you.** The old economy had one
  abstract "$20 fix". It's now a catalogue (`autoload/Drugs.gd`) the pusher
  offers a nightly subset of, and every entry differs on price, relief, how
  long it holds you, how fast it builds tolerance, and how likely it is to
  kill you -- so "what can I afford" and "what can I survive" stop being the
  same question. Prices are anchored to published figures rather than
  invented, the same way the shoplifting list is anchored to CRAVED:
  StreetRx/RADARS crowdsourced price-per-milligram means for diverted
  pharmaceuticals (oxycodone ~$0.97/mg, buprenorphine ~$2.13/mg, methadone
  ~$0.96/mg), per-bag reporting for heroin, and per-tablet ranges for
  benzodiazepines. They are deliberately *fixed* balance numbers -- real
  prices swing enormously by region, purity and quantity, and nothing in
  the catalogue should be read as a current price list.
- **The counterfeit mechanic.** The most important entry is the one that
  lies to you. Per DEA laboratory analysis, most street "oxycodone 30 mg"
  (M30) tablets are pressed fentanyl rather than oxycodone, made with no
  dosing control, and a large share of those carry a potentially lethal
  amount. So in this game the expensive, familiar, apparently-predictable
  pill is the most dangerous thing on the menu, and you don't find out until
  after it hits (`Drugs.resolve_purchase()` settles it at purchase;
  `Pusher3D._handoff_line()` only reveals it at the handoff). That is the
  real shape of the risk, and it does more than any amount of warning text.
- **Interactions that are actually the dangerous part.** Tolerance is shared
  within a drug class, because cross-tolerance is real. Opioids and
  benzodiazepines taken close together multiply the overdose roll, because
  both suppress breathing and the combination is what mostly kills people.
  Buprenorphine stops withdrawal for a long time and *lowers* tolerance, but
  taken too soon after a full agonist it precipitates withdrawal instead of
  relieving it -- the classic way a first attempt at getting on it goes
  wrong. Stimulants do nothing for opioid withdrawal, so scoring meth while
  dopesick is a wasted score.
- **Going over is the second way to lose.** An overdose ends a run outright,
  alongside running out of strikes, and the run-end screen says which
  happened. **Naloxone** is always in the pusher's stock and cancels exactly
  one overdose, leaving you alive and instantly in withdrawal -- which is
  what reversal actually does. It is the cheapest insurance in the game.
- **Verification:** `godot --headless --path . -s res://dev-tools/smoke_test_3d.gd`
  drives the real scenes. It loads every room, and checks every item in
  every store layout is reachable from the door and every guard can call
  the police. Then it steals, gets spotted, and has police arrive and close
  in along the navmesh. The chase follows you through a door. It buys from
  the pusher (stash walk, handoff, hiding from the lookout's whistle), walks
  to every patron seat, and sells to a patron. It gets busted exactly once
  with the clerk still watching, is held by the locked cell, waits it out,
  and walks out of jail. Then it checks Apartment furniture collision and
  sleeps. Finally it covers the stealth and run layers: that browsing
  empty-handed is not suspicious, that carrying stolen goods in view builds
  suspicion without an instant bust, that it drains once you break line of
  sight, that grabbing in plain sight raises the alarm, that strikes end a
  run, that the summary is right, that a finished run always pays Know-How,
  and that buying an upgrade actually moves the numbers the game reads --
  restoring the player's real save afterwards, so running the tests can't
  inflate it. It exits non-zero on any failure.
  `godot --path . -s res://dev-tools/watch_playtest.gd [-- <pause s>]` runs
  the same checks in a window you can watch, with an overlay naming each
  scenario and every check as it passes or fails. It drops to the Low
  preset (the checks count physics frames, which outrun drawn frames at
  12-16 FPS) and skips cutscenes, which pause the tree. `dev-tools/playtest_bot.gd` plays
  a full loop in a real window with screenshots.
  `dev-tools/capture_scene.gd` renders any scene to a PNG, either as an
  `overview` of the room or as `closeup:NodeName` framed on one character.
  `dev-tools/inspect_model.gd` prints an imported model's node tree,
  animation clips, and mesh surface names.
  `dev-tools/drug_sim.gd` plays whole runs against the real catalogue and
  dosing code for several strategies at once and reports how they end --
  **retune the drug economy with this, never by eye.** Overdose risk is per
  dose and a run is 25-30 doses, so figures that look sane individually
  compound into nonsense: the first pass produced an 85-99% overdose rate
  across every strategy. It also caught the opposite failure, where
  tolerance was subtracted from risk linearly and a heavy fentanyl habit
  drove the risk to zero, making the most dangerous drug in the game the
  safest once you'd used enough of it. The target is no dominant strategy:
  buprenorphine maintenance safest but dearest, cheap opioids survivable but
  punishing, fentanyl cheap per dose until tolerance eats you, and mixing an
  opioid with a benzo the deadliest thing on the menu.
- **Bugs fixed while swapping the cast and adding the run structure:**
  - *A flaky test that predates this pass.* `smoke_test_3d.gd`'s "the clerk
    really did see the theft" check failed at random. `Guard3D._ready()`
    seeds `_sweep_t` with `randf() * TAU` and a full sweep takes ~14 s,
    while the check ran 90 physics frames (~1.5 s) -- so the clerk was
    often facing the other way for the whole check. Both bust-related
    checks now aim the guard deterministically instead of hoping.
  - *The alarm latched forever.* The new suspicion meter raises the alarm
    once and then latches, so a single theft can't spawn three officers.
    But nothing cleared the latch, so a guard who raised one alarm was deaf
    for the rest of the visit -- including after a chase the player escaped.
    It now clears whenever `GameState.wanted` goes false.
  - *A grab that took 3.3 seconds.* See `play_once_timed()` above: two
    speed multipliers tuned against different art packs multiplied together.
  - *Seated patrons hovering.* Kenney's sit clip put the hips at floor
    level, so `DiveBar3D.SIT_HEIGHT` raised patrons 0.32 m onto the bench.
    The Quaternius sitting clip already sits them on an imaginary chair with
    feet on the floor, so that offset left them floating above the seat.
  - *`specular` is not a Godot 4 property.* Setting it on a
    `StandardMaterial3D` logs "Godot 3.x SpatialMaterial remapped parameter
    not found" and silently does nothing; it's `metallic_specular`.
  - *Autoloads don't exist for `-s` scripts at compile time.* Already noted
    below for the room builder, and it bites debug scripts too -- reach
    them via `root.get_node("GameState")`, as the smoke test does.
- **Bugs fixed from playtesting:**
  - *Wrong interaction target.* Pressing E used whichever object came into
    range first, not the nearest, so after using the Apartment phone the
    door right next to you did nothing.
  - *Chained busts.* One catch could count as two or three busts: after the
    first, the shopkeeper still saw the theft, re-raised the alarm, and a
    new officer spawned on top of you at the exit. A custody flag now blocks
    all of that until you're booked, and officers take 2 s to arrive.
  - *Stuck after a bust.* The busted scene change was scheduled on the
    officer that had just been freed, so it never fired.
  - *HUD.* The day counter didn't update after sleeping, and the dialogue box
    showed an empty portrait frame for characters without a portrait.
- **Gotcha:** the Kenney `.glb` files were first imported before their
  shared `Textures/colormap.png` had been, which silently baked them in
  untextured (plain white/grey characters and buildings). Deleting their
  `.godot/imported/*.glb-*` files and re-running `--import` fixed it. If
  models ever look flat grey again, that's the first thing to check.
- **Character animation:** each Quaternius body ships 11 clips (idle, walk,
  run, sitting, clapping, punch, jump, death, ...), so there is still no
  separate animation asset -- the clips the game needs are all in the model.
  `npc/CharacterAnimator.gd` finds a model's `AnimationPlayer`, resolves the
  logical clip names against what's actually there (see **Clip names are
  resolved** above), turns on looping for idle/walk/sprint (they import
  non-looping), and cross-fades between idle and moving based on horizontal
  speed. Two of the game's gestures have no exact clip in this pack: the
  grab borrows the punch (a single forward arm extension, which at this
  camera distance reads as reaching for a shelf) and the pusher's
  hand-to-hand borrows the clap. The player walks, and in withdrawal the stride slows along with the
  movement so it reads as a shuffle rather than sliding feet. Police sprint,
  and the shopkeeper, bartender, and patrons idle. Stealing plays the
  `pick-up` clip as a one-shot (`CharacterAnimator.play_once()`, which holds
  off locomotion blending until it ends): the player turns to face the item,
  is rooted in place for a 0.6 s grab (long enough to read as deliberate;
  `play_once_timed()` stretches whatever clip the body has to fit, and
  "Steady Hands" shortens it), and the item leaves the shelf halfway through the
  reach. The item is pulled out of play the instant the grab starts, so it
  can't be stolen twice.
- **Sound:** on top of the shared one-shot/siren/heartbeat sounds, every 3D
  room has positional ambience synthesised by `dev-tools/gen_sfx_3d.py`
  (stdlib only, like `gen_sfx.py`): the Apartment's bare bulb buzzes and
  crackles each time it browns out, and the TV hisses static; the Shop's
  fluorescent lights hum and the drinks cooler drones; a muffled blues
  shuffle plays from the Dive Bar jukebox over crowd murmur; the City has
  distant traffic and wind, and each streetlight buzzes. Dive Bar patrons
  make positional sounds from their seats every 5-14 s, picked to match how
  their portraits read: the gaunt, restless Wiry Guy and Nervous Dave sniff
  and drum their fingers; the glazed Tired Woman and anxious Quiet Kid sigh;
  the heavy drinkers Big Eddie and Old Sailor sip, cough (the Sailor's is a
  wet smoker's cough), and set glasses down. Starting a conversation plays a
  wordless mumbled voice (synthesised vowel formants) at each patron's own
  pitch, from deep Big Eddie to higher Tired Woman. Patrons go quiet while
  you're talking to them. Profiles live in `NPC3D.gd`'s `PATRON_PROFILES`. The player has
  footsteps timed to the walk cycle (and slowed in withdrawal); police have
  positional sprinting footsteps, so you can hear them coming round a
  shelf. An `AudioListener3D` on the player (not the high camera) makes
  sounds pan and swell as you walk past their source. The loops are built to
  be seamless (whole cycles, or a tail-to-head crossfade), and their
  `.import` files set `edit/loop_mode=2`. Levels were balanced by recording
  each room with Godot's `--write-movie` and measuring with ffmpeg's
  `volumedetect`: standing still, each room sits around -28 to -34 dB mean,
  and walking right up to the jukebox, the loudest source, peaks around -6 dB.
- **HUD:** the old full-width top bar hid the top of the 3D view, so it's
  now two small floating panels: cash, day, and craving top-left, and a
  right-aligned "Carrying" panel top-right that `HUD.gd` resizes to fit
  its label and item icons. The WANTED badge floats top-centre. Node paths
  are unchanged, so the 2D scenes use the same HUD without changes.

## Premise

You wake up in your apartment, already craving. Head out into the city, into
the dive bar to find out who needs what, and into the shop across the street
to steal it without being seen. Bring it back, get paid, call your pusher,
get well. Repeat.

## Controls

- **WASD / Arrow keys** — move
- **Shift** — sprint (fast, and very visible to staff; not available in
  withdrawal)
- **E** — interact (talk, steal, open doors, use phone/bed)
- While a dialogue box is open, press **E** again to close it

## Core loop (implemented)

1. **Apartment** — start here. A bed (sleep, only when not wanted by police)
   and a phone (call your pusher, $20 for a full fix) plus the door out to
   the city.
2. **City** — the hub between all three interiors. A street with three
   building fronts (Home, Dive Bar, Shop), each with its own door, plus
   streetlights, a fire hydrant, a dumpster, and a parked car (a random
   color tint each visit) for flavor. Exiting any interior always lands
   you back here, next to that building's door.
3. **Dive Bar** — three patrons, randomized every visit both in *who* shows
   up (name + sprite skin, picked from a pool of 6 names / 4 skins) and
   *what they want* (a different stolen item each time). Talk to them to
   hear the request; bring the item back and they pay you. The bartender
   will also fence *any* stolen item you're still holding for a flat $5,
   no questions asked. Decorated with a back-bar bottle shelf, a neon
   sign, a jukebox, a dartboard, and stools along the counter. Talking to
   the bartender or a patron shows a realistic AI-generated portrait
   (one of 7, keyed by name) in the dialogue box.
4. **Shop** — five steal-able items, shuffled onto a different shelf every
   visit so the layout never repeats, each shelf fleshed out with a
   couple of flanking product boxes, plus a register on the counter and a
   drinks cooler against the wall. The shopkeeper has a sweeping vision
   cone; get spotted mid-steal and the cops show up. Break line of sight
   (shelves block vision) for a few seconds and they give up. Get caught
   and you lose everything you're carrying, plus a cash fine, and wake up
   back home (skipping the city). The shopkeeper is also now a talkable
   character (previously just a silent vision cone with no name) — a
   wary, watchful presence with their own portrait and lines, there to
   make clear they're onto you, not to help you.
5. **Craving meter** drains constantly and gets harder to manage the
   longer you last: tolerance builds day over day, so the pusher's fix
   costs more and withdrawal creeps in faster the further into the run
   you are (`GameState.current_fix_cost()` / `current_craving_decay()`).
   Low on the meter slows you down badly (withdrawal). A green sickness
   tint creeps in as it drops.
6. **Lighting.** Every room is dim/nighttime now, lit only by real
   `PointLight2D` fixtures (ceiling lights, the neon sign, the jukebox,
   streetlights, window glow, a TV's blue flicker) that cast proper hard
   shadows off shelves, tables, counters, and building facades via
   `LightOccluder2D` — walk near a shelf and it throws a real shadow. The
   player has a soft warm glow so you're never lost in the dark; Police
   has a flashing red/blue beacon light to match its siren. A full-screen
   post-process shader (`assets/fx/postfx.gdshader`, applied in
   `HUD.tscn`) adds a vignette and film grain on top for a moodier,
   more graded look.
7. **Sound.** Footsteps alternate with your walk cycle; doors, theft,
   sales, fencing, buying a fix, and sleeping each have their own cue;
   getting busted plays a harsh alarm. Getting spotted starts a looping
   police siren for as long as you're wanted, and the craving meter adds
   a low heartbeat loop once it drops critical — both stop automatically
   when the state clears. Every sound is procedurally synthesized (no
   samples or licensing), via `dev-tools/gen_sfx.py` and a small `SFX`
   autoload that pools one-shot players and drives the two ambient loops
   off `GameState`'s existing signals.
8. **Photoreal surfaces.** Floors and walls across all four rooms are now
   real photographed materials instead of procedural pixel art: dark
   mahogany for the Dive Bar, worn light oak for the Apartment, cracked
   asphalt/concrete for the City street, and weathered red brick shared
   by every wall. The Shop's floor is a clean black-and-white checkerboard
   — generated procedurally instead, since AI image models reliably
   produce warped, fisheye-distorted grids for anything with strict
   geometric regularity (confirmed with two separate failed attempts on
   different prompts/seeds). See `dev-tools/gen_photo_textures.py`.

## Opening the project

Godot 4.5-stable is installed and the `godot-ai` MCP plugin
(`res://addons/godot_ai/`) is already enabled in this project, so Claude
Code can drive a live editor session directly. To open it by hand instead,
launch Godot 4.5.x and "Import" this folder (`~/dopesick-game/project.godot`).

## Known limitations / good next steps

- Characters, items, and world geometry all have real (procedurally
  generated) art now — see `dev-tools/gen_sprites.py`, which writes to
  `assets/sprites/` (characters, items) and `assets/env/` (environment).
  Prop choices were grounded in a quick pass of research on what real
  dive bars, corner shops, and rundown apartments actually look like
  (back-bar bottle displays, neon signage, gondola shelving, curated
  "emotional anchor" clutter rather than noise) rather than guessed from
  scratch. Characters use a brighter, more saturated palette with simple
  highlight/shadow shading bands and a dithered drop shadow at their
  feet; floor/wall/wood textures have matching grain detail
  (`add_grain()`). The player and police have a 3-direction, 2-frame walk
  cycle (down/up/side, side flips for left vs. right); the shopkeeper,
  bartender, and each patron have a distinct static sprite; each
  stealable item has its own icon auto-selected by `item_id` in
  `StealableItem.gd`. Floors, walls, and building facades use tileable
  textures (`TextureRect` with `stretch_mode = TILE`); the bed, phone,
  TV, trash cans, doors, city street props (road/sidewalk tiles,
  streetlight, car, hydrant, dumpster, window), bar props (bottle shelf,
  neon sign, jukebox, dartboard, barstool), shop props (product boxes,
  register, cooler), and apartment squalor details (wall stains, a
  clothes pile, a bottle cluster, an ashtray, a pill bottle) are all
  dedicated sprites. Only the HUD is still flat colored rectangles.
- Shop item placement, Dive Bar patron identity/requests, and the City's
  parked-car color all reshuffle on every visit (see `Shop.gd`'s
  `_shuffle_items()`, `DiveBar.gd`'s `_randomize_patrons()`, and
  `City.gd`).
- Physical room layout now varies too, not just what's on the furniture:
  the Shop picks one of 3 shelf arrangements, the Dive Bar one of 3 table
  arrangements, and the Apartment one of 3 clutter arrangements, each
  time you enter (`Shop.gd`'s `_randomize_layout()`, `DiveBar.gd`'s
  `_randomize_layout()`, `Apartment.gd`'s `_randomize_clutter()`). Item
  markers and flanking product boxes move with their shelf, and patrons
  sit at their table, since those are positioned relative to the slot
  rather than independently. Furniture repositioning happens before
  `WorldRoot._bake_navigation()` runs (it's the first thing each room's
  `_ready()` does, ahead of `super._ready()`), so the baked navmesh and
  the shopkeeper's/police's pathing always match whichever layout got
  picked — no separate re-bake step needed. The Apartment previously had
  no room-specific script (it used the shared `WorldRoot.gd` directly);
  it now has its own `Apartment.gd` since its clutter is purely
  decorative (`TextureRect`s, no `StaticBody2D`) and needed a place to
  live that isn't nav-mesh-relevant. City's three-building layout and
  each room's walls/counter/bed/phone stay fixed — only the freestanding
  furniture moves.
- Police AI paths around obstacles via a baked `NavigationRegion2D` (see
  `world/WorldRoot.gd`) instead of beelining at the player, and only
  re-aims while it actually has line of sight — losing sight means it
  commits to the last-seen spot and gives up after 4s if the player
  doesn't reappear. All four rooms (Apartment, City, Dive Bar, Shop)
  have a nav region, and the theft trigger is still Shop-only (the
  shopkeeper's `_on_spotted_theft()`), but the chase itself is no longer
  confined to the room where it started. Previously, ducking through a
  door mid-chase destroyed the pursuing officer along with the rest of
  the old scene (each room is a fully separate `.tscn`, swapped via
  `change_scene_to_file`) without ever resolving `GameState.wanted` —
  nothing else clears it, so escaping that way silently soft-locked the
  player out of sleeping (`Bed.gd` refuses while wanted) and left the
  siren looping for the rest of the run. `WorldRoot._ready()` now calls
  `_maybe_continue_chase()` right after placing the player at their
  entry marker: if still wanted and no `"police"`-group node already
  exists, it spawns a fresh officer beside wherever the player just
  walked in, in whichever room that is. The chase now genuinely follows
  you door to door until you break line of sight for 4s or get caught —
  verified live by forcing `GameState.wanted = true` at boot (temporary
  test edit, reverted after): a police officer spawned in the Apartment
  with no theft having occurred, gave chase, caught the player (cash
  fine matched `get_busted()`'s 50% cut exactly), cleared `wanted`, and
  correctly did *not* spawn a phantom officer in the City afterward.
  Also fixed a real bug this surfaced: `Shop.gd` already declared its
  own `const PoliceScene`, which collided with the new one on
  `WorldRoot.gd` once `Shop.gd` started inheriting it — GDScript treats
  redeclaring an inherited constant as a parse error, so the Shop broke
  outright until `Shop.gd`'s copy was removed in favor of the inherited
  one. A past session also fixed two bugs found while wiring the nav
  regions up in the first place: `_bake_navigation()` was casting each
  room's `Floor` node `as ColorRect`, which silently failed (returned
  null) after Floor became a `TextureRect` in the art pass, so every
  room's nav outline was quietly using a hardcoded fallback size instead
  of its real floor bounds — harmless where the fallback happened to be
  close enough (Shop/Dive Bar/Apartment), but it clipped a third of
  City's wider street. And City's three building facades had a
  `StaticBody2D` wrapper declared with a collision shape resource that
  was never actually attached via a `CollisionShape2D` node, so the
  buildings had no physical collision at all — the player could walk
  straight through them until this pass added the missing shapes.
- Dialogue portraits (`assets/portraits/`) are realistic AI-generated
  faces — see `dev-tools/gen_portraits.py` (Pollinations.ai for the
  image, `rembg` to cut the background out, then a corner crop to strip
  the free-tier watermark). Deliberately scoped to portraits only, not
  gameplay sprites: an early mockup (character cut out and composited
  into a scaled-up room) showed that photo-generation models default to
  front-facing portraits, not bird's-eye view, so a "realistic" character
  standing in the top-down world just looks like a floating cardboard
  cutout — no amount of scaling fixes a perspective the model can't
  draw. A dialogue box, where a front-facing face is the natural framing,
  has no such mismatch.
- Found another real bug while adding the lighting pass and verifying the
  shopkeeper's vision cone was still legible against the new darker
  rooms: the cone's `Polygon2D` had `z_index = -1` in `Guard.tscn`,
  which sorts it *behind* the floor (`z_index = 0`) — meaning it has
  been fully invisible to players this whole time, pre-dating this
  session's lighting work entirely. It still worked mechanically
  (`can_see_player` was computed correctly), just never rendered. Fixed
  by giving it `z_index = 5` and brightening its color for contrast
  against both the dark unlit floor and the warm lit pools.
- The photoreal floor/wall textures (`dev-tools/gen_photo_textures.py`)
  needed a second attempt to look right: the first pass used an
  offset-and-blend seam technique alone, which left an obvious repeating
  light/dark banding pattern from the source photo's own uneven studio
  lighting. Tried flattening that via a numpy divide-by-blurred-copy
  trick; it over-corrected and crushed the colors badly. What actually
  worked was simpler — crop a small patch from the best-lit center of
  the photo (well clear of any vignette or the corner watermark) and
  only lightly blend the seam. Also worth knowing: judge a tileable
  texture at the size it'll actually render at in-game, not a zoomed
  preview — repetition that's obvious blown up disappears at gameplay
  scale.
- This pass wasn't verified live in the Godot editor — it wasn't running
  this session (the `godot-ai` MCP connection was down, `ps aux` showed
  no Godot process at all). All edits were verified structurally (every
  referenced asset file exists on disk, every `ExtResource`/`SubResource`
  id used is declared, `load_steps` counts match), but not visually.
  Reopen the project and take a look before assuming it's flawless.
- Dialogue portraits were regenerated with descriptions grounded in a
  round of research into the real visible signs of long-term substance
  use, rather than the generic "tired/gaunt" guesses from the first
  pass: opioid/heroin use shows clinically as gauntness, hollow cheeks,
  and sunken dark-circled eyes with a sallow/grayish skin tone;
  benzodiazepine use shows as droopy, "glazed" or unfocused eyes and a
  dull complexion rather than gauntness; long-term heavy drinking (the
  dive bar's barflies) shows as facial flushing and broken capillaries
  across the nose and cheeks. Each of the seven named characters was
  re-pointed at whichever of those a real person with their specific
  habit would actually show, kept humanizing rather than caricatured
  (see `dev-tools/gen_portraits.py`). The shopkeeper is a new eighth
  portrait, deliberately the "straight" character in a cast otherwise
  built around addiction and drink — alert and guarded rather than worn
  down.
- The HUD (`ui/HUD.tscn`) was the one area the last session flagged as
  "still flat colored rectangles" — replaced with `StyleBoxFlat` panels
  (a real bordered top bar, a framed craving meter with its own label, a
  bordered "WANTED" badge, a bordered dialogue portrait, text shadows
  for legibility against busy backgrounds) and a row of real item icons
  next to "Carrying:" instead of a plain comma-separated name list,
  reusing the same icon textures the Shop's shelves already use. No
  script logic changed — `HUD.gd`'s node paths were kept stable so the
  restyle couldn't silently break the signal wiring.
- Wrote a small structural validator (checks every `.tscn` for dangling
  `ExtResource`/`SubResource` references, missing asset files on disk,
  and correct `load_steps` counts) and ran it across the whole project,
  not just this session's edits, since there was no live editor to
  catch mistakes visually. Found no existing bugs beyond what the prior
  session had already fixed — the codebase was clean going in.
