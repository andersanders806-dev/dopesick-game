# Dope Sick

A dark, low-budget 2D top-down stealth game about addiction, theft, and getting by.

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
  `City.gd`). Still only one physical room layout per location though —
  the furniture/wall arrangement itself never changes, just what's on it
  and who's there.
- Police AI paths around obstacles via a baked `NavigationRegion2D` (see
  `world/WorldRoot.gd`) instead of beelining at the player, and only
  re-aims while it actually has line of sight — losing sight means it
  commits to the last-seen spot and gives up after 4s if the player
  doesn't reappear. All four rooms (Apartment, City, Dive Bar, Shop) now
  have a nav region, so any future threat isn't limited to the Shop —
  though police itself still only ever spawns there today (the shop's
  `_on_spotted_theft()` is the only trigger that exists). Fixed two bugs
  found while wiring this up: `_bake_navigation()` was casting each
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
