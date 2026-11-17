#!/usr/bin/env python3
"""SHIP 4: the perf table (trunk vs branch, every run) and the contact sheet, from dev-tools/perf_ship4.gd's output.

  python3 dev-tools/ship4_report.py table <results.txt>...      markdown table to stdout
  python3 dev-tools/ship4_report.py sheet <ship4_dir> <tag> <out.png>
"""
import re
import sys
from collections import defaultdict

LINE = re.compile(
    r"RESULT (\S+) \[(\S+)\] frames (\d+) \(([\d.]+) s\) \| gpu mean ([\d.]+) p95 ([\d.]+) \| frame mean ([\d.]+) "
    r"p50 ([\d.]+) p95 ([\d.]+) p99 ([\d.]+) max ([\d.]+) \| >25ms (\d+) \(visible (\d+)\) \| scale ([\d.]+)"
    r"(?: \| vmax ([\d.]+))?")
ORDER = ["street", "sick", "room:DiveBar3D", "room:StorePharmacy3D", "room:StoreSupermarket3D", "shop", "horde", "ghetto",
         "kart", "go:street_shop", "go:shop_street", "go:title_story", "go:title_zombies", "title", "floor"]


def parse(paths):
    runs = defaultdict(list)  # (scenario, tag) -> [dict]
    for p in paths:
        for line in open(p):
            m = LINE.search(line)
            if m:
                s, tag = m.group(1), m.group(2)
                runs[(s, tag)].append({
                    "gpu": float(m.group(5)), "p95": float(m.group(9)), "p99": float(m.group(10)),
                    "max": float(m.group(11)), "slow": int(m.group(12)), "vis": int(m.group(13)), "scale": float(m.group(14)),
                    "vmax": float(m.group(15)) if m.group(15) else None})
    return runs


def table(paths, last=3):
    runs = parse(paths)
    # (a results.txt keeps every run ever made: the table is the last `last` of each probe and build)
    runs = {k: v[-last:] for k, v in runs.items()}
    tags = sorted({t for (_, t) in runs})
    print("| probe | build | GPU mean ms (runs) | frame p95 ms | frame p99 ms | max ms | visible max ms | frames > 25 ms (visible) per run |")
    print("|---|---|---|---|---|---|---|---|")
    for s in ORDER:
        for t in tags:
            r = runs.get((s, t))
            if not r:
                continue
            print("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
                s, t,
                " / ".join("%.1f" % x["gpu"] for x in r),
                " / ".join("%.1f" % x["p95"] for x in r),
                " / ".join("%.1f" % x["p99"] for x in r),
                " / ".join("%.0f" % x["max"] for x in r),
                " / ".join(("%.0f" % x["vmax"]) if x["vmax"] is not None else "-" for x in r),
                " / ".join("%d (%d)" % (x["slow"], x["vis"]) for x in r)))


