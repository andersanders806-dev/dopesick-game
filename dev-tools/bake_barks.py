#!/usr/bin/env python3
"""Bakes the guards' barks (npc/Guard3D.gd BARKS) with Piper into assets/voice/, under the
file names autoload/Voice.gd looks them up by (speaker id + md5 of "rate|line"). Piper lives in
the main checkout's tools/piper (not in git).

  python3 dev-tools/bake_barks.py /path/to/tools/piper
"""
import hashlib, os, subprocess, sys

PIPER = sys.argv[1] if len(sys.argv) > 1 else "tools/piper"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "voice")
# Voice.CAST: speaker -> (id, rate as GDScript prints it)
SPEAKERS = {"Clerk": (684, "1.0"), "Security": (720, "1.05")}
LINES = ["Hm?", "Huh?", "Who's there?", "What was that?"]

for who, (sid, rate) in SPEAKERS.items():
    for line in LINES:
        key = "%d_%s" % (sid, hashlib.md5(("%s|%s" % (rate, line)).encode()).hexdigest()[:16])
        out = os.path.join(OUT, key + ".wav")
        subprocess.run("printf '%%s' \"$LINE\" | ./piper -m en_US-libritts_r-medium.onnx -s %d --length_scale %s "
                       "--sentence_silence 0.15 -f '%s' >/dev/null 2>&1" % (sid, rate, out),
                       shell=True, cwd=PIPER, env=dict(os.environ, LINE=line, LD_LIBRARY_PATH=PIPER), check=True)
        print(who, line, "->", key)
