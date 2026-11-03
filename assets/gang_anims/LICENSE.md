# Ghetto Wars animation clips (assets/gang_anims/)

`gang_clips.res` is an AnimationLibrary of clips baked onto the Microsoft Rocketbox Bip01 skeleton (MIT, see
assets/rocketbox/LICENSE.md) by `GANG=1 python3 -I dev-tools/retarget_to_bip01.py` (the same bake as the zombies'),
packed by `dev-tools/build_gang_library.gd`, which also builds the "ga_*" composites: the legs and pelvis of a gait
with the torso, head and arms of the pistol aim pose, so every gun is carried at the shoulder.

## Sources

- **Universal Animation Library** (UAL1) by Quaternius, CC0 1.0 (public domain).
  https://opengameart.org/content/universal-animation-library
  Used: Pistol_Aim_Neutral, Pistol_Aim_Up, Pistol_Aim_Down, Pistol_Idle_Loop, Pistol_Shoot, Pistol_Reload,
  Crouch_Idle_Loop, Crouch_Fwd_Loop, Walk_Loop, Jog_Fwd_Loop, Sprint_Loop, Idle_Loop, Roll, Hit_Chest, Hit_Head, Death01.
- **Universal Animation Library 2** (UAL2) by Quaternius, CC0 1.0 (public domain).
  https://opengameart.org/content/universal-animation-library-2
  Used: OverhandThrow, Hit_Knockback.
- No credit is required; it is given anyway (assets/LICENSES.md, the title screen's credits).
