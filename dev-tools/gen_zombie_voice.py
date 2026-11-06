#!/usr/bin/env python3
"""Synthesizes the zombies' voices (generated, not sampled: no licence to carry):
groans, a wet breathing rasp, windup snarls, the lunge roar, pain grunts.

A glottal pulse train with a wandering pitch (jitter, a slow glide), a growl made by
amplitude modulation around 40-75 Hz, noise for the breath and a vowel made by three
resonators whose centres glide from one vowel to the next. Everything is shaped by a
slow envelope and soft-clipped so it sounds strained rather than sung.

    python3 dev-tools/gen_zombie_voice.py       # writes assets/sfx/zombie/*.wav

The names are what npc/ZombieVoice.gd plays.
"""
import math
import os
import struct
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx", "zombie")
SR = 22050
TAU = 2 * math.pi

# Formant centres (F1, F2, F3) of the vowels the groans glide between.
VOWELS = {"u": (320, 800, 2200), "o": (450, 800, 2300), "a": (750, 1150, 2500), "e": (500, 1750, 2500), "i": (300, 2200, 2900)}


def n(sec):
    return int(round(SR * sec))


def smooth(x, k):
    """Moving average (k samples) -- a cheap low-pass for control curves and noise."""
    if k <= 1:
        return x
    c = np.cumsum(np.insert(x, 0, 0.0))
    y = (c[k:] - c[:-k]) / k
    return np.concatenate([np.full(k // 2, y[0]), y, np.full(len(x) - len(y) - k // 2, y[-1])])


def curve(rng, count, lo, hi, k):
    """A wandering control curve between lo and hi."""
    return lo + (hi - lo) * np.clip(0.5 + smooth(rng.standard_normal(count), k) * (k ** 0.5) * 0.45, 0.0, 1.0)


def glide(a, b, count, ease=1.0):
    t = np.linspace(0.0, 1.0, count) ** ease
    return a + (b - a) * t


def source(rng, f0, rough, breath):
    """Pulse train for a pitch curve f0 (Hz per sample); `rough` is the growl depth, `breath` the noise."""
    count = len(f0)
    jitter = 1.0 + smooth(rng.standard_normal(count), 40) * 1.8
    phase = np.cumsum(f0 * jitter / SR)
    saw = 2.0 * (phase % 1.0) - 1.0
    # A pulse-ish wave: a saw with a notch gives the buzzy edge of a strained throat.
    pulse = saw - 0.6 * np.sign(np.sin(TAU * phase * 0.5 + 0.3))
    grow_hz = rng.uniform(38, 70)
    am = 1.0 - rough * (0.5 + 0.5 * np.sin(TAU * grow_hz * np.arange(count) / SR + smooth(rng.standard_normal(count), 300) * 30))
    noise = smooth(rng.standard_normal(count), 3)
    return pulse * am + breath * noise


def resonate(x, centres, bw=(90, 130, 200), gains=(1.0, 1.0, 0.8)):
    """Three glide-able two-pole resonators; centres is (3, count) Hz."""
    count = len(x)
    out = np.zeros(count)
    for f in range(3):
        y1 = y2 = 0.0
        yy = np.empty(count)
        block = 32
        for s in range(0, count, block):
            fc = float(centres[f, s])
            r = math.exp(-math.pi * bw[f] / SR)
            a1 = -2.0 * r * math.cos(TAU * fc / SR)
            a2 = r * r
            g = (1.0 - r) * 2.0
            for i in range(s, min(s + block, count)):
                y = g * x[i] - a1 * y1 - a2 * y2
                yy[i] = y
                y2 = y1
                y1 = y
        out += yy * gains[f]
    # Pre-emphasis: a throat's sound is mostly mids and highs once it leaves the mouth.
    out[1:] = out[1:] - 0.92 * out[:-1]
    return out


def vowel_curve(seq, count):
    """Centres (3, count) gliding through the vowels in seq."""
    pts = [np.array(VOWELS[v], dtype=float) for v in seq]
    out = np.zeros((3, count))
    seg = len(pts) - 1
    for i in range(count):
        u = i / max(count - 1, 1) * seg
        a = min(int(u), seg - 1)
        t = u - a
        t = t * t * (3 - 2 * t)
        out[:, i] = pts[a] * (1 - t) + pts[a + 1] * t
    return out


def env(count, attack, release, shape=1.0, swell=0.0, rng=None):
    t = np.arange(count) / SR
    total = count / SR
    e = np.minimum(t / max(attack, 1e-3), 1.0) * np.minimum((total - t) / max(release, 1e-3), 1.0)
    e = np.clip(e, 0.0, 1.0) ** shape
    if swell:
        e *= 1.0 + swell * np.sin(TAU * (0.7 + 0.5 * (rng.random() if rng is not None else 0.5)) * t)
    return e


def finish(x, peak, drive=1.8):
    x = x / max(float(np.percentile(np.abs(x), 99.5)), 1e-6)
    x = np.tanh(x * drive)
    x = x / max(np.max(np.abs(x)), 1e-6) * peak
    # A little of the old DC out.
    x = x - smooth(x, 400)
    return x


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    x = np.clip(x, -1.0, 1.0)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in x))
    print("wrote %-14s %5.2fs peak %.2f rms %.3f" % (name, len(x) / SR, np.max(np.abs(x)), math.sqrt(float(np.mean(x * x)))))


def groan(seed, sec, f_hi, f_lo, vowels, rough):
    rng = np.random.default_rng(seed)
    c = n(sec)
    f0 = glide(f_hi, f_lo, c, 0.8) * (1.0 + 0.04 * np.sin(TAU * rng.uniform(4, 6) * np.arange(c) / SR))
    x = source(rng, f0, rough, 0.18)
    x = resonate(x, vowel_curve(vowels, c))
    x *= env(c, 0.18, 0.5, 0.8, 0.12, rng)
    return finish(x, 0.7, 1.2)


def rasp(seed, sec, inhale):
    """Breath through a wrecked throat: filtered noise with a wet crackle on top."""
    rng = np.random.default_rng(seed)
    c = n(sec)
    noise = rng.standard_normal(c)
    x = resonate(noise, vowel_curve(["e", "a"] if inhale else ["a", "o"], c), bw=(260, 400, 700))
    t = np.arange(c) / SR
    # In-breath swells to the end, out-breath is loud first.
    e = (t / sec) ** 1.4 if inhale else (1.0 - t / sec) ** 1.2
    e *= np.minimum(t / 0.06, 1.0) * np.minimum((sec - t) / 0.12, 1.0)
    crackle = (rng.random(c) > 0.9985).astype(float)
    crackle = smooth(crackle * rng.standard_normal(c) * 14.0, 6)
    x = x * e + crackle * e * 0.5
    return finish(x, 0.5, 1.0)


def snarl(seed, sec):
    rng = np.random.default_rng(seed)
    c = n(sec)
    f0 = glide(110, 190, c, 0.7)
    x = source(rng, f0, 0.85, 0.35)
    x = resonate(x, vowel_curve(["u", "a", "e"], c), bw=(120, 180, 260))
    x *= env(c, 0.06, 0.18, 0.9)
    return finish(x, 0.8, 1.6)


def lunge_roar(seed, sec):
    rng = np.random.default_rng(seed)
    c = n(sec)
    f0 = glide(230, 120, c, 0.6)
    x = source(rng, f0, 0.55, 0.3)
    x = resonate(x, vowel_curve(["o", "a", "a", "o"], c), bw=(130, 190, 280))
    x *= env(c, 0.05, 0.4, 0.7)
    return finish(x, 0.9, 1.8)


def pain(seed, sec, rising):
    rng = np.random.default_rng(seed)
    c = n(sec)
    f0 = glide(150, 230, c, 0.5) if rising else glide(210, 100, c, 0.6)
    x = source(rng, f0, 0.35, 0.2)
    x = resonate(x, vowel_curve(["a", "e"] if rising else ["a", "o"], c))
    x *= env(c, 0.015, 0.14, 0.8)
    return finish(x, 0.75, 1.5)


def main():
    save("groan_1", groan(1, 1.7, 105, 62, ["u", "o", "a"], 0.45))
    save("groan_2", groan(2, 2.1, 90, 55, ["o", "a", "u"], 0.55))
    save("groan_3", groan(3, 1.4, 130, 80, ["a", "o"], 0.4))
    save("groan_4", groan(4, 2.4, 80, 48, ["u", "a", "o", "u"], 0.6))
    save("groan_5", groan(5, 1.2, 150, 95, ["e", "a", "o"], 0.5))
    save("rasp_in_1", rasp(11, 0.75, True))
    save("rasp_in_2", rasp(12, 0.9, True))
    save("rasp_out_1", rasp(13, 0.95, False))
    save("rasp_out_2", rasp(14, 1.1, False))
    save("snarl_1", snarl(21, 0.55))
    save("snarl_2", snarl(22, 0.7))
    save("snarl_3", snarl(23, 0.45))
    save("lunge_1", lunge_roar(31, 0.9))
    save("lunge_2", lunge_roar(32, 1.1))
    save("pain_1", pain(41, 0.35, True))
    save("pain_2", pain(42, 0.45, False))
    save("pain_3", pain(43, 0.3, True))
    save("pain_4", pain(44, 0.5, False))


if __name__ == "__main__":
    main()
