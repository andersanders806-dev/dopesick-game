#!/usr/bin/env python3
"""Packaging for the corner shop: label textures drawn for Dope Sick (invented brands, DejaVu Sans Bold:
Bitstream Vera licence), written to assets/items/labels/. Boxes get a 3x2 sheet (Godot's BoxMesh
lays its six faces out in 3 columns x 2 rows, so every face carries the design); cans get one wrap.

  python3 dev-tools/gen_product_labels.py
"""
import os, random
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "items", "labels")
os.makedirs(OUT, exist_ok=True)
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
CELL = 256

def font(size, bold=True):
    return ImageFont.truetype(BOLD if bold else REG, size)

def center(d, text, y, f, fill, w=CELL, x0=0, stroke=0, stroke_fill=None):
    box = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
    d.text((x0 + (w - (box[2] - box[0])) / 2 - box[0], y), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)

def barcode(d, x, y, w, h, rnd):
    d.rectangle([x - 4, y - 4, x + w + 4, y + h + 4], fill=(240, 240, 235))
    cx = x
    while cx < x + w:
        bw = rnd.choice([1, 1, 2, 3])
        d.rectangle([cx, y, cx + bw - 1, y + h], fill=(20, 20, 20))
        cx += bw + rnd.choice([1, 2, 2, 3])

def cell(brand, sub, bg, band, fg, accent, rnd, kind="box"):
    im = Image.new("RGB", (CELL, CELL), bg)
    d = ImageDraw.Draw(im)
    # a soft vertical shade and a worn edge so it reads as printed card, not a flat swatch
    for y in range(CELL):
        k = int(18 * (y / CELL))
        d.line([(0, y), (CELL, y)], fill=tuple(max(0, c - k) for c in bg))
    d.rectangle([0, 0, CELL, 52], fill=band)
    center(d, brand, 6, font(34 if len(brand) < 9 else 26), fg, stroke=1, stroke_fill=(0, 0, 0))
    d.polygon([(0, 52), (CELL, 52), (CELL, 64), (0, 74)], fill=accent)
    center(d, sub, 92, font(22), fg if sum(bg) < 380 else (30, 30, 30), stroke=0)
    d.ellipse([CELL / 2 - 46, 122, CELL / 2 + 46, 214], fill=accent, outline=fg, width=4)
    center(d, brand[0], 134, font(64), fg)
    barcode(d, 24, 224, 100, 22, rnd)
    d.text((140, 226), "NET WT 250g", font=font(13, False), fill=(235, 235, 235) if sum(bg) < 380 else (40, 40, 40))
    return im

PRODUCTS = [
    ("northstar", "NORTHSTAR", "FILTER KINGS 20", (245, 245, 240), (190, 25, 25), (255, 255, 255), (30, 30, 150)),
    ("crunchies", "CRUNCHIES", "SALT & VINEGAR", (245, 205, 40), (200, 40, 30), (255, 255, 255), (40, 120, 60)),
    ("fizz", "FIZZ COLA", "ORIGINAL TASTE", (200, 30, 35), (30, 30, 30), (255, 255, 255), (245, 245, 245)),
    ("peak", "PEAK", "ENERGY DRINK", (20, 20, 22), (60, 200, 40), (255, 255, 255), (60, 200, 40)),
    ("volt", "VOLT", "ALKALINE AA x4", (30, 70, 160), (230, 150, 40), (255, 255, 255), (230, 150, 40)),
    ("minty", "MINTY", "FRESH GUM", (40, 170, 170), (20, 110, 120), (255, 255, 255), (255, 255, 255)),
    ("noodle", "NOODLE-UP", "CHICKEN FLAVOUR", (235, 120, 30), (150, 40, 20), (255, 255, 255), (255, 220, 80)),
    ("cocoa", "CHOCO", "MILK BAR", (110, 60, 35), (70, 35, 20), (255, 235, 200), (235, 190, 60)),
    ("dairy", "DAIRY", "SEMI-SKIMMED 1L", (245, 245, 250), (40, 100, 190), (255, 255, 255), (40, 100, 190)),
    ("oats", "OAT CRISP", "BREAKFAST CEREAL", (240, 215, 120), (190, 80, 40), (255, 255, 255), (190, 80, 40)),
]

