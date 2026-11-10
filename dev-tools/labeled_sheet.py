#!/usr/bin/env python3
"""Contact sheet with the label in a strip above each frame (never over it).
usage: labeled_sheet.py <out.png> <cols> <glob> [thumb width]"""
import glob, os, sys, re
from PIL import Image, ImageDraw, ImageFont
out, cols, pattern = sys.argv[1], int(sys.argv[2]), sys.argv[3]
tw = int(sys.argv[4]) if len(sys.argv) > 4 else 480
th = tw * 9 // 16
files = sorted(glob.glob(pattern))
strip = 22
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + strip)), (12, 12, 14))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
except Exception:
    font = ImageFont.load_default()
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * tw, (i // cols) * (th + strip)
    sheet.paste(im, (x, y + strip))
    label = re.sub(r"^\d+_", "", os.path.basename(f)[:-4])
    d.text((x + 6, y + 3), label, fill=(235, 215, 150), font=font)
sheet.save(out)
print(out, len(files), sheet.size)
