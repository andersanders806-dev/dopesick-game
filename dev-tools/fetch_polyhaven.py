#!/usr/bin/env python3
"""Download CC0 PBR texture sets from Poly Haven into assets/pbr/.

Each set gets three 1k JPGs -- albedo (diff), OpenGL normal (nor_gl), and
roughness (rough) -- which build_rooms_3d.gd's _pbr_mat() wires into a
StandardMaterial3D. The procedural/AI textures in assets/env and
assets/env3d were albedo-only, so surfaces had no relief and a single flat
roughness; these give mortar lines, cracks, and wood grain real depth under
the rooms' point lights.

Poly Haven assets are CC0 (https://polyhaven.com/license). Re-running skips
files that are already on disk.

    python3 dev-tools/fetch_polyhaven.py
"""
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "pbr"
RES = "1k"
MAPS = {"Diffuse": "diff", "nor_gl": "nor", "Rough": "rough"}

# local name -> Poly Haven asset id. The local name is what the room
# generator refers to, so a set can be swapped here without touching it.
SETS = {
    "asphalt": "worn_asphalt",
    "sidewalk": "concrete_pavement",
    "brick": "brick_wall_02",
    "wood_floor": "old_wooden_floor_02",
    "concrete_floor": "dirty_concrete",
    "linoleum": "linoleum_brown",
    "linoleum_retro": "old_linoleum_flooring_01",
    "store_tiles": "grey_tiles",
    "checker_tiles": "floor_tiles_06",
    "cinder_block": "concrete_block_wall",
    "wood_panels": "wooden_panels",
    "planks": "weathered_planks",
}


def fetch_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "dopesick-game-asset-fetch"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    credits = []
    for local, asset in SETS.items():
        files = fetch_json(f"https://api.polyhaven.com/files/{asset}")
        info = fetch_json(f"https://api.polyhaven.com/info/{asset}")
        for ph_map, suffix in MAPS.items():
            url = files[ph_map][RES]["jpg"]["url"]
            dest = OUT / f"{local}_{suffix}.jpg"
            if not dest.exists():
                print(f"  {asset} {ph_map} -> {dest.name}")
                req = urllib.request.Request(url, headers={"User-Agent": "dopesick-game-asset-fetch"})
                with urllib.request.urlopen(req) as r:
                    dest.write_bytes(r.read())
        w, h = info.get("dimensions", [2000, 2000])
        authors = ", ".join(info.get("authors", {}))
        credits.append(f"{local}: {info['name']} ({asset}), {w / 1000:g} x {h / 1000:g} m, by {authors}")
    (OUT / "LICENSE.txt").write_text(
        "Textures from Poly Haven (https://polyhaven.com), CC0 1.0 -- public domain.\n\n"
        + "\n".join(credits) + "\n"
    )
    print("\n".join(credits))


if __name__ == "__main__":
    main()
