#!/usr/bin/env python3
"""SHIP 16 B2 contact sheet from dev-tools/capture_b2.gd's frames (.pilot/ship16b2/cap) -> .pilot/ship16b2/sheet.png:
ADS of the sixteen (the bat and the machete mid-swing), four hip views, two reloads with the magazine out, the RPG's
blast, a melee hit, a new wall board, the box, and a gangster with an AK.

    python3 dev-tools/ship16b2_sheet.py
"""
import pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent / ".pilot" / "ship16b2"
CAP = ROOT / "cap"
TILES = [(f"{g}_ads", f"{g.upper()} ADS") for g in ["glock", "tec9", "uzi", "mp5", "vector", "ak", "m16", "sawnoff", "deagle", "aa12", "dmr", "amr", "saw", "rpg"]]
TILES += [("bat_swing_12", "BAT swing"), ("machete_swing_08", "MACHETE swing")]
TILES += [("ak_hip", "AK hip"), ("aa12_hip", "AA-12 hip"), ("saw_hip", "M249 hip"), ("deagle_hip", "DEAGLE hip")]
TILES += [("m16_reload_30", "M16 reload, mag out"), ("sawnoff_reload_30", "SAWN-OFF broken open")]
TILES += [("rpg_blast_01", "RPG blast"), ("melee_hit", "BAT hit"), ("wall_ak", "new wall board"), ("box", "the box"),
          ("gang_ak", "Kings gangster, AK"), ("gang_fight_2", "Ghetto Wars fight")]
W, H, COLS = 320, 180, 6


def main():
    rows = (len(TILES) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * W, rows * H), (16, 16, 16))
    for i, (name, label) in enumerate(TILES):
        f = CAP / (name + ".png")
        if f.exists():
            im = Image.open(f).convert("RGB").resize((W, H))
        else:
            im = Image.new("RGB", (W, H), (60, 0, 0))
            label += " (missing)"
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 8 + 6 * len(label), 14], fill=(0, 0, 0))
        d.text((4, 2), label, fill=(255, 220, 90))
        sheet.paste(im, ((i % COLS) * W, (i // COLS) * H))
    sheet.save(ROOT / "sheet.png")
    print("wrote", ROOT / "sheet.png", len(TILES), "tiles")


if __name__ == "__main__":
    main()
