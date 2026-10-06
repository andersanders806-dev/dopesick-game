---
name: run-dope-sick
description: Launch and drive Dope Sick (this Godot 4.7 game, run through flatpak) to see a change working in the real game - start it in a window for the user, or script the pilot (dev-tools/pilot.gd) to load a room, walk to things, talk, press keys and DualSense buttons, take screenshots and log game state. Use for "run the game", "start it", "check it in the game", "screenshot X", "does Y work in-game".
---

# Running Dope Sick

Godot is the flatpak `org.godotengine.Godot` (4.7.2). The project is
`/home/anders/dopesick-game`; run everything from there.

## Start it for the user

```bash
cd /home/anders/dopesick-game
nohup flatpak run org.godotengine.Godot --path . > /tmp/dopesick-game.log 2>&1 &
```

Opens the title screen in a window (New run asks first or third person;
F3 graphics preset, F4 FPS). This plays with the user's own settings and
save. Don't use it to check things yourself - use the pilot.

## Drive it yourself: the pilot

`dev-tools/pilot.gd` runs the real game in a window from steps on the
command line. It's sandboxed: nothing is saved, and it starts in third
person on Medium whatever the user's settings say.

```bash
cd /home/anders/dopesick-game && rm -rf .pilot
timeout 240 flatpak run org.godotengine.Godot --path . -s res://dev-tools/pilot.gd -- \
  "clock 14:00" "cash 40" "scene City3D" "walk Ray" "interact" "state" "shot menu" \
  "choose 2" "state" "close" "pad TOUCHPAD" "shot notebook" "pad CIRCLE"
```

- Output: each step, then `state:` lines (scene, day, clock, cash,
  craving, strikes, wanted, inventory, position, the interactable E would
  use, the open dialogue and the open menu's options). It ends with
  `PILOT DONE` or `STEP FAILED: <step>` + `PILOT FAILED` (exit 1).
- Screenshots and `pilot.log` go to `.pilot/` in the project. **Read the
  PNGs** - a stuck walk saves `NN_stuck_<target>.png` too.
- Steps (full list in the header of `dev-tools/pilot.gd`): `scene <Name>`
  (`City3D`, `DiveBar3D`, `Apartment3D`, `Jail3D`, `Backyard3D`,
  `Pawn3D`, `Shelter3D`, `MusicStore3D`, `KartCenter3D`,
  `StoreConvenience3D`, `StoreLiquor3D`, `StorePharmacy3D`,
  `StoreSupermarket3D`, `StoreElectronics3D`, or `title`), `clock HH:MM`,
  `day N`, `cash N`, `craving N`, `give <item_id>`, `strip N`,
  `preset <Low|Medium|High|PS5>`, `view <first|third>`, `list`
  (interactables, nearest first - use it to find names to `walk` to),
  `walk <NodeName>`, `interact`, `talk`, `close`, `choose <N>`,
  `key <J|T|N|ESCAPE|TAB|F3|SPACE...>`, `pad <CROSS|CIRCLE|SQUARE|TRIANGLE|OPTIONS|TOUCHPAD|L1|R1|L3|R3|DPAD_*>`,
  `hold <action> <seconds>`, `wait <s>`, `shot <label>`, `state`.

## Gotchas (all hit for real)

- **Set `clock`/`day`/`cash` before `scene`.** Rooms read the time when
  they load: set the clock after and the pusher has already gone off
  shift, shops have closed you out, and so on.
- **The pusher hides when the beat cop is near** (`Pusher3D` HEAT_RANGE):
  `walk Pusher` then sticks 3-4 m short at his hiding spot behind the
  wall. That's the game, not the pilot; wait, or pick another target.
- **Never run two pilot/test processes at once** (the pilot, the smoke
  test): they share `user://` and hang. The user's own game running
  alongside is fine.
- **The user's DualSense is joypad 0, and Godot reads it even when the
  window isn't focused.** If someone touches it while the pilot or a test
  runs, real stick events override the scripted movement (walks stall,
  scenes change by themselves). The pilot sends its own pad presses as
  device 1. If movement acts oddly, sample `Input.get_joy_axis(0, ...)`.
- **Flatpak Godot can't write to `/tmp`** (it has its own); write
  screenshots inside the project. `.pilot/` is gitignored.
- In first person (`view first`) `walk` still steers by world axes, which
  is wrong for a camera-relative player: walk in third person.
- Headless runs (`--headless`) skip cutscenes and can't screenshot; the
  pilot needs a window.

## Tests (not running the game, but next to it)

The headless smoke test is the regression suite:

```bash
cd /home/anders/dopesick-game
flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_test_3d.gd   # ~25 min, all
flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_controller.gd # one area
```

Fails on a `  FAIL` line or any `SCRIPT ERROR`. Area runners:
`smoke_batch1`, `smoke_batch2`, `smoke_controller`, `smoke_view`,
`smoke_aa`, `smoke_perf`, `smoke_ambience`, `smoke_batch1_review`.
