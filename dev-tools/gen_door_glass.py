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

def panorama(night: bool, w=2048, h=1024) -> Image.Image:
	S = w / 512.0
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
	y1 = int(horizon * h)
	# A scatter of clouds by day, a few stars by night.
	if not night:
		for _ in range(26):
			cx = int(rng.integers(0, w)); cy = int(rng.integers(int(0.05 * h), int(0.38 * h)))
			for k in range(int(rng.integers(5, 12))):
				rx = int(rng.integers(int(14 * S), int(46 * S))); ry = int(rng.integers(int(3 * S), int(8 * S)))
				x0 = cx + int(rng.integers(-int(30 * S), int(30 * S))); yy = cy + int(rng.integers(-int(4 * S), int(4 * S)))
				img[max(0, yy - ry):yy + ry, max(0, x0 - rx):x0 + rx] = np.minimum(1.0, img[max(0, yy - ry):yy + ry, max(0, x0 - rx):x0 + rx] * 0.4 + 0.62)
	# The street canyon: building blocks round the whole horizon, two rows deep (the far row paler).
	for row in (0, 1):
		x = 0
		while x < w:
			bw = int(rng.integers(int(14 * S), int(46 * S)))
			bh = int(rng.integers(int((30 if row == 0 else 50) * S), int((105 if row == 0 else 150) * S)))
			col = np.array([[0.30, 0.17, 0.12], [0.22, 0.20, 0.20], [0.35, 0.28, 0.22], [0.18, 0.15, 0.17], [0.42, 0.25, 0.16]][rng.integers(0, 5)])
			col = col * (0.16 if night else (0.78 + 0.3 * rng.random()))
			if row == 1:
				col = col * 0.8 + (np.array([0.02, 0.025, 0.05]) if night else np.array([0.28, 0.32, 0.38])) * 0.2
			yb = y1 - (0 if row == 0 else int(4 * S))
			y0 = max(0, yb - bh)
			img[y0:yb, x:x + bw] = col
			# a cornice and windows
			img[y0:y0 + int(2 * S), x:x + bw] = col * 1.25
			for wy in range(y0 + int(6 * S), yb - int(6 * S), int(11 * S)):
				for wx in range(x + int(4 * S), x + bw - int(5 * S), int(9 * S)):
					if night:
						if rng.random() < 0.4:
							img[wy:wy + int(5 * S), wx:wx + int(4 * S)] = np.array([1.0, 0.72, 0.38]) * (0.5 + 0.7 * rng.random())
					else:
						img[wy:wy + int(5 * S), wx:wx + int(4 * S)] = np.array([0.22, 0.30, 0.38]) * (0.6 + 0.6 * rng.random())
			x += bw + int(rng.integers(0, int(4 * S)))
	# Ground: asphalt with a pavement strip, lane lines; darker toward the nadir.
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
	# Parked cars at the kerb: dark boxes with a roof and windows; lights at night.
	for _ in range(16):
		cx = int(rng.integers(0, w)); cw = int(rng.integers(int(22 * S), int(40 * S))); cy = y1 + int(rng.integers(int(3 * S), int(18 * S)))
		body = (14, 14, 18) if night else (int(rng.integers(40, 150)), int(rng.integers(40, 120)), int(rng.integers(40, 130)))
		d.rectangle([cx, cy, cx + cw, cy + int(9 * S)], fill=body)
		d.rectangle([cx + int(cw * 0.2), cy - int(5 * S), cx + int(cw * 0.75), cy], fill=body)
		if not night:
			d.rectangle([cx + int(cw * 0.25), cy - int(4 * S), cx + int(cw * 0.7), cy - int(1 * S)], fill=(150, 175, 190))
		else:
			d.rectangle([cx, cy + int(4 * S), cx + int(3 * S), cy + int(6 * S)], fill=(255, 235, 190))
			d.rectangle([cx + cw - int(3 * S), cy + int(4 * S), cx + cw, cy + int(6 * S)], fill=(255, 235, 190))
	# The centre line of the road, dashed.
	for x in range(0, w, int(24 * S)):
		d.rectangle([x, y1 + int((h - y1) * 0.5), x + int(10 * S), y1 + int((h - y1) * 0.5) + int(2 * S)], fill=(200, 190, 120) if not night else (70, 66, 40))
	if night:
		for _ in range(40):
			lx = int(rng.integers(0, w)); ly = y1 - int(rng.integers(int(8 * S), int(40 * S)))
			col = [(255, 214, 140), (255, 80, 110), (110, 170, 255), (255, 214, 140)][int(rng.integers(0, 4))]
			d.ellipse([lx - 3 * S, ly - 3 * S, lx + 3 * S, ly + 3 * S], fill=col)
		im = im.filter(ImageFilter.GaussianBlur(0.9 * S))
		glow = Image.fromarray(np.array(im)).filter(ImageFilter.GaussianBlur(5 * S))
		im = Image.fromarray(np.clip(np.array(im).astype(np.float32) + np.array(glow).astype(np.float32) * 0.9, 0, 255).astype(np.uint8))
	else:
		im = im.filter(ImageFilter.GaussianBlur(0.6 * S))
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

def rust(w=128, h=256) -> Image.Image:
	"""Rust and grime streaks for steel doors (RGBA, brown on transparent): runs from the hinges and the lock, a corroded foot, scratches."""
	a = np.zeros((h, w, 4), dtype=np.float32)
	def stripe(x, y0, ln, wd, strength):
		for yy in range(y0, min(h, y0 + ln)):
			t = (yy - y0) / max(ln, 1)
			xx = int(x + rng.normal(0, 0.6))
			for dx in range(-wd, wd + 1):
				if 0 <= xx + dx < w:
					a[yy, xx + dx, 3] = max(a[yy, xx + dx, 3], strength * (1 - t) * (1 - abs(dx) / (wd + 1)))
	for hx in (4, 6):
		for hy in (int(h * 0.12), int(h * 0.48), int(h * 0.82)):
			stripe(hx + int(rng.integers(0, 6)), hy, int(rng.integers(50, 130)), int(rng.integers(1, 4)), 0.6)
	stripe(int(w * 0.84), int(h * 0.42), 80, 2, 0.5)
	for _ in range(16):
		stripe(int(rng.integers(0, w)), int(rng.integers(0, h // 2)), int(rng.integers(30, 110)), 1, 0.25)
	yy = np.linspace(0, 1, h)[:, None]
	foot = np.clip((yy - 0.84) / 0.16, 0, 1) ** 1.3 * (0.35 + 0.65 * rng.random((h, w)))
	a[..., 3] = np.maximum(a[..., 3], foot * 0.75)
	a[..., 0] = 0.36; a[..., 1] = 0.17; a[..., 2] = 0.07
	im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")
	return im.filter(ImageFilter.GaussianBlur(0.9))

rust().save(os.path.join(OUT, "door_rust.png"))
print("rust done")
