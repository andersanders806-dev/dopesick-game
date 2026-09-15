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
   streetlights, a parked car, a fire hydrant, and a dumpster for flavor.
   Exiting any interior always lands you back here, next to that building's
   door.
3. **Dive Bar** — three patrons, each wanting a different stolen item
   (randomized every time you visit). Talk to them to hear the request;
   bring the item back and they pay you. The bartender will also fence
   *any* stolen item you're still holding for a flat $5, no questions asked.
   Decorated with a back-bar bottle shelf, a neon sign, a jukebox, a
   dartboard, and stools along the counter.
4. **Shop** — five steal-able items on shelves, each shelf fleshed out with
   a couple of flanking product boxes, plus a register on the counter and
   a drinks cooler against the wall. The shopkeeper has a sweeping vision
   cone; get spotted mid-steal and the cops show up. Break line of sight
   (shelves block vision) for a few seconds and they give up. Get caught
   and you lose everything you're carrying, plus a cash fine, and wake up
   back home (skipping the city).
5. **Craving meter** drains constantly. Low on the meter slows you down
   badly (withdrawal). A green sickness tint creeps in as it drops.

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
- Only one shop and one bar layout; no day-to-day variety yet beyond the
  randomized patron requests. The city hub is one static street — no
  variation there either.
- No sound.
- Police AI paths around obstacles via a baked `NavigationRegion2D` (see
  `world/WorldRoot.gd`) instead of beelining at the player, and only
  re-aims while it actually has line of sight — losing sight means it
  commits to the last-seen spot and gives up after 4s if the player
  doesn't reappear. Only the Shop scene has a nav region since police
  never spawns elsewhere.
