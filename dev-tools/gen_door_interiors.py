#!/usr/bin/env python3
"""What you glimpse through a door that is open on a room that isn't there (a facade door of a scene-change store
or bar): a perspective picture of an aisle, shelves in colours, ceiling lights, the back wall.
assets/doors/interior_store.png (bright), interior_dim.png (bar / workshop).  usage: gen_door_interiors.py"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "doors")
rng = np.random.default_rng(11)
W, H = 256, 384

def render(bright: bool) -> Image.Image:
	cx, cy = W / 2, H * 0.50
	F = 190.0
	def P(x, y, z):  # x across, y up (0 floor .. 1 ceiling), z depth
		return (cx + x / z * F, cy - (y - 0.46) / z * F)
	im = Image.new("RGB", (W, H), (20, 20, 22))
	d = ImageDraw.Draw(im)
	floor = (206, 204, 196) if bright else (58, 40, 30)
	wall = (200, 214, 210) if bright else (70, 44, 34)
	ceil = (170, 176, 178) if bright else (30, 24, 24)
	# back wall, floor, ceiling, side walls
	zb = 9.0
	d.polygon([P(-1.1, 0, 0.3), P(1.1, 0, 0.3), P(1.1, 0, zb), P(-1.1, 0, zb)], fill=floor)
	d.polygon([P(-1.1, 1, 0.3), P(1.1, 1, 0.3), P(1.1, 1, zb), P(-1.1, 1, zb)], fill=ceil)
	d.polygon([P(-1.1, 0, 0.3), P(-1.1, 1, 0.3), P(-1.1, 1, zb), P(-1.1, 0, zb)], fill=wall)
	d.polygon([P(1.1, 0, 0.3), P(1.1, 1, 0.3), P(1.1, 1, zb), P(1.1, 0, zb)], fill=tuple(int(c * 0.9) for c in wall))
	d.polygon([P(-1.1, 0, zb), P(1.1, 0, zb), P(1.1, 1, zb), P(-1.1, 1, zb)], fill=(236, 238, 232) if bright else (96, 60, 44))
	# floor tile lines
	for z in np.arange(0.5, zb, 0.5):
		d.line([P(-1.1, 0, z), P(1.1, 0, z)], fill=tuple(int(c * 0.82) for c in floor), width=1)
	for x in np.arange(-1.0, 1.01, 0.5):
		d.line([P(x, 0, 0.3), P(x, 0, zb)], fill=tuple(int(c * 0.82) for c in floor), width=1)
	# ceiling light panels
	for z in np.arange(1.4, zb, 1.8):
		d.polygon([P(-0.25, 0.995, z), P(0.25, 0.995, z), P(0.25, 0.995, z + 0.7), P(-0.25, 0.995, z + 0.7)], fill=(255, 255, 245) if bright else (255, 190, 120))
	# shelves both sides: levels of coloured boxes
	cols = [(215, 60, 50), (240, 200, 60), (60, 120, 210), (70, 170, 90), (235, 235, 235), (220, 120, 40)] if bright else [(130, 70, 40), (90, 110, 80), (160, 120, 60), (70, 50, 40)]
	for side in (-1, 1):
		xin, xout = side * 0.62, side * 1.05
		z = 0.5
		while z < zb - 0.4:
			dz = 0.42
			for lvl in range(4):
				y0, y1 = 0.08 + lvl * 0.2, 0.08 + lvl * 0.2 + 0.16
				c = cols[int(rng.integers(0, len(cols)))]
				c = tuple(int(v * (0.55 if not bright else 1.0) * (0.85 + 0.3 * rng.random())) for v in c)
				d.polygon([P(xin, y0, z), P(xin, y1, z), P(xin, y1, z + dz * 0.8), P(xin, y0, z + dz * 0.8)], fill=c)
			z += dz
		# shelf uprights
		for z in np.arange(0.5, zb, 1.7):
			d.line([P(xin, 0, z), P(xin, 0.92, z)], fill=(40, 40, 44), width=2)
	im = im.filter(ImageFilter.GaussianBlur(0.8))
	# vignette so the edges recede
	a = np.array(im).astype(np.float32)
	yy, xx = np.mgrid[0:H, 0:W]
	v = 1.0 - 0.45 * (((xx - cx) / (W * 0.65)) ** 2 + ((yy - cy) / (H * 0.7)) ** 2)
	a *= np.clip(v, 0.35, 1.0)[..., None]
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

os.makedirs(OUT, exist_ok=True)
render(True).save(os.path.join(OUT, "interior_store.png"))
render(False).save(os.path.join(OUT, "interior_dim.png"))
print("done")
