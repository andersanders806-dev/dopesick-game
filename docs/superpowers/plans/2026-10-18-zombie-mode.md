# Zombie Mode ("Dead Block") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A separate COD-Zombies-style round mode on the open block, with COD-feel first person, RE4-Remake-feel third person, and maximum gore that holds 60 FPS on a UHD 620.

**Architecture:** `autoload/ZombieMode.gd` owns the mode's state (round, points, perks, power, save). City3D runs in a zombie variant. Zombies are Rocketbox bodies driven by `npc/Zombie3D.gd` with per-bone hitboxes; weapons are data `Resource`s used by a `player/WeaponHolder.gd` shared by both views; gore lives in `fx/gore/` (wounds shader, sever, gibs, blood pools).

**Tech Stack:** Godot 4.7.2 flatpak, GDScript, Forward+ Vulkan; Rocketbox (MIT), Mixamo clips (player-downloaded), CC0/CC-BY assets with credits.

**Spec:** `docs/superpowers/specs/2026-10-18-zombie-mode-design.md`
**Research:** `docs/superpowers/research/2026-10-18-zombie-gore-gunfeel.md`

## Global Constraints

- Runs after the open-world plan's Tasks 1-2 (block + cells) are merged into the working branch.
- Godot: `flatpak run org.godotengine.Godot`; headless tests `--headless --path . -s res://dev-tools/<script>.gd`; window probes add `--socket=wayland --display-driver wayland`; regenerate scenes with `--headless --path . res://dev-tools/BuildRooms3D.tscn`.
- Zombie mode never reads/writes the story save (`SaveGame`), story fields of GameState, or progress.cfg; its own save is `user://zombies.cfg`.
- Max 20 zombies alive; gib pool 24; blood decal pool 80; ragdolls simulating <= 6; corpses <= 12.
- Performance on Low, UHD 620: 60 FPS with 20 zombies + gore, GPU <= 14 ms, no frame > 33 ms in a horde.
- Names: our own (Iron Lung, Quickhands, Double Shot, Second Wind, Long Legs; "upgrade machine", "mystery box"); no COD audio, logos or names in game.
- Every downloaded asset: license recorded in `assets/<pack>/LICENSE.md` and in the credits screen (ui credits list); CC-BY needs the author + link.
- Checks: `_zombie_<feature>_checks(gs)` in `dev-tools/smoke_test_3d.gd` + focused `dev-tools/smoke_zombie_<feature>.gd`; full smoke passes at the end of each task.
- Never commit `dev-tools/gpu_probe.gd` or `assets/voice/*.wav`.

## Review Focus

1. Dying, quitting mid-round, or alt-F4 in zombie mode, then starting the story — story save, clock, cash, inventory unchanged; test in Z1.
2. Being surrounded by 20 zombies with gore on, upgraded LMG firing — frame time holds; test: horde probe in Z2/Z6.
3. A zombie losing both legs and its head in one shotgun blast — no orphaned limbs, no T-pose, crawler state consistent, points counted once; test in Z6.
4. Switching view (FP/TP) mid-reload, mid-ADS, or while downed — weapon state consistent, no stuck camera; test in Z4/Z5.
5. Buying with exactly enough points / one short, and buying while a power-up (Double Points) is active — never negative points, price unaffected; test in Z3.

---

### Task Z1: Mode shell, rounds and economy

**Files:** Create `autoload/ZombieMode.gd` (registered autoload), `ui/ZombieHud.gd`, `ui/ZombieGameOver.gd`, `world/ZombieBlock.gd` (attached by City3D when mode is zombies: strips story content, sets night/fog/sky); modify `ui/TitleScreen.gd` (button "Zombies" → view choice FP/TP → loads City3D in zombie mode), `world/City3D.gd` (mode branch), `autoload/GameState.gd` (`mode: String = "story"`, not saved in the story save).

**Interfaces:**
- Produces: `ZombieMode.round: int`, `points: int`, `signal round_started(r)`, `signal round_ended(r)`, `func zombie_health(r: int) -> int`, `func zombies_in_round(r: int) -> int`, `func add_points(n: int, reason: String)`, `func try_spend(cost: int) -> bool`, `func save_best()`, power-up state `double_points: bool`, `insta_kill: bool`.

