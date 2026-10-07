#!/usr/bin/env python3
"""Download CC0 PBR materials from ambientCG (https://ambientcg.com) into
assets/pbr/ as <set>_diff.jpg, <set>_nor.jpg, <set>_rough.jpg -- the same
layout fetch_polyhaven.py writes, so build_rooms_3d.gd's _pbr_mat() reads
both. 1K JPG; OpenGL normal maps (Godot's convention).

    python3 -I dev-tools/fetch_ambientcg.py
"""
import io, pathlib, urllib.request, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "pbr"
UA = {"User-Agent": "dopesick-game-asset-fetch"}
# set name in the game -> ambientCG asset id
SETS = {
    "road_worn": "Road009C", "sidewalk_slabs": "PavingStones128", "curb": "Concrete047A",
    "tiles_white": "Tiles141", "tiles_beige": "Tiles139", "plaster_painted": "PaintedPlaster017",
    "bricks_old": "Bricks097", "wood_dark": "Wood066", "leather_red": "Leather037",
    "felt": "Fabric030", "metal_worn": "Metal055A", "metal_brushed": "Metal032",
}
MAPS = {"_Color.jpg": "diff", "_NormalGL.jpg": "nor", "_Roughness.jpg": "rough"}

def main():
    lines = []
    for name, aid in SETS.items():
        lines.append(f"{name}: ambientCG {aid}")
        if all((OUT / f"{name}_{m}.jpg").exists() for m in MAPS.values()):
            continue
        req = urllib.request.Request(f"https://ambientcg.com/get?file={aid}_1K-JPG.zip", headers=UA)
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(req, timeout=300).read()))
        for member in z.namelist():
            for suffix, short in MAPS.items():
                if member.endswith(suffix):
                    (OUT / f"{name}_{short}.jpg").write_bytes(z.read(member))
        print("ok", name, aid)
    lic = OUT / "LICENSE.txt"
    text = lic.read_text() if lic.exists() else ""
    if "ambientCG" not in text:
        text += "\nMaterials from ambientCG (https://ambientcg.com), CC0 1.0 -- public domain:\n"
    for l in lines:
        if l not in text:
            text += l + "\n"
    lic.write_text(text)

main()
