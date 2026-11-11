#!/usr/bin/env python3
"""Dev helper: a contact sheet of named screenshots with the labels in a strip BELOW each frame (never over the picture).
usage: label_sheet.py <out.png> <cols> <file>=<label> [<file>=<label> ...]"""
import sys
from PIL import Image, ImageDraw, ImageFont
out, cols = sys.argv[1], int(sys.argv[2])
items = [a.split("=", 1) for a in sys.argv[3:]]
tw, th, strip, gap = 640, 360, 30, 8
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (tw + gap) + gap, rows * (th + strip + gap) + gap), (16, 16, 18))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
except Exception:
    font = ImageFont.load_default()
for i, (f, label) in enumerate(items):
    x = gap + (i % cols) * (tw + gap)
    y = gap + (i // cols) * (th + strip + gap)
    sheet.paste(Image.open(f).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y))
    d.text((x + 4, y + th + 6), label, fill=(235, 220, 160), font=font)
sheet.save(out)
print(out, sheet.size)
