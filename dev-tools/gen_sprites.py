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


# --- Environment (tileable + dedicated furniture) ---------------------

ENV_OUT = os.path.join(OUT, "..", "env")
ENV_OUT = os.path.normpath(ENV_OUT)
os.makedirs(ENV_OUT, exist_ok=True)


def env_save(img, name):
    path = os.path.join(ENV_OUT, f"{name}.png")
    img.save(path)
    return path


def gen_floor_tile():
    tw, th, sc = 32, 32, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (118, 106, 92, 255)
    d.rectangle([0, 0, tw * sc, th * sc], fill=base)
    board_h = 8
    for row, y in enumerate(range(0, th, board_h)):
        shade = (108, 97, 84, 255) if row % 2 == 0 else (124, 111, 96, 255)
        d.rectangle([0, y * sc, tw * sc, (y + board_h) * sc - int(sc * 0.35)], fill=shade)
        d.line([0, y * sc, tw * sc, y * sc], fill=(70, 62, 52, 200), width=max(1, sc // 6))
    env_save(img.resize((tw, th), Image.LANCZOS), "floor_tile")


def gen_wall_tile():
    tw, th, sc = 32, 32, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (46, 42, 40, 255)
    mortar = (30, 27, 25, 255)
    brick = (58, 52, 48, 255)
    d.rectangle([0, 0, tw * sc, th * sc], fill=base)
    brick_h = 8
    brick_w = 16
    for row, y in enumerate(range(0, th, brick_h)):
        offset = 0 if row % 2 == 0 else brick_w // 2
        d.line([0, y * sc, tw * sc, y * sc], fill=mortar, width=max(1, sc // 5))
        x = -offset
        while x < tw:
            d.rectangle([x * sc, y * sc, (x + brick_w - 1) * sc, (y + brick_h - 1) * sc], fill=brick)
            d.line([(x + brick_w - 1) * sc, y * sc, (x + brick_w - 1) * sc, (y + brick_h) * sc],
                   fill=mortar, width=max(1, sc // 6))
            x += brick_w
    env_save(img.resize((tw, th), Image.LANCZOS), "wall_tile")


def gen_wood_plank():
    tw, th, sc = 32, 16, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, tw * sc, th * sc], fill=(96, 68, 40, 255))
    for i, y in enumerate(range(0, th, 4)):
        shade = (86, 60, 34, 255) if i % 2 == 0 else (104, 74, 44, 255)
        d.rectangle([0, y * sc, tw * sc, (y + 4) * sc - int(sc * 0.3)], fill=shade)
    d.line([0, sc, tw * sc, sc], fill=(140, 108, 66, 160), width=max(1, sc // 6))
    env_save(img.resize((tw, th), Image.LANCZOS), "wood_plank")


def gen_bed():
    w, h, sc = 110, 50, 4
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (24, 20, 16, 255)
    d.rounded_rectangle([0, 0, w * sc, h * sc], radius=3 * sc, fill=(58, 46, 32, 255), outline=outline, width=sc)
    d.rounded_rectangle([4 * sc, 4 * sc, (w - 4) * sc, (h - 4) * sc], radius=2 * sc,
                         fill=(196, 186, 168, 255), outline=outline, width=sc // 2)
    d.rounded_rectangle([4 * sc, 22 * sc, (w - 4) * sc, (h - 4) * sc], radius=2 * sc, fill=(84, 96, 108, 255))
    d.rounded_rectangle([8 * sc, 6 * sc, 34 * sc, 18 * sc], radius=2 * sc,
                         fill=(224, 218, 204, 255), outline=outline, width=sc // 2)
    env_save(img.resize((w, h), Image.LANCZOS), "bed")


def gen_phone():
    w, h, sc = 20, 28, 8
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (18, 10, 10, 255)
    d.rounded_rectangle([3 * sc, 2 * sc, 17 * sc, 26 * sc], radius=sc,
                         fill=(120, 40, 38, 255), outline=outline, width=sc // 2)
    d.rounded_rectangle([1 * sc, 3 * sc, 19 * sc, 8 * sc], radius=sc,
                         fill=(30, 26, 24, 255), outline=outline, width=sc // 2)
    d.rectangle([6 * sc, 12 * sc, 14 * sc, 22 * sc], fill=(70, 22, 20, 255))
    env_save(img.resize((w, h), Image.LANCZOS), "phone")


def gen_tv():
    w, h, sc = 60, 40, 6
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (10, 10, 12, 255)
    d.rounded_rectangle([0, 0, w * sc, (h - 6) * sc], radius=2 * sc, fill=(22, 22, 26, 255), outline=outline, width=sc)
    d.rectangle([5 * sc, 4 * sc, (w - 5) * sc, (h - 12) * sc], fill=(58, 74, 60, 255))
    import random
    random.seed(7)
    for _ in range(40):
        x = random.uniform(6, w - 6)
        y = random.uniform(5, h - 13)
        c = random.choice([(80, 100, 82, 255), (40, 54, 42, 255), (100, 120, 100, 255)])
        d.point([(x * sc, y * sc)], fill=c)
    d.rectangle([(w // 2 - 8) * sc, (h - 6) * sc, (w // 2 + 8) * sc, h * sc], fill=(30, 30, 34, 255))
    env_save(img.resize((w, h), Image.LANCZOS), "tv")


def gen_trash():
    w, h, sc = 18, 18, 8
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (18, 22, 16, 255)
    d.polygon([(3 * sc, 3 * sc), (15 * sc, 3 * sc), (13 * sc, 17 * sc), (5 * sc, 17 * sc)],
              fill=(70, 76, 66, 255), outline=outline)
    d.rectangle([2 * sc, 1 * sc, 16 * sc, 3 * sc], fill=(88, 94, 82, 255), outline=outline, width=sc // 3)
    d.line([6 * sc, 5 * sc, 5 * sc, 14 * sc], fill=(50, 55, 46, 255), width=sc // 3)
    d.line([12 * sc, 5 * sc, 13 * sc, 14 * sc], fill=(50, 55, 46, 255), width=sc // 3)
    env_save(img.resize((w, h), Image.LANCZOS), "trash")


def gen_door():
    w, h, sc = 40, 14, 8
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (24, 16, 8, 255)
    d.rounded_rectangle([0, 0, w * sc, h * sc], radius=sc, fill=(96, 66, 34, 255), outline=outline, width=sc // 2)
    for x in (10, 20, 30):
        d.line([x * sc, 2 * sc, x * sc, (h - 2) * sc], fill=(74, 50, 24, 255), width=max(1, sc // 6))
    d.ellipse([(w - 8) * sc, (h / 2 - 1.5) * sc, (w - 5) * sc, (h / 2 + 1.5) * sc], fill=(210, 190, 120, 255))
    env_save(img.resize((w, h), Image.LANCZOS), "door")


gen_floor_tile()
gen_wall_tile()
gen_wood_plank()
gen_bed()
gen_phone()
gen_tv()
gen_trash()
gen_door()

print("done:", sorted(os.listdir(OUT)))
print("env done:", sorted(os.listdir(ENV_OUT)))
