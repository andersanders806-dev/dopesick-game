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

# Descriptions are grounded in real clinical/visible signs of long-term
# substance use (researched via addiction-medicine sources, not guessed):
# heroin/opioid use shows as gauntness, hollow cheeks, sunken dark-circled
# eyes, and a sallow/grayish skin tone; benzodiazepine use shows as
# droopy, "glazed" or unfocused eyes and a dull complexion rather than
# gauntness; long-term heavy drinking (the dive bar's barflies) shows as
# facial flushing and broken capillaries across the nose and cheeks.
# Kept humanizing, not a caricature -- these are headshots of tired
# people, not gore.
CHARACTERS = {
    "bartender": "a weathered middle-aged bartender with a short greying beard, rolled-up sleeves, tired but kind eyes, faint broken capillaries across his nose from years spent around drink",
    "wiry_guy": "a gaunt wiry man in his late 20s, hollow sunken cheeks, deep dark circles under bloodshot eyes, sallow grayish skin, stubble, restless nervous expression",
    "tired_woman": "an exhausted woman in her 40s, droopy heavy-lidded eyes with a glazed unfocused look, dark circles, dull sallow complexion, messy flat hair, slack tired expression",
    "big_eddie": "a big heavyset barfly in his 50s, broad flushed face with broken capillaries across his nose and cheeks, short cropped grey hair, puffy tired eyes",
    "quiet_kid": "a young quiet teenager in a worn hoodie, pale thin face just starting to hollow out, faint dark circles, downcast anxious eyes",
    "old_sailor": "an old grizzled sailor in his 60s, deeply weathered wrinkled skin, a red bulbous nose with broken veins, a white beard, watery bloodshot eyes, a knit cap",
    "nervous_dave": "a nervous balding man in his 40s, sweaty forehead, glazed heavy-lidded eyes struggling to focus, sallow complexion, wide anxious expression",
    # The pusher: street-level sellers blend in rather than looking like a
    # movie villain, and are often users themselves; what gives them away is
    # behaviour -- constantly checking the street -- not appearance.
    "pusher": "an ordinary-looking man in his 30s in a plain grey zip-up hoodie with the hood down and a faded t-shirt, tired skin with faint dark circles, stubble, eyes glancing sideways as if checking the street behind the camera, tense guarded expression, standing under harsh streetlight",
    "pharmacist": "a tired pharmacist in her 40s in a white lab coat with a name badge, glasses pushed up on her head, polite but wary expression, fluorescent-lit",
    "cashier": "a bored young supermarket cashier in his early 20s in a red store polo shirt with a name tag, slouched, indifferent half-lidded expression",
    "liquor_clerk": "a stern liquor store clerk in his 50s, heavy-set, grey stubble, flannel shirt, arms folded, suspicious narrowed eyes, standing behind scratched plexiglass",
    "security_guard": "a bulky retail security guard in his 30s in a black uniform shirt with a SECURITY patch, radio clipped to his shoulder, buzz cut, alert unimpressed stare",
    "jailer": "a weary middle-aged booking officer at a police station in a dark blue uniform, reading glasses, grey moustache, flat bored expression of someone who has seen it all",
    "shopkeeper": "a tired middle-aged convenience shop owner in a plain apron over a flannel shirt, alert watchful eyes, deep worry lines, arms crossed, wary guarded expression",
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


# Pass character names to (re)generate just those, e.g.
#   .venv-portraits/bin/python3 dev-tools/gen_portraits.py pusher
# With no arguments, every portrait is regenerated. Seeds stay tied to each
# character's position in CHARACTERS either way.
import sys
wanted = set(sys.argv[1:])
ok = 0
todo = 0
for i, (name, desc) in enumerate(CHARACTERS.items()):
    if wanted and name not in wanted:
        continue
    todo += 1
    if process(name, desc, seed=100 + i):
        ok += 1

print(f"\n{ok}/{todo} portraits generated")
print("done:", sorted(os.listdir(OUT)))
