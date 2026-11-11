#!/usr/bin/env python3
"""Procedural textures and one sound for the parked cars (world/ParkedRow.gd):
the soft contact shadow with tyre patches under every car, a parking notice
in a plastic sleeve, a hand-lettered FOR SALE card, a pine air freshener, and
the double-parked van's hazard relay. All generated, nothing to license.

    .venv-portraits/bin/python3 dev-tools/gen_car_props.py
"""
import math
import os
import random
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEC = os.path.join(ROOT, "assets", "decals")
SFX = os.path.join(ROOT, "assets", "sfx")
rng = random.Random(77)
nrng = np.random.default_rng(77)
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def contact_shadow():
    """Top-down, x along the car. A broad soft AO blob, darker under the
    sills and the tyre patches (the wheels sit at +-0.27 of the decal's
    length and +-0.32 of its width: ParkedRow sizes the decal to match)."""
    w, h = 512, 256
    a = np.zeros((h, w), dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xx / w - 0.5) * 2.0
    v = (yy / h - 0.5) * 2.0
    # rounded box, soft edge
    d = np.maximum(np.abs(u) / 0.88, np.abs(v) / 0.82)
    d = np.power(np.power(np.abs(u) / 0.88, 4) + np.power(np.abs(v) / 0.82, 4), 0.25)
    a = np.clip(1.0 - d, 0, 1) ** 0.7 * 0.55
    # darker core under the body
    core = np.clip(1.0 - np.power(np.power(np.abs(u) / 0.72, 4) + np.power(np.abs(v) / 0.55, 4), 0.25), 0, 1)
    a += core * 0.3
    for sx in (-0.268, 0.268):
        for sz in (-0.32, 0.32):
            cx, cz = (0.5 + sx / 2.0) * w, (0.5 + sz / 2.0) * h
            g = np.exp(-(((xx - cx) / 34.0) ** 2 + ((yy - cz) / 20.0) ** 2))
            a += g * 0.45
    n = nrng.random((h // 8, w // 8)).astype(np.float32)
    n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255.0
    a *= 0.85 + 0.3 * n
    a = np.clip(a, 0, 0.92)
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[..., 0:3] = (8, 7, 6)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(DEC, "car_shadow.png"), optimize=True)


def paper_noise(img, amt=14):
    arr = np.array(img).astype(np.int16)
    n = nrng.normal(0, amt, arr.shape[:2])[..., None]
    arr[..., :3] = np.clip(arr[..., :3] + n, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), img.mode)


def ticket():
    """A parking notice: orange header, boxes, a scrawl, in a creased plastic sleeve."""
    w, h = 256, 160
    im = Image.new("RGBA", (w, h), (236, 232, 218, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, 38], fill=(224, 120, 30, 255))
    d.text((10, 6), "PARKING", font=ImageFont.truetype(BOLD, 22), fill=(40, 20, 10, 255))
    d.text((120, 9), "NOTICE", font=ImageFont.truetype(BOLD, 18), fill=(40, 20, 10, 255))
    f = ImageFont.truetype(REG, 11)
    for i, t in enumerate(["VIOLATION", "PLATE", "DATE / TIME", "FINE"]):
        y = 46 + i * 24
        d.text((10, y), t, font=f, fill=(60, 60, 60, 255))
        d.line([(86, y + 13), (w - 12, y + 13)], fill=(90, 90, 90, 255), width=1)
    d.line([(92, 104), (150, 98), (190, 106), (232, 100)], fill=(30, 40, 120, 255), width=2)
    d.line([(92, 128), (130, 124), (170, 130)], fill=(30, 40, 120, 255), width=2)
    d.rectangle([w - 70, 134, w - 10, 152], outline=(190, 40, 30, 255), width=2)
    im = paper_noise(im)
    # sleeve: a glossy diagonal crease
    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.polygon([(0, 70), (60, 0), (80, 0), (0, 100)], fill=(255, 255, 255, 40))
    od.line([(w, 40), (0, 150)], fill=(255, 255, 255, 30), width=3)
    im = Image.alpha_composite(im, ov).filter(ImageFilter.GaussianBlur(0.4))
    im.save(os.path.join(DEC, "car_ticket.png"), optimize=True)


def forsale():
    """Cardboard, marker lettering, a torn corner."""
    w, h = 320, 200
    im = Image.new("RGBA", (w, h), (186, 150, 104, 255))
    arr = np.array(im).astype(np.int16)
    streak = (np.sin(np.arange(w) * 0.9 + nrng.random() * 6) * 6)[None, :, None]
    arr[..., :3] = np.clip(arr[..., :3] + streak + nrng.normal(0, 6, (h, w, 1)), 0, 255)
    im = Image.fromarray(arr.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(im)
    ink = (28, 30, 40, 255)
    red = (170, 30, 24, 255)
    fb = ImageFont.truetype(BOLD, 62)
    for ch, x in zip("FOR", (22, 92, 160)):
        d.text((x + rng.randint(-2, 2), 14 + rng.randint(-3, 3)), ch, font=fb, fill=red)
    fs = ImageFont.truetype(BOLD, 70)
    d.text((22, 70), "SALE", font=fs, fill=red)
    d.text((34, 150), "$800 OBO  555-0188", font=ImageFont.truetype(BOLD, 27), fill=ink)
    # torn corner and tape
    d.polygon([(w, 0), (w - 36, 0), (w, 30)], fill=(0, 0, 0, 0))
    d.rectangle([w // 2 - 28, 0, w // 2 + 28, 12], fill=(215, 205, 160, 200))
    im = im.filter(ImageFilter.GaussianBlur(0.5))
    im.save(os.path.join(DEC, "car_forsale.png"), optimize=True)


def pine():
    """A pine-tree air freshener, faded, on its string."""
    w, h = 96, 160
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line([(w // 2, 0), (w // 2, 30)], fill=(210, 210, 200, 255), width=2)
    d.ellipse([w // 2 - 5, 24, w // 2 + 5, 34], outline=(210, 210, 200, 255), width=2)
    green = (70, 120, 60, 255)
    d.polygon([(48, 34), (16, 84), (80, 84)], fill=green)
    d.polygon([(48, 62), (8, 118), (88, 118)], fill=green)
    d.polygon([(48, 92), (2, 150), (94, 150)], fill=green)
    d.rectangle([44, 150, 52, 160], fill=(90, 62, 40, 255))
    im = paper_noise(im, 10)
    im.save(os.path.join(DEC, "car_pine.png"), optimize=True)


def hazard_relay():
    """The flasher relay: a dry tick on, a softer tock off, 1.2 s loop (about 50 flashes a minute)."""
    sr = 22050
    n = int(sr * 1.2)
    out = np.zeros(n, dtype=np.float32)

    def click(at, amp, f):
        i0 = int(at * sr)
        t = np.arange(int(0.05 * sr)) / sr
        env = np.exp(-t * 180.0)
        sig = (np.sin(2 * math.pi * f * t) * 0.6 + nrng.normal(0, 0.5, t.size)) * env * amp
        out[i0:i0 + t.size] += sig[: n - i0]

    click(0.0, 0.9, 2300)
    click(0.012, 0.4, 900)
    click(0.6, 0.6, 1700)
    click(0.612, 0.3, 700)
    out = np.clip(out * 0.6, -1, 1)
    with wave.open(os.path.join(SFX, "hazard_relay_loop.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes((out * 32767).astype(np.int16).tobytes())


if __name__ == "__main__":
    contact_shadow()
    ticket()
    forsale()
    pine()
    hazard_relay()
    print("done")
