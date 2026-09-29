#!/usr/bin/env python3
"""Paints the cutscene stills (assets/cutscenes/) from the prompts in
dev-tools/cutscene_prompts.json through AI Horde (dev-tools/horde.py).

"{me}" in a prompt becomes the json's "protagonist" description -- the same
man as the 3D player (grey-green t-shirt, blue-grey jeans, short brown
hair) -- and every still showing him shares one seed, which keeps the face
closer from panel to panel than separate seeds did.

    python3 dev-tools/gen_cutscenes.py                 # all stills
    python3 dev-tools/gen_cutscenes.py busted_car      # just some
    SEED=7 python3 dev-tools/gen_cutscenes.py busted_car  # reroll one

Needs Pillow (.venv-portraits has it).
"""
import json
import os
import sys

from horde import paint_all

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cutscenes")
PROMPTS = os.path.join(ROOT, "dev-tools", "cutscene_prompts.json")
# ~16:9 at about one megapixel, multiples of 64, within anonymous limits.
REQ_W, REQ_H = 1216, 704
W, H = 1280, 720
PROTAGONIST_SEED = 4242


def main() -> None:
    data = json.load(open(PROMPTS))
    os.makedirs(OUT, exist_ok=True)
    wanted = set(sys.argv[1:])
    jobs = []
    for i, (name, desc) in enumerate(data["images"].items()):
        if wanted and name not in wanted:
            continue
        seed = PROTAGONIST_SEED if "{me}" in desc else 300 + i
        seed = int(os.environ.get("SEED", seed))
        prompt = data["style_prefix"] + desc.replace("{me}", data["protagonist"]) + data["shared_suffix"]
        jobs.append((name, prompt, seed))

    def save(name, img):
        img.resize((W, H)).save(os.path.join(OUT, name + ".png"), optimize=True)

    ok = paint_all(jobs, data["negative"], REQ_W, REQ_H, save)
    print(f"\n{ok}/{len(jobs)} stills painted into {OUT}")


if __name__ == "__main__":
    main()
