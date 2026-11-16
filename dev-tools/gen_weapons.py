#!/usr/bin/env python3
"""Writes weapons/*.tres (the data of every gun, base and upgraded) from the
table below. Edit the numbers here and re-run; the .tres files are what the
game loads.

    python3 dev-tools/gen_weapons.py
"""
import math
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "weapons"
G = "res://assets/guns/"

# Round 1 zombies have 150 health, round 2 250, round 5 550 (see
# ZombieMode.zombie_health).
BASE = {
    "pistol": dict(name="Service Pistol", damage=40, head=4.0, neck=2.0, limb=0.75, falloff_start=15, falloff_end=50, floor=0.65, rpm=330, auto=False, mag=8, reserve=80,
                   reload=1.7, hip=2.2, ads=0.3, recoil=1.2, zoom=1.3, price=0, in_box=False,
                   model="pistol/service_pistol.gltf", yaw=90, length=0.24, hide=["_b", "magazine_empty", "magazine_loaded", "bullet"]),
    "smg": dict(name="Submachine Gun", damage=28, head=3.0, neck=1.8, limb=0.75, falloff_start=12, falloff_end=40, floor=0.5, rpm=780, auto=True, mag=30, reserve=150,
                reload=2.1, hip=3.0, ads=0.9, recoil=0.8, zoom=1.5, price=1000,
                model="smg/scene.gltf", yaw=0, length=0.52),
    "shotgun": dict(name="Pump Shotgun", damage=30, head=2.0, neck=1.5, limb=0.75, rpm=72, auto=False, mag=6, reserve=54,
                    reload=3.0, hip=5.5, ads=4.5, recoil=4.0, zoom=1.2, price=1200, pellets=8,
                    falloff_start=5, falloff_end=16, floor=0.25,
                    model="shotgun/pump_shotgun_mossberg500.glb", yaw=0, length=1.0),
    "ar": dict(name="Assault Rifle", damage=45, head=4.0, neck=2.0, limb=0.75, falloff_start=30, falloff_end=80, floor=0.7, rpm=660, auto=True, mag=30, reserve=150,
               reload=2.4, hip=2.8, ads=0.5, recoil=1.0, zoom=1.8, price=1400,
               model="ar/scene.gltf", yaw=90, length=0.85),
    "sniper": dict(name="Bolt Rifle", damage=250, head=5.0, neck=2.5, limb=0.9, falloff_start=200, falloff_end=300, floor=0.9, rpm=52, auto=False, mag=5, reserve=30,
                   reload=3.2, hip=6.0, ads=0.02, recoil=5.0, zoom=3.5, price=1500, swap=0.6,
                   model="sniper/bolt_action_rifle_7_62.gltf", yaw=90, length=1.15, hide=["bullet"]),
    "magnum": dict(name="Magnum", damage=110, head=4.5, neck=2.2, limb=0.75, falloff_start=20, falloff_end=60, floor=0.7, rpm=160, auto=False, mag=6, reserve=42,
                   reload=2.5, hip=2.4, ads=0.25, recoil=3.2, zoom=1.35, price=1000,
                   model="magnum/scene.gltf", yaw=0, length=0.3),
    "lmg": dict(name="Light Machine Gun", damage=38, head=3.0, neck=1.8, limb=0.75, falloff_start=30, falloff_end=80, floor=0.7, rpm=620, auto=True, mag=100, reserve=400,
                reload=5.6, hip=3.6, ads=1.2, recoil=0.9, zoom=1.4, price=0, swap=0.7, optic_height=0.045,
                model="lmg/scene.gltf", yaw=180, length=1.0),
    "wonder": dict(name="Arc Caster", damage=900, head=1.0, neck=1.0, limb=1.0, rpm=240, auto=False, mag=20, reserve=160,
                   reload=3.0, hip=1.0, ads=0.2, recoil=1.5, zoom=1.3, price=0, splash=3.0, wonder=True,
                   model="", yaw=0, length=0.5),
}
# The upgraded version of each: a new name, a tint, more of everything.
UPGRADE = {
    "pistol": ("Last Word", (1.0, 0.35, 0.1)),
    "smg": ("Hornet", (1.0, 0.8, 0.1)),
    "shotgun": ("Gutter Blast", (0.9, 0.15, 0.1)),
    "ar": ("Backbone", (0.2, 0.8, 0.9)),
    "sniper": ("Long Goodbye", (0.6, 0.3, 1.0)),
    "magnum": ("Closing Time", (1.0, 0.2, 0.5)),
    "lmg": ("Meat Grinder", (0.3, 1.0, 0.3)),
    "wonder": ("Arc Caster Mk II", (0.4, 0.9, 1.0)),
}

