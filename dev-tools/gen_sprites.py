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


def shade(color, amount):
    """amount>0 lightens, amount<0 darkens. Keeps alpha."""
    r, g, b = color[0], color[1], color[2]
    a = color[3] if len(color) > 3 else 255
    if amount >= 0:
        r = r + (255 - r) * amount
        g = g + (255 - g) * amount
        b = b + (255 - b) * amount
    else:
        r = r * (1 + amount)
        g = g * (1 + amount)
        b = b * (1 + amount)
    return (int(max(0, min(255, r))), int(max(0, min(255, g))), int(max(0, min(255, b))), a)


def dither_ellipse(img, box, color_a, color_b):
    """Draws a 2-color checkerboard-dithered ellipse directly on a native-res
    RGBA image (post-downsample) for a retro/PS1-style dithered shadow."""
    x0, y0, x1, y1 = box
    px = img.load()
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rx, ry = max(1, (x1 - x0) / 2), max(1, (y1 - y0) / 2)
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            if x < 0 or y < 0 or x >= img.width or y >= img.height:
                continue
            nx, ny = (x - cx) / rx, (y - cy) / ry
            if nx * nx + ny * ny <= 1.0:
                c = color_a if (x + y) % 2 == 0 else color_b
                base = px[x, y]
                a = c[3]
                if a >= 255:
                    px[x, y] = c
                else:
                    px[x, y] = (
                        int(base[0] * (1 - a / 255) + c[0] * (a / 255)),
                        int(base[1] * (1 - a / 255) + c[1] * (a / 255)),
                        int(base[2] * (1 - a / 255) + c[2] * (a / 255)),
                        max(base[3], a),
                    )


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
    # highlight (upper-left) + shadow (lower-right) bands for a bit of form/shading
    hi_box = [torso_box[0] + s(0.8), torso_box[1] + s(0.8), torso_box[0] + s(2.6), torso_box[3] - s(1.5)]
    d.rounded_rectangle(hi_box, radius=s(1.0), fill=shade(shirt, 0.28))
    sh_box = [torso_box[2] - s(2.6), torso_box[1] + s(2.0), torso_box[2] - s(0.8), torso_box[3] - s(0.8)]
    d.rounded_rectangle(sh_box, radius=s(1.0), fill=shade(shirt, -0.30))

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

    result = finish(img).convert("RGBA")
    dither_ellipse(result, [cx - 5, 27, cx + 5, 30], (10, 8, 6, 90), (10, 8, 6, 40))
    return result


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

SKIN_A = (234, 190, 150, 255)
SKIN_B = (176, 126, 88, 255)

gen_character_set("player", shirt=(36, 168, 176, 255), skin=SKIN_A, hair=(70, 46, 28, 255))
gen_character_set("police", shirt=(30, 64, 168, 255), pants=(20, 24, 40, 255), hair=(24, 20, 20, 255), skin=SKIN_B)

gen_static_npc("npc_brown", shirt=(168, 108, 56, 255), skin=SKIN_A)
gen_static_npc("npc_red", shirt=(210, 54, 48, 255), skin=SKIN_B)
gen_static_npc("npc_purple", shirt=(150, 70, 200, 255), hair=(90, 62, 30, 255), skin=SKIN_A)
gen_static_npc("npc_grey", shirt=(140, 148, 158, 255), skin=SKIN_B)
gen_static_npc("npc_green", shirt=(60, 176, 96, 255), skin=SKIN_A)


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


def add_grain(img, seed, density, colors):
    import random
    rng = random.Random(seed)
    px = img.load()
    w, h = img.size
    n = int(w * h * density)
    for _ in range(n):
        x, y = rng.randrange(w), rng.randrange(h)
        c = rng.choice(colors)
        base = px[x, y]
        a = c[3] / 255.0
        px[x, y] = (
            int(base[0] * (1 - a) + c[0] * a),
            int(base[1] * (1 - a) + c[1] * a),
            int(base[2] * (1 - a) + c[2] * a),
            255,
        )


