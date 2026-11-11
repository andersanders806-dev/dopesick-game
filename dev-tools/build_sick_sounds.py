#!/usr/bin/env python3
"""Cuts assets/sfx/sick/*.wav (withdrawal coughs, sniffs, a breath catch, a retch,
a fumbled item, the flat exhale and the dose swell) from the BBC Sound Effects
archive (RemArc licence, non-commercial) and the game's own CC0 piano loop.
Sources go in audio-real/_downloads/ (bbc/, bbc_sick/); IDs, cut points and
licence in assets/sfx/CREDITS/sick-stealth.md. Needs ffmpeg.

  python3 dev-tools/build_sick_sounds.py [audio-real dir]
"""
import subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "..", "..", "audio-real", "_downloads")
OUT = os.path.join(ROOT, "assets", "sfx", "sick")
os.makedirs(OUT, exist_ok=True)

def cut(name, src, a, b, af="", fade_in=0.004, fade_out=0.08, peak_db=-3.0, rate=44100):
    """Cut [a, b] s from src, filter, fade, normalise to peak_db, write mono 16-bit WAV."""
    dur = b - a
    chain = [af] if af else []
    chain.append("afade=t=in:d=%.3f" % fade_in)
    chain.append("afade=t=out:st=%.3f:d=%.3f" % (max(0.0, dur - fade_out), fade_out))
    chain.append("alimiter=limit=0.95")
    tmp = os.path.join(OUT, "_tmp.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(a), "-t", str(dur), "-i", src, "-ac", "1",
                    "-ar", str(rate), "-af", ",".join(chain), tmp], check=True)
    # Normalise by measured peak.
    vol = subprocess.run(["ffmpeg", "-v", "info", "-i", tmp, "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    mx = [float(l.split("max_volume:")[1].split("dB")[0]) for l in vol.splitlines() if "max_volume" in l][0]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-af", "volume=%.2fdB" % (peak_db - mx),
                    "-c:a", "pcm_s16le", os.path.join(OUT, name + ".wav")], check=True)
    os.remove(tmp)
    print("wrote", name)

B1 = os.path.join(SRC, "bbc_sick", "07071005.wav")   # One male coughing
B2 = os.path.join(SRC, "bbc_sick", "07034127.wav")   # Man blowing nose
B3 = os.path.join(SRC, "bbc_sick", "07034131.wav")   # Six belches
B4 = os.path.join(SRC, "bbc", "07034133.wav")        # Heavy breathing
B5 = os.path.join(SRC, "bbc_sick", "07002106.wav")   # A bucket dropped three times

# Single coughs (a mild burst) and run-on coughing fits (a severe one).
cut("cough_1", B1, 0.25, 1.30)
cut("cough_2", B1, 6.40, 7.30)
cut("cough_3", B1, 9.05, 10.0)
cut("cough_4", B1, 25.40, 26.40)
cut("cough_fit_1", B1, 11.70, 13.70, fade_out=0.25)
cut("cough_fit_2", B1, 28.40, 30.50, fade_out=0.30)
# Held back behind a hand: the same coughs, dull and quiet.
cut("cough_stifled_1", B1, 6.40, 7.30, af="lowpass=f=900,lowpass=f=900,asetrate=44100*0.9,aresample=44100", peak_db=-12.0)
cut("cough_stifled_2", B1, 9.05, 10.0, af="lowpass=f=800,lowpass=f=800,asetrate=44100*0.92,aresample=44100", peak_db=-12.0)
# A strain with nothing coming out: the breath held against the chest.
cut("stifle_strain", B4, 28.85, 29.60, af="lowpass=f=1100,asetrate=44100*0.8,aresample=44100", fade_in=0.15, fade_out=0.3, peak_db=-14.0)
# Sniffs: the quick ones from the start of the blowing-nose recording.
cut("sniff_1", B2, 0.78, 1.32, fade_out=0.06)
cut("sniff_2", B2, 13.55, 14.25, fade_out=0.08)
# The breath caught sharp, before the burst.
cut("breath_catch", B4, 28.92, 29.38, fade_in=0.02, fade_out=0.12, peak_db=-8.0)
# Retching: the heaved belches.
cut("retch_1", B3, 10.95, 11.85, fade_out=0.2)
cut("retch_2", B3, 16.10, 16.85, fade_out=0.15)
# Something let go of: a bucket hit the floor, harder than a carton, so it carries.
cut("drop_1", B5, 6.75, 8.10, fade_out=0.3)
cut("drop_2", B5, 1.05, 2.10, fade_out=0.25)
# What a dose does once it no longer does anything but stop the pain: a long dull breath out.
cut("exhale_flat", B4, 31.75, 32.60, af="lowpass=f=2200,asetrate=44100*0.85,aresample=44100", fade_in=0.08, fade_out=0.4, peak_db=-9.0)

# The dose swell: the piano loop's decaying chord run backwards into itself, so it blooms
# and then settles (assets/music/shelter_piano.ogg, CC0).
import numpy as np, wave
piano = os.path.join(ROOT, "assets", "music", "shelter_piano.ogg")
raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", "34.8", "-t", "3.6", "-i", piano, "-ac", "1", "-ar", "44100",
                      "-af", "lowpass=f=3200", "-f", "f32le", "-"], capture_output=True).stdout
x = np.frombuffer(raw, dtype=np.float32).copy()
sr = 44100
n = len(x)
rev = x[::-1].copy()
rev *= np.linspace(0.0, 1.0, n) ** 1.6                       # blooms in
fwd = x.copy()
fwd *= np.linspace(1.0, 0.0, n) ** 1.2                       # then settles
cross = int(sr * 0.6)
out = np.zeros(n + n - cross, dtype=np.float32)
out[:n] += rev
out[n - cross:] += fwd
out *= np.clip(np.arange(len(out)) / (sr * 0.05), 0, 1) * np.clip((len(out) - np.arange(len(out))) / (sr * 1.0), 0, 1)
out *= 10 ** (-6.0 / 20) / np.abs(out).max()
with wave.open(os.path.join(OUT, "dose_swell.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((np.clip(out, -1, 1) * 32767).astype("<i2").tobytes())
print("wrote dose_swell")
