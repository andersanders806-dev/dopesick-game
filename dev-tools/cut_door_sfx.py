#!/usr/bin/env python3
"""Cuts assets/sfx/doors/*.ogg out of freesound previews (CC0), see
assets/sfx/doors/CREDITS.txt. Source previews: python3 cut_door_sfx.py <raw dir>
where <raw dir>/<freesound id>.ogg is the "-hq.ogg" preview of that sound
(https://cdn.freesound.org/previews/<id//1000>/<id>_<user id>-hq.ogg).
Each cut: mono 44.1 kHz, silence before the sound trimmed, a short fade in, a cosine fade out (0.12-0.35 s), level set by class (RMS) with the peak held under -2.5 dB, Vorbis q5."""
import sys, os, subprocess, wave, numpy as np

RAW = sys.argv[1]
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "doors")
# name: (freesound id, start s, end s or None, class). The class sets the level: active RMS (dBFS)
# per kind of sound, with the peak held under PEAK_CAP, so one door's layers sit together.
CUTS = {
	"bell": (192761, 0.0, 0.93, "bell"),
	"slam_wood_a": (571797, 0.95, 2.4, "slam"),
	"slam_wood_b": (455540, 1.095, 2.5, "slam"),
	"slam_wood_c": (455540, 3.25, 4.6, "slam"),
	"slam_light": (266440, 0.0, 1.03, "slam"),
	"slam_heavy": (462665, 2.40, 3.9, "slam"),
	"steel_slam_a": (341176, 15.7, 18.0, "slam"),
	"steel_slam_b": (583059, 5.0, 6.05, "slam"),
	"steel_bar": (341176, 0.08, 1.25, "bar"),
	"handle": (330828, 0.28, 0.72, "handle"),
	"latch": (330828, 0.82, 1.25, "latch"),
	"wood_close": (125958, 1.85, 2.9, "close"),
	"rattle_a": (444704, 0.5, 1.6, "rattle"),
	"rattle_b": (444704, 1.9, 3.0, "rattle"),
	"rattle_c": (444704, 3.35, 4.45, "rattle"),
	"creak_a": (455324, 0.4, 3.4, "creak"),
	"creak_b": (590950, 0.0, None, "creak"),
	"creak_c": (638490, 0.0, None, "creak"),
	"creak_d": (406598, 0.0, None, "creak"),
	"scrape_a": (641048, 0.0, 1.7, "scrape"),
	"scrape_b": (679460, 0.0, None, "scrape"),
	# Automatic sliding doors (a supermarket's): the motor and the panels, open and close, and the chime.
	"slide_open": (195906, 0.43, 2.45, "slide"),
	"slide_close": (195906, 5.2, 7.3, "slide"),
	"chime": (555016, 0.0, 1.9, "chime"),
}
RMS_DB = {"bell": -19.0, "chime": -21.0, "slam": -14.0, "bar": -18.0, "handle": -22.0, "latch": -20.0, "close": -18.0,
	"rattle": -22.0, "creak": -26.0, "scrape": -22.0, "slide": -25.0}
PEAK_CAP_DB = -3.5
# Recordings with mains hum in them.
HUM = {"steel_bar", "steel_slam_a"}
LEAD_DB = -38.0

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
		act = seg[np.abs(seg) > 10 ** (-42.0 / 20.0)]
		rms = np.sqrt(np.mean(act ** 2)) if len(act) > 0 else 1e-6
		gain = (10 ** (RMS_DB[peak] / 20.0)) / max(rms, 1e-6)
		m = np.abs(seg).max() * gain
		if m > 10 ** (PEAK_CAP_DB / 20.0):
			gain *= (10 ** (PEAK_CAP_DB / 20.0)) / m
		seg *= gain
		# Cut any silence before the sound starts (a door's click shouldn't arrive late).
		# (By a 3 ms RMS envelope, so one stray click doesn't count as the start.)
		n = int(0.008 * 44100)
		env = np.sqrt(np.convolve(seg ** 2, np.ones(n) / n, mode="same"))
		lead = np.nonzero(env > 10 ** ((RMS_DB[peak] - 22.0) / 20.0))[0]
		if len(lead) > 0 and lead[0] > int(0.006 * 44100):
			seg = seg[max(0, lead[0] - int(0.004 * 44100)):]
		fade = int(0.004 * 44100)
		seg[:fade] *= np.linspace(0, 1, fade)
		# A tail that really dies away: a cosine fade as long as it takes (0.12-0.35 s).
		tail = min(len(seg), int(max(0.12, min(0.35, 0.15 * len(seg) / 44100)) * 44100))
		seg[-tail:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, tail)))
		tmp = os.path.join(OUT, name + ".wav")
		w = wave.open(tmp, "wb")
		w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
		w.writeframes((np.clip(seg, -1, 1) * 32767).astype(np.int16).tobytes())
		w.close()
		# No DC or rumble under 35 Hz; a notch at the mains hum (50/60 Hz and their harmonics) where a recording has it.
		flt = "highpass=f=35"
		if name in HUM:
			flt += "," + ",".join("bandreject=f=%d:width_type=h:w=6" % f for f in (50, 60, 100, 120, 150, 180))
		flt += ",afade=t=out:st=%.3f:d=0.06" % (len(seg) / 44100 - 0.06)
		subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-af", flt, "-c:a", "libvorbis", "-q:a", "5", os.path.join(OUT, name + ".ogg")], check=True)
		os.remove(tmp)
		print(name, "%.2fs" % (len(seg) / 44100))

main()
