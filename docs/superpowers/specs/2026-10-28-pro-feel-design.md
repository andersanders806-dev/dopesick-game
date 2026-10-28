# Pro feel pass — design

Date: 2026-10-28. Status: the player approved all seven items ("all of it, do them all").

## Intent

Make Dope Sick feel like a professional game rather than a prototype. Runs
after the harbour plan (`2026-10-28-night-boat-harbour.md`), because the
new RE4 shoulder camera and the closed rooms change what every shot looks
like. Each item is its own task with tests and renders, measured against
the open-world perf gate (Low, UHD 620: 60 FPS, GPU <= 13 ms, no frame >
25 ms while walking).

## The seven items

1. **Rock-steady 60, no stutter.** Final quiet-machine gate across the
   block, every door scene, the pier, a boat night and the zombie horde;
   fix any frame > 25 ms. Shader/pipeline prewarm on the title screen.
2. **Light and image.** AgX tonemapping; a colour grade per time of day
   (dawn / day / dusk / night, plus a sicker grade that withdrawal blends
   in); wet asphalt that reflects the street lamps in rain (screen-space
   reflection on High+, a cheap reflection-probe / roughness trick on
   Low); volumetric fog cones round street lamps on Medium+.
3. **Sound.** Reverb buses per room size (street, alley, shop, bar,
   apartment, jail, pier); footsteps by surface everywhere; music that
   tenses as suspicion rises (stem layers, not track swaps); ambience and
   music duck under dialogue.
4. **Animation.** Turn in place, start/stop transitions, door-open and
   pick-up animations for the walk-in shops and interactables in reach
   (door scenes may keep the fade, with a door-open animation leading
   into it).
5. **Dialogue as film.** Conversations cut to over-the-shoulder shot /
   reverse shot of the two faces (uses ShoulderCam), with subtitles; the
   box UI goes away.
6. **Menus and HUD.** One font family and style across title, pause,
   settings, notebook, HUD and zombie HUD; controller glyphs shown
   automatically on pad input (PlayStation layout, matching the PS5
   preset); subtitles option; a save icon when the game saves.
7. **Hit feel.** Hit-stop (a few frames) on punches, beatings and zombie
   hits; controller rumble tuned per event; things that fly and break
   (bottles, boxes, shop shelves) with pooled debris.

## Constraints

- Nothing loads while walking; pools for debris; no new addons.
- Withdrawal stays the core mechanic: grades and sound may lean into it,
  never soften it (only Sal's fishing softens it).
- Licences recorded for any new font, sound, animation or LUT;
  non-commercial is fine.

## Left to the builder

Exact grades, reverb settings, which animations come from the Rocketbox
library vs. retargeted Mixamo-free sources, hit-stop lengths, glyph set.
