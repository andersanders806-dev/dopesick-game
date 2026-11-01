#!/usr/bin/env python3
"""Wind that rises: 8 s seamless loop of filtered noise with slow gusts and a low howl.
Writes assets/sfx/tsunami/wind_rise_loop.wav (44.1 kHz, 16-bit mono). Deterministic."""
import numpy as np, wave, os
sr = 44100
n = sr * 8
rng = np.random.default_rng(31)
def circ_filter(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / sr)
    mask = np.exp(-(fr / hi) ** 2) * (1 - np.exp(-(fr / max(lo, 1)) ** 2))
    return np.fft.irfft(f * mask, len(x))
noise = rng.standard_normal(n)
body = circ_filter(noise, 120, 900)
hiss = circ_filter(rng.standard_normal(n), 1800, 6500) * 0.35
t = np.arange(n) / sr
# gusts: slow periodic swells (periods divide 8 s so the loop is seamless)
gust = 0.55 + 0.25 * np.sin(2 * np.pi * t / 8 * 2 + 0.7) + 0.2 * np.sin(2 * np.pi * t / 8 * 5 + 2.1)
howl_f = 310 + 60 * np.sin(2 * np.pi * t / 8 * 3)
howl = np.sin(2 * np.pi * np.cumsum(howl_f) / sr) * 0.05 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 8 * 4 + 1.0))
sig = (body * 1.0 + hiss) * gust + howl
sig = sig / np.max(np.abs(sig)) * 0.89
out = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "tsunami", "wind_rise_loop.wav")
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((sig * 32767).astype("<i2").tobytes())
print("wrote", out)
