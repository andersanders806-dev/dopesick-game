# Zombie Mode Research: Gore, Gunfeel, RE4 Feel, Round Design, Mixamo, Assets

Target: Godot 4.7.2, Forward+ (Vulkan), Intel UHD 620, 60 FPS, ~20 zombies alive, Rocketbox (Bip01) + Mixamo.
Confidence tags: **[verified]** = read from a primary source this session; **[community]** = fan wiki or forum, consistent across sources; **[recall]** = from memory, check before you ship.

---

## 1. Gore and dismemberment

### How the big games do it
- **Left 4 Dead 2: "Rendering Wounds in L4D2"** (Alex Vlachos, GDC 2010) **[verified, slides read]**. PDF: https://cdn.cloudflare.steamstatic.com/apps/valve/2010/gdc2010_vlachos_l4d2wounds.pdf
  - Each wound is an ellipsoid in **pose space**. The **vertex shader** puts the pre-skinned vertex position into the ellipsoid's basis (side, up and forward axes, each divided by that axis's size). It then passes `length(pos)` to the pixel shader, which calls `clip()` when the value is under 1. The ellipsoid-space `xy` also serves as the UV for a **projected texture**. That texture's alpha roughens the cut edge and adds a **blood layer** on the skin and clothes nearby, multiplied by a gradient so the blood doesn't reach too far.
  - The hole is filled by a separate **wound model** (meat, ribs, spine) attached to the base skeleton. Wound models are shared across all infected, with 54 unique wounds per model, and at most **2 active wounds** per zombie.
  - The cost was 15 vertex-shader instructions plus 7 pixel-shader instructions, and the base mesh still took one draw call. Watch out for depth-only and shadow passes: they have to clip too, or you get phantom shadows.
  - Rejected approaches: hard cuts alone (they looked unnatural), separate index buffers, and generating mesh holes automatically.
- **Dead Island 2 FLESH** (Fully Locational Evisceration System for Humanoids). It is procedural and layered: skin, then fat and muscle, then organs, then bone. Damage builds up in steps and depends on weapon type, how often the same spot is hit, and the zombie's health. "There's a volume of mass instead of a shell." No GDC talk turned up; the info comes from press interviews: https://www.tweaktown.com/news/88189/dead-island-2-devs-made-their-own-gore-tech-system-called-flesh/ and https://ggrecon.com/guides/dead-island-2-flesh-system. There is also a fan test bed: https://github.com/multipilled/di2-gore-lab (MIT, Oct 2026, Rust, not Godot).
- **Soldier of Fortune GHOUL**: 26 hit zones. "Gore zones" are pre-authored mesh surfaces that get toggled on, such as a skull showing through a face or a stump cap. **RE2 and RE4 Remake** use the same idea: pre-cut limb pieces, cap meshes, and damage masks that blend in exposed muscle and bone. **Dead Space**: dismemberment is the core mechanic, with fixed sever points at every limb joint plus a hit-count threshold per limb. **COD Zombies** head pop: on a lethal headshot the head is hidden, a blood burst plays, and a neck stump cap appears.
- GutBox (Unity) devlog explains in-mesh severing by re-assigning bone weights and deleting triangles, so no mesh is duplicated: https://luzemrik.itch.io/gutbox/devlog/475023/some-info-on-the-gore-tech

### Recommended Godot pipeline (tiered, all affordable on UHD 620)
**Tier A: sever limbs with bone collapse, caps and gibs (do this first).**
1. Pick sever bones: Head, L/R UpperArm, L/R Forearm, L/R Thigh, L/R Calf.
2. To sever, `skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.001)` on the severed bone. Its children collapse with it, so the skin pinches into the joint.
3. Cover the pinch with a **stump cap**: a low-poly hemisphere with a meat, bone-ring and fat texture, placed with a `BoneAttachment3D` on the *parent* bone and sized per joint.
4. Spawn the **gib**. Use a pre-baked limb mesh, made in an `EditorScenePostImport` script or in Blender. For each sever bone, take the triangles whose highest-weight bone sits in that bone's subtree, save them as a static `ArrayMesh`, and add a cap at the cut. Put it on a `RigidBody3D` with a `CapsuleShape3D` (never a mesh collider), copy the bone's global transform, and apply an impulse along the bullet direction.
   - Alternative for posed gibs: `MeshInstance3D.bake_mesh_from_current_skeleton_pose()` (added in 4.3 **[recall]**), then discard everything outside the subtree. It costs more CPU per sever, so keep it for rare finishers.
