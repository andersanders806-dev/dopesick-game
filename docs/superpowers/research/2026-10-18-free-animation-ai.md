# Free animation and AI art sources for Zombie Mode (no Mixamo)

Date: 2026-10-18. Target: Godot 4.7.2, Rocketbox avatars (3ds Max Bip01, glTF, MIT), Linux laptop with an Intel UHD 620 (no CUDA), 8 threads, 22 GB RAM.
Local tools found: Blender 5.2.2 LTS at `/snap/bin/blender` (headless works), g++ 15, ffmpeg. There's no cmake, ninja or go; `pip install cmake ninja` provides the first two. `~/venv` runs Python 3.14 and doesn't have gradio_client installed.
This replaces the Mixamo plan in `2026-10-18-zombie-gore-gunfeel.md` section 5. That doc's Godot BoneMap and Rest Fixer notes still apply.

**What "verified" means here.** I ran these tests from this laptop with no account during this research:

| Test | Result |
|---|---|
| HY-Motion Space, zombie-walk prompt | Anonymous call worked. 4 s, 52-bone SMPL-H FBX in 14 s. |
| MoMask Space | Anonymous call worked. 22-joint BVH in 5 s. Needs the legacy gradio_client 0.8.1, because the Space uses the ws protocol. |
| FLUX.1-schnell Space | Anonymous call worked. 1024 px image in 9 s. |
| TRELLIS.2 Space | **Refused.** "exceeded your ZeroGPU quota (120s requested vs. 0s left)" after the two calls above. |
| Quaternius UAL 1 and 2 | Downloaded from OpenGameArt without login. I listed every clip and the skeletons. |
| Format conversion | Headless Blender turned both the BVH and the FBX into GLB. |

The rest comes from documentation, model cards and license texts. Each item is marked as one or the other.

---

## 0. TL;DR stack

| Need | 1st choice | Fallback | Account? |
|---|---|---|---|
| Base zombie idle, walk, scratch, hits, death, stand-up | Quaternius UAL 1 + UAL 2 (CC0, direct zip) | Rocketbox's own MIT clips (native Bip01): `walk_drunk`, `walk_injured`, `idle_drunk`, `crouch_*` | No |
| Extra walk variants, run, crawl, grab, bite, stagger, knockdown, scream, window climb, player kick and stab | **NVIDIA Kimodo SOMA via kimodo.cpp, local on CPU** (Apache-2.0 code, NVIDIA Open Model License weights, commercial OK, no territory limit) | HY-Motion 1.0 Space (best zombie quality, anonymous, FBX). **Its license excludes the EU, UK and South Korea.** See section 2. | No (Kimodo); no but ZeroGPU-capped (HY-Motion) |
| Deaths and knockdowns | Godot ragdoll (`PhysicalBoneSimulator3D`) blended from a short AI or Quaternius "hit" clip | UAL1 `Death01`, AI "collapses" clips | No |
| Retargeting onto Bip01 | Headless Blender world-space bake (extend `dev-tools/rocketbox_to_glb.py`) into an animation-only GLB | Godot import retarget (BoneMap + SkeletonProfileHumanoid + Rest Fixer) | No |
| Severed limbs and stumps | **Cut the Rocketbox meshes themselves** in headless Blender (bisect, cap, meat material), so they match skin and clothes | FLUX image to TRELLIS.2 (needs an HF token) | No / HF token |
| Gibs | Procedural Blender (displaced icospheres) + CC0 textures | TripoSR, local on CPU (MIT) | No |
| Guns and melee | Poly Haven CC0 (`service_pistol`, `bolt_action_rifle_7_62`, `machete`, `crowbar_01`, `baseball_bat`, `hatchet`, `fish_knife`) through the existing `dev-tools/fetch_polyhaven_models.py` | OpenGameArt CC0 (Lightning pump-action rifle; Low-poly FPS rifle + hands) | No |
| First-person arms | Rocketbox avatar arms (delete everything above the clavicles), driven by the same Bip01 clips | OGA "low poly fps rifle and hands" (CC0) | No |
| PBR textures | ambientCG + Poly Haven (CC0, APIs, already scripted in `dev-tools/fetch_ambientcg.py`, `dev-tools/fetch_polyhaven.py`) | StableMaterials (OpenRAIL, needs a GPU; skip) | No |
| Decals, blood, UI icons | FLUX.1-schnell Space (Apache-2.0, anonymous), Pollinations (anonymous, now serves only `sana`, Apache-2.0) | CC0 blood packs from the earlier research doc | No |
| Auto-rigging | Not needed: everything skinned comes from Rocketbox. Props stay rigid. | UniRig (MIT, CUDA only; its Space is broken) | n/a |

---

## 1. Free animation libraries (ranked)

