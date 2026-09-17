# Dope Sick

A dark, low-budget top-down stealth game about addiction, theft, and getting by.

## 3D version (current main scene)

The game is being ported from 2D to 3D. The 3D version is now the main
scene (`world/Apartment3D.tscn`) and covers the full loop: Apartment, City,
Dive Bar, and Shop, each a `*3D.tscn` with a matching `*3D.gd` room script.
The original 2D scenes are still in place, untouched, alongside them.

- **Art:** Kenney's CC0 Furniture, City, Food, and Mini Characters kits
  (`assets/kenney/`), reusing the photoreal floor/wall textures from the
  2D pass as triplanar materials.
- **Camera:** a fixed-angle follow camera on the player looking north, so
  every room keeps its south wall low and puts doors on the side walls.
- **Room generation:** all four 3D rooms are *generated*
  by `dev-tools/build_rooms_3d.gd`, not hand-edited. Change the layout
  there and rebuild with
  `godot --headless --path . res://dev-tools/BuildRooms3D.tscn`. It runs
  as a scene rather than via `-s` because the room scripts reference the
  `GameState`/`SFX` autoloads, which don't exist yet when a `-s` script's
  variables are initialised.
- **Behaviour carried over from 2D:** the Shop picks one of 3 shelf layouts
  and shuffles which item sits where; the Dive Bar picks one of 3 table
  layouts and randomises patron names, models, and requests; the City car
  gets a random paint colour; the Apartment picks one of 3 clutter layouts.
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
  `dev-tools/gen_apartment_textures.py`. The mattress, couch, phone crate,
  TV, overturned chair, and box stack all have collision, and the navmesh
  routes around them.
- **Shopkeeper vision:** the line-of-sight ray starts at eye height (1.5 m),
  above the 1.05 m counter, so the counter doesn't blind them. The 2.2 m
  shelves still fully block sight.
- **Verification:** `godot --headless --path . -s res://dev-tools/smoke_test_3d.gd`
  drives the real scenes through the whole loop: steal, get spotted, police
  close in along the navmesh, the chase follows you through a door, sell to
  a patron, buy a fix, sleep. It exits non-zero on any failure.
  `dev-tools/capture_scene.gd` renders any scene to a PNG for a visual check
  without the editor.
- **Gotcha:** the Kenney `.glb` files were first imported before their
  shared `Textures/colormap.png` had been, which silently baked them in
  untextured (plain white/grey characters and buildings). Deleting their
  `.godot/imported/*.glb-*` files and re-running `--import` fixed it. If
  models ever look flat grey again, that's the first thing to check.
- **Character animation:** every Kenney Mini Character `.glb` already ships
  with ~30 clips (idle, walk, sprint, sit, pick-up, emotes, etc.), so there is
  no separate animation asset. `npc/CharacterAnimator.gd` finds a model's
  `AnimationPlayer`, turns on looping for idle/walk/sprint (they import
  non-looping), and cross-fades between idle and moving based on horizontal
  speed. The player walks, and in withdrawal the stride slows along with the
  movement so it reads as a shuffle rather than sliding feet. Police sprint,
  and the shopkeeper, bartender, and patrons idle. Stealing plays the
  `pick-up` clip as a one-shot (`CharacterAnimator.play_once()`, which holds
  off locomotion blending until it ends): the player turns to face the item,
  is rooted in place for the ~0.6 s grab (slowed from Kenney's 0.33 s so it
  reads as deliberate), and the item leaves the shelf halfway through the
  reach. The item is pulled out of play the instant the grab starts, so it
  can't be stolen twice.
- **Sound:** on top of the shared one-shot/siren/heartbeat sounds, every 3D
  room has positional ambience synthesised by `dev-tools/gen_sfx_3d.py`
  (stdlib only, like `gen_sfx.py`): the Apartment's bare bulb buzzes and
  crackles each time it browns out, and the TV hisses static; the Shop's
  fluorescent lights hum and the drinks cooler drones; a muffled blues
  shuffle plays from the Dive Bar jukebox over crowd murmur; the City has
  distant traffic and wind, and each streetlight buzzes. The player has
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