- [ ] Step 1: failing checks: `zombie_health(1)==150, (9)==950, (10)==1045, (20)≈2710±5`; `zombies_in_round` matches r6=27, r7=28, r8=28, r9=29, r10=33 and r1..r5 ramp from 6 upward monotonically; `try_spend` never goes negative, exact-amount purchase succeeds, one short fails; Double Points doubles earnings not prices; starting zombie mode and dying leaves `user://save.json` and story GameState fields byte-identical (hash before/after); title screen has a "Zombies" button.
- [ ] Step 2: run `smoke_zombie_shell.gd`, expect FAIL. Step 3: implement. Step 4: PASS. Step 5: full smoke; commit `feat(zombies): the mode, its rounds and points`.

### Task Z2: Zombies (bodies, animation, navigation, spawning, barricades) + early perf gate

**Files:** Create `npc/Zombie3D.gd`, `npc/ZombieSpawner.gd`, `npc/zombie_rot.gdshader`, `npc/ZombieHitboxes.gd` (builds per-bone Area3D hitboxes on BoneAttachment3D: head, neck, torso, upper/lower arms, upper/lower legs; meta `part`), `world/Barricade.gd`, `dev-tools/fetch_mixamo_retarget.gd` (import pipeline: BoneMap from research §5 into `assets/mixamo/*.fbx` import settings, extracting an AnimationLibrary `res://assets/mixamo/zombie_clips.res`); modify `npc/CharacterAnimator.gd` aliases for zombie clips (`z_walk*`, `z_run`, `z_crawl`, `z_attack*`, `z_hit_*`, `z_death*`, `z_standup`, `z_scream`) with fallbacks to existing clips until Mixamo files exist.

**Interfaces:** Consumes Z1 (`zombie_health`, `round_started`). Produces `Zombie3D.take_hit(part: String, damage: float, dir: Vector3, weapon: Resource) -> void`, `signal died(zombie, part, melee: bool)`, `var legless: bool`, group `zombies`; `ZombieSpawner.alive() -> int`.

- [ ] Step 1: failing checks: spawner never exceeds 20 alive and spawns exactly `zombies_in_round(r)` per round; zombies path to the player across streets (navmesh) and through a barricade only after tearing all boards; boards repaired give 10 points each; hitboxes exist for all 9 parts and a ray at the head hits `part == "head"`; zombie health equals `zombie_health(round)`; runners appear from round 6.
- [ ] Step 2-4: FAIL → implement (rot shader per spec) → PASS.
- [ ] Step 5: **Perf gate** in a window on Low: 20 zombies chasing the player on Main Street, 60 s: report FPS, GPU ms, frames > 33 ms. If over budget: LOD meshes via `dev-tools/slim_glb.py`, animation update every 2nd frame beyond 15 m, shadows off on zombies — until within budget. Record numbers in the report.
- [ ] Step 6: full smoke; commit `feat(zombies): the dead walk the block`.

**Mixamo:** when this task starts, the controller gives the player the clip list (research §5) to download into `assets/mixamo/`; the task proceeds with fallbacks and wires the clips in when present.

### Task Z3: Weapons, purchases, box, upgrade machine

**Files:** Create `weapons/WeaponData.gd` (Resource), `weapons/*.tres` (pistol, SMG, shotgun, AR, sniper, magnum, LMG, wonder weapon + upgraded variants), `player/WeaponHolder.gd` (fire/reload/ammo/swap; hitscan from the active camera through hitboxes; shotgun pellets), `world/WallBuy.gd`, `world/MysteryBox.gd`, `world/UpgradeMachine.gd`; asset fetch `dev-tools/fetch_guns.py` (CC0/CC-BY guns per research §6, licenses recorded).

**Interfaces:** Consumes Z1 points API, Z2 `take_hit`. Produces `WeaponHolder.fire()`, `reload()`, `swap()`, `current: WeaponData`, `signal hit(part, killed)`, `signal fired`.

- [ ] Step 1: failing checks: damage by part (head multiplier per gun) kills a round-1 zombie in the expected shots; ammo/mag/reserve and reload times; wall-buy charges price, gives gun, refills ammo at half; box gives a gun from the pool, never the one held, moves after N uses; upgrade costs 5000 and swaps to the upgraded data; points per hit/kill/headshot/melee as spec.
- [ ] Steps 2-5 as usual; commit `feat(zombies): guns, wall-buys, the box and the upgrade machine`.

### Task Z4: First-person COD feel

**Files:** Create `player/Viewmodel.gd` + `player/viewmodel.gdshader` (draw-on-top depth/projection per research §2, Godot 4.3+ variant), `player/FPFeel.gd` (ADS, sway, bob, recoil kick/recovery, trauma shake, slide), `ui/Hitmarker.gd`, `ui/PointsPopup.gd`; arms from Rocketbox (cut via import) or CC0 MakeHuman arms; procedural reload/inspect tweens; muzzle flash, shell ejection, tracers (pooled).

