"""Bakes animation clips from other skeletons onto the Rocketbox Bip01 rig and
packs them into res://assets/zombie_anims/zombie_clips.res (an AnimationLibrary
every zombie's AnimationPlayer can take).

  python3 -I dev-tools/retarget_to_bip01.py            # whole pipeline
  blender -b --factory-startup -P dev-tools/retarget_to_bip01.py -- <out.glb> <meta.json> [clip ...]

Run from the project root. The plain-python form drives the other two steps:
  1. Blender (this file, below the `bpy` import): reads the Quaternius UAL1/UAL2
     GLBs that dev-tools/fetch_zombie_anims.py unpacked into ~/.cache/dopesick/,
     follows each source bone's *world-space* rotation with the matching Bip01
     bone (the same idea as rocketbox_to_glb.py, but between different
     skeletons), and exports an armature-only GLB plus a metadata JSON.
  2. Godot (dev-tools/build_zombie_library.gd): turns that GLB into the
     AnimationLibrary .res and applies the importer's root scale.
Kimodo (SOMA30) BVH clips go through the same bake: load_source("soma30", bvh) imports
the take with Blender's BVH importer (centimetres -> metres, +Z forward) and SOMA30 below
is the bone map (LeftLeg = thigh, LeftShin = calf; Spine1/Spine2/Chest take the three
Bip01 spine bones). SOMA30 has no fingers, so `claw` curls the Rocketbox ones. The takes
come from dev-tools/fetch_zombie_anims.py --kimodo; z_attack/2/3 use the one picked into
~/.cache/dopesick/kimodo/best/ and fall back to the hand-posed GRAB_* keys when there is
none (or HAND_ATTACKS=1 is set). Raw takes can be baked for a look with
`-- out.glb meta.json take:<take name>` (names as in ~/.cache/dopesick/kimodo/takes/).

How the bake works, per mapped bone (source S -> Bip01 T):
  D(f)    = R_S(f) * R_S_rest^-1           what S did to its own rest pose, in world space
  Q       = shortest arc taking T's rest direction onto S's, so T starts from the
            same T-pose as S (Rocketbox rests in an A-pose, Quaternius in a T-pose)
  R_T(f)  = D(f) * Q * R_T_rest            world rotation T must have
then every bone's local rotation is solved from its parent's. The pelvis
follows the source pelvis, scaled by the leg-length ratio (height above the
floor) with the horizontal drift of loops taken out (CharacterAnimator also
does that at load, and needs the pace: written to `travel`).
"""
import json
import math
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache", "dopesick")
UAL1_GLB = os.path.join(CACHE, "ual1", "Animation Library[Standard]", "Godot", "AnimationLibrary_Godot_Standard.glb")
UAL2_GLB = os.path.join(CACHE, "ual2", "Universal Animation Library 2 [Standard]", "Unreal-Godot", "UAL2_Standard.glb")
AVATAR_FBX = os.path.join(HOME, ".cache", "rocketbox", "Male_Adult_04", "Male_Adult_04.fbx")
WORK = os.path.join(CACHE, "retarget")
KIMODO_TAKES = os.path.join(CACHE, "kimodo", "takes")
KIMODO_BEST = os.path.join(CACHE, "kimodo", "best")   # the chosen takes: <clip>.bvh + <clip>.json (prompt, seed)
OUT_RES = "res://assets/zombie_anims/zombie_clips.res"

# ---------------------------------------------------------------------------
# Bone maps: source bone -> Bip01 bone(s). `{s}` is the side suffix.
# ---------------------------------------------------------------------------
FINGERS = {  # Rocketbox finger -> the three joints, thumb first
    "Finger0": ["Finger0", "Finger01", "Finger02"],
    "Finger1": ["Finger1", "Finger11", "Finger12"],
    "Finger2": ["Finger2", "Finger21", "Finger22"],
    "Finger3": ["Finger3", "Finger31", "Finger32"],
    "Finger4": ["Finger4", "Finger41", "Finger42"],
}

def _side_map(names, sides):
    """names: dict of role -> source name template; returns {source: [bip01 bones]}."""
    m = {}
    for s_src, s_bip, key in sides:
        def put(role, bip):
            if role in names:
                m.setdefault(names[role].format(s=s_src), []).append("Bip01 %s %s" % (s_bip, bip))
        put("clavicle", "Clavicle")
        put("upperarm", "UpperArm")
        put("lowerarm", "Forearm")
        put("hand", "Hand")
        put("thigh", "Thigh")
        put("calf", "Calf")
        put("foot", "Foot")
        put("toe", "Toe0")
        for finger, joints in FINGERS.items():
            for i, j in enumerate(joints):
                role = "%s_%d" % (finger, i + 1)
                if role in names:
                    m.setdefault(names[role].format(s=s_src), []).append("Bip01 %s %s" % (s_bip, j))
    return m

UAL2_NAMES = {
    "clavicle": "clavicle{s}", "upperarm": "upperarm{s}", "lowerarm": "lowerarm{s}", "hand": "hand{s}",
    "thigh": "thigh{s}", "calf": "calf{s}", "foot": "foot{s}", "toe": "ball{s}",
}
for _f, _n in (("Finger0", "thumb"), ("Finger1", "index"), ("Finger2", "middle"), ("Finger3", "ring"), ("Finger4", "pinky")):
    for _i in (1, 2, 3):
        UAL2_NAMES["%s_%d" % (_f, _i)] = "%s_0%d{s}" % (_n, _i)
UAL2 = {"pelvis": ["Bip01 Pelvis", "Bip01 Spine"], "spine_02": ["Bip01 Spine1"], "spine_03": ["Bip01 Spine2"],
        "neck_01": ["Bip01 Neck"], "Head": ["Bip01 Head"]}
UAL2.update(_side_map(UAL2_NAMES, [("_l", "L", "l"), ("_r", "R", "r")]))

UAL1_NAMES = {
    "clavicle": "DEF-shoulder{s}", "upperarm": "DEF-upper_arm{s}", "lowerarm": "DEF-forearm{s}", "hand": "DEF-hand{s}",
    "thigh": "DEF-thigh{s}", "calf": "DEF-shin{s}", "foot": "DEF-foot{s}", "toe": "DEF-toe{s}",
}
for _f, _n in (("Finger1", "f_index"), ("Finger2", "f_middle"), ("Finger3", "f_ring"), ("Finger4", "f_pinky")):
    for _i in (1, 2, 3):
        UAL1_NAMES["%s_%d" % (_f, _i)] = "DEF-%s.0%d{s}" % (_n, _i)
