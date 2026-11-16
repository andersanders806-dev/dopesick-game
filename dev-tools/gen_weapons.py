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
                reload=5.6, hip=3.6, ads=1.2, recoil=0.9, zoom=1.4, price=0, swap=0.7,
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
    if d.get("burst"):
        f("burst_count", d["burst"])
        f("burst_delay", d.get("burst_delay", 0.18))
    pat = d["pattern"]
    f("recoil_pattern", "PackedVector2Array(" + ", ".join(f"{x}, {y}" for x, y in pat) + ")")
    f("recoil_recover", 17.0)
    f("recoil_hold", 3.0)
    f("recoil_first", 1.0)
    f("recoil_ads", 0.75)
    f("recoil_random", 0.1)
    f("kick_back", d["kick_back"])
    f("kick_up", d["kick_up"])
    f("kick_roll", d["kick_roll"])
    f("optic", q(d["optic"]))
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
    f("model_length", d.get("length", 0.6))
    if d.get("hide"):
        f("model_hide", "PackedStringArray(" + ", ".join(q(h) for h in d["hide"]) + ")")
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


def upgraded(wid, d):
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
    k = dict(KNIFE)
    k.update(reload_empty=0.1, chambers=False, ads_time=0.2, sprint=0.0, optic="none", pattern=[(0.0, 0.0)], kick_back=0.0, kick_up=0.0,
             kick_roll=0.0, sound="", foley={}, cues=([], []))
    (OUT / "knife.tres").write_text(tres("knife", k))
    print("wrote", len(list(OUT.glob("*.tres"))), "weapons")


if __name__ == "__main__":
    main()