| # | Source | License | Format / skeleton | Zombie-relevant clips (verified where stated) | Unattended download? | Last activity |
|---|---|---|---|---|---|---|
| 1 | **Quaternius Universal Animation Library 2** — https://opengameart.org/content/universal-animation-library-2 (direct zip: https://opengameart.org/sites/default/files/universal_animation_library_2standard.zip), also https://quaternius.itch.io/universal-animation-library-2 | **CC0** (License.txt in the zip, verified) | GLB (Godot/Unreal) + FBX (Unity). **65-joint UE5-Manny-style skeleton** (`root, pelvis, spine_01..03, neck_01, Head, clavicle_l, upperarm_l, lowerarm_l, hand_l, ..., thigh_l, calf_l, foot_l, ball_l`) | Verified, 43 clips in the free Standard version: **`Zombie_Idle_Loop`, `Zombie_Scratch`, `Zombie_Walk_Fwd_Loop`**, `Hit_Knockback`(+`_RM`), **`LayToIdle`** (stand up from lying), **`ClimbUp_1m_RM`**, `Melee_Hook`(+`_Rec`), `Sword_Regular_A/B/C` (base for a knife stab), `OverhandThrow`, `Consume` (base for feeding), `Idle_No_Loop`. The paid Source tier ($14.99) adds the .blend and about 30% more clips. | Yes, plain curl, no login | Feb 2026 release |
| 2 | **Quaternius UAL 1** — https://opengameart.org/content/universal-animation-library (zip: https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip) | **CC0** | GLB/FBX, **53-joint Rigify `DEF-` skeleton** (different from UAL2) | Verified, 46 clips: **`Death01`, `Hit_Chest`, `Hit_Head`**, `Punch_Jab/Cross`, `Crouch_Fwd_Loop`, `Sprint_Loop`, `Jog_Fwd_Loop`, `Roll`, `Jump_*`, `Pistol_*` (aim, reload, shoot: useful for the player), `PickUp_Table`, `Push_Loop` | Yes | 2024 |
| 3 | **Microsoft Rocketbox's own animations** — https://github.com/microsoft/Microsoft-Rocketbox/tree/master/Assets/Animations | **MIT** | FBX, **native Bip01, no retargeting needed**; the project already fetches them with `dev-tools/fetch_rocketbox.py` | 326 files, all civilian. Useful as zombie bases: `m/f_idle_drunk`, `m_drunk_gestic`, `walk_drunk/injured/bruised`, `run_neutral`, `crouch_in/idle/out`, `idle_roll_head`, `idle_shake_arms`, `knock_door` (base for banging on a barricade), `try_door_*`. No combat or deaths. | Yes | maintained |
| 4 | **CMU Graphics Lab Mocap** — http://mocap.cs.cmu.edu ; BVH conversions by cgspeed; retargeted pack (2000+ clips on a CC0 Quaternius character, FBX/glTF) at https://rancidmilk.itch.io/free-character-animations | Free for commercial products, **may not be resold as raw data** (CMU FAQ). RancidMilk pack: free to use and redistribute, not to sell as animations; scripts are GPL-3.0. | BVH (31 joints, CMU naming) / FBX / glTF | Stumbles, falls, get-ups, crawls, injured walks, drunk walks, kicks, punches. Quality is raw 2000s optical data: jittery feet, needs cleanup. | Yes (cgspeed BVH mirrors; itch free downloads can be scripted) | Data is from 2003–2010 |
| 5 | **Anderson Rohr Halloween mocap pack** (19 clips, several zombie walks, monster attacks) — https://andersonrohr.gumroad.com/l/mocap_pack8 (described at https://80.lv/articles/get-ready-for-halloween-with-these-19-free-mocap-animations) | "Free for personal and commercial projects" (no formal license text; record a screenshot) | FBX on Rokoko, iClone and UE5 Manny skeletons | Zombie walks and attacks (clip names unverified) | Gumroad $0 checkout asks for an email, so it's semi-manual | 2023 |
| 6 | **Rokoko Motion Library** (150 free moves) — https://www.rokoko.com/pricing | Free moves are licensed for commercial projects | FBX/BVH from Rokoko Studio | Generic, few zombie clips | **Needs a Rokoko account and the Studio app.** Not unattended. | 2020 launch |
| 7 | **ActorCore free motions** — https://actorcore.reallusion.com/motion/free | Free; games may need Reallusion's (free) "mass distribution" license request | FBX | Few; no zombie clips confirmed | **Needs a Reallusion account** | — |
| 8 | **Fab (Unreal) free/permanent items**, e.g. "MoCap Online Free Animation Pack" | Fab Standard License allows use in any engine; only Epic's own UE-only content is excluded | FBX (UE5 skeleton) | The free pack has scared walks and deaths. The 141-clip "Zombie NPC Mocap" pack is paid. | **Needs an Epic login** | — |
| 9 | Truebones free packs — https://truebones.gumroad.com | License text not found. **Avoid** until verified. | FBX/BVH | Nothing zombie-specific is free | Gumroad | — |
| ✗ | **Bandai Namco Research Motiondataset** — https://github.com/BandaiNamcoResearchInc/Bandai-Namco-Research-Motiondataset | **CC BY-NC-ND 4.0, not usable** | BVH | — | — | — |
| ✗ | **LAFAN1** (Ubisoft) — https://github.com/ubisoft/ubisoft-laforge-animation-dataset | **CC BY-NC-ND 4.0, not usable** | BVH | — | — | — |
| ✗ | **100STYLE** | License unverified (the dataset page needs checking); research dataset. Treat as unusable. | BVH | Has "Zombie" and "Drunk" styles | — | — |
| ✗ | **BONES-SEED** (bones-studio/seed on HF) | Gated (HF login + form). Revocable; only companies under $1M revenue; no raw redistribution; you must stop shipping if terminated. **Too risky.** | BVH | — | No | 2026 |
| ✗ | Kenney | CC0 but only basic idle, walk and run on blocky characters. Not useful. | | | | |