# --- Handling by class (SHIP 16 B1): what the first-person systems read from the data. -----------------
# ads: seconds hip to sights; sprint: seconds after a sprint before the trigger answers; bump: seconds an empty
# reload adds to the tactical one (the bolt forward on a new magazine); chambers: a tactical reload leaves one in.
CLASS = {
    "pistol": dict(ads_time=0.2, sprint=0.15, bump=0.6, chambers=True, optic="none"),
    "magnum": dict(ads_time=0.2, sprint=0.20, bump=0.6, chambers=False, optic="none"),
    "smg": dict(ads_time=0.2, sprint=0.18, bump=0.7, chambers=True, optic="red_dot"),
    "ar": dict(ads_time=0.3, sprint=0.22, bump=0.7, chambers=True, optic="red_dot"),
    "shotgun": dict(ads_time=0.25, sprint=0.25, bump=0.7, chambers=True, optic="none"),
    "sniper": dict(ads_time=0.4, sprint=0.30, bump=0.7, chambers=False, optic="scope"),
    "lmg": dict(ads_time=0.4, sprint=0.30, bump=0.8, chambers=False, optic="red_dot"),
    "wonder": dict(ads_time=0.2, sprint=0.20, bump=0.6, chambers=False, optic="none"),
}
TACTICAL = 0.85  # a tactical reload is this much of the old single reload time
# Reload foley: cue -> files under assets/sfx/guns/. A cue not listed plays assets/sfx/guns/<cue>.wav (the synthesised one).
C = "common/"
FOLEY = {
    "pistol": {"mag_out": [C + "mag_out_pistol"], "mag_in": [C + "mag_in_pistol"], "rack": [C + "slide_rack"], "bolt": [C + "slide_rack"]},
    "magnum": {"mag_out": [C + "break_open"], "mag_in": [C + "break_close"], "rack": [C + "clip_tick"], "bolt": [C + "clip_tick"]},
    "smg": {"mag_out": [C + "mag_out_pistol"], "mag_in": [C + "mag_in_pistol"], "rack": [C + "slide_rack"], "bolt": [C + "clip_tick"]},
    "ar": {"mag_out": [C + "mag_out_rifle"], "mag_in": [C + "mag_in_rifle"], "rack": [C + "charge_rifle"], "bolt": [C + "clip_tick"]},
    "lmg": {"mag_out": [C + "lmg_cover_open"], "mag_in": [C + "lmg_cover_close"], "rack": [C + "charge_rifle"], "bolt": [C + "charge_rifle"]},
    "shotgun": {"pump": [C + "pump_1", C + "pump_2", C + "pump_3"], "shell_in": [C + "shell_insert_1", C + "shell_insert_2", C + "shell_insert_3"]},
    "sniper": {"bolt": [C + "bolt_open"], "bolt_open": [C + "bolt_open"], "bolt_close": [C + "bolt_close"], "shell_in": [C + "shell_insert_3", C + "shell_insert_2"]},
}
# [fraction of the reload, cue] for a tactical and an empty reload: where player/GunHandling.gd's choreography makes them.
CUES = {
    "pistol": ([[0.22, "mag_out"], [0.64, "mag_in"]], [[0.19, "mag_out"], [0.49, "mag_in"], [0.69, "rack"]]),
    "smg": ([[0.20, "mag_out"], [0.64, "mag_in"]], [[0.17, "mag_out"], [0.53, "mag_in"], [0.75, "bolt"], [0.80, "rack"]]),
    "lmg": ([[0.20, "mag_out"], [0.64, "mag_in"]], [[0.16, "mag_out"], [0.60, "mag_in"], [0.82, "bolt"]]),
    "shotgun": ([], [[0.88, "pump"]]),
    "sniper": ([[0.26, "bolt_open"], [0.66, "bolt_close"]], [[0.26, "bolt_open"], [0.66, "bolt_close"]]),
}
CUES["magnum"] = CUES["pistol"]
CUES["ar"] = CUES["smg"]
CUES["wonder"] = CUES["smg"]


