#!/usr/bin/env python3
"""Dev helper (SHIP 16 B1): .pilot/ship16b1/*.png + recoil.json -> .pilot/ship16b1/sheet.png
ADS per gun, the burst (three rounds) and the recoil traces. Run dev-tools/capture_guns.gd first.
usage: ship16b1_sheet.py [dir]"""
import io
import json
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image, ImageDraw

d = sys.argv[1] if len(sys.argv) > 1 else ".pilot/ship16b1"
GUNS = ["pistol", "magnum", "smg", "ar", "shotgun", "sniper", "lmg"]
cells = [(g + " ADS", f"{g}_ads.png") for g in GUNS]
cells += [(f"burst round {i}", f"burst_{i}.png") for i in (1, 2, 3)]
cells += [("shotgun, first shot", "shotgun_fire.png"), ("lmg, first shot", "lmg_fire.png")]
cols, tw, th = 4, 480, 270
rows = (len(cells) + cols - 1) // cols
head = 18
sheet = Image.new("RGB", (cols * tw, rows * (th + head) + 560), (12, 12, 14))
dr = ImageDraw.Draw(sheet)
for i, (label, f) in enumerate(cells):
    x, y = (i % cols) * tw, (i // cols) * (th + head)
    path = os.path.join(d, f)
    if os.path.exists(path):
        sheet.paste(Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y + head))
    dr.text((x + 4, y + 3), label, fill=(230, 210, 140))

traces = json.load(open(os.path.join(d, "recoil.json")))
fig, ax = plt.subplots(1, 2, figsize=(cols * tw / 100.0, 5.4), dpi=100)
fig.patch.set_facecolor("#0c0c0e")
for a in ax:
    a.set_facecolor("#16161a")
    a.tick_params(colors="#bbb")
    for s in a.spines.values():
        s.set_color("#555")
for g in GUNS:
    pts = traces.get(g, [])
    if not pts:
        continue
    t = [i / 60.0 for i in range(len(pts))]
    ax[0].plot(t, [p[0] for p in pts], label=g, lw=1.6)
    ax[1].plot([-p[1] for p in pts], [p[0] for p in pts], label=g, lw=1.6)
ax[0].set_title("view climb (deg up) over time: the burst and the return to centre", color="#e6d28c", fontsize=10)
ax[0].set_xlabel("seconds", color="#bbb")
ax[0].set_ylabel("deg up", color="#bbb")
ax[1].set_title("recoil path (right deg, up deg): each gun's own pattern", color="#e6d28c", fontsize=10)
ax[1].set_xlabel("right (deg)", color="#bbb")
ax[1].legend(facecolor="#16161a", labelcolor="#ddd", fontsize=8, ncol=2)
fig.tight_layout()
buf = io.BytesIO()
fig.savefig(buf, format="png", facecolor=fig.get_facecolor())
buf.seek(0)
plot = Image.open(buf).convert("RGB")
sheet.paste(plot.resize((cols * tw, 560)), (0, rows * (th + head)))
out = os.path.join(d, "sheet.png")
sheet.save(out)
print(out, sheet.size)
