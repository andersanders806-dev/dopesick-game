#!/usr/bin/env python3
"""Generates the street's decal textures (assets/decals/), all procedural so
there's nothing to license: spray-painted tags with overspray and drips,
torn flyers, grime streaks down the shop fronts, gum and coffee stains,
cracks, litter, oil patches, and puddles (with an ORM map so they come out
glossy and catch the neon). world/StreetDressing.gd places them.

    .venv-portraits/bin/python3 dev-tools/gen_street_decals.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "decals")
os.makedirs(OUT, exist_ok=True)
rng = random.Random(9)
nrng = np.random.default_rng(9)
TAG_FONT = "/usr/share/fonts/truetype/ubuntu/Ubuntu-BI.ttf"
FLYER_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FLYER_BODY = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def noise(w, h, scale, octaves=4):
    """Smooth value noise in 0..1."""
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        small = nrng.random((s, s))
        big = np.array(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255.0
        out += big * amp
        total += amp
        amp *= 0.5
    return out / total


def save(img, name):
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name)


def fit_font(path, text, max_w, start, stroke=0):
    size = start
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    while size > 10:
        font = ImageFont.truetype(path, size)
        b = probe.textbbox((0, 0), text, font=font, stroke_width=stroke)
        if b[2] - b[0] <= max_w:
            return font
        size -= 4
    return ImageFont.truetype(path, size)


def tag(text, fill, outline, name, size=(1024, 512)):
    """A spray-painted piece: soft overspray halo, outline, fill, drips."""
    w, h = size
    font = fit_font(TAG_FONT, text, w * 0.84, int(h * 0.55), 14)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bbox = d.textbbox((0, 0), text, font=font, stroke_width=14)
    x = (w - (bbox[2] - bbox[0])) // 2 - bbox[0]
    y = (h - (bbox[3] - bbox[1])) // 2 - bbox[1]
    # Overspray: the outline colour, blurred wide and faint.
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).text((x, y), text, font=font, fill=outline + (110,), stroke_width=26, stroke_fill=outline + (110,))
    halo = halo.filter(ImageFilter.GaussianBlur(14))
    d.text((x, y), text, font=font, fill=fill + (255,), stroke_width=12, stroke_fill=outline + (255,))
    # Drips from the bottom of the fill.
    alpha = np.array(layer)[:, :, 3]
    cols = np.where(alpha.max(axis=0) > 200)[0]
    for _ in range(9):
        if len(cols) == 0:
            break
        cx = int(rng.choice(cols))
        bottom = int(np.where(alpha[:, cx] > 200)[0].max())
        length = rng.randint(20, 110)
        d.line([(cx, bottom), (cx, min(h - 4, bottom + length))], fill=outline + (235,), width=rng.randint(3, 6))
        d.ellipse([cx - 4, bottom + length - 4, cx + 4, bottom + length + 4], fill=outline + (235,))
    img = Image.alpha_composite(halo, layer)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    # Weathering: knock patches out so it reads as old paint on brick.
    a = np.array(img).astype(np.float32)
    wear = noise(w, h, 6)
    a[:, :, 3] *= np.clip((wear - 0.28) * 2.2, 0.35, 1.0)
    save(Image.fromarray(a.astype(np.uint8)), name)


def circle_a(name):
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = (225, 30, 40, 255)
    d.ellipse([40, 40, 472, 472], outline=col, width=34)
    d.line([(150, 440), (256, 60), (362, 440)], fill=col, width=40, joint="curve")
    d.line([(130, 300), (382, 280)], fill=col, width=36)
    for cx in (150, 362, 256):
        d.line([(cx, 440), (cx, 440 + rng.randint(20, 60))], fill=col, width=6)
    img = img.filter(ImageFilter.GaussianBlur(1.5))
    save(img, name)


def flyer(lines, paper, ink, name):
    w, h = 384, 512
    img = Image.new("RGBA", (w, h), paper + (255,))
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(FLYER_FONT, 58)
    small = ImageFont.truetype(FLYER_BODY, 26)
    y = 40
    big = fit_font(FLYER_FONT, lines[0], w * 0.88, 58)
    for i, line in enumerate(lines):
        font = big if i == 0 else small
        tw = d.textlength(line, font=font)
        d.text(((w - tw) / 2, y), line, font=font, fill=ink)
        y += 80 if i == 0 else 38
    # Tear-off tabs along the bottom, some already gone.
    for i in range(8):
        x0 = 12 + i * 45
        if rng.random() < 0.4:
            d.rectangle([x0, h - 70, x0 + 40, h], fill=(0, 0, 0, 0))
        else:
            d.line([(x0 + 42, h - 70), (x0 + 42, h)], fill=ink, width=2)
    # Grime and a torn edge.
    a = np.array(img).astype(np.float32)
    n = noise(w, h, 5)
    a[:, :, :3] *= (0.7 + 0.3 * n)[..., None]
    edge = noise(w, h, 12, 2)
    border = np.minimum.reduce([np.arange(w)[None, :].repeat(h, 0), (w - 1 - np.arange(w))[None, :].repeat(h, 0),
                                np.arange(h)[:, None].repeat(w, 1), (h - 1 - np.arange(h))[:, None].repeat(w, 1)])
    a[:, :, 3] *= (border > edge * 26).astype(np.float32)
    save(Image.fromarray(a.astype(np.uint8)), name)


def blotch(name, size, color, scale, threshold, soft=6, streak=False):
    w, h = size
    n = noise(w, h, scale)
    if streak:
        # Grime runs down: stretch vertically and fade toward the top.
        n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h // 6)).resize((w, h), Image.BICUBIC)) / 255.0
        n *= np.linspace(0.4, 1.2, h)[:, None]
    yy, xx = np.mgrid[0:h, 0:w]
    fall = 1.0 - np.clip(np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)), 0, 1) ** 2
    if streak:
        fall = np.clip(np.minimum(xx, w - xx) / (w * 0.15), 0, 1)
    a = np.clip((n * fall - threshold) * soft, 0, 1)
    img = np.zeros((h, w, 4), np.uint8)
    img[:, :, :3] = color
    img[:, :, 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(img), name)


def crack(name):
    w, h = 512, 512
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def branch(x, y, ang, length, width):
        for _ in range(length):
            nx = x + math.cos(ang) * 6
            ny = y + math.sin(ang) * 6
            d.line([(x, y), (nx, ny)], fill=(12, 12, 12, 230), width=max(1, int(width)))
            x, y = nx, ny
            ang += rng.uniform(-0.45, 0.45)
            width *= 0.985
            if rng.random() < 0.04 and width > 1.5:
                branch(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.2), length // 2, width * 0.6)
    branch(40, 260, 0.0, 75, 5)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    save(img, name)


def litter(name):
    w, h = 512, 256
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(14):
        x, y = rng.randint(30, w - 60), rng.randint(30, h - 40)
        kind = rng.random()
        if kind < 0.35:  # cigarette butts
            ang = rng.uniform(0, math.pi)
            ex, ey = x + math.cos(ang) * 22, y + math.sin(ang) * 22
            d.line([(x, y), (ex, ey)], fill=(230, 225, 210, 255), width=6)
            d.line([(x, y), (x + math.cos(ang) * 8, y + math.sin(ang) * 8)], fill=(200, 140, 60, 255), width=6)
        elif kind < 0.7:  # scraps of paper and receipts
            pts = [(x + rng.randint(-26, 26), y + rng.randint(-18, 18)) for _ in range(5)]
            shade = rng.randint(170, 235)
            d.polygon(pts, fill=(shade, shade, shade - 12, 235))
        elif kind < 0.85:  # a bottle cap
            d.ellipse([x, y, x + 14, y + 14], fill=(160, 160, 150, 255), outline=(90, 90, 85, 255))
        else:  # a flattened can
            d.rounded_rectangle([x, y, x + 40, y + 18], 5, fill=(180, 30, 35, 255), outline=(120, 120, 120, 255))
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    save(img, name)


def puddle(name):
    w, h = 512, 512
    n = noise(w, h, 4)
    yy, xx = np.mgrid[0:h, 0:w]
    fall = 1.0 - np.clip(np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)), 0, 1) ** 1.5
    a = np.clip((n * fall - 0.22) * 9.0, 0, 1)
    img = np.zeros((h, w, 4), np.uint8)
    img[:, :, 0], img[:, :, 1], img[:, :, 2] = 18, 22, 28
    img[:, :, 3] = (a * 210).astype(np.uint8)
    save(Image.fromarray(img), name)
    # ORM: occlusion 1, roughness near 0 where wet, not metallic.
    orm = np.zeros((h, w, 3), np.uint8)
    orm[:, :, 0] = 255
    orm[:, :, 1] = (255 * (1.0 - 0.95 * a)).astype(np.uint8)
    save(Image.fromarray(orm), name.replace(".png", "_orm.png"))


tag("NO FUTURE", (240, 60, 130), (20, 20, 25), "tag_nofuture.png")
tag("DSK", (70, 220, 230), (25, 20, 60), "tag_dsk.png", (768, 512))
tag("BLOCK 9", (250, 220, 60), (120, 20, 20), "tag_block9.png")
tag("EAT THE RICH", (235, 235, 230), (200, 30, 40), "tag_eattherich.png", (1280, 512))
circle_a("tag_circle_a.png")
flyer(["LOST DOG", "answers to Biscuit", "last seen by the", "laundromat", "PLEASE CALL"], (238, 234, 210), (30, 30, 30), "flyer_lostdog.png")
flyer(["WE BUY", "GOLD", "cash today", "no questions", "PAWN - on the block"], (250, 220, 70), (20, 20, 20), "flyer_gold.png")
flyer(["LIVE TONITE", "THE SICKNESS", "+ NO FUTURE", "the basement", "$3 at the door"], (230, 60, 110), (15, 15, 15), "flyer_gig.png")
flyer(["NEED HELP?", "free & confidential", "harm reduction", "naloxone kits", "ask at the shelter"], (200, 225, 240), (20, 40, 70), "flyer_help.png")
blotch("grime_streak.png", (512, 1024), (10, 10, 8), 5, 0.25, soft=2.2, streak=True)
blotch("stain_dark.png", (512, 512), (14, 12, 10), 5, 0.3, soft=4.0)
blotch("stain_coffee.png", (256, 256), (60, 40, 20), 3, 0.35, soft=5.0)
blotch("stain_oil.png", (512, 512), (6, 6, 8), 4, 0.25, soft=5.0)
crack("crack.png")
litter("litter.png")
puddle("puddle.png")