# --- SHIP 16 B2: sixteen more (stats, names and prices from the 16A roster). `cls` is the class whose handling
# numbers the gun starts from, `handling` the family its animations are cut for; the per-gun view tables are in
# player/Viewmodel.gd and player/GunHandling.gd under the gun's own id.
NEW = {
    "glock": dict(name="Street Nine", cls="pistol", damage=42, head=4.0, neck=2.0, limb=0.75, falloff_start=15, falloff_end=50, floor=0.65, rpm=400, auto=False,
                  mag=17, reserve=136, reload=1.6, hip=2.3, ads=0.3, recoil=0.9, zoom=1.3, price=500, in_box=False, pattern_kind="pistol",
                  model="glock/scene.gltf", yaw=-90, length=0.2, hide=["shell_bullet", "bullet_bullet"]),
    "tec9": dict(name="Spray Can", cls="smg", damage=24, head=3.0, neck=1.6, limb=0.75, falloff_start=8, falloff_end=30, floor=0.45, rpm=900, auto=True,
                 mag=32, reserve=160, reload=1.9, hip=4.4, ads=1.7, recoil=0.9, zoom=1.3, price=750, in_box=False, pattern_kind="spray", optic="none",
                 ads_time=0.18, sprint=0.15, foley="pistolmag",
                 model="tec9/scene.gltf", yaw=180, turn=(0, 0, -66), length=0.3, hide=["9mm"]),
    "uzi": dict(name="Corner Store", cls="smg", damage=25, head=3.0, neck=1.7, limb=0.75, falloff_start=10, falloff_end=36, floor=0.5, rpm=720, auto=True,
                mag=32, reserve=160, reload=1.9, hip=3.2, ads=1.0, recoil=0.8, zoom=1.4, price=800, in_box=False, pattern_kind="smg", optic="none",
                modes=["auto", "semi"], foley="pistolmag",
                model="uzi/scene.gltf", yaw=0, length=0.45),
    "mp5": dict(name="Night Shift", cls="smg", damage=30, head=3.5, neck=1.8, limb=0.75, falloff_start=14, falloff_end=45, floor=0.55, rpm=800, auto=True,
                mag=30, reserve=150, reload=2.0, hip=2.6, ads=0.6, recoil=0.6, zoom=1.5, price=1100, pattern_kind="smg", optic="built_in",
                modes=["auto", "burst", "semi"], foley="bmag",
                model="mp5/scene.gltf", yaw=-90, length=0.7),
    "vector": dict(name="Needle", cls="smg", damage=22, head=3.0, neck=1.7, limb=0.75, falloff_start=8, falloff_end=28, floor=0.45, rpm=1200, auto=True,
                   mag=25, reserve=150, reload=1.7, hip=2.8, ads=0.7, recoil=0.5, zoom=1.4, price=0, pattern_kind="vector", optic="red_dot", optic_height=0.0,
                   modes=["auto", "burst"], mode_burst=2, foley="bmag",
                   model="vector/scene.gltf", yaw=180, length=0.6, hide=["backsight", "backscrew", "backaim", "frontsight", "frontclamp", "backclamp"]),
    "ak": dict(name="Rust Bucket", cls="ar", damage=55, head=3.5, neck=1.9, limb=0.75, falloff_start=28, falloff_end=80, floor=0.7, rpm=600, auto=True,
               mag=30, reserve=150, reload=2.5, hip=3.2, ads=0.7, recoil=1.6, zoom=1.8, price=1500, pattern_kind="ak", optic="none",
               modes=["auto", "semi"], ads_time=0.32,
               model="ak/scene.gltf", yaw=90, length=0.88),
    "m16": dict(name="Beat Cop", cls="ar", damage=50, head=4.5, neck=2.2, limb=0.75, falloff_start=40, falloff_end=100, floor=0.75, rpm=800, auto=False,
                mag=30, reserve=150, reload=2.3, hip=2.6, ads=0.35, recoil=1.0, zoom=2.0, price=1300, pattern_kind="burst", optic="none",
                burst=3, burst_delay=0.18, modes=["burst", "semi"],
                model="m16/scene.gltf", yaw=0, length=0.99, hide=["m855"]),
    "sawnoff": dict(name="Back Porch", cls="shotgun", handling="break", damage=26, head=2.0, neck=1.5, limb=0.75, rpm=180, auto=False, mag=2, reserve=36,
                    reload=2.2, bump=0.0, chambers=False, hip=7.5, ads=6.5, recoil=4.5, zoom=1.1, price=900, in_box=False, pellets=10,
                    falloff_start=3, falloff_end=18, floor=0.2, pattern_kind="shotgun", ads_time=0.2, sprint=0.18, optic_height=0.012, relief=0.3,
                    model="sawnoff/scene.gltf", yaw=180, length=0.4, hide=["polysurface2"]),
    "deagle": dict(name="Sledge", cls="pistol", damage=150, head=3.5, neck=2.0, limb=0.8, falloff_start=22, falloff_end=65, floor=0.7, rpm=200, auto=False,
                   mag=7, reserve=49, reload=2.3, hip=2.6, ads=0.25, recoil=3.8, zoom=1.35, price=0, pattern_kind="cannon", ads_time=0.24, sprint=0.2,
                   model="deagle/scene.gltf", yaw=180, length=0.27, hide=["_bullet_0"]),
    "aa12": dict(name="Broom", cls="shotgun", handling="ar", damage=16, head=2.0, neck=1.5, limb=0.75, rpm=240, auto=True, mag=20, reserve=100,
                 reload=4.0, bump=0.7, chambers=False, hip=5.0, ads=4.0, recoil=3.0, zoom=1.2, price=0, pellets=8,
                 falloff_start=4, falloff_end=16, floor=0.25, pattern_kind="autoshot", ads_time=0.3, sprint=0.26, optic="none", foley="rifle", swap=0.55,
                 model="aa12/scene.gltf", yaw=90, length=0.95, hide=["12x70", "1270n1", "8rnd", "drum mag_11"]),
    "dmr": dict(name="Pawnbroker", cls="ar", damage=130, head=4.0, neck=2.2, limb=0.8, falloff_start=60, falloff_end=140, floor=0.8, rpm=240, auto=False,
                mag=15, reserve=90, reload=2.8, hip=3.4, ads=0.12, recoil=2.4, zoom=2.4, price=1800, pattern_kind="marksman", optic="none",
                ads_time=0.36, sprint=0.26, swap=0.5,
                model="dmr/scene.gltf", yaw=180, length=1.12),
    "amr": dict(name="Bridge Burner", cls="sniper", handling="ar", damage=600, head=3.0, neck=2.0, limb=0.9, falloff_start=200, falloff_end=300, floor=0.9, rpm=40,
                auto=False, mag=5, reserve=25, reload=4.6, bump=0.8, chambers=False, hip=7.0, ads=0.02, recoil=8.0, zoom=4.5, price=0, pierce=2,
                pattern_kind="cannon", optic="scope", optic_height=0.008, ads_time=0.5, sprint=0.34, swap=0.8, foley="amr",
                model="amr/scene.gltf", yaw=90, length=1.45, hide=["50 bmg_0", "50bmg_1", "10rnd mag_3"]),
    "saw": dict(name="Iron Hog", cls="lmg", handling="belt", foley="belt", damage=42, head=3.0, neck=1.8, limb=0.75, falloff_start=32, falloff_end=85, floor=0.7, rpm=750, auto=True,
                mag=120, reserve=360, reload=5.4, hip=3.8, ads=1.1, recoil=1.4, zoom=1.5, price=0, pattern_kind="lmg", optic="red_dot", optic_height=0.022,
                swap=0.75, model="saw/scene.gltf", yaw=90, length=1.04, bones={"Bipod_01": 0.001}),
    "rpg": dict(name="Landlord", cls="shotgun", handling="launcher", damage=900, head=1.0, neck=1.0, limb=1.0, rpm=30, auto=False, mag=1, reserve=8,
                reload=3.8, bump=0.0, chambers=False, tactical=1.0, hip=1.5, ads=0.3, recoil=5.0, zoom=1.2, price=0, splash=4.0, projectile="rocket",
                self_damage=60.0, falloff_start=200, falloff_end=300, floor=1.0, pattern_kind="cannon", ads_time=0.4, sprint=0.32, swap=0.8,
                optic_height=0.0, relief=0.22, sound="rpg",
                model="rpg/scene.gltf", yaw=0, length=0.95, moves={"pcylinder8": (-0.06, -0.116, -0.33)}),
}
NEW_UPGRADE = {
    "glock": ("Switch", (1.0, 0.5, 0.1)),
    "tec9": ("Graffiti", (1.0, 0.2, 0.8)),
    "uzi": ("Open All Night", (0.2, 0.9, 1.0)),
    "mp5": ("Graveyard Shift", (0.5, 0.4, 1.0)),
    "vector": ("Pin Cushion", (1.0, 0.9, 0.2)),
    "ak": ("Rust Belt Reaper", (1.0, 0.4, 0.1)),
    "m16": ("Dirty Cop", (0.2, 0.5, 1.0)),
    "sawnoff": ("Last Orders", (0.9, 0.15, 0.1)),
    "deagle": ("Wrecking Ball", (1.0, 0.8, 0.2)),
    "aa12": ("Clean Sweep", (0.3, 1.0, 0.5)),
    "dmr": ("Repo Man", (0.7, 0.3, 1.0)),
    "amr": ("Scorched Earth", (1.0, 0.3, 0.1)),
    "saw": ("Hog Wild", (0.4, 1.0, 0.3)),
    "rpg": ("Evict All", (1.0, 0.25, 0.15)),
}
# Melee weapons for the melee slot (the knife's place): bought off the wall, upgraded at the machine.
MELEE = {
    "bat": dict(name="Slugger", up="Grand Slam", tint=(1.0, 0.6, 0.2), damage=200, head=2.0, neck=1.5, limb=0.8, rpm=70, price=600,
                range=2.3, arc=70.0, targets=2, swing=0.5, hit=0.42, heavy=1.8, heavy_time=1.5, lunge=3.6, knock=7.5,
                model="bat/scene.gltf", yaw=-90, length=0.85,
                foley={"swing": [C + "bat_swing_1", C + "bat_swing_2"], "swing_heavy": [C + "swing_heavy_1", C + "swing_heavy_2", C + "swing_heavy_3"],
                       "hit": [C + "bat_hit_1", C + "bat_hit_2", C + "bat_hit_3"], "hit_wall": [C + "bat_hit_wall"],
                       "kill": [C + "melee_kill_1", C + "melee_kill_2", C + "melee_kill_3"]}),
    "machete": dict(name="Cane Cutter", up="Chop Shop", tint=(0.9, 0.15, 0.1), damage=130, head=2.5, neck=2.0, limb=0.8, rpm=110, price=600,
                    range=2.5, arc=100.0, targets=3, swing=0.36, hit=0.4, heavy=1.7, heavy_time=1.45, lunge=3.4, knock=2.0,
                    model="machete/scene.gltf", yaw=180, length=0.65,
                    foley={"swing": [C + "machete_swing_1", C + "machete_swing_2", C + "swing_light_2"], "swing_heavy": [C + "swing_heavy_2", C + "swing_heavy_3"],
                           "hit": [C + "machete_hit_1", C + "machete_hit_2", C + "machete_hit_3", C + "machete_hit_4"], "hit_wall": [C + "machete_hit_wall"],
                           "kill": [C + "melee_kill_1", C + "melee_kill_2", C + "melee_kill_3"]}),
}
# Reload foley of the new guns, by style.
NEW_FOLEY = {
    "pistolmag": FOLEY["smg"],
    "bmag": {"mag_out": [C + "mag_out_b"], "mag_in": [C + "mag_in_b"], "rack": [C + "charge_rifle"], "bolt": [C + "clip_tick"]},
    "rifle": FOLEY["ar"],
    "amr": {"mag_out": [C + "mag_out_b"], "mag_in": [C + "mag_in_b"], "rack": [C + "charge_b"], "bolt": [C + "clip_tick"]},
    "break": {"break_open": [C + "break_open"], "shell_in": [C + "shell_insert_1", C + "shell_insert_2", C + "shell_insert_3"], "break_close": [C + "break_close"]},
    "launcher": {"rocket_in": [C + "rocket_load"], "bolt": [C + "clip_tick"]},
    "belt": {"cover_open": [C + "lmg_cover_open"], "mag_out": [C + "mag_out_b"], "mag_in": [C + "mag_in_b"], "cover_close": [C + "lmg_cover_close"],
             "bolt": [C + "charge_rifle"], "rack": [C + "charge_rifle"]},
    "mode": {},
}
FOLEY["break"] = NEW_FOLEY["break"]
FOLEY["launcher"] = NEW_FOLEY["launcher"]
CUES["break"] = ([[0.14, "break_open"], [0.5, "shell_in"], [0.82, "break_close"]], [[0.12, "break_open"], [0.4, "shell_in"], [0.62, "shell_in"], [0.84, "break_close"]])
CUES["launcher"] = ([[0.62, "rocket_in"], [0.86, "bolt"]], [[0.62, "rocket_in"], [0.86, "bolt"]])
FOLEY["belt"] = NEW_FOLEY["belt"]
CUES["belt"] = ([[0.1, "cover_open"], [0.24, "mag_out"], [0.6, "mag_in"], [0.82, "cover_close"]],
                [[0.1, "cover_open"], [0.24, "mag_out"], [0.6, "mag_in"], [0.82, "cover_close"], [0.92, "bolt"]])