**Verdict:** Quaternius UAL1 and UAL2 plus Rocketbox's own clips cover idle, one zombie walk, scratch, three hit reactions, death, stand-up, a climb and the player's pistol set, all CC0 or MIT and downloadable unattended today. Everything else on the list (bites, grabs, crawls, staggers, knockdowns, window climbs, screams, kick and stab finishers, extra walk styles) has to come from AI generation (section 2).

---

## 2. AI text-to-motion

### 2a. Candidates

| Model | Code / weights license | Output license | Free, unattended access from this laptop | Output format | Zombie quality |
|---|---|---|---|---|---|
| **NVIDIA Kimodo** (Mar 2026; v1.2 on 2026-10-15) — https://github.com/nv-tlabs/kimodo (3.8k★, pushed 2026-10-15) | Apache-2.0 code. **SOMA and G1 weights: NVIDIA Open Model License**: "Models are commercially usable", "NVIDIA claims no ownership rights in outputs", worldwide, no revenue or MAU cap. If you redistribute the *model* you must include a NOTICE; this doesn't apply to outputs. Training data is the licensed Bones Rigplay mocap, so there's no SMPL/AMASS taint. **The SMPLX-RP checkpoint is research-only. Don't use it.** | Yours | **(a) Local on CPU via kimodo.cpp** — https://github.com/localai-org/kimodo.cpp (Apache-2.0, 915★, pushed 2026-09-17). Ungated GGUF weights: https://huggingface.co/LocalAI-io/Kimodo-SOMA-RP-v1.1-GGML + text encoder https://huggingface.co/LocalAI-io/Llama-3-Kimodo-GGML (Q4_K 4.4 GB / Q8 8.1 GB; Meta Llama 3 Community License, fine for outputs). Supports CPU and Vulkan (the UHD 620 shows up as a Vulkan 1.4 device). Unlimited and fully offline. **I didn't build it** (needs cmake + ninja via pip and about 6–9 GB of downloads). Expect seconds to a minute per clip on CPU (the profiling doc gives 1.25 s per Q8 text encode on Vulkan iGPU-class hardware). **(b)** Official Space https://huggingface.co/spaces/nvidia/Kimodo is RUNNING on a dedicated L40S (not ZeroGPU), but it's a Viser websocket UI, so only browser automation can drive it. | `kmd-generate` writes raw .f32 streams; `scripts/export_bvh.py` writes a **30-joint SOMA BVH** (Hips, Spine1, Spine2, Chest, Neck1, Neck2, Head, LeftShoulder, LeftArm, LeftForeArm, LeftHand, **LeftLeg = thigh**, **LeftShin**, LeftFoot, LeftToeBase …). The demo also writes a skeleton-only GLB. 30 fps. | Not tested. Trained on 700 h of professional game mocap (Bones Rigplay), so it should be stronger on combat, falls and get-ups than HumanML3D models. Whether it knows "zombie" as a style is unverified. Describe the body mechanics instead ("drags right foot, torso hunched forward, arms reaching"). |
| **Tencent HY-Motion 1.0** (Dec 2025, 1B params) — https://github.com/Tencent-Hunyuan/HY-Motion-1.0 (2.6k★), Space https://huggingface.co/spaces/tencent/HY-Motion-1.0 (RUNNING, zero-a10g) | **Tencent HY-Motion Community License**: "DOES NOT APPLY IN THE EUROPEAN UNION, UNITED KINGDOM AND SOUTH KOREA"; "You must not use, reproduce, modify, distribute, or display … Output … outside the Territory". A licence is needed above 1M MAU. | "Tencent claims no rights in Outputs", **but you may not use or display the output in the EU, UK or South Korea.** A game sold on Steam in the EU would breach this. HF also flags `extra_gated_eu_disallowed`. | **Verified anonymous gradio_client call:** `/generate_motion_func` returned an FBX in 14 s. Each call uses anonymous ZeroGPU quota (2 min/day per IP; 5 min with a free HF token; 25–40 min with PRO at $9/mo). | **FBX, 52-bone SMPL-H skeleton** (`Pelvis, L_Hip, L_Knee, L_Ankle, L_Foot, Spine1-3, Neck, Head, L_Collar, L_Shoulder, L_Elbow, L_Wrist`, fingers), 30 fps, with a wooden mannequin mesh. Verified in Blender. | **Good.** The Space ships a built-in example, "A person walks like a zombie, dragging their feet…", plus "collapses to the ground after being hit" and "stumbles, being hit". My test render shows a believable hunched, dragging shamble with a tilted head; the arms reached forward less than the prompt asked. |
| **MoMask** (CVPR'24) — https://github.com/EricGuo5513/momask-codes (MIT, last push 2024-09), Space https://huggingface.co/spaces/MeYourHint/MoMask (RUNNING on **cpu-basic, so no ZeroGPU quota**) | MIT code, but **trained on HumanML3D, which is derived from AMASS (non-commercial research license)**. Commercial use of the output is legally grey. | Grey | **Verified:** legacy `gradio_client==0.8.1`, `fn_index=3`, returns HTML with `file/./cached/<id>/sample_repeat0.bvh`; download from `https://meyourhint-momask.hf.space/file=./cached/<id>/sample_repeat0.bvh`. 5 s per clip, no quota. | **BVH, 22 joints** (Hips, LeftUpLeg, LeftLeg, LeftFoot, LeftToe, Spine, Spine1, Spine2, Neck, Head, LeftShoulder, LeftArm, LeftForeArm, LeftHand …), 20 fps, no fingers | Medium. HumanML3D has some "zombie" captions. Feet slide; there are no fingers. Good for **prototyping and timing only.** |
| MDM — https://github.com/GuyTevet/motion-diffusion-model (MIT, 2025-10) | MIT code, AMASS-trained (grey) | Grey | No working public Space (pcuenq/mdm is old) | SMPL joints (npy) | Older than MoMask |
| T2M-GPT — https://github.com/Mael-zys/T2M-GPT (Apache-2.0, 2024) | AMASS-trained (grey) | Grey | No live Space | npy | Older |
| MotionGPT — https://github.com/OpenMotionLab/MotionGPT (MIT) | AMASS-trained (grey) | Grey | Space shows **RUNTIME_ERROR** | npy | Older |
| Light-T2M, MotionLCM, etc. | Research, AMASS-trained | Grey | No Spaces found | — | — |

**Conclusion:** For legally clean, unlimited, offline generation, use **Kimodo SOMA through kimodo.cpp**. Use **HY-Motion only if the game will never be distributed in the EU, UK or South Korea** (the territory clause covers *displaying* outputs), or as a reference to hand-key against. The user's locale looks Scandinavian; Denmark, Sweden and Finland are EU, Norway is not, but Steam sells into the EU anyway. Use MoMask for quick, quota-free blocking only.

### 2b. Running Kimodo locally (from the README; not built in this research)
```bash
python3 -m venv ~/kimodo-venv && ~/kimodo-venv/bin/pip install cmake ninja huggingface_hub
export PATH=~/kimodo-venv/bin:$PATH
git clone --recursive https://github.com/localai-org/kimodo.cpp ~/src/kimodo.cpp && cd ~/src/kimodo.cpp
# sudo apt install libvulkan-dev glslc   # optional, for the Vulkan backend on the UHD 620; CPU works without it
scripts/download_gguf_weights.sh --output "$PWD" --model soma-rp-v1.1 --text-quantization q4_k_m   # about 5 GB, no login
cmake --preset release && cmake --build --preset release
echo "A zombie lurches forward, dragging its right foot, torso hunched, arms reaching out in front." > p.txt
# usage (src/generate.cpp): kmd-generate MOTION.gguf TEXT_BUNDLE PROMPT.txt FRAMES STEPS SEED OUTPUT_DIR
build/release/kmd-generate <soma-rp-v1.1.gguf> <text-bundle> p.txt 150 <steps> 1 out/zwalk1
python3 scripts/export_bvh.py --help     # .f32 streams -> 30-joint SOMA BVH
```
`kmd-generate --server MOTION TEXT` keeps the models loaded between prompts, and `--sequence` builds multi-prompt clips with transitions (for example idle → lunge → bite). Builds and paths need checking on the first run. **Name trap:** in SOMA, `LeftLeg` is the *thigh* and `LeftShin` the calf, which is the opposite of Mixamo's convention. Godot's BoneMap auto-guess will get this wrong, so map it by hand.

### 2c. HY-Motion call (verified)
```python
# pip install gradio_client  (2.x)
from gradio_client import Client
c = Client("tencent/HY-Motion-1.0", download_files="out/")
p = "A person walks like a zombie, dragging their right foot, arms reaching forward, head tilted."
html, fbx_files = c.predict(p, p, "0", 4.0, 5.0, api_name="/generate_motion_func")  # seeds "0" = 1 sample; "0,1,2,3" = 4 samples (4x quota)
```
`/_prompt_engineering` runs an LLM rewrite of the prompt; skip it to save quota. Set the duration between 0.5 and 12 s.

### 2d. Prompt list to generate (with either model)
Several shamble walks (dragging one leg, hunched, stiff-legged, sideways lurch); lurching run; belly crawl dragging with arms; lunge and grab with both hands; grab-and-bite at shoulder height; bite on the floor while crawling; hit reactions (struck on the head, chest, left or right shoulder, left or right leg); stagger back two steps; drop to one knee then rise; knocked backwards onto the back; fall forward onto the face; get up from the back or from the front; climb through a window, leg over the sill; scream with the head thrown back; banging fists on a door. Player clips: front push kick; downward knife stab to the head of a kneeling target; knife thrust forward. Generate 3–4 seeds each and keep the best one. Mirror left and right clips in Blender instead of generating both.

---

## 3. Video-to-motion

| Tool | License | Unattended here? | Notes |
|---|---|---|---|
| GVHMR — https://github.com/zju3dv/GVHMR (2.1k★, 2026-09) | **"educational, research and non-profit purposes only"**, so not usable | Space LittleFrog/GVHMR: gradio config fetch failed (stale) | Best monocular quality, but the license excludes it |
| WHAM — https://github.com/yohanshin/WHAM (MIT, last push 2024-04) | MIT code, but outputs **SMPL**. The SMPL body model is non-commercial; Meshcapade sells commercial licenses from €1,500/yr. | Needs CUDA; no Space | Grey |
| 4D-Humans / HMR 2.0 — https://github.com/shubham-goel/4D-Humans (MIT) | Same SMPL issue | Needs CUDA | Per-frame jitter |
| TRAM — https://github.com/yufu-wang/tram (MIT) | SMPL | Needs CUDA | — |
| FreeMoCap — https://github.com/freemocap/freemocap (AGPL-3.0 app; your output data is yours) | OK | Runs on CPU, but needs **real multi-webcam footage** of a human performer | The best *legal* route if someone will act |
| Rokoko Vision — https://www.rokoko.com/pricing | Free Starter tier, single-cam, FBX export | **Account + browser**, not unattended | Decent |
| DeepMotion Animate 3D | **Free tier is personal and non-commercial**, 60 s/month | Account | Not usable on the free tier |

**AI video to mocap:** Wan 2.2 (Apache-2.0) and LTX-Video (Apache-2.0) Spaces run on ZeroGPU too, so a single clip eats the whole anonymous quota. Generated video has inconsistent limbs and foot contacts, and the extracted motion would also need GVHMR (non-commercial) or a SMPL-based tool. **Realism vs effort is poor. Skip it.** Text-to-motion models (section 2) were trained on real mocap and give cleaner results directly.

---

## 4. Retargeting onto Rocketbox Bip01

The project already has `dev-tools/rocketbox_to_glb.py`, which bakes world-space rotations per bone in headless Blender, because the Rocketbox animation rest pose doesn't match the avatar's. Generalize it into a `retarget_to_bip01.py`.

### Recommended: headless Blender bake → animation-only GLB
1. **Convert to Blender:** BVH via `bpy.ops.import_anim.bvh(axis_forward='-Z', axis_up='Y', update_scene_fps=True)` (built into Blender 5.2, verified). FBX/GLB via `import_scene.fbx` or `import_scene.gltf`. Delete the source meshes.
2. Import one Rocketbox avatar FBX/GLB (the target Bip01 armature).
3. **Bone map** (source → Bip01):
   - SMPL-H (HY-Motion): Pelvis→`Bip01 Pelvis`, Spine1→`Bip01 Spine`, Spine2→`Bip01 Spine1`, Spine3→`Bip01 Spine2`, Neck, Head, L_Collar→`Bip01 L Clavicle`, L_Shoulder→`L UpperArm`, L_Elbow→`L Forearm`, L_Wrist→`L Hand`, L_Hip→`L Thigh`, L_Knee→`L Calf`, L_Ankle→`L Foot`, L_Foot→`L Toe0`, Index1-3→`L Finger1/11/12`, Middle→`Finger2x`, Ring→`Finger3x`, Pinky→`Finger4x`, Thumb→`Finger0x`.
   - HumanML3D BVH (MoMask): Hips, Spine, Spine1, Spine2, Neck, Head, LeftShoulder, LeftArm, LeftForeArm, LeftHand, LeftUpLeg, LeftLeg, LeftFoot, LeftToe.
   - SOMA30 (Kimodo): Hips, Spine1, Spine2, Chest, Neck1 (+Neck2 folded into Head), LeftShoulder, LeftArm, LeftForeArm, LeftHand, **LeftLeg→Thigh, LeftShin→Calf**, LeftFoot, LeftToeBase.
   - UAL2 (UE-style): pelvis, spine_01..03, neck_01, Head, clavicle_l, upperarm_l, lowerarm_l, hand_l, thigh_l, calf_l, foot_l, ball_l.
   - UAL1: DEF-hips, DEF-spine.001..003, DEF-neck, DEF-head, DEF-shoulder.L, DEF-upper_arm.L, DEF-forearm.L, DEF-hand.L, DEF-thigh.L, DEF-shin.L, DEF-foot.L, DEF-toe.L.
4. **Rest alignment:** pose the source in a reference frame matching the Rocketbox bind pose (A-pose). The simplest way is to compute, per mapped bone, `offset = src_rest_world⁻¹ · tgt_rest_world` once. Then for each frame: `tgt_world = src_world(frame) · offset`. Convert to the target's local pose and keyframe it, the same as the existing script's world-space follow.
5. **Root:** copy the pelvis translation scaled by `tgt_leg_length / src_leg_length`. For in-place loops, zero X/Z (keep Y bob) and drive locomotion from the CharacterBody. Store root motion separately if `AnimationMixer.root_motion_track` is used.
6. **Fingers:** keep the Rocketbox rest pose, or map them for SMPL-H. Face bones are untouched; drive the screaming jaw procedurally via `Bip01 MJaw`.
7. Clean up: apply a Butterworth or Euler filter on noisy sources (CMU, MoMask) and foot-plant IK if sliding is visible. Resample to 30 fps. Mirror L/R variants with `pose.copy` / `paste(flipped=True)`.
8. Export **an armature-only GLB** (Bip01 skeleton, no mesh, one action per clip) to `assets/anims/zombie_*.glb`. In Godot, import it as an *Animation Library* and attach it to every Rocketbox zombie's AnimationPlayer. Track paths match because every avatar shares Bip01 names.
9. Command: `blender -b --factory-startup -P dev-tools/retarget_to_bip01.py -- <src.bvh|fbx|glb> <rocketbox_avatar.fbx> <map: smplh|hml3d|soma30|ual1|ual2> <out.glb>`.

Free Blender add-ons, if a ready-made solver is preferred:
- Rokoko Studio Live for Blender (LGPL-3.0, has a retarget panel, no login needed for retargeting): https://github.com/Rokoko/rokoko-studio-live-blender
- Diffeomorphic "Retarget BVH": https://github.com/Diffeomorphic/retarget_bvh (license NOASSERTION; check it)

Auto-Rig Pro is paid. Calling either add-on headless works but is fiddly. A custom 150-line bake script is more predictable.

### Alternative: Godot import retarget
1. Rocketbox: Advanced Import → Skeleton3D → Retarget → `BoneMap` with `SkeletonProfileHumanoid`, mapped by hand once and saved as `.tres`.
2. Source GLB/FBX (Godot imports FBX natively via ufbx, so HY-Motion FBX can go straight in; BVH has to go through Blender first): create a BoneMap for each source family using the maps above.
3. Rest Fixer: Apply Node Transforms, Normalize Position Tracks, **Overwrite Axis**, Fix Silhouette; keep Rename Bones on. Import As: Animation Library.
4. Downside: every zombie's skeleton gets renamed to `%GeneralSkeleton` / profile names, the 3ds Max biped axis quirks need Overwrite Axis, and errors only show up at runtime. The Blender bake keeps native Bip01 tracks, which existing project code (`CharacterAnimator`) already expects.

---

## 5. AI for art assets

### 5a. Image/text-to-3D

| Model | License | Free access here | Notes |
|---|---|---|---|
| **TRELLIS.2** (4B, PBR GLB) — https://github.com/microsoft/TRELLIS.2 (12k★), Space https://huggingface.co/spaces/microsoft/TRELLIS.2 (RUNNING) | **MIT** code and weights (ungated) | Gradio API verified: `/start_session` → `/preprocess_image` → `/image_to_3d(image, seed, "512"/"1024"/"1536")` → `/extract_glb(decimation_target, texture_size)`. **Each call reserves 120 s of ZeroGPU, more than the anonymous quota left after any other use. In practice it needs a free HF token (5 min/day ≈ 2 runs) or HF PRO.** Local use needs a 24 GB NVIDIA GPU. | Best open quality. PBR, closed meshes, good for props and limb pieces |
| Hunyuan3D-2 / 2.1 / 2mini-Turbo — Spaces RUNNING (zero-a10g) | **Tencent Hunyuan Community License: EU/UK/South Korea excluded** (`extra_gated_eu_disallowed`) | ZeroGPU | Same territory problem as HY-Motion. Avoid. |
| Stable Fast 3D — https://huggingface.co/spaces/stabilityai/stable-fast-3d (RUNNING) | Stability AI Community License (free under $1M annual revenue); weights **gated** (HF login) | Space via ZeroGPU; **local CPU supported** (`SF3D_USE_CPU=1`) once the gated weights are accepted | Fast, UV-unwrapped, 1–2k textures; mediocre geometry |
| **TripoSR** — https://github.com/VAST-AI-Research/TripoSR | **MIT**, ungated | Space RUNTIME_ERROR; **runs locally on CPU** (torchmcubes CPU fallback) | Low detail and vertex colours, but **fully offline and unlimited**. Fine for gibs and debris. |
| Meshy / Tripo free tiers | Meshy free: reportedly CC BY 4.0 (attribution), sources conflict. Tripo free: reportedly **non-commercial**. | **Accounts needed** | Don't rely on them |

**Realistic quality for this game:**
- **Limbs and stumps:** AI meshes won't match Rocketbox skin, clothing or texel density. Instead, in headless Blender, take each Rocketbox avatar, duplicate it, bisect at the elbow, knee or neck along the bone (weights > 0.5 to that bone chain), fill the hole, and give the cap a separate "flesh/bone" material (a CC0 ambientCG meat or plastic texture tinted red, plus an inner bone cylinder). That produces matching severed arm, leg and head pieces plus the stump caps for the remaining body. This is how AA games do it.
- **Gibs:** about 6 procedural chunks (displaced icospheres, the earlier doc's idea). Optionally use TripoSR or TRELLIS.2 on FLUX renders of "chunk of raw meat with bone shard" for variety.
- **Guns:** AI guns come out soft and lumpy. Use Poly Haven CC0 (`service_pistol`, `bolt_action_rifle_7_62`) via the API the project already uses, plus OGA CC0 (https://opengameart.org/content/lightning-pump-action-rifle, rigged, with pump and trigger animations; https://opengameart.org/content/low-poly-fps-rifle-and-hands). Melee: Poly Haven `machete`, `crowbar_01`, `baseball_bat`, `hatchet`, `fish_knife` (knife finisher prop).
- **First-person arms:** cut a Rocketbox avatar down to its arms and clavicles (same Bip01 skeleton, MIT), so player clips (kick or stab sources retargeted the same way) and the gun hand IK share one pipeline.

### 5b. Textures and PBR
ambientCG (CC0, API at `https://ambientcg.com/api/v2/full_json`) and Poly Haven (CC0, `https://api.polyhaven.com`) are already scripted in `dev-tools/`. Use them for skin rot, blood-soaked fabric, concrete, wood and boards. StableMaterials (https://huggingface.co/gvecchio/StableMaterials, OpenRAIL) needs a GPU and has no working Space, so skip it. For zombie skin variants, recolour the Rocketbox diffuse maps in Python (Pillow): desaturate, add green/grey tint and multiply in CC0 grime or bruise masks. Or do it in a Godot shader with a "rot" mask and blood decals, which costs no extra textures.

### 5c. 2D images (decals, blood, icons)
- **FLUX.1-schnell** — https://huggingface.co/spaces/black-forest-labs/FLUX.1-schnell. **Apache-2.0**, so outputs are free for commercial use. Anonymous call verified: `/infer(prompt, seed, randomize_seed, w, h, steps=4)`, 9 s for 1024², costing a few seconds of ZeroGPU quota each. The image quality for a "severed forearm on white" prop was good (clean background, usable for image-to-3D or a reference).
- **Pollinations** (`https://image.pollinations.ai/prompt/...`, already used by `dev-tools/gen_photo_textures.py`). Still anonymous and free, but `/models` now lists only **`sana`** (NVIDIA Sana; HF metadata says Apache-2.0, worth verifying). The `model=flux` parameter in the existing script is probably ignored. No quota observed; good for bulk decals.
- For blood decals, generate on a white or black background, then threshold and alpha-key with Pillow, and pack into an atlas.

### 5d. Auto-rigging
UniRig (https://github.com/VAST-AI-Research/UniRig, MIT) needs CUDA (spconv) and its Space shows RUNTIME_ERROR. RigNet is GPL-3.0 and needs CUDA. Anything World, Tripo and Meshy rigging all need accounts. **Not needed:** every skinned character is Rocketbox (already rigged), and gore pieces are rigid bodies or child meshes of bones.

---

## 6. Accounts, GPU and quota flags
- **ZeroGPU quota** (https://huggingface.co/docs/hub/spaces-zerogpu): anonymous 2 min/day per IP, free account 5 min, PRO about 25–40 min. Failed calls can still consume quota. All the 3D Spaces and HY-Motion use it. **The best one-time investment is a free HF account plus a read token** (the user creates it; the agent reads `HF_TOKEN`), or HF PRO at $9/mo for bulk 3D work.
- Kimodo local, TripoSR local, MoMask Space (cpu-basic), Pollinations, Quaternius, Rocketbox, Poly Haven, ambientCG and OpenGameArt need **no account and no quota**.
- **Needs CUDA (can't run locally):** TRELLIS.2, Hunyuan3D, UniRig, GVHMR, WHAM, 4D-Humans, HY-Motion, Kimodo's Python version (kimodo.cpp avoids this).
- **License red flags:** Tencent HY-Motion and Hunyuan3D (EU/UK/South Korea exclusion); AMASS-trained text-to-motion (MoMask, MDM, T2M-GPT, MotionGPT: grey); SMPL-based video mocap (grey or paid); GVHMR, Bandai Namco, LAFAN1 and DeepMotion free tier (non-commercial); BONES-SEED (revocable, revenue-capped).
- Record every source in `assets/LICENSES.md`: the URL, license, download date and a copy of the license text (CMU FAQ quote, Anderson Rohr page, NVIDIA Open Model License).

## 7. Exact agent steps (this laptop)
```bash
# 0. Tool venv (keep it out of the project)
python3 -m venv ~/venv-assets && ~/venv-assets/bin/pip install gradio_client pillow huggingface_hub cmake ninja
python3 -m venv ~/venv-gradio3 && ~/venv-gradio3/bin/pip install "gradio_client==0.8.1"   # MoMask only

# 1. CC0 libraries
mkdir -p ~/asset-src/ual && cd ~/asset-src/ual
curl -LO https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip
curl -LO https://opengameart.org/sites/default/files/universal_animation_library_2standard.zip
unzip -o '*.zip'
python3 dev-tools/fetch_rocketbox.py         # existing: Rocketbox MIT anims (drunk/injured walks, crouch)

# 2. AI motion: Kimodo local (section 2b). HY-Motion only if the EU, UK and South Korea are excluded from distribution (section 2c).

# 3. Retarget everything to Bip01 (new script, section 4)
blender -b --factory-startup -P dev-tools/retarget_to_bip01.py -- src.bvh assets/rocketbox/Male_Adult_04.glb soma30 assets/anims/zombie_walk_drag.glb

# 4. Gore meshes from Rocketbox (new Blender script: bisect + cap per limb)
# 5. Props: dev-tools/fetch_polyhaven_models.py service_pistol bolt_action_rifle_7_62 machete crowbar_01 fish_knife
# 6. Decals: FLUX.1-schnell Space (gradio_client) or Pollinations, then Pillow alpha-key and atlas
```

## Sources
- Quaternius UAL2: https://quaternius.com/packs/universalanimationlibrary2.html · https://opengameart.org/content/universal-animation-library-2 · UAL1: https://opengameart.org/content/universal-animation-library
- Rocketbox: https://github.com/microsoft/Microsoft-Rocketbox · MoveBox: https://github.com/microsoft/MoveBox-for-Microsoft-Rocketbox
- CMU: http://mocap.cs.cmu.edu · RancidMilk CMU retarget: https://rancidmilk.itch.io/free-character-animations
- Bandai Namco: https://github.com/BandaiNamcoResearchInc/Bandai-Namco-Research-Motiondataset · LAFAN1: https://github.com/ubisoft/ubisoft-laforge-animation-dataset · BONES-SEED license: https://bones.studio/info/seed-license
- Anderson Rohr: https://80.lv/articles/get-ready-for-halloween-with-these-19-free-mocap-animations · Rokoko: https://www.rokoko.com/pricing · ActorCore: https://actorcore.reallusion.com/motion/free · Fab license: https://www.fab.com/cla
- Kimodo: https://github.com/nv-tlabs/kimodo · https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.2 · kimodo.cpp: https://github.com/localai-org/kimodo.cpp · NVIDIA Open Model License: https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/
- HY-Motion: https://github.com/Tencent-Hunyuan/HY-Motion-1.0 · https://huggingface.co/tencent/HY-Motion-1.0/blob/main/LICENSE.txt · Space: https://huggingface.co/spaces/tencent/HY-Motion-1.0
- MoMask: https://github.com/EricGuo5513/momask-codes · https://huggingface.co/spaces/MeYourHint/MoMask · MDM: https://github.com/GuyTevet/motion-diffusion-model · T2M-GPT: https://github.com/Mael-zys/T2M-GPT · MotionGPT: https://github.com/OpenMotionLab/MotionGPT
- GVHMR: https://github.com/zju3dv/GVHMR · WHAM: https://github.com/yohanshin/WHAM · 4D-Humans: https://github.com/shubham-goel/4D-Humans · FreeMoCap: https://github.com/freemocap/freemocap · SMPL licensing: https://meshcapade.com/assets/body-models · DeepMotion FAQ: https://www.deepmotion.com/faq
- ZeroGPU quotas: https://huggingface.co/docs/hub/spaces-zerogpu
- TRELLIS.2: https://github.com/microsoft/TRELLIS.2 · https://huggingface.co/spaces/microsoft/TRELLIS.2 · Hunyuan3D-2.1: https://huggingface.co/tencent/Hunyuan3D-2.1 · SF3D: https://github.com/Stability-AI/stable-fast-3d · TripoSR: https://github.com/VAST-AI-Research/TripoSR · UniRig: https://github.com/VAST-AI-Research/UniRig
- FLUX.1-schnell: https://huggingface.co/spaces/black-forest-labs/FLUX.1-schnell · Pollinations: https://image.pollinations.ai/models · Sana: https://huggingface.co/Efficient-Large-Model/Sana_1600M_1024px
- Poly Haven API: https://api.polyhaven.com/assets?t=models · ambientCG: https://ambientcg.com · OGA guns: https://opengameart.org/content/lightning-pump-action-rifle , https://opengameart.org/content/low-poly-fps-rifle-and-hands
- Godot retargeting: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html · Rokoko Blender add-on: https://github.com/Rokoko/rokoko-studio-live-blender