def sheet(d, tag, out, floor_label="", extras=()):
    from PIL import Image, ImageDraw
    import csv
    import os
    cells = []
    for s in ORDER:
        base = os.path.join(d, "%s_%s" % (s.replace(":", "-"), tag))
        if not (os.path.exists(base + ".png") and os.path.exists(base + ".csv")):
            continue
        img = Image.open(base + ".png").convert("RGB").resize((640, 360))
        ms = []
        fades = []
        with open(base + ".csv") as f:
            for row in csv.DictReader(f):
                ms.append(float(row["ms"]))
                fades.append(float(row.get("fade", 0.0) or 0.0))
        # a frame counts as seen when the frame before it left the screen not black (the probe's own rule)
        seen = [i == 0 or fades[i - 1] < 0.5 for i in range(len(ms))]
        dr = ImageDraw.Draw(img, "RGBA")
        # graph strip along the bottom: one column per frame group, 0..50 ms, with the 25 ms and 16.7 ms lines
        gh, top = 90, 360 - 90
        dr.rectangle([0, top, 640, 360], fill=(0, 0, 0, 170))
        for y_ms, col in ((16.7, (80, 200, 80, 200)), (25.0, (230, 80, 60, 230))):
            y = 360 - gh * min(y_ms, 50.0) / 50.0
            dr.line([0, y, 640, y], fill=col, width=1)
        n = len(ms)
        step = max(1, n // 640)
        for x in range(640):
            chunk = ms[x * n // 640:max(x * n // 640 + 1, (x + 1) * n // 640)]
            if not chunk:
                continue
            lo = x * n // 640
            v = max(chunk)
            black = not any(seen[lo:lo + len(chunk)])
            h = gh * min(v, 50.0) / 50.0
            col = (110, 110, 110, 200) if black else ((255, 90, 60, 255) if v > 25.0 else (150, 200, 255, 220))
            dr.line([x, 360, x, 360 - h], fill=col)
        vis = [v for v, k in zip(ms, seen) if k]
        slow = sum(1 for v in vis if v > 25.0)
        secs = sum(ms) / 1000.0
        dr.rectangle([0, 0, 640, 36], fill=(0, 0, 0, 190))
        dr.text((6, 4), "%s [%s]   seen: max %.1f ms, > 25 ms: %d in %.0f s (%.1f/min)" % (
            s, tag, max(vis) if vis else 0.0, slow, secs, slow * 60.0 / max(secs, 1.0)), fill=(255, 255, 255, 255))
        if floor_label:
            dr.text((6, 20), floor_label + "   (grey: behind black, not counted)", fill=(200, 200, 200, 255))
        cells.append(img)
    # extra tiles ("label=path.png"): the title's loading card and the menu after it
    for e in extras:
        label, path = e.split("=", 1)
        img = Image.open(path).convert("RGB").resize((640, 360))
        dr = ImageDraw.Draw(img, "RGBA")
        dr.rectangle([0, 0, 640, 20], fill=(0, 0, 0, 190))
        dr.text((6, 4), label, fill=(255, 255, 255, 255))
        cells.append(img)
    if not cells:
        print("nothing to put on the sheet")
        return
    cols = 3
    rows = (len(cells) + cols - 1) // cols
    sheet_img = Image.new("RGB", (cols * 640, rows * 360), (0, 0, 0))
    for i, c in enumerate(cells):
        sheet_img.paste(c, ((i % cols) * 640, (i // cols) * 360))
    sheet_img.save(out)
    print("wrote", out, len(cells), "cells")


def pairs(paths):
    """Each probe run (tags p1/p2) against the floor run measured right before it (tags pf1_<probe>/pf2_<probe>)."""
    runs = parse(paths)
    print("| probe | round | seen/min (max ms) | paired floor seen/min (max ms) | verdict |")
    print("|---|---|---|---|---|")
    for s in ORDER:
        for r in (1, 2):
            a = runs.get((s, "p%d" % r))
            f = runs.get((s.replace(":", "-") + "-floor", "pf%d" % r)) or runs.get(("floor", "pf%d_%s" % (r, s.replace(":", "-"))))
            if not a:
                continue
            x = a[-1]
            secs = SECS.get(s, 60.0)
            per = x["vis"] * 60.0 / secs
            fm = ("%.1f (%.0f)" % (f[-1]["vis"] * 60.0 / 60.0, f[-1]["vmax"] or f[-1]["max"])) if f else "-"
            ok = f and per <= f[-1]["vis"] * 1.0 + 1e-9 and (x["vmax"] or x["max"]) <= 40.0
            print("| %s | %d | %.1f (%.0f) | %s | %s |" % (s, r, per, x["vmax"] or x["max"], fm, "pass" if ok else "fail"))


SECS = {"title": 30.0}

if __name__ == "__main__":
    if sys.argv[1] == "table":
        table(sys.argv[2:])
    elif sys.argv[1] == "sheet":
        sheet(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "", sys.argv[6:])
    elif sys.argv[1] == "pairs":
        pairs(sys.argv[2:])