def gen_floor_tile():
    tw, th, sc = 32, 32, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (176, 132, 78, 255)
    d.rectangle([0, 0, tw * sc, th * sc], fill=base)
    board_h = 8
    for row, y in enumerate(range(0, th, board_h)):
        shade = (162, 118, 66, 255) if row % 2 == 0 else (190, 144, 86, 255)
        d.rectangle([0, y * sc, tw * sc, (y + board_h) * sc - int(sc * 0.35)], fill=shade)
        d.line([0, y * sc, tw * sc, y * sc], fill=(108, 76, 42, 220), width=max(1, sc // 6))
    small = img.resize((tw, th), Image.LANCZOS).convert("RGBA")
    add_grain(small, 1, 0.05, [(140, 100, 56, 200), (206, 164, 104, 160)])
    env_save(small, "floor_tile")


def gen_wall_tile():
    tw, th, sc = 32, 32, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (150, 78, 56, 255)
    mortar = (74, 46, 36, 255)
    brick = (172, 92, 62, 255)
    d.rectangle([0, 0, tw * sc, th * sc], fill=base)
    brick_h = 8
    brick_w = 16
    for row, y in enumerate(range(0, th, brick_h)):
        offset = 0 if row % 2 == 0 else brick_w // 2
        d.line([0, y * sc, tw * sc, y * sc], fill=mortar, width=max(1, sc // 5))
        x = -offset
        while x < tw:
            tone = brick if (x // brick_w) % 2 == 0 else shade(brick, 0.08)
            d.rectangle([x * sc, y * sc, (x + brick_w - 1) * sc, (y + brick_h - 1) * sc], fill=tone)
            d.line([(x + brick_w - 1) * sc, y * sc, (x + brick_w - 1) * sc, (y + brick_h) * sc],
                   fill=mortar, width=max(1, sc // 6))
            x += brick_w
    small = img.resize((tw, th), Image.LANCZOS).convert("RGBA")
    add_grain(small, 2, 0.04, [(120, 62, 44, 200), (200, 118, 84, 140)])
    env_save(small, "wall_tile")


def gen_wood_plank():
    tw, th, sc = 32, 16, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, tw * sc, th * sc], fill=(158, 104, 54, 255))
    for i, y in enumerate(range(0, th, 4)):
        tone = (142, 90, 44, 255) if i % 2 == 0 else (172, 116, 62, 255)
        d.rectangle([0, y * sc, tw * sc, (y + 4) * sc - int(sc * 0.3)], fill=tone)
    d.line([0, sc, tw * sc, sc], fill=(212, 160, 92, 180), width=max(1, sc // 6))
    small = img.resize((tw, th), Image.LANCZOS).convert("RGBA")
    add_grain(small, 3, 0.06, [(120, 76, 36, 200), (196, 142, 82, 160)])
    env_save(small, "wood_plank")


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
    d.rounded_rectangle([0, 0, w * sc, h * sc], radius=sc, fill=(150, 96, 46, 255), outline=outline, width=sc // 2)
    for x in (10, 20, 30):
        d.line([x * sc, 2 * sc, x * sc, (h - 2) * sc], fill=(112, 70, 32, 255), width=max(1, sc // 6))
    d.ellipse([(w - 8) * sc, (h / 2 - 1.5) * sc, (w - 5) * sc, (h / 2 + 1.5) * sc], fill=(230, 205, 110, 255))
    env_save(img.resize((w, h), Image.LANCZOS), "door")


# --- City street props --------------------------------------------------

def gen_road_tile():
    tw, th, sc = 32, 32, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, tw * sc, th * sc], fill=(58, 58, 64, 255))
    d.rectangle([0, 13 * sc, tw * sc, 15 * sc], fill=(210, 190, 90, 230))
    small = img.resize((tw, th), Image.LANCZOS).convert("RGBA")
    add_grain(small, 10, 0.06, [(40, 40, 46, 200), (78, 78, 86, 160)])
    env_save(small, "road_tile")


def gen_sidewalk_tile():
    tw, th, sc = 32, 32, 8
    img = Image.new("RGBA", (tw * sc, th * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, tw * sc, th * sc], fill=(158, 158, 150, 255))
    d.line([0, 0, tw * sc, 0], fill=(110, 110, 104, 255), width=max(1, sc // 5))
    d.line([0, 0, 0, th * sc], fill=(110, 110, 104, 255), width=max(1, sc // 5))
    small = img.resize((tw, th), Image.LANCZOS).convert("RGBA")
    add_grain(small, 11, 0.05, [(130, 130, 122, 200), (182, 182, 174, 160)])
    env_save(small, "sidewalk_tile")


def gen_streetlight():
    w, h, sc = 14, 56, 6
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (18, 18, 20, 255)
    d.rectangle([(w / 2 - 1.2) * sc, 14 * sc, (w / 2 + 1.2) * sc, h * sc], fill=(60, 62, 68, 255), outline=outline, width=sc // 3)
    d.ellipse([1 * sc, 0, (w - 1) * sc, 15 * sc], fill=(255, 226, 140, 235), outline=outline, width=sc // 3)
    d.ellipse([3 * sc, 3 * sc, (w - 3) * sc, 12 * sc], fill=(255, 244, 200, 255))
    env_save(img.resize((w, h), Image.LANCZOS), "streetlight")


def gen_car():
    w, h, sc = 34, 58, 6
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (16, 14, 18, 255)
    body = (196, 62, 58, 255)
    d.rounded_rectangle([1 * sc, 2 * sc, (w - 1) * sc, (h - 2) * sc], radius=6 * sc, fill=body, outline=outline, width=sc // 2)
    d.rounded_rectangle([4 * sc, 12 * sc, (w - 4) * sc, 30 * sc], radius=4 * sc, fill=(120, 168, 196, 235), outline=outline, width=sc // 3)
    d.line([4 * sc, 21 * sc, (w - 4) * sc, 21 * sc], fill=outline, width=sc // 3)
    for y in (8, h - 12):
        d.rounded_rectangle([0, y * sc, w * sc, (y + 5) * sc], radius=sc, fill=(24, 24, 28, 255))
    d.rounded_rectangle([2 * sc, 3 * sc, (w - 2) * sc, 7 * sc], radius=2 * sc, fill=shade(body, 0.25))
    env_save(img.resize((w, h), Image.LANCZOS), "car")


def gen_hydrant():
    w, h, sc = 14, 20, 8
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (60, 14, 12, 255)
    red = (208, 54, 42, 255)
    d.rounded_rectangle([3 * sc, 2 * sc, 11 * sc, 18 * sc], radius=3 * sc, fill=red, outline=outline, width=sc // 3)
    d.ellipse([2 * sc, 0, 12 * sc, 5 * sc], fill=shade(red, 0.2), outline=outline, width=sc // 4)
    d.ellipse([0, 7 * sc, 3 * sc, 11 * sc], fill=shade(red, -0.1), outline=outline, width=sc // 4)
    d.ellipse([11 * sc, 7 * sc, 14 * sc, 11 * sc], fill=shade(red, -0.1), outline=outline, width=sc // 4)
    env_save(img.resize((w, h), Image.LANCZOS), "hydrant")


def gen_dumpster():
    w, h, sc = 46, 30, 6
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (24, 40, 22, 255)
    green = (58, 92, 52, 255)
    d.rounded_rectangle([0, 6 * sc, w * sc, h * sc], radius=2 * sc, fill=green, outline=outline, width=sc // 3)
    d.rectangle([0, 2 * sc, w * sc, 8 * sc], fill=shade(green, 0.22), outline=outline, width=sc // 3)
    for x in range(4, w - 4, 8):
        d.line([x * sc, 9 * sc, x * sc, (h - 2) * sc], fill=shade(green, -0.2), width=sc // 4)
    env_save(img.resize((w, h), Image.LANCZOS), "dumpster")


def gen_window():
    w, h, sc = 22, 26, 8
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (40, 30, 20, 255)
    d.rounded_rectangle([0, 0, w * sc, h * sc], radius=sc, fill=(70, 50, 32, 255), outline=outline, width=sc // 2)
    d.rectangle([3 * sc, 3 * sc, (w - 3) * sc, (h - 3) * sc], fill=(255, 214, 120, 235))
    d.line([w / 2 * sc, 3 * sc, w / 2 * sc, (h - 3) * sc], fill=outline, width=sc // 3)
    d.line([3 * sc, h / 2 * sc, (w - 3) * sc, h / 2 * sc], fill=outline, width=sc // 3)
    env_save(img.resize((w, h), Image.LANCZOS), "window")


gen_floor_tile()
gen_wall_tile()
gen_wood_plank()
gen_bed()
gen_phone()
gen_tv()
gen_trash()
gen_door()
gen_road_tile()
gen_sidewalk_tile()
gen_streetlight()
gen_car()
gen_hydrant()
gen_dumpster()
gen_window()

print("done:", sorted(os.listdir(OUT)))
print("env done:", sorted(os.listdir(ENV_OUT)))