def pattern_of(kind, r):
    """Per-class recoil tables: [right, up] degrees per shot. `r` is the gun's recoil number (the size of it)."""
    up = r * 0.45
    out = []
    for i in range(24):
        n = i + 1
        if kind == "pistol":          # a snap straight up, a hair to the right
            x, y = 0.08 * up * (1 if i % 2 == 0 else -0.6), up
        elif kind == "cannon":        # one big hit, up and right
            x, y = 0.22 * up, up * 1.05
        elif kind == "shotgun":
            x, y = 0.12 * up * (1 if i % 2 == 0 else -1), up
        elif kind == "autoshot":      # the AA-12 pushes back more than up, then walks left
            x, y = (-0.25 * up if n > 4 else 0.1 * up), up * (0.9 if n <= 4 else 0.55)
        elif kind == "smg":           # climbs for eight, then holds and weaves
            x, y = 0.3 * up * math.sin(n * 0.9), up * (1.0 if n <= 8 else 0.45)
        elif kind == "spray":         # the TEC-9: little climb, all over the place sideways
            x, y = 0.75 * up * math.sin(n * 2.3 + 0.6) * (1.0 if n > 2 else 0.4), up * (0.8 if n <= 6 else 0.4)
        elif kind == "vector":        # barely climbs, drifts left
            x, y = -0.22 * up * min(n / 6.0, 1.0), up * (0.9 if n <= 5 else 0.35)
        elif kind == "ak":            # hard up for five, then right for eight, then back left (the AK's hook)
            if n <= 5:
                x, y = 0.1 * up, up * 1.15
            elif n <= 13:
                x, y = 0.42 * up, up * 0.6
            else:
                x, y = -0.45 * up * (1.0 if (n - 14) % 10 < 6 else -0.8), up * 0.45
        elif kind == "burst":         # three rounds: a tight rising triangle
            x, y = [(0.0, 0.7), (0.12, 1.0), (-0.06, 1.25)][i % 3]
            x, y = x * up, y * up
        elif kind == "marksman":
            x, y = 0.15 * up * (1 if i % 2 == 0 else -1), up
        elif kind == "lmg":           # heavy: settles after six, a slow snake
            x, y = 0.28 * up * math.sin(n * 0.55), up * (1.0 if n <= 6 else 0.5)
        else:
            x, y = -up * math.sin(n * 1.7) * 0.35, up
        out.append((round(x, 4), round(y, 4)))
    return out
