#!/usr/bin/env python3
"""Procedurally generates low-budget top-down pixel-art sprites for Dope Sick.

Outputs PNGs into dopesick-game/assets/sprites/. Characters get a 3-direction
x 2-frame walk set (down/side/up); side faces left and is flipped in-engine
for right-facing movement. Static NPCs get a single idle frame. Items get a
16x16 icon each.
"""
import os
from PIL import Image, ImageDraw

OUT = "/home/anders/dopesick-game/assets/sprites"
os.makedirs(OUT, exist_ok=True)

W, H = 24, 32
SCALE = 4  # draw big, downsample for clean anti-aliased edges at native res


def canvas():
    return Image.new("RGBA", (W * SCALE, H * SCALE), (0, 0, 0, 0))


def finish(img):
    return img.resize((W, H), Image.LANCZOS)


def s(v):
    return int(round(v * SCALE))


def draw_char(shirt, skin, pants, hair, facing, frame, outline=(20, 16, 14, 255)):
    """facing: 'down' | 'up' | 'side'. frame: 0 or 1 (walk pose)."""
    img = canvas()
    d = ImageDraw.Draw(img)
    cx = W / 2

    leg_w, leg_h = 4, 6
    leg_y0 = 22
    gap = 2
    lx = cx - gap - leg_w
    rx = cx + gap
    # alternate which leg leads
    lead_offset = -2 if frame == 0 else 2
    trail_offset = 2 if frame == 0 else -2

    def leg(x, y_off):
        d.rounded_rectangle(
            [s(x), s(leg_y0 + y_off), s(x + leg_w), s(leg_y0 + y_off + leg_h)],
            radius=s(1.2), fill=pants, outline=outline, width=s(0.5),
        )

    if facing == "side":
        leg(cx - 3, lead_offset * 0.5)
        leg(cx - 1, trail_offset * 0.5)
    else:
        leg(lx, lead_offset * 0.4)
        leg(rx, trail_offset * 0.4)

    # torso
    if facing == "side":
        torso_box = [s(cx - 5.5), s(13), s(cx + 4.5), s(23)]
    else:
        torso_box = [s(cx - 7), s(13), s(cx + 7), s(23)]
    d.rounded_rectangle(torso_box, radius=s(2.5), fill=shirt, outline=outline, width=s(0.6))

    # arms (small nubs at torso sides), skip for side view (occluded)
    if facing != "side":
        arm_y = 14 + (1 if frame == 0 else -1)
        d.rounded_rectangle([s(cx - 9), s(arm_y), s(cx - 6.5), s(arm_y + 7)],
                             radius=s(1.2), fill=shirt, outline=outline, width=s(0.5))
        arm_y2 = 14 + (-1 if frame == 0 else 1)
        d.rounded_rectangle([s(cx + 6.5), s(arm_y2), s(cx + 9), s(arm_y2 + 7)],
                             radius=s(1.2), fill=shirt, outline=outline, width=s(0.5))

    # head
    if facing == "side":
        head_box = [s(cx - 3), s(3), s(cx + 6), s(13)]
    else:
        head_box = [s(cx - 5.5), s(3), s(cx + 5.5), s(13)]
    d.ellipse(head_box, fill=skin, outline=outline, width=s(0.6))

    # hair / back-of-head
    if facing == "up":
        d.pieslice(head_box, 180, 360, fill=hair, outline=outline, width=s(0.5))
        d.ellipse([head_box[0], head_box[1], head_box[2], head_box[1] + s(5)], fill=hair)
    elif facing == "side":
        hb = head_box
        d.pieslice([hb[0] - s(0.5), hb[1], hb[2] - s(2), hb[1] + s(7)], 200, 340, fill=hair, outline=outline, width=s(0.4))
    else:
        d.pieslice([head_box[0], head_box[1], head_box[2], head_box[1] + s(7)], 180, 360, fill=hair, outline=outline, width=s(0.5))

    # face (down only): two small dot eyes
    if facing == "down":
        ey = 8
        d.ellipse([s(cx - 3), s(ey), s(cx - 1.6), s(ey + 1.4)], fill=(30, 26, 24, 255))
        d.ellipse([s(cx + 1.6), s(ey), s(cx + 3), s(ey + 1.4)], fill=(30, 26, 24, 255))
    elif facing == "side":
        d.ellipse([s(cx + 2.2), s(7), s(cx + 3.6), s(8.4)], fill=(30, 26, 24, 255))

    return finish(img)


def save(img, name, tag):
    path = os.path.join(OUT, f"{name}_{tag}.png")
    img.save(path)
    return path


def gen_character_set(name, shirt, skin=(224, 188, 154, 255), pants=(40, 40, 48, 255), hair=(58, 42, 30, 255)):
    for facing in ("down", "side", "up"):
        for frame in (0, 1):
            img = draw_char(shirt, skin, pants, hair, facing, frame)
            save(img, name, f"{facing}_{frame}")


def gen_static_npc(name, shirt, skin=(224, 188, 154, 255), pants=(40, 40, 48, 255), hair=(58, 42, 30, 255)):
    img = draw_char(shirt, skin, pants, hair, "down", 0)
    save(img, name, "idle")


# --- Characters -------------------------------------------------------

gen_character_set("player", shirt=(92, 108, 116, 255))
gen_character_set("police", shirt=(38, 56, 102, 255), pants=(24, 30, 46, 255), hair=(20, 20, 24, 255))

