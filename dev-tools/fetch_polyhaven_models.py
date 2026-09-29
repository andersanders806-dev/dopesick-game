#!/usr/bin/env python3
"""Download CC0 3D models from Poly Haven into assets/polyhaven/<id>/.

Each model is the 1k-texture glTF (the .gltf, its .bin, and its textures),
which Godot imports directly. Chosen for low polygon counts (all under
~15k triangles) so they stay affordable on integrated graphics -- see the
polycounts in the notes below. Re-running skips what's already on disk.

    python3 dev-tools/fetch_polyhaven_models.py
"""
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "polyhaven"
UA = {"User-Agent": "dopesick-game-asset-fetch"}

MODELS = [
    # street
    "trashbag",            # 4.5k
    "street_rat",          # 14k
    "water_manhole_cover", # 6.3k
    "utility_box_01",      # 4.4k
    "security_light",      # 4.7k
    "old_tyre",            # 2.9k
    # apartment
    "sofa_02",             # 2.7k
    "Television_01",       # 1.9k
    # bar
    "dartboard",           # 6.8k
    # stores
    "CashRegister_01",     # 9.9k
    "security_camera_01",  # 13.6k
    "WetFloorSign_01",     # 0.2k
    # backyard, shelter, jail
    "barrel_stove",        # 11.4k
    "plastic_crate_01",    # 18k (one or two only)
    "propane_tank",        # 5.2k
    "rollershutter_door",  # 1.1k
    "plastic_monobloc_chair_01",  # 3.4k
    "metal_office_desk",   # 6.9k
]


def get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r:
        return r.read()


def main() -> None:
    credits = []
    for mid in MODELS:
        files = json.loads(get(f"https://api.polyhaven.com/files/{mid}"))
        info = json.loads(get(f"https://api.polyhaven.com/info/{mid}"))
        g = files["gltf"]["1k"]["gltf"]
        dest = OUT / mid
        dest.mkdir(parents=True, exist_ok=True)
        todo = [(g["url"], dest / f"{mid}.gltf")]
        todo += [(v["url"], dest / rel) for rel, v in g["include"].items()]
        for url, path in todo:
            if path.exists():
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(get(url))
        credits.append(f"{mid}: {info['name']} by {', '.join(info.get('authors', {}))}")
        print("ok", mid)
    (OUT / "LICENSE.txt").write_text(
        "3D models from Poly Haven (https://polyhaven.com), CC0 1.0 -- public domain.\n\n"
        + "\n".join(credits) + "\n")


if __name__ == "__main__":
    main()
