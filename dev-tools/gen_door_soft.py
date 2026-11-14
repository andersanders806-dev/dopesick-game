#!/usr/bin/env python3
"""Out-of-focus copies of the door street panoramas (assets/doors/glass_street_{day,night}.png) for
interactables/sky_dome.gdshader: the street seen through a room's doorway is a hand-wide slice of the panorama, so
it is blurred in advance (Gaussian, wrapped round the horizon, then halved to 1024x512) and the shader needs one
texture fetch instead of a ring of taps. Night lamps become bokeh.
usage: gen_door_soft.py  (writes assets/doors/glass_street_{day,night}_soft.png)"""
import os, sys
from PIL import Image, ImageFilter

D = os.path.join(os.path.dirname(__file__), "..", "assets", "doors")
OUT = sys.argv[1] if len(sys.argv) > 1 else D
for name in ("day", "night"):
	img = Image.open(os.path.join(D, "glass_street_%s.png" % name)).convert("RGB")
	w, h = img.size
	pad = 64
	wide = Image.new("RGB", (w + 2 * pad, h))
	wide.paste(img, (pad, 0))
	wide.paste(img.crop((w - pad, 0, w, h)), (0, 0))
	wide.paste(img.crop((0, 0, pad, h)), (w + pad, 0))
	blur = wide.filter(ImageFilter.GaussianBlur(9)).crop((pad, 0, pad + w, h))
	blur.resize((w // 2, h // 2), Image.LANCZOS).save(os.path.join(OUT, "glass_street_%s_soft.png" % name))
	print(name, "ok")
