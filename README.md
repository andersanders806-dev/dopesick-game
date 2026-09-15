# Dope Sick

A dark, low-budget 2D top-down stealth game about addiction, theft, and getting by.

## Premise

You wake up in your apartment, already craving. Head to the dive bar and find
out who needs what. Steal it from the shop across the way without being seen.
Bring it back, get paid, call your pusher, get well. Repeat.

## Controls

- **WASD / Arrow keys** — move
- **E** — interact (talk, steal, open doors, use phone/bed)
- While a dialogue box is open, press **E** again to close it

## Core loop (implemented)

1. **Apartment** — start here. A bed (sleep, only when not wanted by police)
   and a phone (call your pusher, $20 for a full fix) plus the door out.
2. **Dive Bar** — three patrons, each wanting a different stolen item
   (randomized every time you visit). Talk to them to hear the request;
   bring the item back and they pay you. The bartender will also fence
   *any* stolen item you're still holding for a flat $5, no questions asked.
3. **Shop** — five steal-able items on shelves. The shopkeeper has a sweeping
   vision cone; get spotted mid-steal and the cops show up. Break line of
   sight (shelves block vision) for a few seconds and they give up. Get
   caught and you lose everything you're carrying, plus a cash fine, and
   wake up back home.
4. **Craving meter** drains constantly. Low on the meter slows you down
   badly (withdrawal). A green sickness tint creeps in as it drops.

## Opening the project

Godot 4.5-stable is installed and the `godot-ai` MCP plugin
(`res://addons/godot_ai/`) is already enabled in this project, so Claude
Code can drive a live editor session directly. To open it by hand instead,
launch Godot 4.5.x and "Import" this folder (`~/dopesick-game/project.godot`).

## Known limitations / good next steps

- Characters and items have real sprites now (`assets/sprites/`, generated
  procedurally — see `dev-tools/gen_sprites.py`): the player and police
  have a 3-direction, 2-frame walk cycle (down/up/side, side flips for
  left vs. right); the shopkeeper, bartender, and each patron have a
  distinct static sprite; each stealable item has its own icon
  auto-selected by `item_id` in `StealableItem.gd`. World geometry (walls,
  shelves, counters, tables, doors, bed/phone) and the HUD are still flat
  colored rectangles — a tileset/level art pass is the natural next step.
- Only one shop and one bar layout; no day-to-day variety yet beyond the
  randomized patron requests.
- No sound.
- Police AI paths around obstacles via a baked `NavigationRegion2D` (see
  `world/WorldRoot.gd`) instead of beelining at the player, and only
  re-aims while it actually has line of sight — losing sight means it
  commits to the last-seen spot and gives up after 4s if the player
  doesn't reappear. Only the Shop scene has a nav region since police
  never spawns elsewhere.