for name, brand, sub, bg, band, fg, accent in PRODUCTS:
    rnd = random.Random(name)
    sheet = Image.new("RGB", (CELL * 3, CELL * 2))
    for i in range(6):
        sheet.paste(cell(brand, sub, bg, band, fg, accent, random.Random(name + str(i))), ((i % 3) * CELL, (i // 3) * CELL))
    sheet.save(os.path.join(OUT, name + "_box.png"))

# Held / shelf models: the carton, the AA blister, the charger, the shades card, two cans.
def single(name, im):
    im.save(os.path.join(OUT, name + ".png"))

def sheet_of(maker):
    s = Image.new("RGB", (CELL * 3, CELL * 2))
    for i in range(6):
        s.paste(maker(i), ((i % 3) * CELL, (i // 3) * CELL))
    return s

# cigarette carton: white with a red band and a crest
def carton(i):
    im = Image.new("RGB", (CELL, CELL), (240, 240, 236))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, CELL, 84], fill=(185, 25, 28))
    center(d, "NORTHSTAR", 14, font(36), (255, 255, 255), stroke=1, stroke_fill=(90, 0, 0))
    center(d, "FILTER KINGS", 54, font(20), (255, 220, 220))
    d.polygon([(CELL / 2, 100), (CELL / 2 + 38, 150), (CELL / 2, 200), (CELL / 2 - 38, 150)], fill=(185, 25, 28))
    center(d, "N", 120, font(54), (255, 255, 255))
    center(d, "10 x 20 CIGARETTES", 208, font(17), (40, 40, 40))
    d.rectangle([0, 238, CELL, CELL], fill=(190, 190, 185))
    center(d, "SMOKING KILLS", 238, font(14), (30, 30, 30))
    return im
single("cigs_box", sheet_of(carton))

def aa(i):
    im = Image.new("RGB", (CELL, CELL), (28, 60, 150))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, CELL, 70], fill=(18, 40, 110))
    center(d, "VOLT", 8, font(52), (250, 170, 40), stroke=2, stroke_fill=(10, 20, 60))
    center(d, "ALKALINE  AA x4", 78, font(24), (255, 255, 255))
    for k in range(4):
        x = 36 + k * 48
        d.rectangle([x, 120, x + 28, 215], fill=(235, 165, 45))
        d.rectangle([x, 120, x + 28, 150], fill=(25, 25, 25))
    center(d, "LONG LASTING POWER", 224, font(15), (230, 235, 255))
    return im
single("batteries_box", sheet_of(aa))

def charger(i):
    im = Image.new("RGB", (CELL, CELL), (238, 238, 234))
    d = ImageDraw.Draw(im)
    center(d, "USB-C", 70, font(60), (40, 40, 44))
    center(d, "5V 2A  FAST CHARGE", 150, font(22), (90, 90, 95))
    d.rectangle([20, 20, CELL - 20, CELL - 20], outline=(190, 190, 185), width=4)
    return im
single("charger_box", sheet_of(charger))

def shades(i):
    im = Image.new("RGB", (CELL, CELL), (235, 230, 220))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, CELL, 56], fill=(30, 30, 34))
    center(d, "SHADES", 6, font(40), (250, 220, 90))
    d.ellipse([30, 90, 118, 150], fill=(25, 25, 28)); d.ellipse([138, 90, 226, 150], fill=(25, 25, 28))
    d.rectangle([118, 104, 138, 112], fill=(25, 25, 28))
    center(d, "UV400  POLARISED", 170, font(18), (40, 40, 40))
    d.rectangle([60, 200, 196, 236], fill=(250, 220, 90)); center(d, "$ 16", 202, font(28), (30, 30, 30))
    return im
single("sunglasses_box", sheet_of(shades))

def can(name, bg, fg, accent, word, sub):
    im = Image.new("RGB", (CELL * 2, CELL), bg)
    d = ImageDraw.Draw(im)
    for x in range(0, CELL * 2, 32):
        d.polygon([(x, 0), (x + 16, 0), (x + 48, CELL), (x + 32, CELL)], fill=tuple(min(255, c + 12) for c in bg))
    d.rectangle([0, 0, CELL * 2, 22], fill=(190, 190, 195)); d.rectangle([0, CELL - 22, CELL * 2, CELL], fill=(190, 190, 195))
    for ox in (0, CELL):
        center(d, word, 70, font(60), fg, w=CELL, x0=ox, stroke=3, stroke_fill=(0, 0, 0))
        d.polygon([(ox + 112, 150), (ox + 152, 150), (ox + 134, 182), (ox + 160, 182), (ox + 106, 236), (ox + 124, 192), (ox + 100, 192)], fill=accent)
        center(d, sub, 34, font(16), (230, 230, 230), w=CELL, x0=ox)
    im.save(os.path.join(OUT, name + ".png"))
can("can_peak", (22, 22, 24), (80, 215, 50), (80, 215, 50), "PEAK", "ENERGY DRINK 250ml")
can("can_nitro", (30, 120, 40), (255, 255, 255), (255, 235, 60), "NITRO", "ENERGY DRINK 250ml")
print("labels in", OUT)
