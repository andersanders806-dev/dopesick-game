#!/usr/bin/env python3
"""Builds the cutscene clips: real footage, 3 s each, graded to the game's look.

Source: Mixkit (Stock Video Free License -- free for commercial projects,
including this one; not to be redistributed as raw stock, which is why each
clip here is cut, regraded, grained and re-encoded). Credits in
assets/cutscenes/video/CREDITS.md.

    python3 dev-tools/make_cutscene_video.py            # all
    python3 dev-tools/make_cutscene_video.py busted     # one

Needs curl and ffmpeg (with libtheora). Writes
assets/cutscenes/video/<scene>.ogv, 1280x720, 24 fps, no audio (the game
plays its own sound over it).
"""
import os
import subprocess
import sys
import tempfile

LENGTH = 3.0
# scene: (Mixkit id, start second, what it shows)
CLIPS = {
    "intro": (31415, 0.0, "Frustrated boy in his bed for not being able to sleep"),
    "busted": (49329, 9.9, "Handcuffed man walking to a police car"),
    "sent_away": (46820, 9.0, "Judge pronounces sentence in court"),
    "first_score": (18247, 1.0, "Hands of people during a money transaction"),
    "released": (17536, 3.0, "Hand on a wire fence by night"),
    "new_day": (3977, 2.0, "View of a window with a curtain"),
    "temptation": (6754, 3.0, "City street traffic by night"),
    "relapse": (3526, 0.0, "Street lamps at night"),
    "resisted": (22646, 0.5, "Crossing a wet road at night"),
    "recovered": (22240, 1.0, "Woman opening dark curtains"),
    "overdose": (17376, 3.0, "Police car lights flashing"),
}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cutscenes", "video")
# Cold and worn: less colour, a touch of contrast, teal shadows and amber
# highlights like the in-game LUT, moving grain, a vignette, and fades so
# the cut in and out is soft.
GRADE = ",".join([
    "scale=1280:720:force_original_aspect_ratio=increase", "crop=1280:720",
    "eq=saturation=0.72:contrast=1.1:brightness=-0.035:gamma=0.95",
    "colorbalance=rs=-0.05:gs=0.01:bs=0.06:rh=0.06:gh=0.02:bh=-0.05",
    "noise=alls=9:allf=t", "vignette=PI/4.2",
    "fade=t=in:st=0:d=0.25", f"fade=t=out:st={LENGTH - 0.35}:d=0.35",
    "fps=24", "format=yuv420p",
])


def build(scene: str) -> None:
    vid, start, _ = CLIPS[scene]
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, f"{vid}.mp4")
        subprocess.run(["curl", "-sfL", "-o", src, f"https://assets.mixkit.co/videos/{vid}/{vid}-720.mp4"], check=True)
        dst = os.path.join(OUT, scene + ".ogv")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-i", src, "-t", str(LENGTH),
                        "-vf", GRADE, "-an", "-c:v", "libtheora", "-q:v", "7", dst], check=True)
    print(f"{scene}: {os.path.getsize(dst) // 1024} KB")


if __name__ == "__main__":
    for s in sys.argv[1:] or CLIPS:
        build(s)
