"""Procedural textures for the 3D Apartment's squalor pass.

Writes to assets/env3d/. Run with the project venv:
    .venv-portraits/bin/python dev-tools/gen_apartment_textures.py

Everything is noise-driven (no AI generation, no samples), seeded so reruns
are stable. Based on common details in documentary and news photos of drug
houses: water-damage rings on walls and ceilings, grime, bare mattresses with
old yellow-brown stains, worn upholstery, weathered boards nailed over
windows, and punched/torn drywall.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "env3d"
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(1987)
SIZE = 256


def value_noise(size: int, cell: int, rng) -> np.ndarray:
    """Tileable smooth value noise in [0, 1]."""
    n = size // cell
    grid = rng.random((n, n))
    ys = np.arange(size) / cell
    y0 = np.floor(ys).astype(int)
    t = ys - y0
    t = t * t * (3 - 2 * t)
    y1 = (y0 + 1) % n
    y0 %= n
    rows = grid[y0][:, None, :] * (1 - t)[:, None, None] + grid[y1][:, None, :] * t[:, None, None]
    rows = rows[:, 0, :]
    out = rows[:, y0] * (1 - t)[None, :] + rows[:, y1] * t[None, :]
    return out


def fbm(size: int, rng, octaves=(64, 32, 16, 8, 4)) -> np.ndarray:
    total = np.zeros((size, size))
    amp, norm = 1.0, 0.0
    for cell in octaves:
        total += value_noise(size, cell, rng) * amp
        norm += amp
        amp *= 0.55
    return total / norm


def radial(size: int, cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
    y, x = np.mgrid[0:size, 0:size]
    return np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)


def save(arr: np.ndarray, name: str) -> None:
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(OUT / name)
    print("wrote", OUT / name)


def stain(name: str, color, ring_color, strength: float, seed_shift: int) -> None:
    """A blotchy stain with a darker tide-mark ring, the way water damage
    dries. Transparent everywhere else, for use as a Decal."""
    rng = np.random.default_rng(1987 + seed_shift)
    noise = fbm(SIZE, rng)
    d = radial(SIZE, SIZE / 2, SIZE / 2, SIZE * 0.36, SIZE * 0.3) + (noise - 0.5) * 0.9
    body = np.clip(1.0 - d, 0, 1) ** 0.7
    ring = np.exp(-((d - 0.92) ** 2) / 0.004) * (d < 1.05)
    alpha = np.clip(body * 0.55 + ring * 0.8, 0, 1) * strength
    alpha *= 0.75 + 0.25 * fbm(SIZE, rng, (16, 8, 4))
    rgb = np.zeros((SIZE, SIZE, 3))
    for c in range(3):
        rgb[..., c] = color[c] * (1 - ring) + ring_color[c] * ring
    save(np.dstack([rgb, alpha * 255]), name)


def mattress() -> None:
    """Off-white ticking stripes, grimy, with several overlapping old stains."""
    noise = fbm(SIZE, RNG)
    x = np.arange(SIZE)
    stripes = ((x // 10) % 2 == 0).astype(float)[None, :].repeat(SIZE, 0)
    base = np.dstack([
        205 - stripes * 40,
        198 - stripes * 38,
        178 - stripes * 20,
    ]).astype(float)
    base *= (0.8 + 0.25 * noise)[..., None]
    for _ in range(6):
        cx, cy = RNG.uniform(20, SIZE - 20, 2)
        r = RNG.uniform(18, 60)
        d = radial(SIZE, cx, cy, r, r * RNG.uniform(0.6, 1.2)) + (fbm(SIZE, RNG) - 0.5) * 0.8
        s = np.clip(1 - d, 0, 1) ** 0.5 * RNG.uniform(0.35, 0.7)
        ring = np.exp(-((d - 0.95) ** 2) / 0.006) * 0.5
        tint = np.array([150, 115, 55])
        k = np.clip(s + ring, 0, 0.85)[..., None]
        base = base * (1 - k) + tint * k
    save(base, "mattress_stained.png")


def couch() -> None:
    """Worn brown-olive upholstery: weave texture, shiny worn patches, grime."""
    noise = fbm(SIZE, RNG)
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    weave = ((x % 4 < 2) ^ (y % 4 < 2)).astype(float) * 0.06
    shade = 0.75 + 0.35 * noise + weave
    base = np.dstack([92 * shade, 80 * shade, 52 * shade])
    worn = np.clip(fbm(SIZE, RNG, (32, 16)) - 0.55, 0, 1) * 2.2
    base += worn[..., None] * np.array([40, 34, 22])
    grime = np.clip(0.5 - fbm(SIZE, RNG, (64, 32, 8)), 0, 1) * 1.6
    base *= (1 - grime * 0.5)[..., None]
    save(base, "couch_worn.png")


def planks() -> None:
    """Weathered grey-brown plywood/board grain for boarded-up windows."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    warp = fbm(SIZE, RNG, (64, 32)) * 30
    grain = np.sin((y + warp) * 0.35) * 0.5 + 0.5
    fine = fbm(SIZE, RNG, (8, 4))
    shade = 0.55 + 0.2 * grain + 0.3 * fine
    base = np.dstack([118 * shade, 104 * shade, 86 * shade])
    rot = np.clip(fbm(SIZE, RNG, (32, 16, 8)) - 0.6, 0, 1) * 2.5
    base *= (1 - rot * 0.6)[..., None]
    save(base, "plank_weathered.png")


def drywall_hole() -> None:
    """A fist-sized hole punched through drywall: dark void, jagged torn
    paper edge, crumbled gypsum halo. RGBA, for a Decal."""
    noise = fbm(SIZE, RNG, (32, 16, 8, 4))
    d = radial(SIZE, SIZE / 2, SIZE / 2, SIZE * 0.26, SIZE * 0.22) + (noise - 0.5) * 0.7
    rgba = np.zeros((SIZE, SIZE, 4))
    hole = d < 0.8
    edge = (d >= 0.8) & (d < 1.0)
    halo = (d >= 1.0) & (d < 1.35)
    rgba[hole] = [14, 12, 10, 255]
    rgba[edge] = [212, 204, 188, 255]
    halo_a = np.clip((1.35 - d) / 0.35, 0, 1) * 150
    rgba[..., 0] = np.where(halo, 170, rgba[..., 0])
    rgba[..., 1] = np.where(halo, 160, rgba[..., 1])
    rgba[..., 2] = np.where(halo, 145, rgba[..., 2])
    rgba[..., 3] = np.where(halo, halo_a, rgba[..., 3])
    img = Image.fromarray(rgba.astype(np.uint8)).filter(ImageFilter.SMOOTH)
    img.save(OUT / "drywall_hole.png")
    print("wrote", OUT / "drywall_hole.png")


if __name__ == "__main__":
    stain("stain_water.png", (120, 95, 55), (70, 50, 25), 0.85, 1)
    stain("stain_grime.png", (35, 30, 25), (20, 17, 14), 0.9, 2)
    mattress()
    couch()
    planks()
    drywall_hole()
