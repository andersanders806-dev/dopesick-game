#!/usr/bin/env python3
"""Dev helper: .pilot/z5play_*.png -> one contact sheet. usage: contact_sheet.py <out.png> [cols] [glob]"""
import glob, os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 4
files = sorted(glob.glob(sys.argv[3] if len(sys.argv) > 3 else ".pilot/z5play_*.png"))
tw, th = 480, 270
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), (12, 12, 14))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * tw, (i // cols) * (th + 18)
    sheet.paste(im, (x, y + 18))
    d.text((x + 4, y + 3), os.path.basename(f)[8:-4], fill=(230, 210, 140))
sheet.save(out)
print(out, len(files), sheet.size)
