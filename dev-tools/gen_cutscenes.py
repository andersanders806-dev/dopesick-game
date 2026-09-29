#!/usr/bin/env python3
"""Paints the cutscene stills (assets/cutscenes/) from the prompts in
dev-tools/cutscene_prompts.json through AI Horde (https://stablehorde.net),
a free, open-source, volunteer-run Stable Diffusion network with a public
API. The anonymous key works; a free registered key from
https://stablehorde.net/register gets you through the queue faster --
put it in the AI_HORDE_KEY environment variable.

(The prompts were first tried on Perchance's generator, which gave the look
we wanted but can't be saved from a script; Pollinations, which
gen_portraits.py used, has since gone paid.)

    python3 dev-tools/gen_cutscenes.py                 # all stills
    python3 dev-tools/gen_cutscenes.py busted_car      # just some
    SEED=7 python3 dev-tools/gen_cutscenes.py busted_car  # reroll one

Needs Pillow (.venv-portraits has it).
"""
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cutscenes")
PROMPTS = os.path.join(ROOT, "dev-tools", "cutscene_prompts.json")
API = "https://stablehorde.net/api/v2"
KEY = os.environ.get("AI_HORDE_KEY", "0000000000")
# A photographic SDXL model. Fallbacks are tried in order if it has no
# workers online at the moment.
MODELS = ["Juggernaut XL", "ICBINP XL", "AlbedoBase XL 3.1", "SDXL 1.0"]
# ~16:9 at about one megapixel, multiples of 64, within anonymous limits.
REQ_W, REQ_H = 1216, 704
W, H = 1280, 720


def call(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "apikey": KEY, "Content-Type": "application/json",
        "Client-Agent": "dopesick-game:1.0:github",
    })
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read())


def submit(prompt: str, negative: str, seed: int) -> str:
    job = call("POST", "/generate/async", {
        "prompt": f"{prompt} ### {negative}",
        "params": {"width": REQ_W, "height": REQ_H, "steps": 30, "cfg_scale": 6.0,
                   "sampler_name": "k_dpmpp_2m", "karras": True, "seed": str(seed), "n": 1},
        "models": MODELS, "nsfw": False, "censor_nsfw": True, "r2": True,
    })
    return job["id"]


def fetch(jid: str) -> Image.Image | None:
    gen = call("GET", f"/generate/status/{jid}")["generations"][0]
    print("  painted by", gen.get("model"), "seed", gen.get("seed"))
    if gen.get("censored"):
        print("  censored by the worker's safety filter -- reword or reroll")
        return None
    img = gen["img"]
    raw = urllib.request.urlopen(img, timeout=120).read() if img.startswith("http") else base64.b64decode(img)
    return Image.open(io.BytesIO(raw)).convert("RGB")


def main() -> None:
    data = json.load(open(PROMPTS))
    os.makedirs(OUT, exist_ok=True)
    wanted = set(sys.argv[1:])
    todo = []
    for i, (name, desc) in enumerate(data["images"].items()):
        if wanted and name not in wanted:
            continue
        seed = int(os.environ.get("SEED", 300 + i))
        todo.append((name, data["style_prefix"] + desc + data["shared_suffix"], seed))
    total = len(todo)
    # The anonymous queue runs 10-20 minutes a job, so keep as many queued
    # side by side as the Horde allows; it answers 429 past its per-user
    # cap, and the rest wait for a slot.
    ok = 0
    pending = {}
    while todo or pending:
        while todo:
            name, prompt, seed = todo[0]
            try:
                pending[name] = submit(prompt, data["negative"], seed)
            except urllib.error.HTTPError as e:
                if e.code != 429:
                    raise
                break
            todo.pop(0)
            print("queued", name, flush=True)
        time.sleep(20)
        for name, jid in list(pending.items()):
            try:
                st = call("GET", f"/generate/check/{jid}")
            except urllib.error.HTTPError as e:
                print(name, "check failed:", e.code)
                continue
            if st.get("faulted"):
                print(name, "faulted")
                del pending[name]
            elif st.get("done"):
                print(name, "done", flush=True)
                img = fetch(jid)
                if img:
                    img.resize((W, H), Image.LANCZOS).save(os.path.join(OUT, name + ".png"), optimize=True)
                    ok += 1
                del pending[name]
        print(f"  {len(pending)} in the queue, {len(todo)} waiting for a slot", flush=True)
    print(f"\n{ok}/{total} stills painted into {OUT}")


if __name__ == "__main__":
    main()
