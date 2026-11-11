#!/usr/bin/env python3
"""Checks assets/sfx/doors/*.ogg: length, peak, active RMS, silence before the sound, level of the last
100 ms (a clean tail), DC offset, and mains hum (50/60 Hz and harmonics against their neighbours).
Flags anything that fails. usage: door_sfx_report.py [dir]"""
import sys, os, glob, subprocess, wave, tempfile
import numpy as np

d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "doors")
print("%-14s %5s %6s %6s %6s %6s %6s %5s  %s" % ("file", "len", "peak", "rms", "lead", "tail", "hum", "dc", "flags"))
bad = 0
for f in sorted(glob.glob(os.path.join(d, "*.ogg"))):
	tmp = tempfile.mktemp(suffix=".wav")
	subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", f, "-ac", "1", "-ar", "44100", tmp], check=True)
	w = wave.open(tmp)
	a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768.0
	os.remove(tmp)
	db = lambda x: 20 * np.log10(max(x, 1e-6))
	peak = db(np.abs(a).max())
	act = a[np.abs(a) > 10 ** (-42 / 20)]
	rms = db(np.sqrt(np.mean(act ** 2))) if len(act) else -99
	n = int(0.008 * 44100)
	env = np.sqrt(np.convolve(a ** 2, np.ones(n) / n, mode="same"))
	nz = np.nonzero(env > 10 ** ((rms - 22.0) / 20))[0]
	lead = nz[0] / 44.1 if len(nz) else 999
	# The last 10 ms: a clean ending is silence (no click, no cut-off noise).
	tail = db(np.sqrt(np.mean(a[-441:] ** 2)))
	dc = abs(np.mean(a))
	spec = np.abs(np.fft.rfft(a * np.hanning(len(a))))
	freqs = np.fft.rfftfreq(len(a), 1 / 44100)
	hum = 0.0
	for base in (50.0, 60.0):
		for k in (1, 2, 3):
			f0 = base * k
			band = spec[(freqs > f0 - 1.5) & (freqs < f0 + 1.5)]
			near = spec[((freqs > f0 - 12) & (freqs < f0 - 4)) | ((freqs > f0 + 4) & (freqs < f0 + 12))]
			if len(band) and len(near) and near.mean() > 0:
				hum = max(hum, db(band.max() / near.mean()))
	flags = []
	if peak > -1.5: flags.append("CLIP")
	if lead > 12: flags.append("LEAD %.0fms" % lead)
	if tail > -60: flags.append("TAIL")
	if hum > 22: flags.append("HUM")
	if dc > 0.005: flags.append("DC")
	if len(a) / 44100 < 0.15: flags.append("SHORT")
	bad += bool(flags)
	print("%-14s %5.2f %6.1f %6.1f %6.1f %6.1f %6.1f %5.3f  %s" % (os.path.basename(f), len(a) / 44100, peak, rms, lead, tail, hum, dc, " ".join(flags)))
print("%d flagged" % bad)