gen_static_npc("npc_brown", shirt=(107, 89, 77, 255))
gen_static_npc("npc_red", shirt=(140, 56, 46, 255))
gen_static_npc("npc_purple", shirt=(96, 68, 122, 255), hair=(80, 60, 40, 255))
gen_static_npc("npc_grey", shirt=(96, 96, 100, 255), skin=(200, 164, 132, 255))
gen_static_npc("npc_green", shirt=(70, 110, 78, 255))


# --- Items --------------------------------------------------------------

IW, IH, ISCALE = 16, 16, 8


def item_canvas():
    return Image.new("RGBA", (IW * ISCALE, IH * ISCALE), (0, 0, 0, 0))


def item_finish(img):
    return img.resize((IW, IH), Image.LANCZOS)


def isc(v):
    return int(round(v * ISCALE))


def gen_whiskey():
    img = item_canvas()
    d = ImageDraw.Draw(img)
    outline = (25, 15, 5, 255)
    d.rounded_rectangle([isc(6.5), isc(1), isc(9.5), isc(5)], radius=isc(0.6),
                         fill=(70, 40, 15, 255), outline=outline, width=isc(0.4))
    d.rounded_rectangle([isc(4), isc(4.5), isc(12), isc(14.5)], radius=isc(1.6),
                         fill=(150, 90, 25, 230), outline=outline, width=isc(0.5))
    d.rectangle([isc(4.6), isc(8.5), isc(11.4), isc(11.5)], fill=(235, 220, 190, 255), outline=outline, width=isc(0.3))
    save(item_finish(img), "item_whiskey", "icon")


def gen_cigs():
    img = item_canvas()
    d = ImageDraw.Draw(img)
    outline = (40, 30, 20, 255)
    d.rectangle([isc(3), isc(4), isc(13), isc(13)], fill=(238, 234, 222, 255), outline=outline, width=isc(0.5))
    d.rectangle([isc(3), isc(7), isc(13), isc(9.2)], fill=(178, 40, 36, 255))
    for x in (5, 7.4, 9.8):
        d.rectangle([isc(x), isc(4), isc(x + 1.2), isc(6.6)], fill=(214, 210, 198, 255), outline=outline, width=isc(0.25))
    save(item_finish(img), "item_cigs", "icon")


def gen_charger():
    img = item_canvas()
    d = ImageDraw.Draw(img)
    outline = (18, 18, 20, 255)
    d.rounded_rectangle([isc(4), isc(6), isc(11), isc(14)], radius=isc(1.4),
                         fill=(28, 28, 32, 255), outline=outline, width=isc(0.4))
    d.rectangle([isc(6), isc(3.5), isc(7), isc(6.5)], fill=(200, 200, 205, 255))
    d.rectangle([isc(8.5), isc(3.5), isc(9.5), isc(6.5)], fill=(200, 200, 205, 255))
    d.line([isc(11), isc(10), isc(14.5), isc(10)], fill=(235, 235, 235, 255), width=isc(1.1))
    d.ellipse([isc(13.5), isc(9), isc(15.5), isc(11)], fill=(235, 235, 235, 255), outline=outline, width=isc(0.3))
    save(item_finish(img), "item_charger", "icon")


def gen_batteries():
    img = item_canvas()
    d = ImageDraw.Draw(img)
    outline = (24, 30, 18, 255)

    def battery(x0):
        d.rounded_rectangle([isc(x0), isc(3), isc(x0 + 4.6), isc(14)], radius=isc(0.8),
                             fill=(84, 140, 70, 255), outline=outline, width=isc(0.4))
        d.rectangle([isc(x0 + 1.3), isc(1.2), isc(x0 + 3.3), isc(3.2)], fill=(200, 160, 70, 255), outline=outline, width=isc(0.25))
        d.rectangle([isc(x0), isc(6.5), isc(x0 + 4.6), isc(9)], fill=(235, 232, 220, 255))

    battery(3.2)
    battery(8.4)
    save(item_finish(img), "item_batteries", "icon")


def gen_watch():
    img = item_canvas()
    d = ImageDraw.Draw(img)
    outline = (30, 26, 20, 255)
    d.rounded_rectangle([isc(6.5), isc(0.5), isc(9.5), isc(4)], radius=isc(0.6), fill=(60, 50, 40, 255), outline=outline, width=isc(0.3))
    d.rounded_rectangle([isc(6.5), isc(12), isc(9.5), isc(15.5)], radius=isc(0.6), fill=(60, 50, 40, 255), outline=outline, width=isc(0.3))
    d.ellipse([isc(3), isc(3), isc(13), isc(13)], fill=(205, 180, 90, 255), outline=outline, width=isc(0.6))
    d.ellipse([isc(4.2), isc(4.2), isc(11.8), isc(11.8)], fill=(245, 242, 230, 255), outline=outline, width=isc(0.35))
    cx, cy = 8, 8
    d.line([isc(cx), isc(cy), isc(cx), isc(cy - 2.6)], fill=(30, 26, 20, 255), width=isc(0.5))
    d.line([isc(cx), isc(cy), isc(cx + 2.0), isc(cy + 0.6)], fill=(30, 26, 20, 255), width=isc(0.5))
    save(item_finish(img), "item_watch", "icon")


gen_whiskey()
gen_cigs()
gen_charger()
gen_batteries()
gen_watch()

print("done:", sorted(os.listdir(OUT)))
