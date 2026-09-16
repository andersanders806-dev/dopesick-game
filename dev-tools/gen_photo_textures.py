#!/usr/bin/env python3
"""Fetches photoreal top-down material photos from Pollinations.ai (free,
no key), crops a clean well-lit patch away from the corner watermark, and
seam-blends it into a tileable texture. Writes straight into
dopesick-game/assets/env/, overwriting the matching procedural filename
where every room already references it (wall_tile.png, sidewalk_tile.png,
road_tile.png -- no .tscn edits needed for those), or as a new file for
the three room-specific floor materials (each room's Floor node points at
its own file: floor_wood_dark.png for the Dive Bar, floor_wood_worn.png
for the Apartment, floor_checkered.png for the Shop).

Needs numpy is NOT required -- an earlier attempt at flattening uneven
photo lighting via a numpy divide-by-blurred-copy trick over-corrected and
crushed the colors badly. What actually worked: crop a small, evenly-lit
patch from the CENTER of the source photo (well away from any vignette or
the corner watermark) and only lightly blend the seam -- verified by
tiling the result at in-game scale, not just a zoomed 2x2 preview, since
minor imperfections that are obvious zoomed in disappear entirely once
the tile repeats at actual gameplay size.

Checkerboard/grid patterns are a confirmed AI weak point -- two separate
attempts (different prompts, different seeds) both came out as a warped,
fisheye-distorted mess instead of a clean grid. That one is generated
procedurally with plain PIL instead, which draws a perfect checkerboard
trivially. General lesson: AI photo-gen for organic/irregular material
texture (wood grain, brick, cracked concrete), procedural code for
anything with strict geometric regularity.

Needs a venv (system Python is externally-managed):
    python3 -m venv .venv-textures
    .venv-textures/bin/pip install pillow
    .venv-textures/bin/python3 dev-tools/gen_photo_textures.py
"""
import os
import random
import time
import urllib.parse
import urllib.request
from PIL import Image, ImageDraw, ImageFilter

OUT = "/home/anders/dopesick-game/assets/env"
os.makedirs(OUT, exist_ok=True)

PROMPT_TEMPLATE = (
    "seamless tileable texture, top-down flat lay photograph of {desc}, "
    "even studio lighting, no shadows, no vignette, flat surface, photorealistic, 4k"
)


def fetch(prompt, seed, path):
    url = "https://image.pollinations.ai/prompt/" + urllib.parse.quote(prompt)
    url += f"?width=768&height=768&nologo=true&model=flux&seed={seed}"
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.5.0"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp, open(path, "wb") as f:
                f.write(resp.read())
            if os.path.getsize(path) > 5000:
                return True
        except Exception as e:
            print("  attempt", attempt, "failed:", e)
        time.sleep(4)
    return False


def make_seamless(im, band=24, blur=10, mask_blur=14):
    w, h = im.size
    offset = Image.new("RGB", (w, h))
    offset.paste(im, (w // 2, h // 2))
    offset.paste(im, (w // 2 - w, h // 2))
    offset.paste(im, (w // 2, h // 2 - h))
    offset.paste(im, (w // 2 - w, h // 2 - h))
    blurred = offset.filter(ImageFilter.GaussianBlur(blur))
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.rectangle([0, h // 2 - band, w, h // 2 + band], fill=255)
    d.rectangle([w // 2 - band, 0, w // 2 + band, h], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(mask_blur))
    return Image.composite(blurred, offset, mask)


def process(name, desc, seed, crop_box, tile_size=64):
    raw_path = os.path.join(OUT, f"_raw_{name}.png")
    prompt = PROMPT_TEMPLATE.format(desc=desc)
    print("generating", name, "...")
    if not fetch(prompt, seed, raw_path):
        print("  FAILED", name)
        return False
    img = Image.open(raw_path).convert("RGB")
    patch = img.crop(crop_box)
    seamless = make_seamless(patch)
    final = seamless.resize((tile_size, tile_size), Image.LANCZOS)
    final.save(os.path.join(OUT, f"{name}.png"))
    os.remove(raw_path)
    print("  done:", name)
    return True


def add_road_line(path):
    road = Image.open(path).convert("RGB")
    w, h = road.size
    d = ImageDraw.Draw(road)
    line_h = max(2, h // 8)
    y0 = h // 2 - line_h // 2
    d.rectangle([0, y0, w, y0 + line_h], fill=(225, 200, 90))
    road.save(path)


def gen_checkered_floor(path, size=64, sq=16):
    img = Image.new("RGB", (size, size), (235, 232, 225))
    d = ImageDraw.Draw(img)
    for y in range(0, size, sq):
        for x in range(0, size, sq):
            if ((x // sq) + (y // sq)) % 2 == 0:
                d.rectangle([x, y, x + sq - 1, y + sq - 1], fill=(30, 30, 34))
    rng = random.Random(5)
    px = img.load()
    for _ in range(int(size * size * 0.04)):
        x, y = rng.randrange(size), rng.randrange(size)
        base = px[x, y]
        shade = tuple(max(0, min(255, c + rng.randint(-20, 20))) for c in base)
        px[x, y] = shade
    img.save(path)


TEXTURES = [
    # (output filename, description, seed, crop box)
    ("floor_wood_dark", "dark worn mahogany hardwood floor planks, dive bar", 11, (80, 80, 340, 340)),
    ("floor_wood_worn", "aged worn light oak wood floor planks with scuff marks, old apartment", 21, (90, 90, 350, 350)),
    ("sidewalk_tile", "cracked weathered grey concrete sidewalk pavement", 41, (90, 90, 350, 350)),
    ("road_tile", "cracked dark grey asphalt road surface with small pebbles", 51, (90, 90, 350, 350)),
    ("wall_tile", "old red brick wall, mortar lines, weathered", 61, (100, 100, 360, 360)),
]

ok = 0
for name, desc, seed, box in TEXTURES:
    if process(name, desc, seed, crop_box=box):
        ok += 1

add_road_line(os.path.join(OUT, "road_tile.png"))
gen_checkered_floor(os.path.join(OUT, "floor_checkered.png"))

print(f"\n{ok}/{len(TEXTURES)} AI textures generated, plus procedural checkered floor + road line")