# Recovery by class: how fast the view comes home (released, held), the first shot's and the ADS multiple, the random share.
RECOVER = {
    "pistol": (19.0, 4.0, 1.0, 0.8, 0.1), "cannon": (11.0, 2.0, 1.0, 0.85, 0.08), "shotgun": (12.0, 2.5, 1.0, 0.9, 0.12),
    "autoshot": (12.0, 2.5, 1.15, 0.85, 0.14), "smg": (18.0, 3.2, 1.1, 0.7, 0.12), "spray": (16.0, 2.6, 1.2, 0.8, 0.22),
    "vector": (20.0, 3.6, 1.0, 0.65, 0.1), "ak": (14.0, 2.6, 1.25, 0.72, 0.1), "burst": (20.0, 5.0, 1.0, 0.65, 0.06),
    "marksman": (13.0, 2.4, 1.0, 0.7, 0.08), "lmg": (13.0, 2.4, 1.3, 0.62, 0.12),
}


def derive_new(wid, d):
    """A new gun's handling block: its class's numbers (CLASS), its own where it names them."""
    c = CLASS[d["cls"]]
    d = dict(d)
    fam = d.get("handling", d["cls"])
    old = float(d["reload"])
    d["reload"] = round(old * d.get("tactical", TACTICAL), 2)
    d["reload_empty"] = round(old + d.get("bump", c["bump"]), 2)
    d["chambers"] = d.get("chambers", c["chambers"])
    d["ads_time"] = d.get("ads_time", c["ads_time"])
    d["sprint"] = d.get("sprint", c["sprint"])
    d["optic"] = d.get("optic", c["optic"] if d["cls"] in ("sniper",) else "none")
    d["pattern"] = pattern_of(d["pattern_kind"], d["recoil"])
    d["recover"] = RECOVER[d["pattern_kind"]]
    heavy = min(max(d["recoil"] / 4.0, 0.0), 1.0)
    d["kick_back"] = round(lerp(0.02, 0.05, heavy), 4)
    d["kick_up"] = round(lerp(2.0, 6.0, heavy), 3)
    d["kick_roll"] = round(0.03 * (1.0 + heavy), 4)
    d["sound"] = d.get("sound", wid)
    fo = d.get("foley")
    d["foley"] = dict(NEW_FOLEY[fo]) if isinstance(fo, str) else dict(FOLEY.get(fam, {}))
    if d.get("modes"):
        d["foley"]["mode"] = [C + "clip_tick"]
    d["cues"] = CUES[fam]
    d["handling_family"] = fam
    return d


