# Zombie animation clips (assets/zombie_anims/)

`zombie_clips.res` is an AnimationLibrary of clips baked onto the Microsoft
Rocketbox Bip01 skeleton (MIT, see assets/rocketbox/LICENSE.md). It is built
by `dev-tools/fetch_zombie_anims.py` + `dev-tools/retarget_to_bip01.py`.

## Sources

- **Universal Animation Library** (UAL1) by Quaternius, CC0 1.0 (public domain).
  https://opengameart.org/content/universal-animation-library
  Used: Hit_Head, Hit_Chest, Death01, Walk_Loop, Sprint_Loop.
- **Universal Animation Library 2** (UAL2) by Quaternius, CC0 1.0 (public domain).
  https://opengameart.org/content/universal-animation-library-2
  Used: Zombie_Idle_Loop, Zombie_Walk_Fwd_Loop, Zombie_Scratch, LayToIdle,
  ClimbUp_1m_RM, Hit_Knockback, Sword_Regular_A.
- Downloaded 2026-10-26. No credit is required; it is given anyway
  (assets/LICENSES.md, the title screen's credits).

- **NVIDIA Kimodo** (SOMA-RP v1.1, text-to-motion), run locally through
  **kimodo.cpp** by the LocalAI team. Downloaded and generated 2026-10-26.
  - Model: https://github.com/nv-tlabs/kimodo (code Apache-2.0). Weights used:
    the SOMA-RP v1.1 checkpoint, **NVIDIA Open Model License**
    (https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/):
    commercial use allowed, NVIDIA claims no ownership of outputs. The motion
    data it was trained on is licensed Bones Rigplay mocap (no AMASS/SMPL).
    The SMPL-X-RP checkpoint is research-only and is NOT used.
  - Runtime: https://github.com/localai-org/kimodo.cpp (Apache-2.0), pinned
    commit ed8a931, CPU build, with GGML (MIT, https://github.com/ggml-org/ggml).
    GGUF conversions of the weights: https://huggingface.co/LocalAI-io/Kimodo-SOMA-RP-v1.1-GGML
  - Text encoder: https://huggingface.co/LocalAI-io/Llama-3-Kimodo-GGML (Q4_K_M), an
    LLM2Vec conversion of Meta Llama 3 8B Instruct under the **Meta Llama 3
    Community License** (https://www.llama.com/llama3/license/). Built with
    Meta Llama 3. It only turns our prompts into embeddings on the developer's
    machine; no Llama weights ship in the game. Generated motion is ours.
  Used: z_attack, z_attack2, z_attack3, z_crawl, z_scream, p_kick, z_walk3, z_hit_leg, z_death2, and (Z5, 2026-11-02) z_rise, z_land, z_hit_leg_l, z_hit_arm_l, z_hit_arm_r, z_stumble, z_walk4, z_limp_l, z_walk_hurt_l, z_walk_hurt_r, z_lunge, z_bite, z_smash (see "Kimodo clips" below).

## Modified for the game

Retargeted from the UE/Rigify skeletons onto Bip01 (world-space rotation
follow with a rest-pose alignment), resampled to 30 fps, pelvis height scaled
to the avatar's legs, loop drift removed. `z_walk2` and `z_run` are gaits
leaned forward with a head tilt added on top (derived, not captured).
The nine Kimodo clips (table below) are baked the same way (SOMA30 bone map; LeftLeg =
thigh). Added on top, in `dev-tools/retarget_to_bip01.py`: relaxed-claw fingers (SOMA has
none); the take's forward travel cut (30-60 %); for the three attacks a hunched-torso and
head-thrust layer (`ZL_A/B/C`), and for `z_attack2` hand-keyed swiping/reaching arms on
the take's legs; loops (`z_crawl`, `z_walk3`) are eased back into their first pose and
kept in place; `p_kick` is eased back to its guard at the end; `z_walk3` is slowed to
4.2 s. The older hand-posed attacks (our own keyframes on the legs of Zombie_Idle_Loop)
stay in the script as fallbacks (`HAND_ATTACKS=1`, or when no take is picked).

## Kimodo clips

Prompts describe body mechanics (Kimodo has no real grip on "zombie"); 10 DDIM
steps, 30 fps, Q4_K_M text encoder. The prompt text, every variant tried and the
reason it was dropped are in `dev-tools/fetch_zombie_anims.py` (KIMODO_CLIPS). Per-clip take (also in the
clip's `source` metadata): see the table.

| Clip | Take | Seed | Generation time | Prompt |
|---|---|---|---|---|
| z_attack | z_attack_h_s1 | 1 | 39 s | A person lunges one step forward, both arms stretched out in front at chest level, hands clawing and grabbing at the air, then pulls both arms back to the chest and bends forward. |
| z_attack2 | z_attack2_h_s1 | 1 | 39 s | A person lunges one step forward and swipes one arm across the body at chest level, clawing at the air from low to high, then grabs forward with both hands. |
| z_attack3 | z_attack3_h_s2 | 2 | 38 s | A person lunges one step forward with both arms spread wide, then wraps both arms around someone in front, hugging and pulling them in tight. |
| z_crawl | z_crawl_c_s1 | 1 | 60 s | A soldier does a low crawl forward on the ground, forearms and elbows pulling the body along, one arm reaching forward and then the other, legs dragging behind. |
| z_scream | z_scream_c_s3 | 3 | 39 s | A person roars, tilting the head back with the chest pushed out and arms hanging straight down, then snaps the head forward. |
| p_kick | p_kick_d_s3 | 3 | 29 s | A person lifts the right knee up and thrusts the foot out in a straight kick. |
| z_walk3 | z_walk3_a_s1 | 1 | 44 s | A person shambles forward, dragging the right foot, torso hunched forward, arms hanging and swaying, head tilted. |
| z_hit_leg | z_hit_leg_a_s3 | 3 | 40 s | A person is struck in the right thigh, the leg buckles and they stumble and drop down onto one knee. |
| z_death2 | z_death2_a_s2 | 2 | 36 s | A person falls forward onto their face and lies still on the ground. |

Z5 clips (bodies that move like bodies), baked the same way (`dev-tools/retarget_to_bip01.py <clip> ...`
merges just those clips into the library; prompts and every variant tried are in
`dev-tools/fetch_zombie_anims.py` KIMODO_CLIPS; 2 seeds each, the take chosen by eye). `z_walk4` is slowed to
5 s, `z_lunge` stays in place (the zombie supplies the ground covered).

| Clip | Take | Seed | Generation time | Prompt |
|---|---|---|---|---|
| z_rise | z_rise_b_s1 | 1 | 119 s | A person lying on their stomach pushes both hands against the ground, heaves the chest up, pulls one knee under the body, then the other, and stands up slowly, hunched, arms hanging. |
| z_land | z_land_b_s1 | 1 | 71 s | A person lands from a jump in a low crouch, knees bent deep, torso bent forward, then rises and staggers a step forward. |
| z_hit_leg_l | z_hit_leg_l_a_s1 | 1 | 59 s | A person is struck in the left thigh, the leg buckles and they stumble and drop down onto one knee. |
| z_hit_arm_l | z_hit_arm_l_a_s1 | 1 | 70 s | A person is struck in the left shoulder, the upper body spins to the left with the left arm thrown back, then they steady themselves. |
| z_hit_arm_r | z_hit_arm_r_a_s2 | 2 | 56 s | A person is struck in the right shoulder, the upper body spins to the right with the right arm thrown back, then they steady themselves. |
| z_stumble | z_stumble_a_s1 | 1 | 82 s | A person is shoved hard in the chest, staggers backwards several steps with the arms flailing, nearly falls and catches their balance. |
| z_walk4 | z_walk4_a_s1 | 1 | 98 s | A person lurches forward unevenly, slow then sudden quicker steps, swaying from side to side, the head lolling, the arms swinging loosely. |
| z_limp_l | z_limp_l_a_s2 | 2 | 129 s | A person shambles forward, dragging the left foot, torso hunched forward, arms hanging and swaying, head tilted. |
| z_walk_hurt_l | z_walk_hurt_l_a_s2 | 2 | 132 s | A person walks slowly leaning heavily to the left, the left arm hanging limp and motionless, the right arm swinging, head tilted to the left. |
| z_walk_hurt_r | z_walk_hurt_r_a_s2 | 2 | 114 s | A person walks slowly leaning heavily to the right, the right arm hanging limp and motionless, the left arm swinging, head tilted to the right. |
| z_lunge | z_lunge_a_s1 | 1 | 106 s | A hunched person suddenly breaks into a fast lunging stride forward, both arms thrown out in front, hands clawing. |
| z_bite | z_bite_a_s2 | 2 | 114 s | A person grabs someone in front by the shoulders with both hands, pulls them in close and jerks the head forward to bite, then shakes the head from side to side. |
| z_smash | z_smash_a_s1 | 1 | 89 s | A person raises both fists together high above the head and slams them down hard in front of the body, bending forward. |

HY-Motion/Hunyuan (EU territory exclusion), Mixamo and non-commercial
datasets are not used.
