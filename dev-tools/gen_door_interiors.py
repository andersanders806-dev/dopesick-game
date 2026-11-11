#!/usr/bin/env python3
"""The room seen through a door whose room isn't there (a scene-change store's or bar's facade door): the faces of
a box room for interactables/interior_map.gdshader (interior mapping: it has real depth as you move).
Walls with shelves, floor tiles, a ceiling with lights, a back wall; bright (store) and dim (bar, workshop).
Made for this game, no third-party material.  usage: gen_door_interiors.py -> assets/doors/room_*.png"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "doors")
rng = np.random.default_rng(23)
W_ROOM, H_ROOM, D_ROOM = 1.5, 2.2, 7.0
PX = 140  # pixels per metre

def noise(im: Image.Image, sigma=3.0) -> Image.Image:
	a = np.array(im).astype(np.float32)
	a += rng.normal(0, sigma, a.shape)
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

def shelf_wall(bright: bool) -> Image.Image:
	w, h = int(D_ROOM * PX), int(H_ROOM * PX)
	wall = (206, 216, 212) if bright else (62, 40, 30)
	im = Image.new("RGB", (w, h), wall)
	d = ImageDraw.Draw(im)
	pal = [(214, 58, 48), (240, 200, 60), (60, 118, 208), (66, 168, 90), (236, 236, 232), (222, 122, 42), (150, 80, 170)] if bright else [(120, 66, 38), (88, 108, 76), (150, 114, 58), (66, 48, 38), (110, 50, 44)]
	levels = 5
	shelf_h = int(h * 0.78 / levels)
	base = int(h * 0.08)
	for lv in range(levels):
		y1 = h - (base + lv * shelf_h)
		y0 = y1 - shelf_h + 6
		d.rectangle([0, y1, w, y1 + 5], fill=(60, 60, 66) if bright else (36, 28, 24))  # the shelf board
		x = 8
		while x < w - 8:
			bw = int(rng.integers(14, 40)); bh = int(rng.integers(int(shelf_h * 0.55), shelf_h - 8))
			c = pal[int(rng.integers(0, len(pal)))]
			c = tuple(int(v * (0.8 + 0.3 * rng.random())) for v in c)
			d.rectangle([x, y1 - bh, x + bw, y1], fill=c)
			# a label band
			d.rectangle([x + 2, y1 - bh * 0.6, x + bw - 2, y1 - bh * 0.4], fill=tuple(min(255, v + 60) for v in c))
			x += bw + int(rng.integers(1, 6))
	# uprights
	for x in range(0, w, int(PX * 1.4)):
		d.rectangle([x, int(h * 0.04), x + 6, h], fill=(40, 40, 46))
	# the kick board and a skirting line, the ceiling margin
	d.rectangle([0, h - base // 2, w, h], fill=(120, 120, 116) if bright else (30, 22, 18))
	d.rectangle([0, 0, w, int(h * 0.1)], fill=tuple(int(v * 0.92) for v in wall))
	return noise(im.filter(ImageFilter.GaussianBlur(0.7)), 2.0)

def floor_tex(bright: bool) -> Image.Image:
	w, h = int(W_ROOM * PX), int(D_ROOM * PX)
	base = (204, 202, 194) if bright else (56, 38, 28)
	im = Image.new("RGB", (w, h), base)
	d = ImageDraw.Draw(im)
	step = PX // 2
	for y in range(0, h, step):
		d.line([0, y, w, y], fill=tuple(int(v * 0.8) for v in base), width=2)
	for x in range(0, w, step):
		d.line([x, 0, x, h], fill=tuple(int(v * 0.8) for v in base), width=2)
	# scuffs and a worn path down the middle
	for _ in range(60):
		x = int(rng.integers(0, w)); y = int(rng.integers(0, h))
		d.ellipse([x - 10, y - 4, x + 10, y + 4], fill=tuple(int(v * (0.86 + 0.1 * rng.random())) for v in base))
	return noise(im.filter(ImageFilter.GaussianBlur(0.8)), 2.0)

def ceiling_tex(bright: bool) -> Image.Image:
	w, h = int(W_ROOM * PX), int(D_ROOM * PX)
	base = (176, 180, 182) if bright else (30, 24, 22)
	im = Image.new("RGB", (w, h), base)
	d = ImageDraw.Draw(im)
	for y in range(0, h, int(PX * 0.6)):
		d.line([0, y, w, y], fill=tuple(int(v * 0.85) for v in base), width=2)
	lamp = (255, 255, 246) if bright else (255, 190, 120)
	for y in range(int(PX * 1.2), h - PX, int(PX * 1.9)):
		d.rectangle([w * 0.3, y, w * 0.7, y + int(PX * 0.6)], fill=lamp)
	im = im.filter(ImageFilter.GaussianBlur(1.6))
	return noise(im, 2.0)

def back_tex(bright: bool) -> Image.Image:
	w, h = int(W_ROOM * PX), int(H_ROOM * PX)
	im = Image.new("RGB", (w, h), (232, 236, 230) if bright else (92, 58, 42))
	d = ImageDraw.Draw(im)
	# a pair of doors to the back, a sign over them, a notice
	dw = int(w * 0.5)
	x0 = (w - dw) // 2
	d.rectangle([x0, int(h * 0.22), x0 + dw, h], fill=(244, 244, 240) if bright else (56, 36, 28))
	d.line([w // 2, int(h * 0.22), w // 2, h], fill=(150, 150, 150), width=3)
	d.rectangle([x0 + 8, int(h * 0.3), x0 + dw // 2 - 8, int(h * 0.62)], fill=(150, 176, 190) if bright else (80, 60, 48))
	d.rectangle([w // 2 + 8, int(h * 0.3), x0 + dw - 8, int(h * 0.62)], fill=(150, 176, 190) if bright else (80, 60, 48))
	d.rectangle([x0, int(h * 0.1), x0 + dw, int(h * 0.19)], fill=(200, 50, 40) if bright else (220, 150, 70))
	return noise(im.filter(ImageFilter.GaussianBlur(0.7)), 2.0)

os.makedirs(OUT, exist_ok=True)
for name, bright in (("store", True), ("dim", False)):
	shelf_wall(bright).save(os.path.join(OUT, "room_wall_%s.png" % name))
	floor_tex(bright).save(os.path.join(OUT, "room_floor_%s.png" % name))
	ceiling_tex(bright).save(os.path.join(OUT, "room_ceiling_%s.png" % name))
	back_tex(bright).save(os.path.join(OUT, "room_back_%s.png" % name))
print("done")