def upgraded_new(wid, d):
    name, tint = NEW_UPGRADE[wid]
    u = upgraded(wid, d, name, tint)
    if wid == "glock":
        # The Switch: the same pistol with the auto sear in (and the selector to take it back out).
        u["auto"] = True
        u["mag"] = 25
        u["rpm"] = 1000
        u["modes"] = ["auto", "semi"]
        u["foley"] = dict(u["foley"], mode=[C + "clip_tick"])
        u["pattern"] = pattern_of("spray", d["recoil"] * 1.2)
        u["recover"] = RECOVER["spray"]
    return u


def melee_tres(wid, m, up=False):
    d = dict(name=m["up"] if up else m["name"], damage=m["damage"] * (2 if up else 1), head=m["head"], neck=m["neck"], limb=m["limb"], rpm=m["rpm"], auto=False,
             mag=1, reserve=0, reload=0.1, reload_empty=0.1, chambers=False, hip=0.0, ads=0.0, recoil=0.0, zoom=1.0, price=0 if up else m["price"],
             ammo_price=0, in_box=False, melee=True, ads_time=0.2, sprint=0.0, optic="none", pattern=[(0.0, 0.0)], kick_back=0.0, kick_up=0.0, kick_roll=0.0,
             sound="", foley=m["foley"], cues=([], []), model=m["model"], yaw=m["yaw"], length=m["length"], handling_family="melee",
             melee_range=m["range"], melee_arc=m["arc"], melee_targets=m["targets"] + (1 if up else 0), swing_time=m["swing"], swing_hit=m["hit"],
             heavy_mult=m["heavy"], heavy_time=m["heavy_time"], lunge_range=m["lunge"], knockback=m["knock"] * (1.3 if up else 1.0))
    if up:
        d["tint"] = m["tint"]
    return d