for _i in (1, 2, 3):
    UAL1_NAMES["Finger0_%d" % _i] = "DEF-thumb.0%d{s}" % _i
UAL1 = {"DEF-hips": ["Bip01 Pelvis", "Bip01 Spine"], "DEF-spine.002": ["Bip01 Spine1"], "DEF-spine.003": ["Bip01 Spine2"],
        "DEF-neck": ["Bip01 Neck"], "DEF-head": ["Bip01 Head"]}
UAL1.update(_side_map(UAL1_NAMES, [(".L", "L", "l"), (".R", "R", "r")]))

# SOMA30 (Kimodo BVH): the naming trap -- LeftLeg is the THIGH, LeftShin the calf.
SOMA_NAMES = {
    "clavicle": "{s}Shoulder", "upperarm": "{s}Arm", "lowerarm": "{s}ForeArm", "hand": "{s}Hand",
    "thigh": "{s}Leg", "calf": "{s}Shin", "foot": "{s}Foot", "toe": "{s}ToeBase",
}
SOMA30 = {"Hips": ["Bip01 Pelvis"], "Spine1": ["Bip01 Spine"], "Spine2": ["Bip01 Spine1"], "Chest": ["Bip01 Spine2"],
          "Neck1": ["Bip01 Neck"], "Head": ["Bip01 Head"]}
SOMA30.update(_side_map(SOMA_NAMES, [("Left", "L", "l"), ("Right", "R", "r")]))

MAPS = {"ual1": UAL1, "ual2": UAL2, "soma30": SOMA30}

# The child each source bone points at, for the rest-pose alignment.
def dir_child(skel, bone):
    """Source bone whose head defines this bone's direction, or None (leaf: inherit the parent's)."""
    if skel == "ual2":
        t = {"pelvis": "thigh_l", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "Head"}
        for s in ("l", "r"):
            t.update({"clavicle_%s" % s: "upperarm_%s" % s, "upperarm_%s" % s: "lowerarm_%s" % s,
                      "lowerarm_%s" % s: "hand_%s" % s, "hand_%s" % s: "middle_01_%s" % s,
                      "thigh_%s" % s: "calf_%s" % s, "calf_%s" % s: "foot_%s" % s, "foot_%s" % s: "ball_%s" % s})
            for n in ("thumb", "index", "middle", "ring", "pinky"):
                t["%s_01_%s" % (n, s)] = "%s_02_%s" % (n, s)
                t["%s_02_%s" % (n, s)] = "%s_03_%s" % (n, s)
        return t.get(bone)
    if skel == "ual1":
        t = {"DEF-hips": "DEF-thigh.L", "DEF-spine.002": "DEF-spine.003", "DEF-spine.003": "DEF-neck", "DEF-neck": "DEF-head"}
        for s in ("L", "R"):
            t.update({"DEF-shoulder.%s" % s: "DEF-upper_arm.%s" % s, "DEF-upper_arm.%s" % s: "DEF-forearm.%s" % s,
                      "DEF-forearm.%s" % s: "DEF-hand.%s" % s, "DEF-hand.%s" % s: "DEF-f_middle.01.%s" % s,
                      "DEF-thigh.%s" % s: "DEF-shin.%s" % s, "DEF-shin.%s" % s: "DEF-foot.%s" % s, "DEF-foot.%s" % s: "DEF-toe.%s" % s})
            for n in ("thumb", "f_index", "f_middle", "f_ring", "f_pinky"):
                t["DEF-%s.01.%s" % (n, s)] = "DEF-%s.02.%s" % (n, s)
                t["DEF-%s.02.%s" % (n, s)] = "DEF-%s.03.%s" % (n, s)
        return t.get(bone)
    if skel == "soma30":
        t = {"Hips": "LeftLeg", "Spine1": "Spine2", "Spine2": "Chest", "Chest": "Neck1", "Neck1": "Head"}
        for s in ("Left", "Right"):
            t.update({"%sShoulder" % s: "%sArm" % s, "%sArm" % s: "%sForeArm" % s, "%sForeArm" % s: "%sHand" % s,
                      "%sLeg" % s: "%sShin" % s, "%sShin" % s: "%sFoot" % s, "%sFoot" % s: "%sToeBase" % s})
        return t.get(bone)
    return None

# ---------------------------------------------------------------------------
# Clips: out name -> (skeleton, source action, options)
#   loop    : looping clip, last sample dropped if it repeats the first, drift removed
#   hunch   : "zombify" -- lean the torso, tilt the head (a derived clip, not a captured one)
#   keep_root: leave the source's travel in the pelvis (climbs)
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Hand-posed attacks ("grab" option): the legs and the idle sway of
# Zombie_Idle_Loop, with the torso, head and arms driven by keyframed poses
# (no library has a zombie grab; the boxing clips read as a fight). Per key:
#   spine : pitch in degrees of Spine, Spine1, Spine2 (forward lean, cumulative)
#   neck, head : extra pitch; roll : head tilt; yaw : head turn
#   L, R  : (w, upper-arm dir, forearm dir, twist) -- w blends from the clip's own
#           arm (0) to the aimed one (1); dirs are (forward, outward, up) in the
#           avatar's frame (not normalised); twist spins the hand about the forearm.
# Poses are keyed by clip fraction and eased between keys.
# ---------------------------------------------------------------------------
def _key(t, spine=(0, 0, 0), neck=0.0, head=0.0, roll=0.0, yaw=0.0, L=None, R=None, both=None):
    rest = (0.0, (0, 0, -1), (0, 0, -1), 0.0)
    if both is not None:
        L = R = both
    return (t, list(spine) + [neck, head, roll, yaw] + _flat(L or rest) + _flat(R or rest))

def _flat(a):
    return [a[0]] + list(a[1]) + list(a[2]) + [a[3]]