5. Pool the gibs at around **24 live at most**, oldest recycled first. After about 4 s asleep, freeze them (`freeze = true`) and fade or sink them out after 20 to 30 s. Set gibs to `cast_shadow = OFF`.
6. Thresholds, borrowed from Dead Space and COD: each limb has its own HP, about 35% of total HP for arms and 45% for legs. Shotguns and explosives can sever at once; pistols take several hits. Head HP equals the lethal headshot threshold, so a killing headshot on a "pop" weapon always triggers the head pop.

**Tier B: L4D2-style wound cutouts (most visual payoff per millisecond).**
- Write a ShaderMaterial on the zombie body with **2 to 4 wound slots**. Godot does skinning in a compute pass before the vertex shader, so `VERTEX` arrives already skinned and there is no direct "pre-skinned" position.
  - **Option 1 (recommended)**: at import, bake the rest-pose position into `CUSTOM0.xyz` using `ArrayMesh` custom formats. At hit time, transform the hit point into the hit bone's local space using the current pose, then into rest space, and store the ellipsoid (`mat4` inverse basis) in rest space. Done that way, the shader needs **no per-frame updates**.
  - **Option 2**: give each zombie its own material (20 materials is fine), and every frame write each wound's model-space `mat4` from the bone's global pose.
- The shader computes `d = length(inv_ellipsoid * rest_pos)` in the vertex stage and interpolates it. In the fragment stage, `if (d < 1.0 - edge_noise) discard;`. For the band `d < 1.3`, blend in a blood and torn-flesh texture projected from ellipsoid-space xy (L4D2's blood layer). Godot runs the same shader in shadow and depth passes, so there are no phantom shadows.
- Inside the hole, put **wound interior meshes**: 4 to 6 generic ones (rib cage, gut cavity, skull, thigh meat and bone, neck spine). Attach each to the bone with `BoneAttachment3D`, cull backfaces off on the interior shell, and use dark red emission at about 0.05 so the hole reads at night.
- Cost: `discard` turns off some early-Z on that material. At 20 zombies about 1.8 m tall, the fill cost is small next to night lighting, so it's acceptable on UHD 620.

**Tier C: progressive surface damage (cheap FLESH-lite).** Keep a per-zombie 64x64 **damage mask texture** (an `ImageTexture` updated on hit by painting a circle at the hit UV, via `Image.fill_rect`/blend, a few hundred microseconds). The shader lerps skin, then bloodied skin, then muscle, then bone across mask levels 0.33, 0.66 and 1.0, each hit adds more, and you get DI2's step-by-step layers. With a UV lookup from the raycast (via `MeshDataTool` face lookup, or a cheaper option, the nearest of 8 to 16 pre-picked UV hotspots per bone), this costs almost nothing on the GPU.

### Blood
- **Decals**: Forward+ decals are clustered and share a **512 clustered-element default limit** with lights and probes in view (Project Settings > Rendering > Limits > Cluster Builder > Max Clustered Elements). Decals can't run custom shaders. Docs: https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html
  - UHD 620 budget: pool about **64 to 96 world blood decals** (wall splats, floor pools, drag trails). Use 512 px textures from one atlas. Keep `upper_fade`/`lower_fade` short and `distance_fade_enabled` on at about 25 m.
  - Spawning: on a hit, raycast from the exit point along the bullet direction, 0.5 to 3 m. If it hits a wall, place a splat decal aligned to the normal, rotated randomly and scaled by weapon. Fire 1 to 3 more random-cone rays for shotguns.
  - Floor pools: on death, spawn a decal under the pelvis and tween its `size` from 0.3 to 1.6 m over 4 s.
- **Particles**: use **GPUParticles3D** with 32 to 64 particles per burst. Use **alpha-scissor or opaque** materials, not alpha-blend; overdraw is what actually hurts an iGPU. Turn on collision with a `GPUParticlesCollisionHeightField3D` over the block so drops hit the ground. Keep one pooled emitter per effect type and move it with `restart()`/`emit_particle()`. CPUParticles3D works too, but at 20 zombies GPU is better. Ready-made: https://github.com/newlaptopfor-oss/Godot_Blood_Effect (MIT, Godot 4.7+, active Oct 2026).
- **Neck fountain** after a head pop: a looping emitter at 1.5 to 2 s, BoneAttachment on the Neck, 20 particles per second.
- **Screen blood**: a full-screen `ColorRect` canvas shader with 3 to 4 splat textures. It turns on when a gib or kill happens within 2.5 m of the camera, or when the player takes damage. Fade over 1.5 to 3 s with a downward-drip UV offset. Cost is one full-screen texture fetch, which is cheap.
- **Bloody weapon and arms**: a viewmodel shader parameter for blood amount, which rises after melee kills.
- **CC0 blood textures**: https://opengameart.org/node/52811 (high-resolution splatter, CC0), https://opengameart.org/content/liquid-splatter-pixel-texture (CC0), https://opengameart.org/node/168322 (Screaming Brain Studios Horror Texture Pack, 300 textures with stains, CC0), https://opengameart.org/node/119417 (about 100 splatters, CC0). For gib meshes there's little good CC0, so make about 6 chunk meshes in Blender: random noise-displaced icospheres with a meat material. **Quaternius** and **Kenney** have nothing gory.

### Ragdolls and hit reactions
- **PhysicalBoneSimulator3D** (4.3+). Strip it down to **11 bodies**: pelvis, spine, chest, head, 2x upper arm, 2x forearm, 2x thigh, 2x calf. Small bones cost as much as big ones. For a **partial ragdoll** on a hit reaction, call `physical_bones_start_simulation(["L UpperArm","L Forearm"])` and blend with the **`influence`** property, 0.3 to 0.6 for a flinch. Wrong bone names fail silently. Docs: https://docs.godotengine.org/en/stable/tutorials/physics/ragdoll_system.html
- UHD 620 / CPU budget: **at most 4 to 6 simulating ragdolls** at once. After 3 s, or once velocity is under a threshold, stop the simulation and leave the corpse in its final pose. Corpse cap is about 12; past that, sink and fade the oldest. Use Jolt physics, which is the default for new projects in recent 4.x **[recall]**.
- **Hit reactions without physics**: put an additive "hit" layer in the AnimationTree (Mixamo "Zombie Reaction Hit" as an additive one-shot). Better still is a procedural bone impulse: add a spring-damped rotation offset to the hit bone and its parent with `set_bone_pose_rotation` after the animation runs, using `SkeletonModifier3D._process_modification()`. That's very cheap and looks great.
- **Crawlers**: when a leg is severed, or on an explosive near-kill, switch the state machine to the crawler set (Mixamo "Zombie Crawl" / "Running Crawl"), set the capsule to lying, change the navmesh agent height to 0.6 m, and give it a lower attack ("Zombie Biting" on the floor).
- Repos to read: https://github.com/Alenvei/Dismemberment_Tutorial_Godot4.2 (MIT, Dec 2023), https://github.com/gamecolab-personal-projects/Godot_Dismemberment (no license, Jan 2026, "head explosion like in M..." so read it but don't copy it), https://github.com/ToxicCrack/GodotDismembermentProto (MIT, 2019, Godot 3).

---

## 2. COD gunfeel in Godot

- **Recoil**: split it into two layers.
  - **Actual**: the camera pitches up per shot (AR 0.4° to 0.8°, SMG 0.3° to 0.5°) with a per-weapon horizontal pattern (a curve resource indexed by shot number plus a little random jitter). The camera recovers about 60 to 80% when you stop firing.
  - **Visual**: the viewmodel kicks back 2 to 5 cm, rotates up 2° to 6°, and rolls a little. A critically damped spring brings it back (stiffness about 200, damping about 20).
  - Bullets go where the crosshair actually points; the visual kick doesn't affect accuracy.
- **ADS**: lerp over 0.2 s (pistol/SMG), 0.3 s (AR), 0.35 to 0.5 s (LMG/sniper). The world FOV multiplier is about **0.8 to 0.85** for irons and red dots, 0.65 for 2x/ACOG, and **0.25 to 0.33** for sniper scopes, shown as a full-screen scope overlay with breath sway and hold-breath. Mouse sensitivity scales with the FOV ratio. ADS sway is a Lissajous loop with amplitude about 0.1° to 0.3°. Moving speed while ADS is about 0.6x.
- **Viewmodel rendering**: take the **shader approach**, not a SubViewport (a second viewport costs too much on UHD 620). Write a custom projection in the vertex shader with its own viewmodel FOV (around 55° to 65° vertical) and push the depth toward the near plane. Since **4.3 Godot uses reverse-Z**, older shaders break, so use the updated one: https://godotshaders.com/shader/first-person-view-model-shader-updated-for-godot-4-3/ (forum thread on the shadow bug: https://forum.godotengine.org/t/fixing-weapon-clipping-using-shader-causes-shadow-bug/91595). Set the viewmodel to `cast_shadow = OFF` and draw its own fake shadow, or use none.
- **Hitmarkers**: 4 short diagonal strokes about 8 px from the crosshair, shown for 0.12 s with a scale punch 1.3 to 1.0. Body hits are white, headshots slightly bigger, and kills turn red. Play a crisp "tick" sound, a short high transient around 2 to 4 kHz, plus a heavier thump on a kill. On kills, show a "+points" popup next to the score, COD-zombies style.
- **Bob and sway**: on walk, a figure-8 at step frequency (~1.8 Hz walk, 2.6 Hz sprint), amplitude 1 to 2 cm. Mouse-look sway lags behind input by 2° to 4°. Sprint puts the weapon in a canted, lowered pose.
- **Slide**: from a sprint, press crouch for 0.7 s; speed starts at 1.4x sprint and drops off, the camera lowers 0.6 m with a 4° roll, and FOV goes up 5.
- **Muzzle flash**: 2 crossed alpha-scissor quads with random rotation plus one `OmniLight3D` at about 1.5 m range for 1 frame. Pool that one light and don't spawn new ones; a light costs a cluster slot. **Shells**: pooled RigidBody3D, or cheaper GPUParticles with mesh draw, plus a tink sound. **Tracers**: a stretched emissive quad moving at 300 m/s, every 3rd round.
- **Camera shake**: use Squirrel Eiserloh's trauma model (GDC 2016, "Juicing Your Cameras With Math"): `shake = trauma²`, with noise-driven yaw, pitch and roll, and trauma decaying at about 1.5 per second.
- **Repos**:
  - https://github.com/Jeh3no/Godot-simple-FPS-weapon-system (MIT, 113 stars, active Jun 2026): sway, procedural recoil, viewmodel camera.
  - https://github.com/Jeh3no/Godot-Simple-State-Machine-First-Person-Controller (MIT, 91 stars, Jun 2026): slide and movement.
  - https://github.com/WynnSystems907/COBRA-FPS-Feelkit (MIT, Dec 2025): bob, recoil, hit feedback.
  - https://github.com/indieAYUSH/Simple-and-Modular-weapon-system-for-godot-4.x (MIT, Jul 2026).
  - https://github.com/2nafish117/godot-viewmodel-render-test (MIT, viewmodel FOV idea).
  - https://github.com/Valks-Games/zombies (MIT, C#, 2023).

---

## 3. RE4 Remake third-person feel

- **Camera**: right shoulder offset about +0.45 m to the side, +0.15 m up, 1.6 m back for exploring. Aiming pulls it in to about 0.9 m back and 0.55 m to the side, and the FOV narrows from about 60° to 48° over 0.2 s. Add a `SpringArm3D` with a small collision margin, and support a shoulder swap.
- **Aim walk**: you can't sprint while aiming, and you walk at about **1.2 m/s** with the turn rate clamped. Feet plant while the upper body twists (aim offset). The weight of this is what sells the feel.
- **Laser sight**: a thin unshaded additive cylinder (or `ImmediateMesh` line) from the muzzle to the raycast hit, plus a small dot (unshaded billboard quad, not a Decal) at the hit point. Add a little noise wobble that shrinks the longer you hold still ("focus"). The reticle tightens over about 0.6 s when you're stationary.
- **Stagger to finisher**: RE4R behaviour **[community]**: https://progametalk.com/resident-evil-4-remake/how-to-melee-attacks/ and https://www.destructoid.com/how-to-perform-a-suplex-in-resident-evil-4-answered/
  - **Headshot**: the enemy staggers with hands to its face, and a melee prompt appears. Hitting it from the **front** is a roundhouse kick with area knockback that knocks nearby enemies down too.
  - **Knee or leg shot**: the enemy drops to a kneel. From behind, the finisher is a suplex or neck stab; a suplex can pop the head for an instant kill.
  - **Arm shot**: the enemy drops its weapon, or for a zombie, the grab is cancelled.
  - **Knife parry**: block in a ~0.2 s window just before a hit lands, which deflects the attack and staggers the enemy. Knives have durability.
- **Implementation**:
  - Per zombie, track a stagger accumulator per body region that decays after about 1.5 s. Thresholds: head 1 to 2 pistol hits, legs about 3.
  - While staggered (1.2 to 1.8 s window), show a prompt within 2.2 m. Pick the finisher from the dot product of the zombie's forward and the direction to the player.
  - For the finisher, line up the player and zombie with a short tween and play paired animations. Pair Mixamo "Zombie Reaction Hit" or a knockback clip on the zombie with a kick clip on the player.
  - Use the RE "melee kill" in our zombie mode as a points bonus, like the COD knife.

---

## 4. COD Zombies round numbers (we use our own names; these are the numbers from World at War through Black Ops 1)

- **Health** **[community, consistent]**: round 1 = 150, then +100 per round up to 950 at round 9. From round 10 on, multiply by 1.1 each round (r10 = 1045, r20 ≈ 2710, r30 ≈ 7030, r50 ≈ 47,295).
- **Count, solo** **[recall, reproduces known values]**: rounds 1 to 5 are hand-tuned at 6, 8, 13, 18, 24. From round 6 on:
  `mult = max(1, r/5); if r >= 10: mult *= r*0.15; total = 24 + int(0.5*6*mult)` (solo); co-op is `24 + int((players-1)*6*mult)`.
  Check: r6 = 27, r7 = 28, r8 = 28, r9 = 29, r10 = 33, which matches the community tables. COD caps **24 alive** with the rest held in reserve, so our cap of **20** fits.
- **Spawn delay** **[recall]**: starts at 2.0 s and multiplies by 0.95 each round, with a floor around 0.08 to 0.1 s.
- **Speed** **[recall]**: `move_speed = r * 8` (randomised per zombie). Under 35 walks, 35 to 70 runs, above 70 sprints. So rounds 1 to 3 are walkers, runners start appearing around round 4 to 5, and sprinters around 9 or later.
- **Points** **[recall, BO1]**: 10 per bullet hit, 60 for a body kill, 70 for a neck kill, **100 for a headshot kill**, **130 for a melee kill**, and 10 per barricade board repaired. Double Points doubles all of these.
- **Prices** **[community / recall]**:
  - Mystery box **950** (Fire Sale makes it 10).
  - Pack-a-Punch **5000**.
  - Doors and debris **750 / 1000 / 1250 / 1500** as you go deeper.
  - Wall buys: starter rifle and shotgun 500, SMG 1000 to 1200, AR 1200 to 1400, pump shotgun 1500; ammo costs half the gun's price, or 4500 for an upgraded gun.
  - Perks: tank (health) **2500** (https://giantbomb.com/wiki/Locations/Kino_Der_Toten), reload **3000**, fire rate 2000, revive 500 solo / 1500 co-op, stamina 2000, extra weapon slot 4000. Cold War switched to flat escalating prices, 2500 rising by 500 per perk owned.
- **Power-ups** **[recall]**: the first drop happens once 2000 points have been earned, and each threshold after that is 1.14x the last, with at most 4 drops per round. The pool is Max Ammo, Insta-Kill (30 s), Double Points (30 s), Nuke (+400), Carpenter (+200) and Fire Sale.
- **Round transition**: the last zombie dies, about 10 s of break with a round-end sting and a big round-number animation, then a round-start sting. Spawning picks the nearest active zone spawners, and a zombie that has been stuck or far away for 15 s or more respawns.
- Health becomes a damage sponge after round 30; insta-kill, headshot multipliers (headshots do about 2 to 4x) and PaP keep it playable.

---

## 5. Mixamo zombie clips and retargeting

**Clips to download** (names as they appear in Mixamo search; **[recall]**, so search "zombie" on mixamo.com and confirm):
- Idle: **Zombie Idle**, **Zombie Scream**, **Zombie Agonizing**
- Walk: **Zombie Walk** (several variants exist; get every one, since walk variety matters most), **Walking** (zombie pack), **Zombie Turn**
- Run: **Zombie Running**, **Zombie Run**
- Crawl: **Zombie Crawl**, **Running Crawl**
- Attack: **Zombie Attack**, **Zombie Punching**, **Zombie Kicking**, **Zombie Headbutt**, **Zombie Biting**, **Zombie Neck Bite**
- Hit: **Zombie Reaction Hit**, plus generic **Hit Reaction**, **Head Hit**, **Big Hit To Head**, **Stomach Hit**, **Knocked Down**
- Death: **Zombie Dying**, **Zombie Death**, and generic **Dying**/**Falling Back Death**
- Spawn: **Zombie Stand Up**, **Zombie Transition** (use for climbing out of the ground or through a window)
- Player-side finishers: **Roundhouse Kick**/**Mma Kick**, **Stabbing**

**Download settings**: FBX Binary, **Without Skin** (one skinned "Y Bot" download as the bone-map source), **30 FPS**, Keyframe Reduction none, and tick **In Place** on locomotion where offered (root motion off). For a root-motion run, keep it off and drive speed from the NavigationAgent instead.

**Retarget onto Rocketbox Bip01** (docs: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html):
1. Import the Rocketbox glTF. In Advanced Import, select the Skeleton3D, go to Retarget, create a BoneMap with **SkeletonProfileHumanoid**, and map it by hand:
   - Root → Bip01, Hips → Bip01 Pelvis, Spine → Bip01 Spine, Chest → Bip01 Spine1, UpperChest → Bip01 Spine2, Neck → Bip01 Neck, Head → Bip01 Head.
   - LeftShoulder → Bip01 L Clavicle, LeftUpperArm → L UpperArm, LeftLowerArm → L Forearm, LeftHand → L Hand.
   - LeftUpperLeg → L Thigh, LeftLowerLeg → L Calf, LeftFoot → L Foot, LeftToes → L Toe0.
   - Fingers: Finger0 = thumb, 1 = index, and so on. Map the right side the same way.
   - Save the BoneMap as a `.tres` and reuse it for every Rocketbox character.
2. Import each Mixamo FBX and apply the **same profile** (Mixamo auto-maps). Use Import As: Animation Library and save to `.res`.
3. Turn on the Rest Fixer options on **both** sides: **Apply Node Transforms**, **Normalize Position Tracks**, **Overwrite Axis** (needed here, because the 3ds Max biped's odd pelvis and spine axes are the usual cause of twisted torsos), **Fix Silhouette** (Rocketbox isn't an exact T-pose), and **Reset All Bone Poses After Import**. Keep **Rename Bones** on so both skeletons become `%GeneralSkeleton` with profile names. The shared AnimationLibrary then plays on any zombie.
4. Pitfalls:
   - Twisted hands or forearms: remap, and check the red dots in the BoneMap (https://forum.godotengine.org/t/ue-fbx-animations-work-on-ue-skeleton-but-break-on-mixamo-after-retargeting-in-godot/135712).
   - Biped twist bones (`Bip01 L ForeTwist`, etc.): leave them unmapped with "Unmapped Bone Transform: Reset", or they pinch.
   - Hips height: Normalize Position Tracks scales it to the target's hips height.
   - Mixamo hip translation drifts; use In Place or strip XZ position on the Hips track.
   - Mixamo clips are 30 fps; set the loop mode by hand.
   - Helper: https://godotengine.org/asset-library/asset/5096 **MixaBridge** (MIT, Godot 4.4+, auto-maps Mixamo to SkeletonProfileHumanoid and batch-builds the AnimationLibrary).
5. Variety and cost: randomise `AnimationTree` speed scale (0.85 to 1.15) and start offsets, and switch to `AnimationPlayer` for zombies far away. Twenty AnimationTrees run fine on the CPU; skinning runs on the GPU compute pass. Use Rocketbox's lower-poly variants (or decimate to about 8 to 10k tris) beyond 15 m, using `visibility_range` LODs.

---

## 6. Free arms, guns and sound assets

| Asset | URL | License | Notes |
|---|---|---|---|
| FPS arms (rigged only) | https://opengameart.org/content/fps-arms-rigged-only | CC0 | About 8k tris, MakeHuman, IK rig, **not animated** |
| CC0 Flat Guns West / East | https://pichuliru.itch.io/cc0-flat-western-guns , https://pichuliru.itch.io/cc0-flat-guns-east | CC0 | 10 guns each, **rigged** (mag and slide bones), flat-shaded low poly |
| Quaternius 50+ LowPoly Guns | https://quaternius.itch.io/50-lowpoly-guns | CC0 | AK, M4, pistol, shotgun, sniper; stylized, very light |
| Quaternius Low Poly Guns / GunPack Vol.1 (WW2) | https://opengameart.org/content/low-poly-guns-pack | CC0 | Not rigged |
| Ultimate Low Poly Guns (71) | https://opengameart.org/content/ultimate-low-poly-guns | **CC-BY 4.0** | Credit TastyTony and Pichuliru |
| Animated FPS Pistol | https://levraicoincoin.itch.io/animated-fps-pistol | CC-BY 4.0 (wording unclear, confirm) | Arms and animations |
| Animated pistol (DJMaesen) | https://sketchfab.com/3d-models/animated-pistol-bd896167e7ca44f19597d3afe6a8d83f | CC-BY | Fire, reload, draw |
| Gun reload SFX | https://opengameart.org/content/gun-reload-sound-effects , https://opengameart.org/content/gun-reload-sounds | CC0 | Small sets |
| Authentic gun sounds (F8) | https://f8studios.itch.io/snakes-second-authentic-gun-sounds-pack | Free commercial use, no credit (not CC) | 9mm, .308, 20 ga, plus reloads |
| **Sonniss GDC Game Audio Bundles** | https://sonniss.com/gameaudiogdc | Royalty-free, commercial OK (custom license, not CC) | Many GB of real firearm, gore-foley and creature recordings. The **best realistic source** **[recall]** |
| Zombies Sound Pack | https://opengameart.org/content/zombies-sound-pack | CC0 | 24 WAVs |
| Zomby sfx pack | https://opengameart.org/content/zomby-sfx-pack | CC0 | 6 voice calls; randomise pitch 0.5 to 1.5 |
| Freesound | https://freesound.org (filter License: CC0) | CC0 per file | Gore foley: wet meat squelch, bone crack, cabbage and celery smash |

**Gaps**: no free source gives you realistic, rigged, *animated* arms with a full gun set (pistol, SMG, shotgun, AR, sniper, magnum, LMG). The closest commercial match is Ironbelly's Animated FPS Starter Kit (paid). Practical free route:
1. Take the CC0 MakeHuman arms (or the Rocketbox arms, cut from a Rocketbox body, MIT-licensed) and a CC0 gun set.
2. Animate reloads in Blender (10 to 20 clips), or do it **procedurally** in Godot: tweens for mag-out and mag-in, slide rack, and an ADS pose. Many COD-feel demos do this.
3. For realism, pick guns from Sketchfab's downloadable CC-BY filter with under 15k tris each, credited in the game.

**Gore SFX** carries more of the gore impression than visuals do. Layer 2 to 3 samples per hit (impact crack, wet splat, bone snap), randomise pitch ±8%, and give a head pop its own heavy sound.

---

## UHD 620 budget summary (things to watch)
- **Too heavy**:
  - SubViewport viewmodel → use the depth or projection shader instead.
  - Mesh-collider gibs → use capsules.
  - More than 6 simulating ragdolls → freeze to pose.
  - Alpha-blended blood particles filling the screen → use alpha-scissor and keep each burst under 64 particles.
  - Runtime mesh slicing (DI2-style real cuts) → bake limb pieces at import and use shader ellipsoid cutouts.
  - More than 100 decals plus many lights → pool about 80 and keep under the 512 cluster limit.
  - SDFGI, volumetric fog at high settings → fake the night with fog depth plus a few lights.
  - Shadows from gibs, shells or particles → OFF.
- **Cheap but very effective**: ellipsoid wound cutouts plus interior meshes, bone-collapse sever plus stump caps, damage-mask texture layers, screen blood, procedural hit flinch, layered gore audio, and the hitmarker sound.
