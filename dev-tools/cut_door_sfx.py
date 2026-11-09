#!/usr/bin/env python3
"""Cuts assets/sfx/doors/*.ogg out of freesound previews (CC0), see
assets/sfx/doors/CREDITS.txt. Source previews: python3 cut_door_sfx.py <raw dir>
where <raw dir>/<freesound id>.ogg is the "-hq.ogg" preview of that sound
(https://cdn.freesound.org/previews/<id//1000>/<id>_<user id>-hq.ogg).
Each cut: mono 44.1 kHz, 6 ms fades, peak-normalised to -3 dB, Vorbis q5."""
import sys, os, subprocess, wave, numpy as np

RAW = sys.argv[1]
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "doors")
# name: (freesound id, start s, end s or None, peak dB)
CUTS = {
	"bell": (192761, 0.0, 0.93, -4),
	"slam_wood_a": (571797, 0.95, 2.4, -2),
	"slam_wood_b": (455540, 1.05, 2.5, -2),
	"slam_wood_c": (455540, 3.25, 4.6, -3),
	"slam_light": (266440, 0.0, 1.03, -4),
	"slam_heavy": (462665, 2.3, 3.9, -2),
	"steel_slam_a": (341176, 15.7, 18.0, -3),
	"steel_slam_b": (475313, 0.0, 1.2, -3),
	"steel_bar": (341176, 0.08, 1.25, -4),
	"handle": (330828, 0.28, 0.72, -6),
	"latch": (330828, 0.78, 1.25, -5),
	"wood_close": (125958, 1.85, 2.9, -5),
	"rattle_a": (444704, 0.5, 1.6, -4),
	"rattle_b": (444704, 1.9, 3.0, -4),
	"rattle_c": (444704, 3.35, 4.45, -4),
	"creak_a": (455324, 0.4, 3.4, -9),
	"creak_b": (590950, 0.0, None, -9),
	"creak_c": (638490, 0.0, None, -9),
	"creak_d": (406598, 0.0, None, -9),
	"scrape_a": (641048, 0.0, 1.7, -4),
	"scrape_b": (679460, 0.0, None, -7),
}

def read(path):
	tmp = path + ".tmp.wav"
	subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-ac", "1", "-ar", "44100", tmp], check=True)
	w = wave.open(tmp)
	a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
	os.remove(tmp)
	return a

def main():
	os.makedirs(OUT, exist_ok=True)
	cache = {}
	for name, (fid, t0, t1, peak) in CUTS.items():
		if fid not in cache:
			cache[fid] = read(os.path.join(RAW, "%d.ogg" % fid))
		a = cache[fid]
		i0 = int(t0 * 44100)
		i1 = len(a) if t1 is None else min(len(a), int(t1 * 44100))
		seg = a[i0:i1].copy()
		fade = int(0.006 * 44100)
		seg[:fade] *= np.linspace(0, 1, fade)
		tail = min(len(seg), int(0.03 * 44100))
		seg[-tail:] *= np.linspace(1, 0, tail)
		m = np.abs(seg).max()
		seg *= (10 ** (peak / 20.0)) / max(m, 1e-6)
		tmp = os.path.join(OUT, name + ".wav")
		w = wave.open(tmp, "wb")
		w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
		w.writeframes((np.clip(seg, -1, 1) * 32767).astype(np.int16).tobytes())
		w.close()
		subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], check=True)
		os.remove(tmp)
		print(name, "%.2fs" % (len(seg) / 44100))

main()
