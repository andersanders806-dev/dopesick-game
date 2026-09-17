"""Procedural textures for the 3D Apartment and Dive Bar.

Writes to assets/env3d/. Run with the project venv:
    .venv-portraits/bin/python dev-tools/gen_env3d_textures.py

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


# --- Dive Bar -------------------------------------------------------------------
# Grounded in write-ups of what makes a "true" dive bar: dated wood-panelled
# walls, sticky linoleum tile floors, red vinyl (Naugahyde) booths and
# ripped vinyl stools, and a pool table with faded felt.


def wood_paneling() -> None:
    """Dark 1970s-style wall panelling: vertical boards with deep grooves,
    fine grain, and years of smoke-darkened patina. Tiles horizontally
    (4 boards per texture)."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    board_w = SIZE // 4
    warp = fbm(SIZE, RNG, (64, 32)) * 6
    grain = np.sin((x + warp) * 0.9 + np.sin(y * 0.02) * 3) * 0.5 + 0.5
    fine = fbm(SIZE, RNG, (8, 4))
    per_board = np.array([0.85, 1.0, 0.9, 1.05])[(x // board_w) % 4]
    shade = (0.55 + 0.18 * grain + 0.2 * fine) * per_board
    groove = ((x % board_w) < 3) | ((x % (board_w // 2)) == 0)
    shade = np.where(groove, shade * 0.35, shade)
    base = np.dstack([96 * shade, 60 * shade, 34 * shade])
    patina = fbm(SIZE, RNG, (64, 32, 16))
    base *= (0.75 + 0.3 * patina)[..., None]
    save(base, "wood_paneling.png")


def vinyl_red() -> None:
    """Cracked red Naugahyde: glossy creases, pale cracks where the vinyl
    has split, darker grime in the seams."""
    noise = fbm(SIZE, RNG)
    crease = np.abs(np.sin(fbm(SIZE, RNG, (32, 16)) * 25))
    shade = 0.7 + 0.25 * noise + 0.15 * (crease > 0.97)
    base = np.dstack([150 * shade, 22 * shade, 24 * shade])
    # Cracks only where the seat gets the most wear, not all over.
    wear = fbm(SIZE, RNG, (64, 32)) > 0.62
    cracks = (np.abs(fbm(SIZE, RNG, (16, 8, 4)) - 0.5) < 0.006) & wear
    base[cracks] = [190, 150, 130]
    grime = np.clip(0.45 - fbm(SIZE, RNG, (64, 32)), 0, 1) * 1.5
    base *= (1 - grime * 0.6)[..., None]
    save(base, "vinyl_red.png")


def linoleum() -> None:
    """Worn two-tone linoleum tiles (4x4 per texture) with scuffs, dark grime
    in the seams, and sticky dried-spill blotches."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    tile = SIZE // 4
    checker = ((x // tile) + (y // tile)) % 2
    base = np.where(checker[..., None] == 0, np.array([158, 140, 104]), np.array([98, 70, 48])).astype(float)
    base *= (0.8 + 0.3 * fbm(SIZE, RNG))[..., None]
    seam = ((x % tile) < 2) | ((y % tile) < 2)
    base[seam] *= 0.35
    scuffs = np.clip(fbm(SIZE, RNG, (8, 4)) - 0.62, 0, 1) * 3
    base *= (1 - scuffs * 0.5)[..., None]
    for _ in range(5):
        cx, cy = RNG.uniform(0, SIZE, 2)
        r = RNG.uniform(14, 40)
        d = radial(SIZE, cx, cy, r, r * RNG.uniform(0.5, 1.0)) + (fbm(SIZE, RNG) - 0.5) * 0.6
        k = (np.clip(1 - d, 0, 1) ** 0.4 * 0.45)[..., None]
        base = base * (1 - k) + np.array([60, 40, 18]) * k
    save(base, "linoleum_worn.png")


def felt_faded() -> None:
    """Pool-table felt faded unevenly from green toward grey-olive, with
    chalk smudges and a couple of drink rings."""
    noise = fbm(SIZE, RNG)
    fade = fbm(SIZE, RNG, (128, 64))
    green = np.array([34, 96, 58])
    faded = np.array([84, 104, 78])
    k = np.clip(fade * 1.3 - 0.2, 0, 1)[..., None]
    base = green * (1 - k) + faded * k
    base = base * (0.85 + 0.2 * noise)[..., None]
    chalk = np.clip(fbm(SIZE, RNG, (16, 8)) - 0.72, 0, 1) * 1.8
    base = base * (1 - chalk[..., None]) + np.array([120, 150, 190]) * chalk[..., None]
    for _ in range(2):
        cx, cy = RNG.uniform(40, SIZE - 40, 2)
        d = radial(SIZE, cx, cy, 18, 18)
        ring = (np.exp(-((d - 1.0) ** 2) / 0.01) * 0.5)[..., None]
        base = base * (1 - ring) + np.array([40, 50, 30]) * ring
    save(base, "felt_faded.png")


# --- Jail ---------------------------------------------------------------------
# Holding cells, per first-hand accounts and news photos: concrete block walls
# "painted and repainted" beige, bare concrete floors.


def cinder_block() -> None:
    """Painted cinder-block wall: staggered 2:1 blocks, recessed mortar,
    several coats of glossy beige paint that pool in the joints and scuff
    where people lean."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    bh, bw = SIZE // 4, SIZE // 2
    row = y // bh
    offset = np.where(row % 2 == 0, 0, bw // 2)
    joint = ((y % bh) < 5) | (((x + offset) % bw) < 5)
    paint = np.array([196, 180, 146])
    base = np.tile(paint, (SIZE, SIZE, 1)).astype(float)
    pores = np.clip(fbm(SIZE, RNG, (4, 2)) - 0.62, 0, 1) * 2
    base *= (0.93 + 0.08 * fbm(SIZE, RNG, (32, 16)) - pores * 0.25)[..., None]
    base[joint] *= 0.72
    scuff = np.clip(fbm(SIZE, RNG, (64, 16, 8)) - 0.63, 0, 1) * 2.5
    base *= (1 - scuff * 0.3)[..., None]
    save(base, "cinder_block_beige.png")


def concrete_floor() -> None:
    """Sealed grey concrete floor, scuffed and stained, with hairline cracks."""
    noise = fbm(SIZE, RNG)
    base = np.dstack([128 * (0.8 + 0.3 * noise), 126 * (0.8 + 0.3 * noise), 120 * (0.8 + 0.3 * noise)])
    cracks = np.abs(fbm(SIZE, RNG, (32, 16, 8)) - 0.5) < 0.0018
    base[cracks] *= 0.6
    stain = np.clip(0.42 - fbm(SIZE, RNG, (64, 32)), 0, 1) * 1.8
    base *= (1 - stain * 0.45)[..., None]
    save(base, "concrete_floor.png")


# --- Stores ---------------------------------------------------------------------


def vinyl_tile() -> None:
    """Commercial vinyl composition tile (the speckled off-white 12" squares
    in pharmacies and supermarkets), with scuffs from carts and dark seams."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    tile = SIZE // 4
    base = np.tile(np.array([214, 210, 198]), (SIZE, SIZE, 1)).astype(float)
    per_tile = RNG.uniform(0.94, 1.04, (4, 4))[(y // tile) % 4, (x // tile) % 4]
    base *= per_tile[..., None]
    speckle = RNG.random((SIZE, SIZE))
    base[speckle > 0.985] *= 0.6
    base[speckle < 0.012] *= 0.85
    seam = ((x % tile) < 1) | ((y % tile) < 1)
    base[seam] *= 0.7
    scuff = np.clip(fbm(SIZE, RNG, (16, 8, 4)) - 0.66, 0, 1) * 2.2
    base *= (1 - scuff * 0.35)[..., None]
    save(base, "vinyl_tile.png")


if __name__ == "__main__":
    stain("stain_water.png", (120, 95, 55), (70, 50, 25), 0.85, 1)
    stain("stain_grime.png", (35, 30, 25), (20, 17, 14), 0.9, 2)
    mattress()
    couch()
    planks()
    drywall_hole()
    wood_paneling()
    vinyl_red()
    linoleum()
    felt_faded()
    cinder_block()
    concrete_floor()
    vinyl_tile()