def recoil_pattern(r):
    """The old family kick as a table: a climb of 0.45 degrees per point of recoil with a sine drift to the side."""
    up = r * 0.45
    return [(round(-up * math.sin((i + 1) * 1.7) * 0.35, 4), round(up, 4)) for i in range(24)]


def lerp(a, b, t):
    return a + (b - a) * t


UP_PRICE = 5000
UP_AMMO = 4500
KNIFE = dict(name="Knife", damage=150, head=1.0, neck=1.0, limb=1.0, rpm=100, auto=False, mag=1, reserve=0, reload=0.1,
             hip=0.0, ads=0.0, recoil=0.0, zoom=1.0, price=0, in_box=False, melee=True)


def tres(wid, d, upgrade_id=None, upgraded=False, base=""):
    ext = []
    body = []
    if upgrade_id:
        ext.append(f'[ext_resource type="Resource" path="res://weapons/{upgrade_id}.tres" id="2_up"]')
    head = f'[gd_resource type="Resource" load_steps={2 + len(ext)} format=3]\n\n'
    head += '[ext_resource type="Script" path="res://weapons/WeaponData.gd" id="1_wd"]\n'
    if ext:
        head += "\n".join(ext) + "\n"
    head += "\n[resource]\nscript = ExtResource(\"1_wd\")\n"
    f = lambda k, v: body.append(f"{k} = {v}")
    q = lambda s: '"' + s + '"'
    f("id", q(wid))
    f("display_name", q(d["name"]))
    if base:
        f("base_id", q(base))
    if upgraded:
        f("upgraded", "true")
    if d.get("melee"):
        f("melee", "true")
    f("damage", float(d["damage"]))
    f("head_mult", d["head"])
    f("neck_mult", d["neck"])
    f("limb_mult", d["limb"])
    f("pellets", d.get("pellets", 1))
    f("falloff_start", float(d.get("falloff_start", 60)))
    f("falloff_end", float(d.get("falloff_end", 150)))
    f("falloff_floor", d.get("floor", 0.6))
    f("splash_radius", float(d.get("splash", 0.0)))
    f("rpm", float(d["rpm"]))
    f("auto", "true" if d["auto"] else "false")
    f("mag_size", d["mag"])
    f("reserve_max", d["reserve"])
    f("reload_time", float(d["reload"]))
    f("reload_time_empty", float(d["reload_empty"]))
    f("chambers", "true" if d["chambers"] else "false")
    f("spread_hip", d["hip"])
    f("spread_ads", d["ads"])
    f("recoil", d["recoil"])
    f("ads_zoom", d["zoom"])
    f("swap_time", d.get("swap", 0.4))
    f("ads_time", d["ads_time"])
    f("sprint_fire_delay", d["sprint"])
    if d.get("handling_family") and d["handling_family"] != (base or wid):
        f("handling", q(d["handling_family"]))
    if d.get("burst"):
        f("burst_count", d["burst"])
        f("burst_delay", d.get("burst_delay", 0.18))
    if d.get("modes"):
        f("fire_modes", "PackedStringArray(" + ", ".join(q(m) for m in d["modes"]) + ")")
        f("mode_burst", d.get("mode_burst", 3))
    if d.get("pierce"):
        f("pierce", d["pierce"])
    if d.get("projectile"):
        f("projectile", q(d["projectile"]))
        f("self_damage", float(d.get("self_damage", 0.0)))
    if d.get("melee"):
        for k in ("melee_range", "melee_arc", "melee_targets", "swing_time", "swing_hit", "heavy_mult", "heavy_time", "lunge_range", "knockback"):
            if k in d:
                f(k, d[k])
    pat = d["pattern"]
    f("recoil_pattern", "PackedVector2Array(" + ", ".join(f"{x}, {y}" for x, y in pat) + ")")
    rec = d.get("recover", (17.0, 3.0, 1.0, 0.75, 0.1))
    f("recoil_recover", rec[0])
    f("recoil_hold", rec[1])
    f("recoil_first", rec[2])
    f("recoil_ads", rec[3])
    f("recoil_random", rec[4])
    f("kick_back", d["kick_back"])
    f("kick_up", d["kick_up"])
    f("kick_roll", d["kick_roll"])
    f("optic", q(d["optic"]))
    if "optic_height" in d:
        f("optic_height", d["optic_height"])
    if d.get("relief"):
        f("eye_relief", d["relief"])
    f("sound_set", q(d["sound"]))
    fo = d["foley"]
    if fo:
        f("foley", "{\n" + ",\n".join(f'"{k}": [' + ", ".join(q(v) for v in vs) + "]" for k, vs in fo.items()) + "\n}")
    for key, cues in (("reload_cues_tactical", d["cues"][0]), ("reload_cues_empty", d["cues"][1])):
        f(key, "[" + ", ".join(f'[{t}, "{c}"]' for t, c in cues) + "]")
    f("price", d["price"])
    f("ammo_price", d.get("ammo_price", d["price"] // 2))
    f("in_box", "true" if d.get("in_box", True) else "false")
    if d.get("wonder"):
        f("wonder", "true")
    if upgrade_id:
        f("upgrade", 'ExtResource("2_up")')
    if d.get("model"):
        f("model", q(G + d["model"]))
    f("model_yaw", float(d.get("yaw", 0)))
    if d.get("turn") and tuple(d["turn"]) != (0, 0, 0):
        f("model_turn", "Vector3(%s, %s, %s)" % tuple(d["turn"]))
    f("model_length", d.get("length", 0.6))
    if d.get("hide"):
        f("model_hide", "PackedStringArray(" + ", ".join(q(h) for h in d["hide"]) + ")")
    if d.get("moves"):
        f("model_moves", "{\n" + ",\n".join(f'"{k}": Vector3({v[0]}, {v[1]}, {v[2]})' for k, v in d["moves"].items()) + "\n}")
    if d.get("bones"):
        f("model_bones", "{\n" + ",\n".join((f'"{k}": Vector3({v[0]}, {v[1]}, {v[2]})' if isinstance(v, tuple) else f'"{k}": {float(v)}') for k, v in d["bones"].items()) + "\n}")
    if d.get("tint"):
        r, g, b = d["tint"]
        f("tint", f"Color({r}, {g}, {b}, 1)")
    return head + "\n".join(body) + "\n"


def derive(wid, d):
    """The handling block of a base gun, from its class and the numbers above."""
    c = CLASS[wid]
    d = dict(d)
    old = float(d["reload"])
    d["reload"] = round(old * TACTICAL, 2)
    d["reload_empty"] = round(old + c["bump"], 2)
    d["chambers"] = c["chambers"]
    d["ads_time"] = c["ads_time"]
    d["sprint"] = c["sprint"]
    d["optic"] = c["optic"]
    d["pattern"] = recoil_pattern(d["recoil"])
    heavy = min(max(d["recoil"] / 4.0, 0.0), 1.0)
    d["kick_back"] = round(lerp(0.02, 0.05, heavy), 4)
    d["kick_up"] = round(lerp(2.0, 6.0, heavy), 3)
    d["kick_roll"] = round(0.03 * (1.0 + heavy), 4)
    d["sound"] = wid if wid in FOLEY else ""
    d["foley"] = FOLEY.get(wid, {})
    d["cues"] = CUES[wid]
    return d


def upgraded(wid, d, name=None, tint=None):
    if name is None:
        name, tint = UPGRADE[wid]
    u = dict(d)
    u["name"] = name
    u["damage"] = d["damage"] * 2
    u["mag"] = math.ceil(d["mag"] * 1.5)
    u["reserve"] = math.ceil(d["reserve"] * 1.5)
    u["reload"] = round(d["reload"] * 0.85, 2)
    u["reload_empty"] = round(d["reload_empty"] * 0.85, 2)
    u["ads"] = d["ads"] * 0.8
    u["tint"] = tint
    u["price"] = 0
    u["ammo_price"] = UP_AMMO
    u["in_box"] = False
    return u


def main():
    OUT.mkdir(exist_ok=True)
    for wid, d in BASE.items():
        d = derive(wid, d)
        (OUT / f"{wid}.tres").write_text(tres(wid, d, upgrade_id=f"{wid}_up"))
        (OUT / f"{wid}_up.tres").write_text(tres(f"{wid}_up", upgraded(wid, d), upgraded=True, base=wid))
    for wid, d in NEW.items():
        d = derive_new(wid, d)
        (OUT / f"{wid}.tres").write_text(tres(wid, d, upgrade_id=f"{wid}_up"))
        (OUT / f"{wid}_up.tres").write_text(tres(f"{wid}_up", upgraded_new(wid, d), upgraded=True, base=wid))
    for wid, m in MELEE.items():
        (OUT / f"{wid}.tres").write_text(tres(wid, melee_tres(wid, m), upgrade_id=f"{wid}_up"))
        (OUT / f"{wid}_up.tres").write_text(tres(f"{wid}_up", melee_tres(wid, m, True), upgraded=True, base=wid))
    k = dict(KNIFE)
    k.update(reload_empty=0.1, chambers=False, ads_time=0.2, sprint=0.0, optic="none", pattern=[(0.0, 0.0)], kick_back=0.0, kick_up=0.0,
             kick_roll=0.0, sound="", foley={}, cues=([], []))
    (OUT / "knife.tres").write_text(tres("knife", k))
    print("wrote", len(list(OUT.glob("*.tres"))), "weapons")


if __name__ == "__main__":
    main()