- [ ] Step 1: failing checks: ADS reaches target FOV within 0.2 s ± 0.03; hip spread > ADS spread; recoil recovers to aim within 0.35 s after release; hitmarker shows 0.12 s, red on kill; slide only from sprint, lasts ~0.8 s; switching to TP mid-ADS/mid-reload leaves state consistent; viewmodel never clips (its material uses the depth shader).
- [ ] Step 2-4; Step 5: window captures of firing/ADS for review (screenshots in scratchpad), feel tuning against research numbers; commit `feat(zombies): first person that feels like a modern shooter`.

### Task Z5: Third-person RE4-Remake feel

**Files:** Create `player/ShoulderCam.gd` (over-shoulder rig, shoulder swap), `player/LaserSight.gd`, `player/TPCombat.gd` (aim walk 1.2 m/s, stagger prompts, kick AoE, knife finisher/neck stab, parry window), modify `npc/Zombie3D.gd` (stagger states per part).

- [ ] Step 1: failing checks: aiming slows to 1.2 m/s; head hit staggers and offers "Kick" for ~1.2 s; kick knocks down zombies within 1.5 m; leg hit kneels → "Knife" finisher kills with melee points; arm hit cancels a grab; parry within the window frees the player; view switch mid-aim restores camera.
- [ ] Steps 2-5; commit `feat(zombies): third person with weight`.

### Task Z6: Gore

**Files:** Create `fx/gore/wound.gdshader` (pose-space ellipsoid cutouts, 2 wounds, damage mask layering skin → flesh → bone), `fx/gore/Wounds.gd`, `fx/gore/Sever.gd` (bone scale-to-zero, stump caps, gib spawn), `fx/gore/GibPool.gd` (24), `fx/gore/BloodDecals.gd` (pool 80, raycast placement, drips from stumps, pools under corpses), `fx/gore/BloodFX.gd` (particle bursts < 64, neck fountain), `fx/gore/ScreenBlood.gd`, `fx/gore/Ragdolls.gd` (PhysicalBoneSimulator3D 11 bones, <= 6 active, freeze after 3 s, corpses <= 12); `dev-tools/bake_gore.gd` (bake rest pose to CUSTOM0, pre-cut limb gibs and stump caps per Rocketbox zombie body); gore textures/meshes fetched (CC0) or made procedurally; gore toggle in the mode menu.

- [ ] Step 1: failing checks: per-limb thresholds sever exactly that limb; both legs → `legless` and crawl clip; lethal headshot → head hidden, stump visible, fountain emitting; pools never exceed caps (fire 500 shots); one shotgun blast severing several parts awards points once and leaves no orphan nodes; gore off → no severs/decals but kills still count.
- [ ] Step 2-4; Step 5: horde perf with gore (same gate as Z2) and screenshots of wounds/severs/head pops for AA review; commit `feat(zombies): gore`.

### Task Z7: Map flow, perks, power, power-ups, downs, audio

**Files:** Create `world/ZombieDoor.gd` (paid blockades), `world/PowerSwitch.gd`, `world/PerkMachine.gd` (5 perks), `world/PowerUp.gd`, `ui/DownedOverlay.gd`; audio fetch `dev-tools/fetch_zombie_audio.py` (gun SFX, zombie vocals, licenses); original stingers via the existing SFX generation tools (`dev-tools/gen_sfx*.py`); build placements in `dev-tools/city/zombie_layout.gd` (doors, wall-buys, box spots, perks, power, upgrade machine across the block).

- [ ] Step 1: failing checks: doors cost and open nav (path exists only after purchase); perks need power, cost as spec, effects apply (health, reload ×0.5, fire rate ×1.33, stamina ×2); Second Wind revives up to 3 times; downed 30 s → game over saves best; power-up drop thresholds (2000, ×1.14, max 4/round) and effects; Nuke +400, Carpenter repairs all boards +200.
- [ ] Steps 2-5; commit `feat(zombies): the block's doors, power, perks and power-ups`.

### Task Z8: Polish and final gate

- [ ] Window playthrough to round 10 in each view (bot or scripted inputs): FPS/GPU/hitch numbers, screenshots of every area and gore beat reviewed for AA quality; credits list complete; fixes; full smoke; commit `polish(zombies): Dead Block`.

## Execution order

Z1 → Z2 → Z3 → Z4 → Z5 → Z6 → Z7 → Z8, after open-world Tasks 1-2. Sequential (one implementer at a time).
