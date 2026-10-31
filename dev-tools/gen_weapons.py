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
    "pistol": dict(name="Service Pistol", damage=40, head=2.5, neck=1.6, limb=0.8, rpm=330, auto=False, mag=8, reserve=80,
                   reload=1.7, hip=2.2, ads=0.3, recoil=1.2, zoom=1.3, price=0, in_box=False,
                   model="pistol/service_pistol.gltf", yaw=90, length=0.24, hide=["_b", "magazine_empty", "magazine_loaded", "bullet"]),
    "smg": dict(name="Submachine Gun", damage=28, head=1.5, neck=1.25, limb=0.8, rpm=780, auto=True, mag=30, reserve=150,
                reload=2.1, hip=3.0, ads=0.9, recoil=0.8, zoom=1.5, price=1000,
                model="smg/scene.gltf", yaw=0, length=0.52),
    "shotgun": dict(name="Pump Shotgun", damage=30, head=1.4, neck=1.2, limb=0.8, rpm=72, auto=False, mag=6, reserve=54,
                    reload=3.0, hip=5.5, ads=4.5, recoil=4.0, zoom=1.2, price=1200, pellets=8,
                    falloff_start=5, falloff_end=16, floor=0.25,
                    model="shotgun/scene.gltf", yaw=90, length=0.95),
    "ar": dict(name="Assault Rifle", damage=45, head=2.0, neck=1.5, limb=0.8, rpm=660, auto=True, mag=30, reserve=150,
               reload=2.4, hip=2.8, ads=0.5, recoil=1.0, zoom=1.8, price=1400,
               model="ar/scene.gltf", yaw=90, length=0.85),
    "sniper": dict(name="Bolt Rifle", damage=250, head=3.0, neck=2.0, limb=0.9, rpm=52, auto=False, mag=5, reserve=30,
                   reload=3.2, hip=6.0, ads=0.02, recoil=5.0, zoom=3.5, price=1500, swap=0.6,
                   model="sniper/bolt_action_rifle_7_62.gltf", yaw=90, length=1.15, hide=["bullet"]),
    "magnum": dict(name="Magnum", damage=110, head=2.2, neck=1.5, limb=0.8, rpm=160, auto=False, mag=6, reserve=42,
                   reload=2.5, hip=2.4, ads=0.25, recoil=3.2, zoom=1.35, price=1000,
                   model="magnum/scene.gltf", yaw=0, length=0.3),
    "lmg": dict(name="Light Machine Gun", damage=38, head=1.5, neck=1.25, limb=0.8, rpm=620, auto=True, mag=100, reserve=400,
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
    f("spread_hip", d["hip"])
    f("spread_ads", d["ads"])
    f("recoil", d["recoil"])
    f("ads_zoom", d["zoom"])
    f("swap_time", d.get("swap", 0.4))
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


def upgraded(wid, d):
    name, tint = UPGRADE[wid]
    u = dict(d)
    u["name"] = name
    u["damage"] = d["damage"] * 2
    u["mag"] = math.ceil(d["mag"] * 1.5)
    u["reserve"] = math.ceil(d["reserve"] * 1.5)
    u["reload"] = round(d["reload"] * 0.85, 2)
    u["ads"] = d["ads"] * 0.8
    u["tint"] = tint
    u["price"] = 0
    u["ammo_price"] = UP_AMMO
    u["in_box"] = False
    return u


def main():
    OUT.mkdir(exist_ok=True)
    for wid, d in BASE.items():
        (OUT / f"{wid}.tres").write_text(tres(wid, d, upgrade_id=f"{wid}_up"))
        (OUT / f"{wid}_up.tres").write_text(tres(f"{wid}_up", upgraded(wid, d), upgraded=True, base=wid))
    (OUT / "knife.tres").write_text(tres("knife", KNIFE))
    print("wrote", len(list(OUT.glob("*.tres"))), "weapons")


if __name__ == "__main__":
    main()
