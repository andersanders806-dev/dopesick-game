#!/usr/bin/env python3
"""Fetch Dead Block's gun models into assets/guns/<id>/ and write the licence files.

Poly Haven (CC0): service_pistol (the pistol), bolt_action_rifle_7_62 (the sniper rifle).
Sketchfab (CC BY 4.0, free API token in $SKETCHFAB_TOKEN or ~/.config/sketchfab/token --
never in the repo): the SMG, shotgun, assault rifle, magnum and LMG.
The wonder weapon is kitbashed in code (weapons/GunModel.gd) and needs no download.

Textures larger than 1024 px are scaled down (needs Pillow) to keep the game small.
Re-running skips what's already on disk.

    python3 dev-tools/fetch_guns.py
"""
import io
import json
import os
import pathlib
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "guns"
UA = {"User-Agent": "dopesick-game-asset-fetch"}

POLYHAVEN = {"pistol": "service_pistol", "sniper": "bolt_action_rifle_7_62"}

# id: (Sketchfab uid, title, author)
SKETCHFAB = {
    "smg": ("238fa4b18f1247e99231529f98d11a61", "MPX SMG", "nebula075"),
    "shotgun": ("8766498ce778479aa03c3b6078937510", "Low-Poly Remington 870", "TastyTony"),
    "ar": ("fbdf159836224d67b193ca527d4f4333", "HK 416 Assault Rifle - Low Poly", "Derek Flanagan"),
    "magnum": ("9191c62d1cec4087809102dcc81493bb", "Low Poly Magnum Revolver", "austincford"),
    "lmg": ("03978b66f0c646f19e9502634f0ad20a", "DP28 Light Machine Gun Low-poly PBR", "MaX3Dd"),
}


def get(url: str, headers=None) -> bytes:
    h = dict(UA)
    h.update(headers or {})
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=120) as r:
        return r.read()


def token() -> str:
    t = os.environ.get("SKETCHFAB_TOKEN")
    if t:
        return t.strip()
    p = pathlib.Path.home() / ".config" / "sketchfab" / "token"
    return p.read_text().strip()


def shrink_textures(folder: pathlib.Path, limit=1024) -> None:
    try:
        from PIL import Image
    except ImportError:
        return
    for img in list(folder.rglob("*.png")) + list(folder.rglob("*.jpg")) + list(folder.rglob("*.jpeg")):
        with Image.open(img) as im:
            if max(im.size) <= limit:
                continue
            im = im.copy()
        im.thumbnail((limit, limit), Image.LANCZOS)
        im.save(img)


def polyhaven(gid: str, mid: str) -> str:
    dest = OUT / gid
    info = json.loads(get(f"https://api.polyhaven.com/info/{mid}"))
    if not (dest / f"{mid}.gltf").exists():
        files = json.loads(get(f"https://api.polyhaven.com/files/{mid}"))
        g = files["gltf"]["1k"]["gltf"]
        dest.mkdir(parents=True, exist_ok=True)
        todo = [(g["url"], dest / f"{mid}.gltf")]
        todo += [(v["url"], dest / rel) for rel, v in g["include"].items()]
        for url, path in todo:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(get(url))
    return f"{gid}: {info['name']} by {', '.join(info.get('authors', {}))}"


def sketchfab(gid: str, uid: str) -> None:
    dest = OUT / gid
    if (dest / "scene.gltf").exists():
        return
    meta = json.loads(get(f"https://api.sketchfab.com/v3/models/{uid}/download",
                          {"Authorization": f"Token {token()}"}))
    zdata = get(meta["gltf"]["url"])
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(zdata)) as z:
        z.extractall(dest)
    shrink_textures(dest)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    ph = []
    for gid, mid in POLYHAVEN.items():
        ph.append(polyhaven(gid, mid))
        print("ok", gid)
    for gid, (uid, _title, _author) in SKETCHFAB.items():
        sketchfab(gid, uid)
        print("ok", gid)
    lines = ["# Gun models", "",
             "Dead Block's guns (assets/guns/<id>/), fetched by dev-tools/fetch_guns.py on 2026-10-27.",
             "The wonder weapon is built in code (weapons/GunModel.gd) from primitives: ours, no licence.", "",
             "## CC0 -- Poly Haven (https://polyhaven.com), public domain", ""]
    lines += [f"- {x}" for x in ph]
    lines += ["", "## CC BY 4.0 -- Sketchfab (https://creativecommons.org/licenses/by/4.0/)", "",
              "Textures scaled to 1024 px max. Models are otherwise unmodified.", ""]
    for gid, (uid, title, author) in SKETCHFAB.items():
        lines.append(f'- {gid}: "{title}" by {author} (https://sketchfab.com/3d-models/{uid})')
    (OUT / "LICENSE.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
