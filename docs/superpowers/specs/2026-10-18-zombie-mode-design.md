# Zombie mode ("Dead Block") — design

Date: 2026-10-18. Status: approved in conversation ("make sure to use google
to get the most gory shit ... dont settle. go on").
Research: `docs/superpowers/research/2026-10-18-zombie-gore-gunfeel.md`
(numbers tagged verified / community / recall there; recall values are
starting points to tune, not facts).
Depends on: the open-world block (`2026-10-18-open-world-block-design.md`,
Tasks 1-2 at least: the block and its cells).

## Intent

A separate, replayable zombie mode on the new open block: Call of Duty
Zombies' round-based loop, first person that feels like COD, third person
that feels like Resident Evil 4 Remake, and gore as far as the engine and
the UHD 620 allow — the player asked for maximum gore, researched, not
settled.

Player decisions:
- Core loop: rounds in the open block (COD Zombies style).
- Third person: RE4 Remake feel.
- Assets: CC0/CC-BY with credits, plus Mixamo zombie animations the player
  downloads from a list we give.

## Mode shell

- Title screen entry "Zombies". Its own state (`autoload/ZombieMode.gd`)
  and save (`user://zombies.cfg`: best round, kills, headshots, time).
  Never reads or writes the story save, GameState story fields, or
  settings beyond Graphics.
- View: first or third person chosen at start, toggle any time (the same
  key as the story's view toggle).
- Map: City3D in a zombie variant (`GameState.mode == "zombies"` or a
  scene flag): story NPCs, shops' interactions, cars' traffic and
  passers-by removed; permanent night, dense fog, red-tinged sky, fires in
  the camp, flickering streetlights.

## Rounds and economy (COD numbers, our names)

- Zombie health: 150 at round 1, +100 per round to 950 at round 9, then
  x1.1 per round.
- Zombies per round (solo): `mult = max(1, r/5); if r >= 10: mult *= r*0.15;
  total = 24 + int(0.5*6*mult)`; rounds 1-5 use a gentler ramp starting at
  6 (tune by playtest). Max 20 alive (UHD 620 budget), the rest in reserve.
- Runners mixed in from round 6, rising to all runners by round 15.
- Points: 10 per hit, 60 body kill, 70 neck kill, 100 headshot kill,
  130 melee kill, 10 per board repaired. Start with 500.
- Doors/blockades: 750-1250 into West Ave, East Ave, the alley, the park
  gate, the underpass.
- Wall guns (chalk outlines): SMG 1000, shotgun 1200, AR 1400, sniper 1500,
  magnum 1000 (ammo refills at half price).
- Mystery box 950 (random from the full pool incl. LMG and one wonder
  weapon; moves after a few uses).
- Perks (need power): Iron Lung (health, 2500), Quickhands (reload, 3000),
  Double Shot (fire rate, 2000), Second Wind (solo self-revive, 500,
  max 3 buys), Long Legs (stamina, 2000).
- Upgrade machine 5000: more damage, mag size and reserve, new look.
- Power switch in the underpass camp.
- Power-ups: first drop after 2000 points, then each threshold x1.14,
  max 4 per round: Max Ammo, Insta-Kill (30 s), Double Points (30 s),
  Nuke (+400), Carpenter (+200).
- Barricades: Main Street shop windows; zombies tear boards, the player
  rebuilds for points.
- Downed: bleed-out 30 s; Second Wind revives. Game over screen shows
  round, kills, headshots, time, best.

## Combat — shared

- Data-driven weapons (`Resource` per gun: damage, head/neck/limb
  multipliers, rate, mag, reserve, reload times, spread hip/ADS, recoil
  pattern, ADS zoom, sounds, viewmodel/worldmodel scenes, upgraded
  variant).
- Hitscan via physics raycasts against per-bone hitboxes (Area3D/
  CollisionShape3D on BoneAttachment3D: head, neck, torso, upper/lower
  arms, upper/lower legs). Bullets go where the crosshair points; recoil
  is visual + pattern applied to aim.
- Knife (quick melee), 2 frag grenades refilled each round.

## First person (COD)

- Viewmodel arms + gun drawn on top with a depth/projection shader (no
  SubViewport), separate viewmodel FOV; ADS lerp ~0.2 s with zoom per gun,
  sway and bob, recoil kick + recovery, muzzle flash, shell ejection,
  tracers, camera shake via trauma.
- Hitmarkers: 4 strokes ~8 px from the crosshair, 0.12 s, scale 1.3 -> 1.0;
  bigger for headshots, red for kills; tick sound, thump on kill; "+points"
  popups next to the score.
- Sprint, slide, reload cancel, weapon swap (2 slots).
- Arms: Rocketbox arms (MIT) or CC0 MakeHuman arms; reloads/inspects
  procedural (IK hand offsets + gun part tweens) since no free animated
  arms set exists.

## Third person (RE4 Remake)

- Tight over-shoulder camera (right shoulder, swap key), aim walk ~1.2 m/s,
  laser sight with a dot and a slight focus wobble that tightens while
  holding aim.
- Per-body-part reactions: head hit -> stagger -> "Kick" prompt (knock-down
  AoE); leg hit -> kneel -> "Knife" finisher (or behind: neck stab); arm
  hit -> cancels a grab; knife parry window on a grab.
- Melee finishers award the melee-kill points.

## Zombies

- Rocketbox bodies with a rot shader (pale/grey-green skin, veins, dirt,
  blood stains, torn clothes via alpha-scissor damage mask), eyes glow
  faintly.
- Mixamo clips retargeted to the Rocketbox (Bip01) skeleton through
  BoneMap + SkeletonProfileHumanoid at import (research §5 bone map):
  walks (several), run, crawl, attacks, bite, hit reactions (front/back/
  left/right/head), deaths, stand-up, scream. Until downloaded, existing
  Rocketbox clips stand in.
- Navigation: NavigationAgent3D on the block navmesh, avoidance only near
  the player, repath every 0.5-1 s; spawn at block spawn points out of
  sight, via windows/barricades.
- Groans: positional, per zombie, louder when close/attacking.

## Gore (maximum, within budget)

- Wounds: L4D2-style pose-space ellipsoid cutouts (rest pose baked to
  CUSTOM0 at import; up to 2 active wounds per zombie in the shader) with
  wound interior meshes (4-6 variants: flesh, ribs, bone) and a per-zombie
  64x64 damage mask that layers skin -> flesh -> bone with repeated hits
  (FLESH-like build-up).
- Dismemberment at fixed sever points (head, upper/lower arms, upper/lower
  legs) after per-limb damage thresholds: bone scaled to ~0, stump cap
  mesh on the parent, a severed-limb gib (pre-baked at import) on a
  RigidBody3D with a capsule; gibs pooled (24), no shadows, freeze when
  asleep, fade after 30 s (keep the latest).
- Head pops on lethal headshots: head hidden, neck stump, blood fountain
  particles, chunks.
- Leg loss -> crawler (crawl clips), still dangerous.
- Blood: pooled decals (~80, oldest recycled) on floor/walls from
  raycasts at hit and from dripping stumps; blood pools under corpses;
  particle bursts (< 64 particles, alpha scissor); screen blood on the
  camera for close kills (vignette + splats, alpha-scissor, fades).
- Corpses: ragdoll on death via PhysicalBoneSimulator3D (11 bones), max 4-6
  simulating, frozen after 3 s, corpses removed oldest-first beyond 12.
- Gore setting: on/off (default on) in the mode's menu.

## Audio / music

- Licensed gun sounds (Sonniss GDC bundle, CC0 packs), CC0 zombie vocals;
  original round-start / round-end stingers and ambient music (no COD
  audio or names). Hitmarker tick, kill thump.

## Performance (UHD 620, Low)

- 60 FPS with 20 zombies alive in view plus gore on; GPU <= 14 ms; no
  frame > 33 ms during a horde. Distant zombies use LOD meshes
  (dev-tools/slim_glb.py) and skip animation updates (process every 2nd
  frame beyond 15 m). Measured early (Task Z2) before content piles up.

## Testing

- Smoke sections: round math, economy/purchases, perks/power, downs,
  weapons (damage by body part, ammo, reload, box, upgrade), zombie
  spawning/caps/pathing, barricades, gore (sever thresholds, gib pool
  caps, decal pool caps, ragdoll caps), mode isolation (story save
  untouched), view toggle in both modes.
- Probes: horde perf (20 zombies + gore), gunfeel captures (ADS timing,
  recoil recovery), screenshots for AA review.

## Out of scope

- Co-op, more maps, a story/easter-egg quest, killstreaks, controller
  aim-assist beyond a light slowdown.
