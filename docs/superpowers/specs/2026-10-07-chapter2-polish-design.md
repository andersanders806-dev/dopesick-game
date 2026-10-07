# Chapter 2: Smoothness and Presentation -- Design and Plan

Part of the AA push: 1. world art (done), **2. polish and presentation**
(this), 3. story and characters. The partner asked for chapter 2 "full
auto" -- no approval stops -- plus "make the game less laggy with walking
and all that". Decisions below are mine, recorded so they can be checked.

## What was measured (UHD 620, 2026-10-07)

- Walking the street: no hitches; steady but low frame rate. High 55.9 ms
  (18 FPS), Medium 25.8 ms (39 FPS). GPU-bound. The partner's settings are
  on High.
- Going through a door: 3.6-5.3 s frozen. City3D: scene file load
  0.8-1.9 s, `_ready` 3.2-3.5 s (Facades 1.5 s re-loading the two facade
  kits, StreetScenes 0.8 s and Booster 0.2 s re-loading character models),
  first frame 1.7 s the first time (shader compile).

## A. Smoothness

1. **Facade kit cache.** `Facades.gd` keeps the kit meshes in a static
   cache for the session: only the first City visit pays to load them.
2. **Character model cache.** `CharacterCast.scene_for(path)` returns a
   cached PackedScene; NPCs, pedestrians, booster, alley and cast loaders
   use it.
3. **Room scenes stay loaded, and the next one loads ahead.** A new
   autoload `SceneLoader` (`autoload/SceneLoader.gd`): `prefetch(path)`
   starts a threaded load; `go(path)` fades out, waits for the load,
   changes scene with the cached PackedScene, fades in. Doors prefetch
   their target when the player comes within 4 m. Every room visited stays
   cached for the session.
4. **No 18 FPS on High.** On an integrated GPU, if High averages under
   24 FPS for 5 s, Graphics switches to Medium once per session with a
   toast saying why and that F3 puts it back; after the player picks High
   again with F3 it doesn't step down again that session.

## B. Presentation

5. **Fade between rooms** (0.25 s out, 0.35 s in) via `SceneLoader.go`,
   used by doors, the police/jail transitions and continuing a save.
6. **Arrival card.** On entering a room: its name and the time, small,
   upper left under the HUD, fading after 2.5 s ("THE DIVE BAR - 20:14").
7. **Interaction prompts.** A small label floats over whatever E / Square
   would use, saying what it does: "Enter the Dive Bar", "Talk to Ray",
   "Take: vodka", "Sleep", "Take your guitar"... Each interactable can
   answer `prompt_text()`; anything else gets a sensible default. Hidden in
   dialogue, menus, first-person (shown as a centre-bottom hint instead).

## Constraints

- Gameplay unchanged; full smoke test green.
- Memory: room scenes cached for the session (14 rooms at most); character
  models cached (43 at most). Measure resident memory after visiting every
  room and record it.

## Tasks

1. **Caches** (A1, A2): tests -- second City load is under 40% of the
   first; `CharacterCast.scene_for` returns the same object twice.
2. **SceneLoader + fades + arrival card** (A3, B5, B6): tests -- doors go
   through `SceneLoader`, a prefetched door transition is under 0.5 s of
   frozen time, the fade node exists and ends transparent, the card shows
   the room name.
3. **Auto step-down on High** (A4): test with a simulated slow FPS feed.
4. **Interaction prompts** (B7): tests -- prompt text for a door, an NPC,
   an item, the bed; hidden in dialogue.
5. README, full regression, measurements, screenshots.
