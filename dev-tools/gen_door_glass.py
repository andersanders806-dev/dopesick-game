#!/usr/bin/env python3
"""Textures for interactables/DoorGlass.gd (shop-door glass): a street reflection (equirectangular, day and
night: sky, a canyon of buildings with windows, lamps, a wet-looking road, a few cars) and a smudge mask
(fingerprints round the push zone, streaks, a dirty bottom edge). Made for this game, no third-party material.
usage: gen_door_glass.py  (writes assets/doors/glass_*.png)"""
import os
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "doors")
rng = np.random.default_rng(7)

def panorama(night: bool, w=512, h=256) -> Image.Image:
	img = np.zeros((h, w, 3), dtype=np.float32)
	ys = np.linspace(0, 1, h)[:, None]
	horizon = 0.5
	if night:
		top = np.array([0.02, 0.03, 0.07]); low = np.array([0.10, 0.07, 0.10])
	else:
		top = np.array([0.42, 0.55, 0.72]); low = np.array([0.80, 0.82, 0.82])
	t = np.clip(ys / horizon, 0, 1) ** 0.6
	sky = top[None, None, :] * (1 - t[..., None]) + low[None, None, :] * t[..., None]
	img[:] = sky
	# The street canyon: building blocks round the whole horizon.
	x = 0
	while x < w:
		bw = int(rng.integers(14, 46))
		bh = int(rng.integers(30, 105))
		col = np.array([[0.30, 0.17, 0.12], [0.22, 0.20, 0.20], [0.35, 0.28, 0.22], [0.18, 0.15, 0.17]][rng.integers(0, 4)])
		if night:
			col = col * 0.16
		else:
			col = col * (0.75 + 0.3 * rng.random())
		y1 = int(horizon * h)
		y0 = max(0, y1 - bh)
		img[y0:y1, x:x + bw] = col
		# windows
		for wy in range(y0 + 5, y1 - 6, 11):
			for wx in range(x + 4, x + bw - 5, 9):
				if night:
					if rng.random() < 0.38:
						lit = np.array([1.0, 0.72, 0.38]) * (0.5 + 0.7 * rng.random())
						img[wy:wy + 5, wx:wx + 4] = lit
				else:
					img[wy:wy + 5, wx:wx + 4] = np.array([0.22, 0.30, 0.38]) * (0.6 + 0.6 * rng.random())
		x += bw + int(rng.integers(0, 4))
	# Ground: asphalt with a pavement strip and the lamps' pools; darker toward the nadir.
	y1 = int(horizon * h)
	g = np.linspace(0, 1, h - y1)[:, None]
	if night:
		road = np.array([0.045, 0.045, 0.06]); walk = np.array([0.10, 0.09, 0.09])
	else:
		road = np.array([0.30, 0.31, 0.33]); walk = np.array([0.52, 0.5, 0.47])
	ground = road[None, None, :] * (1 - 0.5 * g[..., None])
	ground[:int((h - y1) * 0.16), :, :] = walk * 0.8
	img[y1:] = ground
	im = Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8))
	d = ImageDraw.Draw(im)
	# Cars: dark boxes at the kerb; their lights at night.
	for _ in range(7):
		cx = int(rng.integers(0, w)); cw = int(rng.integers(22, 40)); cy = y1 + int(rng.integers(3, 18))
		d.rectangle([cx, cy, cx + cw, cy + 9], fill=(14, 14, 18) if night else (60, 62, 70))
		if night:
			d.rectangle([cx, cy + 4, cx + 3, cy + 6], fill=(255, 235, 190))
			d.rectangle([cx + cw - 3, cy + 4, cx + cw, cy + 6], fill=(255, 235, 190))
	if night:
		# Lamps and neon: bright spots with a halo.
		for _ in range(11):
			lx = int(rng.integers(0, w)); ly = y1 - int(rng.integers(8, 40))
			col = [(255, 214, 140), (255, 80, 110), (110, 170, 255), (255, 214, 140)][int(rng.integers(0, 4))]
			d.ellipse([lx - 3, ly - 3, lx + 3, ly + 3], fill=col)
		im = im.filter(ImageFilter.GaussianBlur(0.9))
		glow = Image.fromarray(np.array(im)).filter(ImageFilter.GaussianBlur(5))
		im = Image.fromarray(np.clip(np.array(im).astype(np.float32) + np.array(glow).astype(np.float32) * 0.9, 0, 255).astype(np.uint8))
	else:
		im = im.filter(ImageFilter.GaussianBlur(0.9))
	return im

def smudge(w=128, h=256) -> Image.Image:
	m = np.zeros((h, w), dtype=np.float32)
	# soft cloudy film
	noise = rng.random((h // 8, w // 8)).astype(np.float32)
	film = np.array(Image.fromarray((noise * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0
	film = np.array(Image.fromarray((film * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255.0
	m += film * 0.25
	# dirt at the bottom edge and the corners
	yy = np.linspace(0, 1, h)[:, None]
	m += np.clip((yy - 0.78) / 0.22, 0, 1) ** 1.5 * 0.55
	# vertical rain streaks
	for _ in range(26):
		x = int(rng.integers(0, w)); y0 = int(rng.integers(0, h // 2)); ln = int(rng.integers(30, 120))
		m[y0:y0 + ln, x:x + 1] += 0.18 * rng.random()
	im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
	d = ImageDraw.Draw(im)
	# fingerprints and palm marks round hand height (about 45% down) on the latch side
	for _ in range(22):
		cx = int(w * (0.62 + 0.3 * rng.random())); cy = int(h * (0.38 + 0.2 * rng.random()))
		rx = int(rng.integers(2, 5)); ry = int(rng.integers(3, 7))
		v = int(110 + 120 * rng.random())
		d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=v)
	im = im.filter(ImageFilter.GaussianBlur(0.6))
	return im

os.makedirs(OUT, exist_ok=True)
panorama(False).save(os.path.join(OUT, "glass_street_day.png"))
panorama(True).save(os.path.join(OUT, "glass_street_night.png"))
smudge().save(os.path.join(OUT, "glass_smudge.png"))
print("done")
