#!/usr/bin/env python3
"""Generates realistic dialogue-portrait art via Pollinations.ai (free, no
key) + rembg background removal, for use in HUD dialogue boxes only (NOT
top-down gameplay sprites -- AI photo models default to front-facing
portraits, not bird's-eye view, so a "realistic" character standing in the
top-down world looks like a floating cardboard cutout; confirmed via a
mockup before committing to this approach).

Needs a venv (system Python is externally-managed) with rembg + onnxruntime:
    python3 -m venv .venv-portraits
    .venv-portraits/bin/pip install rembg onnxruntime
    .venv-portraits/bin/python3 dev-tools/gen_portraits.py

First run downloads a ~1GB background-removal model to ~/.rembg/ -- slow
once, fast after. Pollinations.ai is a shared free community service; a
generation attempt can hit a 429/500 from rate limiting, so fetch() retries
with backoff.
"""
import os
import time
import urllib.parse
import urllib.request
from rembg import remove
from PIL import Image

OUT = "/home/anders/dopesick-game/assets/portraits"
os.makedirs(OUT, exist_ok=True)

CHARACTERS = {
    "bartender": "a weathered middle-aged bartender with a short greying beard, rolled-up sleeves, tired but kind eyes",
    "wiry_guy": "a thin wiry young man with a gaunt face, sunken cheeks, stubble, nervous eyes",
    "tired_woman": "an exhausted middle-aged woman with dark circles under her eyes, messy hair, tired expression",
    "big_eddie": "a big heavyset man with a broad face, short cropped hair, tired heavy-lidded eyes",
    "quiet_kid": "a young quiet teenager with a hoodie, downcast eyes, pale face",
    "old_sailor": "an old grizzled sailor with a white beard, weathered wrinkled skin, a knit cap",
    "nervous_dave": "a nervous balding man in his 40s, sweaty forehead, wide anxious eyes",
}

PROMPT_TEMPLATE = (
    "realistic photo portrait of {desc}, head and shoulders, plain neutral "
    "grey background, soft studio lighting, looking at camera, photorealistic, 4k"
)


def fetch(prompt: str, seed: int, path: str) -> bool:
    url = "https://image.pollinations.ai/prompt/" + urllib.parse.quote(prompt)
    url += f"?width=512&height=512&nologo=true&model=flux&seed={seed}"
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


def clean_watermark(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h - 55, h):
        for x in range(w - 190, w):
            if 0 <= x < w and 0 <= y < h:
                px[x, y] = (0, 0, 0, 0)
    return img


def process(name: str, desc: str, seed: int):
    raw_path = os.path.join(OUT, f"_raw_{name}.png")
    prompt = PROMPT_TEMPLATE.format(desc=desc)
    print("generating", name, "...")
    if not fetch(prompt, seed, raw_path):
        print("  FAILED to generate", name)
        return False

    raw = Image.open(raw_path)
    cut = remove(raw)
    cut = clean_watermark(cut)

    bbox = cut.getbbox()
    if bbox:
        cut = cut.crop(bbox)

    # pad to square, center, then resize to final portrait size
    size = max(cut.size)
    square = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    square.paste(cut, ((size - cut.width) // 2, (size - cut.height) // 2), cut)
    final = square.resize((200, 200), Image.LANCZOS)
    final.save(os.path.join(OUT, f"{name}.png"))
    os.remove(raw_path)
    print("  done:", name)
    return True


ok = 0
for i, (name, desc) in enumerate(CHARACTERS.items()):
    if process(name, desc, seed=100 + i):
        ok += 1

print(f"\n{ok}/{len(CHARACTERS)} portraits generated")
print("done:", sorted(os.listdir(OUT)))
