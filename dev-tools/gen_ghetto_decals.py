#!/usr/bin/env python3
"""Ghetto Wars' set textures (assets/ghetto/), all procedural -- nothing to licence, and
the crews' marks are our own designs (a crown, an anchor), no real gang's symbols:

  tag_kings_crown / tag_kings_word   EASTSIDE KINGS: gold on purple
  tag_dock_anchor / tag_dock_word    DOCK BOYS: acid green on olive
  tag_xout_kings / tag_xout_dock     a crew crossing out the other's mark
  window_smash                       a shop window kicked in (decal on the front)
  glass_shards                       what's on the pavement under it
  tape_police                        hazard tape, tiled along its length

    /home/anders/dopesick-game/.venv-portraits/bin/python3 dev-tools/gen_ghetto_decals.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ghetto")
os.makedirs(OUT, exist_ok=True)
rng = random.Random(77)
nrng = np.random.default_rng(77)
TAG_FONT = "/usr/share/fonts/truetype/ubuntu/Ubuntu-BI.ttf"
TAPE_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

GOLD, PURPLE = (244, 196, 48), (92, 30, 150)
TEAL, ORANGE = (172, 214, 52), (46, 70, 12)  # Dock Boys: acid green on dark olive (their clothes are olive with a yellow band)


def noise(w, h, scale, octaves=4):
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


def spray(draw_shape, fill, outline, name, size, drips=7, line=14):
    """draw_shape(draw, color, grow) paints the mark; this puts the paint on: overspray halo, outline,
    fill, drips, worn patches."""
    w, h = size
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    draw_shape(ImageDraw.Draw(halo), outline + (105,), line * 2)
    halo = halo.filter(ImageFilter.GaussianBlur(13))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    draw_shape(d, outline + (255,), line)
    draw_shape(d, fill + (255,), 0)
    alpha = np.array(layer)[:, :, 3]
    cols = np.where(alpha.max(axis=0) > 200)[0]
    for _ in range(drips):
        if len(cols) == 0:
            break
        cx = int(rng.choice(cols))
        bottom = int(np.where(alpha[:, cx] > 200)[0].max())
        length = rng.randint(24, 120)
        c = outline + (235,) if rng.random() < 0.6 else fill + (235,)
        d.line([(cx, bottom), (cx, min(h - 4, bottom + length))], fill=c, width=rng.randint(3, 6))
        d.ellipse([cx - 4, bottom + length - 4, cx + 4, bottom + length + 4], fill=c)
    img = Image.alpha_composite(halo, layer).filter(ImageFilter.GaussianBlur(1.1))
    a = np.array(img).astype(np.float32)
    wear = noise(w, h, 6)
    a[:, :, 3] *= np.clip((wear - 0.15) * 2.6, 0.62, 1.0)
    save(Image.fromarray(a.astype(np.uint8)), name)


def crown(d, col, g):
    # A five-pointed crown: band, three peaks with ball tips, jewels on the band.
    pts = [(100, 350), (82, 160), (180, 258), (256, 118), (332, 258), (430, 160), (412, 350)]
    d.polygon(pts, fill=col)
    if g:
        d.line(pts + [pts[0]], fill=col, width=g * 2, joint="curve")
    d.rounded_rectangle([88 - g, 340 - g, 424 + g, 410 + g], radius=14, fill=col)
    for cx, cy in ((82, 146), (256, 104), (430, 146)):
        d.ellipse([cx - 26 - g, cy - 26 - g, cx + 26 + g, cy + 26 + g], fill=col)
    if not g:
        for cx in (170, 256, 342):
            d.polygon([(cx, 352), (cx + 22, 375), (cx, 398), (cx - 22, 375)], fill=PURPLE + (255,))


def anchor(d, col, g):
    w = 30 + g
    d.ellipse([256 - 40 - g // 2, 70 - g // 2, 256 + 40 + g // 2, 150 + g // 2], outline=col, width=20 + g // 2)
    d.line([(256, 140), (256, 420)], fill=col, width=w)
    d.line([(184, 186), (328, 186)], fill=col, width=26 + g)
    d.arc([104, 200, 408, 456], 0, 180, fill=col, width=w)
    for sx in (-1, 1):
        tip = (256 + sx * 152, 330)
        d.polygon([(tip[0] - sx * 38, tip[1] - 10), (tip[0] + sx * 14, tip[1] - 70 - g // 2), (tip[0] + sx * 38, tip[1] + 20 + g // 2)], fill=col)


def word(text):
    def draw(d, col, g):
        size = 280
        while True:
            font = ImageFont.truetype(TAG_FONT, size)
            bbox = d.textbbox((0, 0), text, font=font, stroke_width=g)
            if bbox[2] - bbox[0] < 930:
                break
            size -= 8
        x = (1024 - (bbox[2] - bbox[0])) // 2 - bbox[0]
        y = (384 - (bbox[3] - bbox[1])) // 2 - bbox[1]
        d.text((x, y), text, font=font, fill=col, stroke_width=g, stroke_fill=col)
    return draw


def xout(fill, edge):
    def draw(d, col, g):
        wd = 70 + g
        d.line([(60, 70), (450, 450)], fill=col, width=wd)
        d.line([(450, 60), (62, 452)], fill=col, width=wd)
    return draw


def window_smash():
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 250, 260
    # The hole: a ragged shape, dark behind it.
    pts = []
    for i in range(18):
        a = i / 18 * math.tau
        r = rng.uniform(55, 120) * (1.25 if i % 2 else 0.8)
        pts.append((cx + math.cos(a) * r * 1.2, cy + math.sin(a) * r))
    d.polygon(pts, fill=(8, 8, 10, 245))
    for a, b in zip(pts, pts[1:] + pts[:1]):
        d.line([a, b], fill=(225, 235, 240, 235), width=3)
    # Cracks: spokes with kinks, and rings joining them.
    spokes = []
    for i in range(14):
        a = i / 14 * math.tau + rng.uniform(-0.15, 0.15)
        pt = (cx, cy)
        path = [pt]
        r = 0
        while r < rng.uniform(170, 250):
            r += rng.uniform(25, 55)
            a += rng.uniform(-0.12, 0.12)
            pt = (cx + math.cos(a) * r * 1.1, cy + math.sin(a) * r)
            path.append(pt)
        spokes.append(path)
        d.line(path, fill=(220, 232, 238, 210), width=2)
    for k in (2, 3, 4):
        ring = [s[k] for s in spokes if len(s) > k]
        for a, b in zip(ring, ring[1:]):
            d.line([a, b], fill=(220, 232, 238, 150), width=1)
    # Teeth of glass left in the frame below.
    for x in range(40, 470, 26):
        h = rng.randint(10, 46)
        d.polygon([(x, size - 4), (x + 13, size - 4 - h), (x + 26, size - 4)], fill=(190, 215, 225, 150))
    save(img.filter(ImageFilter.GaussianBlur(0.6)), "window_smash.png")


def glass_shards():
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(190):
        x = int(np.clip(nrng.normal(size / 2, 105), 8, size - 8))
        y = int(np.clip(nrng.normal(size / 2, 80), 8, size - 8))
        s = rng.randint(3, 15)
        pts = [(x + rng.randint(-s, s), y + rng.randint(-s, s)) for _ in range(3)]
        v = rng.randint(190, 255)
        d.polygon(pts, fill=(v - 25, v, v, rng.randint(70, 215)))
    save(img.filter(ImageFilter.GaussianBlur(0.5)), "glass_shards.png")


def tape():
    w, h = 1024, 64
    img = Image.new("RGBA", (w, h), (236, 196, 18, 255))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(TAPE_FONT, 40)
    text = "POLICE LINE  DO NOT CROSS  "
    x = 4
    while x < w:
        d.text((x, 10), text, font=f, fill=(20, 18, 10, 255))
        x += int(d.textlength(text, font=f))
    d.rectangle([0, 0, w, 5], fill=(20, 18, 10, 255))
    d.rectangle([0, h - 6, w, h], fill=(20, 18, 10, 255))
    a = np.array(img).astype(np.float32)
    a[:, :, :3] *= (0.8 + 0.2 * noise(w, h, 5))[..., None]
    save(Image.fromarray(a.astype(np.uint8)), "tape_police.png")


if __name__ == "__main__":
    spray(crown, GOLD, PURPLE, "tag_kings_crown.png", (512, 512), 6)
    spray(word("EASTSIDE KINGS"), GOLD, PURPLE, "tag_kings_word.png", (1024, 384), 9, 12)
    spray(anchor, TEAL, ORANGE, "tag_dock_anchor.png", (512, 512), 6)
    spray(word("DOCK BOYS"), TEAL, ORANGE, "tag_dock_word.png", (1024, 384), 9, 12)
    spray(xout(TEAL, ORANGE), TEAL, ORANGE, "tag_xout_dock.png", (512, 512), 4, 8)
    spray(xout(PURPLE, PURPLE), PURPLE, (14, 6, 24), "tag_xout_kings.png", (512, 512), 4, 8)
    window_smash()
    glass_shards()
    tape()
