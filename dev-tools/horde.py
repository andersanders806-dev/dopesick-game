"""AI Horde (https://stablehorde.net) client shared by gen_cutscenes.py and
gen_portraits.py: a free, open-source, volunteer-run Stable Diffusion
network. The anonymous key works; a free registered key from
https://stablehorde.net/register gets through the queue faster -- put it in
AI_HORDE_KEY.

paint_all() keeps as many jobs queued side by side as the Horde allows (it
answers 429 past a per-user cap) and hands each finished image to a
callback, because the anonymous queue runs 10-20 minutes a job.
"""
import base64
import io
import json
import os
import time
import urllib.error
import urllib.request

from PIL import Image

API = "https://stablehorde.net/api/v2"
KEY = os.environ.get("AI_HORDE_KEY", "0000000000")
# Photographic SDXL models, best first; any with workers online will do.
MODELS = ["Juggernaut XL", "ICBINP XL", "AlbedoBase XL 3.1", "SDXL 1.0"]


def call(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "apikey": KEY, "Content-Type": "application/json",
        "Client-Agent": "dopesick-game:1.0:github",
    })
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read())


def submit(prompt: str, negative: str, seed: int, width: int, height: int) -> str:
    job = call("POST", "/generate/async", {
        "prompt": f"{prompt} ### {negative}",
        "params": {"width": width, "height": height, "steps": 30, "cfg_scale": 6.0,
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


def paint_all(jobs: list, negative: str, width: int, height: int, on_done) -> int:
    """jobs: [(name, prompt, seed)]. on_done(name, image) for each success."""
    todo = list(jobs)
    pending = {}
    ok = 0
    while todo or pending:
        while todo:
            name, prompt, seed = todo[0]
            try:
                pending[name] = submit(prompt, negative, seed, width, height)
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
            except (urllib.error.HTTPError, urllib.error.URLError) as e:
                print(name, "check failed:", e)
                continue
            if st.get("faulted"):
                print(name, "faulted")
                del pending[name]
            elif st.get("done"):
                print(name, "done", flush=True)
                try:
                    img = fetch(jid)
                except Exception as e:
                    print(name, "fetch failed:", e)
                    img = None
                if img:
                    on_done(name, img)
                    ok += 1
                del pending[name]
        print(f"  {len(pending)} in the queue, {len(todo)} waiting for a slot", flush=True)
    return ok