def grab_params(keys, t):
    """Flat parameter vector for clip fraction t (smoothstep between the keys)."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-6)
            u = u * u * (3.0 - 2.0 * u)
            return [a + (b - a) * u for a, b in zip(v0, v1)]
    return keys[-1][1]



def _arms(w, u, f, tw=0.0):
    return (w, u, f, tw)

# z_attack: both arms reach out at shoulder height, hands open, the body lurches
# in, the hands rake back to the chest and the head snaps forward to bite.
REACH = _arms(1.0, (0.98, 0.14, 0.05), (0.99, 0.10, 0.04), 0.0)
CLAW = _arms(1.0, (0.10, 0.35, -0.9), (0.95, 0.0, 0.25), 0.0)
GRAB_A = [
    _key(0.00),
    _key(0.14, spine=(-3, -8, -12), head=-4, both=_arms(0.7, (0.35, 0.55, -0.2), (0.9, 0.2, 0.35))),
    _key(0.32, spine=(0, 3, 5), head=-22, both=REACH),
    _key(0.46, spine=(1, 5, 8), head=-24, both=REACH),
    _key(0.64, spine=(0, 2, 4), head=-14, both=CLAW),
    _key(0.78, spine=(2, 6, 10), neck=22, head=-12, both=CLAW),
    _key(0.86, spine=(3, 8, 12), neck=26, head=-8, both=CLAW),
    _key(1.00),
]


# z_attack2: a raking claw swipe, one arm high and across, the other reaching, then the bite.
SWIPE_UP = _arms(1.0, (0.25, 0.55, 0.8), (0.15, 0.35, 0.95), 0.0)
SWIPE_END = _arms(1.0, (0.85, -0.45, -0.3), (0.8, -0.6, -0.35), 0.0)
GRAB_B = [
    _key(0.00),
    _key(0.18, spine=(-3, -8, -12), head=-6, L=_arms(0.8, (0.6, 0.4, 0.0), (0.95, 0.1, 0.1)), R=SWIPE_UP),
    _key(0.38, spine=(1, 5, 8), head=-22, L=REACH, R=SWIPE_END),
    _key(0.55, spine=(2, 6, 9), head=-24, L=REACH, R=SWIPE_END),
    _key(0.74, spine=(2, 7, 11), neck=22, head=-10, both=CLAW),
    _key(0.84, spine=(3, 8, 12), neck=26, head=-6, both=CLAW),
    _key(1.00),
]

# z_attack3: arms flung wide, then swept in around the victim, then the bite.
WIDE = _arms(1.0, (0.45, 0.9, 0.15), (0.75, 0.7, 0.15), 0.0)
HUG = _arms(1.0, (0.7, -0.15, -0.1), (0.35, -0.9, 0.0), 0.0)
GRAB_C = [
    _key(0.00),
    _key(0.20, spine=(-3, -8, -12), head=-6, both=WIDE),
    _key(0.40, spine=(1, 5, 8), head=-22, both=WIDE),
    _key(0.58, spine=(2, 6, 10), head=-24, both=HUG),
    _key(0.76, spine=(2, 7, 11), neck=26, head=-10, both=HUG),
    _key(0.86, spine=(3, 8, 12), neck=30, head=-6, both=HUG),
    _key(1.00),
]

# ---------------------------------------------------------------------------
# The zombie layer on the Kimodo attacks: the take's legs and weight shift are kept,
# the torso is hunched forward on top (Spine, Spine1, Spine2 pitch, cumulative), the head
# tilts and then thrusts forward at the bite (neck forward-down, head back up a little so
# the face stays on the target). Same keys as GRAB_* above; arms with w=0 keep the take's.
# ---------------------------------------------------------------------------
ZL_A = [   # z_attack: both arms are the take's (it reaches out at chest height and pulls in)
    _key(0.00),
    _key(0.15, spine=(2, 4, 5), head=-3, roll=4),
    _key(0.40, spine=(3, 6, 8), head=-9, roll=6),
    _key(0.62, spine=(3, 7, 9), neck=8, head=-5, roll=7),
    _key(0.80, spine=(4, 9, 12), neck=28, head=-9, roll=5),
    _key(0.92, spine=(3, 7, 9), neck=20, head=-5, roll=4),
    _key(1.00),
]
ZL_C = [   # z_attack3: the hug; the bite comes after the arms close
    _key(0.00),
    _key(0.20, spine=(2, 4, 5), head=-3, roll=4),
    _key(0.45, spine=(3, 6, 8), head=-9, roll=6),
    _key(0.68, spine=(3, 7, 10), neck=8, head=-5, roll=7),
    _key(0.84, spine=(4, 9, 12), neck=28, head=-9, roll=5),
    _key(0.94, spine=(3, 7, 9), neck=20, head=-5, roll=4),
    _key(1.00),
]
# z_attack2: Kimodo legs, hand-keyed arms. The right arm rakes: out to the side and low, then
# across the body at belly-to-chest height (hook fingers), then both arms reach and grab, then the bite.
RAKE_WIND = _arms(1.0, (0.20, 0.80, -0.75), (0.40, 0.85, -0.50), 0.0)
RAKE_MID = _arms(1.0, (0.70, -0.10, -0.65), (0.80, -0.55, -0.30), 0.0)
RAKE_END = _arms(1.0, (0.55, -0.60, -0.30), (0.45, -0.85, 0.05), 0.0)
REACH_B = _arms(1.0, (0.98, 0.14, 0.02), (0.99, 0.10, 0.02), 0.0)
PULL_B = _arms(1.0, (0.55, 0.20, -0.55), (0.85, 0.05, 0.30), 0.0)
ZL_B = [
    _key(0.00),
    _key(0.14, spine=(1, 2, 3), head=-3, roll=4, R=RAKE_WIND, L=_arms(0.5, (0.45, 0.35, -0.55), (0.7, 0.2, -0.3))),
    _key(0.30, spine=(3, 6, 8), head=-8, roll=6, R=RAKE_MID, L=_arms(0.7, (0.5, 0.30, -0.40), (0.8, 0.2, -0.2))),
    _key(0.44, spine=(4, 8, 10), head=-9, roll=7, R=RAKE_END, L=_arms(0.8, (0.6, 0.30, -0.30), (0.9, 0.15, -0.1))),
    _key(0.62, spine=(3, 7, 9), neck=6, head=-5, roll=7, both=REACH_B),
    _key(0.74, spine=(3, 7, 10), neck=10, head=-5, roll=6, both=REACH_B),
    _key(0.84, spine=(4, 9, 12), neck=28, head=-9, roll=5, both=PULL_B),
    _key(0.93, spine=(3, 7, 9), neck=20, head=-5, roll=4, both=PULL_B),
    _key(1.00),
]
# z_scream: Kimodo's arms (spread, tensed) and legs; the roar is keyed on top: a breath in (chest
# out, head back), the head thrown back as the jaw opens, then thrust forward and down with the
# mouth wide, then back to rest. The jaw keys are ZL_S_JAW (clip fractions, degrees).
ZL_S = [
    _key(0.00),
    _key(0.16, spine=(-2, -3, -4), neck=-8, head=-6),
    _key(0.30, spine=(-3, -6, -8), neck=-26, head=-20, roll=3),
    _key(0.48, spine=(-3, -6, -8), neck=-30, head=-22, roll=-3),
    _key(0.62, spine=(2, 6, 7), neck=22, head=-4, roll=0),
    _key(0.76, spine=(3, 8, 10), neck=26, head=-6, roll=2),
    _key(0.90, spine=(1, 3, 4), neck=8, head=-2),
    _key(1.00),
]
ZL_S_JAW = [(0.0, 0.0), (0.18, 4.0), (0.30, 28.0), (0.48, 34.0), (0.62, 40.0), (0.76, 34.0), (0.88, 8.0), (1.0, 0.0)]
GRAB_TABLES = {"ZL_A": ZL_A, "ZL_B": ZL_B, "ZL_C": ZL_C, "ZL_S": ZL_S}

HUNCH_WALK = {"spine1": 10.0, "spine2": 12.0, "head_pitch": 14.0, "head_roll": 12.0}
HUNCH_RUN = {"spine1": 14.0, "spine2": 14.0, "head_pitch": 10.0, "head_roll": 10.0}
CLIPS = {
    # Quaternius UAL2 zombie set (CC0)
    "z_idle":          ("ual2", "Zombie_Idle_Loop", {"loop": True}),
    "z_walk":          ("ual2", "Zombie_Walk_Fwd_Loop", {"loop": True}),
    "z_scratch":       ("ual2", "Zombie_Scratch", {}),
    "z_standup":       ("ual2", "LayToIdle", {}),
    "z_climb":         ("ual2", "ClimbUp_1m_RM", {"keep_root": True}),
    "z_hit_knockback": ("ual2", "Hit_Knockback", {}),
    "z_attack":        ("ual2", "Zombie_Idle_Loop", {"grab": GRAB_A, "dur": 1.6}),
    "z_attack2":       ("ual2", "Zombie_Idle_Loop", {"grab": GRAB_B, "dur": 1.5}),
    "p_stab":          ("ual2", "Sword_Regular_A", {}),
    # Quaternius UAL1 (CC0)
    "z_hit_head":      ("ual1", "Hit_Head", {}),
    "z_hit_chest":     ("ual1", "Hit_Chest", {}),
    "z_death":         ("ual1", "Death01", {}),
    "z_attack3":       ("ual2", "Zombie_Idle_Loop", {"grab": GRAB_C, "dur": 1.8}),
    # Derived: a human gait leaned into a zombie's
    "z_walk2":         ("ual1", "Walk_Loop", {"loop": True, "hunch": HUNCH_WALK}),
    "z_run":           ("ual1", "Sprint_Loop", {"loop": True, "hunch": HUNCH_RUN}),
}

# Kimodo clips: when ~/.cache/dopesick/kimodo/best/<clip>.bvh exists (picked with
# fetch_zombie_anims.py --kimodo-pick), the clip is baked from that take instead of
# the hand-posed GRAB_* above, which stay as the fallback (and with HAND_ATTACKS=1 in
# the environment). Options: claw = finger curl, root_xy = share of the take's
# forward travel kept, grab = the zombie layer's keys (ZL_*: hunch, head thrust, and for
# z_attack2 the swiping arms).
KIMODO_OPTS = {
    "z_attack":  {"claw": 1.0, "root_xy": 0.3, "grab": "ZL_A"},
    "z_attack2": {"claw": 1.0, "root_xy": 0.3, "grab": "ZL_B"},
    "z_attack3": {"claw": 1.0, "root_xy": 0.3, "grab": "ZL_C"},
    # The rest of the Kimodo clips (loopify closes a take into a cycle; loops stay in place).
    "z_crawl":   {"loop": True, "loopify": 24, "claw": 0.8, "floor_bones": 0.05},
    "z_scream":  {"root_xy": 0.3, "claw": 1.3, "grab": "ZL_S", "jaw": ZL_S_JAW},
    "p_kick":    {"root_xy": 0.3, "settle": 14},
    "z_walk3":   {"loop": True, "loopify": 24, "dur": 4.2},
    "z_hit_leg": {"root_xy": 0.5, "floor_bones": 0.05},
    "z_death2":  {"root_xy": 0.6, "floor_bones": 0.05},
}
for _name, _opt in KIMODO_OPTS.items():
    if _name.startswith("z_attack") and os.environ.get("HAND_ATTACKS"):
        continue
    if os.path.exists(os.path.join(KIMODO_BEST, _name + ".bvh")):
        CLIPS[_name] = ("soma30", _name, _opt)

# GANG=1: the armed humans of Ghetto Wars (Quaternius UAL1/UAL2, CC0): plain human clips, no zombie layer.
# They go to assets/gang_anims/gang_clips.res; dev-tools/build_gang_library.gd also builds the "aim" composites
# (legs of a gait, the arms and torso of the pistol aim pose).
GANG_CLIPS = {
    "g_aim":         ("ual1", "Pistol_Aim_Neutral", {"loop": True}),
    "g_aim_up":      ("ual1", "Pistol_Aim_Up", {"loop": True}),
    "g_aim_down":    ("ual1", "Pistol_Aim_Down", {"loop": True}),
    "g_idle":        ("ual1", "Pistol_Idle_Loop", {"loop": True}),
    "g_shoot":       ("ual1", "Pistol_Shoot", {}),
    "g_reload":      ("ual1", "Pistol_Reload", {}),
    "g_crouch_idle": ("ual1", "Crouch_Idle_Loop", {"loop": True}),
    "g_crouch_walk": ("ual1", "Crouch_Fwd_Loop", {"loop": True}),
    "g_walk":        ("ual1", "Walk_Loop", {"loop": True}),
    "g_jog":         ("ual1", "Jog_Fwd_Loop", {"loop": True}),
    "g_sprint":      ("ual1", "Sprint_Loop", {"loop": True}),
    "g_stand":       ("ual1", "Idle_Loop", {"loop": True}),
    "g_roll":        ("ual1", "Roll", {}),
    "g_throw":       ("ual2", "OverhandThrow", {}),
    "g_hit_chest":   ("ual1", "Hit_Chest", {}),
    "g_hit_head":    ("ual1", "Hit_Head", {}),
    "g_hit_knock":   ("ual2", "Hit_Knockback", {}),
    "g_death":       ("ual1", "Death01", {}),
}
if os.environ.get("GANG"):
    CLIPS = GANG_CLIPS

# ---------------------------------------------------------------------------
try:
    import bpy
    from mathutils import Matrix, Quaternion, Vector
except ImportError:
    bpy = None


def drive():
    """Plain python: run Blender for the bake, then Godot for the .res."""
    os.makedirs(WORK, exist_ok=True)
    gang = bool(os.environ.get("GANG"))
    glb = os.path.join(WORK, "gang_clips.glb" if gang else "zombie_clips.glb")
    meta = os.path.join(WORK, "gang_clips_meta.json" if gang else "zombie_clips_meta.json")
    here = os.path.abspath(__file__)
    subprocess.run(["/snap/bin/blender", "-b", "--factory-startup", "-P", here, "--", glb, meta] + sys.argv[1:], check=True)
    subprocess.run(["flatpak", "run", "org.godotengine.Godot", "--headless", "--path", ".", "-s",
                    "res://dev-tools/build_gang_library.gd" if gang else "res://dev-tools/build_zombie_library.gd",
                    "--", glb, meta, "res://assets/gang_anims/gang_clips.res" if gang else OUT_RES], check=True)


def rot_of(m):
    return m.to_3x3().normalized()


def blender_main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out_glb, out_meta = args[0], args[1]
    only = set(args[2:])
    for name in list(only):
        if name.startswith("take:"):
            # A raw Kimodo take (fetch_zombie_anims.py --kimodo), baked under its own name for the probe.
            CLIPS[name[5:]] = ("soma30", name, json.loads(os.environ.get("TRIAL_OPTS", "{}")))
            only.discard(name)
            only.add(name[5:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 24   # what the glTF clips are timed in; 30 again for the export

    # --- target: the Rocketbox avatar's armature, stripped to bones.
    bpy.ops.import_scene.fbx(filepath=AVATAR_FBX)
    tgt = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in list(bpy.data.objects):
        if o.type != "ARMATURE":
            bpy.data.objects.remove(o)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    tgt.animation_data_create()
    tgt_world = tgt.matrix_world.copy()
    tgt_rw = rot_of(tgt_world)
    tgt_bones = tgt.data.bones
    t_rest = {b.name: rot_of(b.matrix_local) for b in tgt_bones}          # armature space
    t_head_w = {b.name: tgt_world @ b.head_local for b in tgt_bones}      # world
    t_rest_w = {n: tgt_rw @ r for n, r in t_rest.items()}                 # world rotation at rest
    t_order = [b.name for b in tgt_bones if b.parent is None]
    i = 0
    while i < len(t_order):
        t_order += [c.name for c in tgt_bones[t_order[i]].children]
        i += 1
    up = Vector((0, 0, 1))
    t_fwd = (t_head_w["Bip01 L Toe0"] - t_head_w["Bip01 L Foot"])
    t_fwd.z = 0
    t_fwd.normalize()
    t_pelvis_rest = t_head_w["Bip01 Pelvis"].copy()

    results = {}
    meta = {}
    sources = {}
    for out_name, (skel, action_name, opt) in CLIPS.items():
        if only and out_name not in only:
            continue
        if skel == "soma30":
            # One armature per BVH (each is a single take); drop the previous one.
            if "soma30" in sources:
                bpy.data.objects.remove(sources["soma30"]["arm"])
            bvh = os.path.join(KIMODO_TAKES, action_name[5:], "take.bvh") if action_name.startswith("take:") \
                else os.path.join(KIMODO_BEST, action_name + ".bvh")
            sources["soma30"] = load_source(skel, bvh)
            src = sources[skel]
            act = src["arm"].animation_data.action
        else:
            if skel not in sources:
                sources[skel] = load_source(skel)
            src = sources[skel]
            act = bpy.data.actions.get(src["prefix"] + action_name) or bpy.data.actions.get(action_name)
        if act is None:
            print("MISSING SOURCE ACTION", skel, action_name)
            continue
        results[out_name] = bake(out_name, src, act, opt, tgt, tgt_world, tgt_rw, t_rest, t_head_w, t_rest_w, t_order,
                                 t_fwd, t_pelvis_rest, up, meta)
    export(tgt, out_glb)
    with open(out_meta, "w") as f:
        json.dump(meta, f, indent=1)
    print("WROTE", out_glb, os.path.getsize(out_glb) // 1024, "KB;", len(results), "clips")


def load_source(skel, bvh=None):
    before = set(bpy.data.objects)
    before_actions = set(bpy.data.actions)
    if skel == "soma30":
        # Kimodo's 30-joint SOMA BVH (centimetres, Y up, +Z forward, 30 fps).
        bpy.ops.import_anim.bvh(filepath=bvh, axis_forward="Z", axis_up="Y", global_scale=0.01,
                                frame_start=1, use_fps_scale=False, update_scene_fps=False, rotate_mode="NATIVE")
    else:
        bpy.ops.import_scene.gltf(filepath={"ual1": UAL1_GLB, "ual2": UAL2_GLB}[skel])
    arm = next(o for o in set(bpy.data.objects) - before if o.type == "ARMATURE")
    for o in list(set(bpy.data.objects) - before):
        if o.type != "ARMATURE":
            bpy.data.objects.remove(o)
    # Two libraries import actions with the same names: tell them apart.
    for a in set(bpy.data.actions) - before_actions:
        a.name = skel + "|" + a.name
    arm.animation_data_create()
    world = arm.matrix_world.copy()
    rw = rot_of(world)
    bones = arm.data.bones
    mp = MAPS[skel]
    s_head = {b.name: world @ b.head_local for b in bones}
    s_rest_w = {b.name: rw @ rot_of(b.matrix_local) for b in bones}
    fwd = s_head[next(k for k in mp if mp[k] == ["Bip01 L Toe0"])] - s_head[next(k for k in mp if mp[k] == ["Bip01 L Foot"])]
    fwd.z = 0
    fwd.normalize()
    src = {"arm": arm, "world": world, "rw": rw, "head": s_head, "rest_w": s_rest_w, "fwd": fwd, "skel": skel,
           "prefix": skel + "|", "map": mp, "fps": None}
    if skel == "soma30":
        src["json"] = os.path.splitext(bvh)[0] + ".json" if os.path.basename(bvh) != "take.bvh" else os.path.join(os.path.dirname(bvh), "take.json")
        # The BVH root sits at the origin at rest: take the leg ratio from hips-to-toes instead.
        src["fps"] = 30.0
        src["pel_h"] = s_head["Hips"].z - s_head["LeftToeBase"].z
        src["bvh"] = True
    return src


def bake(out_name, src, act, opt, tgt, tgt_world, tgt_rw, t_rest, t_head_w, t_rest_w, t_order, t_fwd, t_pelvis_rest, up, meta):
    skel, arm, mp = src["skel"], src["arm"], src["map"]
    # Turn the source to face the way the avatar does (both are -Y here; kept general).
    yaw = src["fwd"].rotation_difference(t_fwd)
    Y = yaw.to_matrix()
    # Mapped target bone -> source bone (the pelvis maps onto two: Pelvis and Spine).
    t_to_s = {}
    for sname, tnames in mp.items():
        for t in tnames:
            t_to_s[t] = sname
    # Alignment Q per target bone, from the rest directions.
    Q = {}
    for t in t_order:
        s = t_to_s.get(t)
        if s is None:
            continue
        child = dir_child(skel, s)
        if child is None or child not in mp:
            Q[t] = None   # filled from the parent below
            continue
        tc = mp[child][0]
        d_s = (Y @ (src["head"][child] - src["head"][s]))
        d_t = t_head_w[tc] - t_head_w[t]
        Q[t] = d_t.rotation_difference(d_s).to_matrix() if d_s.length > 1e-6 and d_t.length > 1e-6 else None
    for t in t_order:
        if t in t_to_s and Q.get(t) is None:
            p = tgt.data.bones[t].parent
            while p is not None and Q.get(p.name) is None:
                p = p.parent
            Q[t] = Q[p.name] if p is not None else Matrix.Identity(3)
    ref_w = {t: Q[t] @ t_rest_w[t] for t in Q}                 # R_T_ref
    s_rest_w = src["rest_w"]
    if src.get("bvh"):
        leg = (t_pelvis_rest.z - t_head_w["Bip01 L Toe0"].z) / src["pel_h"]
    else:
        leg = t_pelvis_rest.z / (Y @ src["head"][next(k for k in mp if mp[k][0] == "Bip01 Pelvis")]).z

    # Sample the source.
    src_fps = src["fps"] or float(bpy.context.scene.render.fps)
    f0, f1 = act.frame_range
    n = max(1, int(round((f1 - f0) / src_fps * 30.0)))
    if opt.get("loop") is None and (f1 - f0) < 1:
        n = 1
    if opt.get("dur"):
        n = int(round(opt["dur"] * 30.0))   # stretch the source over this many seconds
    attach(arm, act)
    frames = []
    pel_s = next(k for k in mp if mp[k][0] == "Bip01 Pelvis")
    for i in range(n + 1):
        fr = f0 + (f1 - f0) * i / n
        bpy.context.scene.frame_set(int(fr), subframe=fr - int(fr))
        ev = arm.evaluated_get(bpy.context.evaluated_depsgraph_get())
        rots = {}
        for sname in mp:
            m = src["world"] @ ev.pose.bones[sname].matrix
            rots[sname] = Y @ rot_of(m)
        pel = Y @ (src["world"] @ ev.pose.bones[pel_s].matrix).translation
        feet = {}
        toe_z = 9.0
        for sname in mp:
            if mp[sname] == ["Bip01 L Foot"] or mp[sname] == ["Bip01 R Foot"]:
                feet[sname] = Y @ (src["world"] @ ev.pose.bones[sname].matrix).translation
            elif mp[sname] == ["Bip01 L Toe0"] or mp[sname] == ["Bip01 R Toe0"]:
                toe_z = min(toe_z, (Y @ (src["world"] @ ev.pose.bones[sname].matrix).translation).z)
        frames.append((rots, pel, feet, toe_z))
    k_blend = int(opt.get("loopify", 0))
    if k_blend and len(frames) > 2 * k_blend:
        # A generated take is not a cycle: ease the last k_blend frames into the first
        # (rotations and hip height; the travel is taken out below), so the loop closes.
        n_f = len(frames)
        for i in range(n_f - k_blend, n_f):
            u = (i - (n_f - k_blend) + 1) / float(k_blend)
            w = u * u * (3.0 - 2.0 * u)
            rots_i, pel_i, feet_i, toe_i = frames[i]
            rots_0, pel_0 = frames[0][0], frames[0][1]
            blended = {s_: rots_i[s_].to_quaternion().slerp(rots_0[s_].to_quaternion(), w).to_matrix() for s_ in rots_i}
            pel_b = Vector((pel_i.x, pel_i.y, pel_i.z + (pel_0.z - pel_i.z) * w))
            frames[i] = (blended, pel_b, feet_i, toe_i)
    k_settle = int(opt.get("settle", 0))
    if k_settle:
        # A take that ends mid-move (the kick's leg still out): ease back to the first pose
        # over k_settle extra frames, so a one-shot ends where it began.
        rots_l, pel_l, feet_l, toe_l = frames[-1]
        rots_0, pel_0 = frames[0][0], frames[0][1]
        for j in range(1, k_settle + 1):
            w = j / float(k_settle)
            w = w * w * (3.0 - 2.0 * w)
            blended = {s_: rots_l[s_].to_quaternion().slerp(rots_0[s_].to_quaternion(), w).to_matrix() for s_ in rots_l}
            pel_b = Vector((pel_l.x, pel_l.y, pel_l.z + (pel_0.z - pel_l.z) * w))
            frames.append((blended, pel_b, feet_l, toe_l))
    if opt.get("loop"):
        # A loop whose last frame repeats the first would stall once a cycle.
        same = all(frames[0][0][s].to_quaternion().rotation_difference(frames[-1][0][s].to_quaternion()).angle < 0.02 for s in mp)
        if same:
            frames.pop()

    # Pelvis path: height scaled to the avatar's legs; ground drift out for loops.
    cnt = len(frames)
    pel_xy = [Vector((f[1].x, f[1].y, 0)) for f in frames]
    if opt.get("keep_root"):
        base = pel_xy[0]
        drift = [Vector((0, 0, 0)) for _ in frames]
    elif opt.get("loop"):
        base = sum(pel_xy, Vector()) / cnt
        span = max(cnt - 1, 1)
        total = pel_xy[-1] - pel_xy[0]
        drift = [total * (i / span) - total * 0.5 for i in range(cnt)]
    else:
        base = pel_xy[0]
        drift = [Vector((0, 0, 0)) for _ in frames]
    # Planted-foot pace: how fast the lower of the feet moves backwards, per second.
    travel = 0.0
    if opt.get("loop"):
        speeds = []
        for i in range(1, cnt):
            low = min(frames[i][2], key=lambda s: frames[i][2][s].z)
            d = (frames[i][2][low] - frames[i - 1][2][low])
            d.z = 0
            speeds.append(d.length * 30.0 * leg)
        speeds.sort()
        travel = speeds[len(speeds) // 2] if speeds else 0.0
        drift_speed = (pel_xy[-1] - pel_xy[0]).length / max(cnt - 1, 1) * 30.0 * leg
        travel = max(travel, drift_speed)

    # Torso lean for the derived clips (world-space, absolute).
    hunch = opt.get("hunch")
    side_axis = up.cross(t_fwd).normalized()   # forward lean = rotation about up x forward
    def extra_for(t):
        if not hunch:
            return None
        pitch = roll = 0.0
        if t == "Bip01 Spine1":
            pitch = hunch["spine1"]
        elif t == "Bip01 Spine2" or any(k in t for k in ("Clavicle", "UpperArm", "Forearm", "Hand", "Finger")):
            pitch = hunch["spine1"] + hunch["spine2"]
        elif t in ("Bip01 Neck", "Bip01 Head"):
            pitch = hunch["spine1"] + hunch["spine2"] + (hunch["head_pitch"] if t == "Bip01 Head" else hunch["head_pitch"] * 0.5)
            roll = hunch["head_roll"] * (1.0 if t == "Bip01 Head" else 0.5)
        if not pitch and not roll:
            return None
        e = Quaternion(side_axis, math.radians(pitch)).to_matrix() if pitch else Matrix.Identity(3)
        if roll:
            e = Quaternion(t_fwd, math.radians(roll)).to_matrix() @ e
        return e

    # Hand-posed attacks: the avatar's frame, and each arm bone's own axis.
    grab = opt.get("grab")
    if isinstance(grab, str):
        grab = GRAB_TABLES[grab]
    left_v = t_head_w["Bip01 L UpperArm"] - t_head_w["Bip01 R UpperArm"]
    left_v.z = 0
    left_v.normalize()
    bone_axis = {}
    if grab:
        for side in ("L", "R"):
            for b_, c_ in (("UpperArm", "Forearm"), ("Forearm", "Hand"), ("Hand", "Finger2")):
                tn = "Bip01 %s %s" % (side, b_)
                d = t_head_w["Bip01 %s %s" % (side, c_)] - t_head_w[tn]
                bone_axis[tn] = (t_rest_w[tn].inverted() @ d).normalized()

    def grab_override(t, rw_, gp):
        """Apply the keyed pose gp (grab_params) to bone t, whose world rotation is rw_."""
        pitch = {"Bip01 Spine": gp[0], "Bip01 Spine1": gp[1], "Bip01 Spine2": gp[2],
                 "Bip01 Neck": gp[3], "Bip01 Head": gp[4]}.get(t, 0.0)
        if pitch:
            rw_ = Quaternion(side_axis, math.radians(pitch)).to_matrix() @ rw_
        if t == "Bip01 Head":
            if gp[5]:
                rw_ = Quaternion(t_fwd, math.radians(gp[5])).to_matrix() @ rw_
            if gp[6]:
                rw_ = Quaternion(up, math.radians(gp[6])).to_matrix() @ rw_
        if t in bone_axis and not t.endswith("Hand"):
            side = t.split(" ")[1]
            a = 7 if side == "L" else 15
            w, u, f, tw = gp[a], gp[a + 1:a + 4], gp[a + 4:a + 7], gp[a + 7]
            want = u if t.endswith("UpperArm") else f
            out = left_v if side == "L" else -left_v
            dw = (t_fwd * want[0] + out * want[1] + up * want[2]).normalized()
            cur = (rw_ @ bone_axis[t]).normalized()
            blend = (cur * (1.0 - w) + dw * w).normalized()
            rw_ = cur.rotation_difference(blend).to_matrix() @ rw_
            if tw and t.endswith("Forearm"):
                rw_ = Quaternion(blend, math.radians(tw * w)).to_matrix() @ rw_
        return rw_

    # Claw hands (SOMA30 has no fingers): curl the Rocketbox finger joints toward the
    # palm by a fixed relaxed-claw pose. The curl axis of each bone is whichever of
    # its local X/Z axes bends the finger toward the palm (the palm faces the body in
    # the A-pose, so the palm normal is the side vector pointing inwards).
    claw_q = {}
    if opt.get("claw"):
        amount = float(opt["claw"])
        for side in ("L", "R"):
            palm = -left_v if side == "L" else left_v
            for finger, joints in FINGERS.items():
                angles = (8, 12, 10) if finger == "Finger0" else (24, 40, 30)
                for j, ang in zip(joints, angles):
                    tn = "Bip01 %s %s" % (side, j)
                    d = t_rest_w[tn] @ Vector((0, 1, 0))
                    best, score = None, -9.0
                    for cand in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 0, 1)), Vector((0, 0, -1))):
                        sc = (t_rest_w[tn] @ cand).cross(d).dot(palm)
                        if sc > score:
                            best, score = cand, sc
                    claw_q[tn] = Quaternion(best, math.radians(ang * amount))
    root_xy = float(opt.get("root_xy", 1.0))   # share of the source's horizontal travel kept

    # Jaw (Bip01 MJaw): keys [(clip fraction, degrees open), ...], eased between. The opening
    # axis is whichever bone-local X/Z swings the chin (jaw head -> bottom lip) downwards.
    jaw_keys = opt.get("jaw")
    jaw_axis = None
    if jaw_keys:
        jd = t_head_w["Bip01 MBottomLip"] - t_head_w["Bip01 MJaw"]
        best_sc = -9.0
        for cand in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 0, 1)), Vector((0, 0, -1))):
            sc = (t_rest_w["Bip01 MJaw"] @ cand).cross(jd).dot(-up)
            if sc > best_sc:
                jaw_axis, best_sc = cand, sc
    def jaw_deg(f):
        if f <= jaw_keys[0][0]:
            return jaw_keys[0][1]
        for (t0, d0), (t1, d1) in zip(jaw_keys, jaw_keys[1:]):
            if f <= t1:
                u = (f - t0) / max(t1 - t0, 1e-6)
                return d0 + (d1 - d0) * u * u * (3.0 - 2.0 * u)
        return jaw_keys[-1][1]

    # Pose the avatar from frame i of the source, with the pelvis `dz` higher.
    pb_all = tgt.pose.bones
    for pb in pb_all:
        pb.rotation_mode = "QUATERNION"
    bones = tgt.data.bones
    inv_rw = tgt_rw.inverted()
    root_name = next(t for t in t_order if bones[t].parent is None)

    def pose(i, dz):
        rots, pel = frames[i][0], frames[i][1]
        pose_rot = {}
        delta = {}
        gp = grab_params(grab, i / max(len(frames) - 1, 1)) if grab else None
        for t in t_order:
            b = bones[t]
            if grab:
                delta[t] = delta[b.parent.name] if b.parent is not None else Matrix.Identity(3)
            if t in t_to_s:
                s = t_to_s[t]
                rw_ = (rots[s] @ (Y @ s_rest_w[s] if src.get("bvh") else s_rest_w[s]).inverted()) @ ref_w[t]
                if grab:
                    base_ = rw_
                    rw_ = delta[t] @ rw_
                    rw_ = grab_override(t, rw_, gp)
                    delta[t] = rw_ @ base_.inverted()
                ex = extra_for(t)
                if ex is not None:
                    rw_ = ex @ rw_
                Rpose = inv_rw @ rw_
            elif b.parent is not None:
                Rpose = pose_rot[b.parent.name] @ t_rest[b.parent.name].inverted() @ t_rest[t]
                if t in claw_q:
                    Rpose = Rpose @ claw_q[t].to_matrix()
                elif jaw_axis is not None and t == "Bip01 MJaw":
                    Rpose = Rpose @ Quaternion(jaw_axis, math.radians(jaw_deg(i / max(len(frames) - 1, 1)))).to_matrix()
            else:
                Rpose = t_rest[t]
            pose_rot[t] = Rpose
            pb = pb_all[t]
            if b.parent is None:
                if opt.get("keep_root"):
                    xy = (pel - base) * leg
                else:
                    xy = (pel - base - drift[i]) * leg * root_xy
                p = Vector((xy.x + t_pelvis_rest.x, xy.y + t_pelvis_rest.y, pel.z * leg + dz))
                loc = b.matrix_local.inverted() @ (Matrix.Translation(tgt_world.inverted() @ p) @ Rpose.to_4x4())
                pb.location = loc.translation
                pb.rotation_quaternion = loc.to_quaternion()
            elif t in t_to_s:
                pre = pose_rot[b.parent.name] @ t_rest[b.parent.name].inverted() @ t_rest[t]
                pb.rotation_quaternion = (pre.inverted() @ Rpose).to_quaternion()
            elif t in claw_q:
                pb.rotation_quaternion = claw_q[t]
            elif jaw_axis is not None and t == "Bip01 MJaw":
                pb.rotation_quaternion = Quaternion(jaw_axis, math.radians(jaw_deg(i / max(len(frames) - 1, 1))))

    # Pass 1: how far do the toes sink (or float) compared with the source's?
    tgt.animation_data.action = None
    toes = [pb_all["Bip01 L Toe0"], pb_all["Bip01 R Toe0"]]
    low = 9.0
    low_body = []
    body = [pb for pb in pb_all if "Finger" not in pb.name and "Toe" not in pb.name]
    for i in range(len(frames)):
        pose(i, 0.0)
        bpy.context.view_layer.update()
        low = min(low, min((tgt_world @ tb.matrix).translation.z for tb in toes))
        if opt.get("floor_bones") is not None:
            low_body.append(min((tgt_world @ pb.matrix).translation.z for pb in body))
    src_low = min(f[3] for f in frames) * leg
    shift = max(-0.12, min(0.12, src_low - low))
    lift = [0.0] * len(frames)
    if opt.get("floor_bones") is not None:
        # Lying and kneeling clips: the toes are not what touches the floor. Lift each frame
        # just enough that no body bone (a bone sits inside its limb) is below `floor_bones`
        # metres, smoothed over 7 frames so the hips do not jitter; never lowers the body.
        shift = 0.0
        need = [max(0.0, float(opt["floor_bones"]) - lb) for lb in low_body]
        for i in range(len(need)):
            win = need[max(0, i - 3):i + 4]
            lift[i] = max(need[i], sum(win) / len(win))
    print("   floor shift %s: %+.3f m (avatar toes %.3f, source %.3f)" % (out_name, shift, low, src_low))

    # Pass 2: write the keys.
    new = bpy.data.actions.new(out_name)
    new.use_fake_user = True
    tgt.animation_data.action = new
    if hasattr(new, "slots"):
        tgt.animation_data.action_slot = new.slots[0] if len(new.slots) else new.slots.new(id_type="OBJECT", name="Bip01")
    for i in range(len(frames)):
        pose(i, shift + lift[i])
        for t in t_order:
            if t in t_to_s or t in claw_q or (jaw_axis is not None and t == "Bip01 MJaw"):
                pb = pb_all[t]
                if bones[t].parent is None:
                    pb.keyframe_insert("location", frame=i + 1)
                pb.keyframe_insert("rotation_quaternion", frame=i + 1)
    track = tgt.animation_data.nla_tracks.new()
    track.name = out_name
    track.strips.new(out_name, 1, new)
    track.mute = True
    tgt.animation_data.action = None
    source = "%s:%s" % (skel, act.name.split("|")[-1])
    if skel == "soma30" and os.path.exists(src["json"]):
        # Which take this was: prompt(s) and seed, from the sidecar fetch_zombie_anims.py wrote.
        info = json.load(open(src["json"]))
        source = "Kimodo SOMA-RP v1.1 seed %s: %s" % (info.get("seed"), " / ".join(seg[1] for seg in info.get("segments", [])))
    meta[out_name] = {"source": source, "loop": bool(opt.get("loop")),
                      "travel": round(travel, 3), "frames": len(frames), "hunch": bool(hunch or grab),
                      "root_motion": bool(opt.get("keep_root"))}
    print("CLIP", out_name, "<-", meta[out_name])
    return new


def attach(arm, act):
    ad = arm.animation_data
    ad.action = act
    if hasattr(act, "slots") and len(act.slots):
        ad.action_slot = act.slots[0]


def export(tgt, out_glb):
    bpy.context.scene.render.fps = 30
    bpy.ops.object.select_all(action="DESELECT")
    tgt.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    os.makedirs(os.path.dirname(out_glb), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_glb, export_format="GLB", use_selection=True,
        export_animations=True, export_animation_mode="NLA_TRACKS",
        export_force_sampling=False, export_optimize_animation_size=False,
        export_def_bones=False, export_apply=False,
    )


if bpy is None:
    drive()
else:
    blender_main()
