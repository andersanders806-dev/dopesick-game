#!/usr/bin/env python3
"""Synthesizes the pool minigame's sounds (assets/sfx/pool_*.wav): ball on
ball, ball on cushion, cue tip on ball, and a ball dropping into a pocket.
Synthesized rather than sampled so there's no licence to track -- the
open-source pool games checked on GitHub ship recordings without one.

    .venv-portraits/bin/python3 dev-tools/gen_pool_sfx.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def partials(freqs, decays, amps, sec):
    x = t(sec)
    return sum(a * np.sin(2 * np.pi * f * x) * np.exp(-x / d) for f, d, a in zip(freqs, decays, amps))


def lowpass(sig, cutoff):
    # One-pole, run forward and back for a gentle slope and no phase smear.
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.zeros_like(sig)
    for pass_ in range(2):
        y = 0.0
        src = sig if pass_ == 0 else out[::-1].copy()
        res = np.zeros_like(sig)
        for i, v in enumerate(src):
            y = (1 - a) * v + a * y
            res[i] = y
        out = res if pass_ == 0 else res[::-1]
    return out


def burst(sec, decay, cutoff):
    x = t(sec)
    return lowpass(rng.standard_normal(len(x)) * np.exp(-x / decay), cutoff)


def save(name, sig, gain=0.9):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * gain
    # 3 ms fade in, so nothing clicks at the start.
    n = int(SR * 0.003)
    sig[:n] *= np.linspace(0, 1, n)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())
    print("wrote", name)


# Phenolic resin on resin: bright, glassy, very short.
clack = partials([2950, 4380, 6120, 8200], [0.012, 0.008, 0.005, 0.003], [1.0, 0.6, 0.35, 0.2], 0.12)
clack += 0.5 * burst(0.12, 0.0015, 9000)
save("pool_clack.wav", clack)

# Rubber cushion under cloth: a dull thump with a little wood knock.
cushion = partials([165, 330, 900], [0.035, 0.02, 0.008], [1.0, 0.4, 0.25], 0.2)
cushion += 0.6 * burst(0.2, 0.012, 1400)
save("pool_cushion.wav", cushion, 0.8)

# Leather tip on the cue ball: soft click, then the shaft's woody ring.
cue = partials([1250, 2300, 420], [0.006, 0.004, 0.03], [0.8, 0.4, 0.5], 0.15)
cue += 0.4 * burst(0.15, 0.002, 5000)
save("pool_cue.wav", cue, 0.8)

# Into the pocket: a knock on the jaw, a leather thud, then the ball
# rattling to a stop in the pocket bag.
x = t(0.7)
pocket = np.zeros_like(x)
pocket[: len(t(0.15))] += 0.7 * partials([2600, 3900], [0.006, 0.004], [1, 0.5], 0.15)
thud = partials([110, 220], [0.06, 0.03], [1.0, 0.4], 0.3) + 0.5 * burst(0.3, 0.02, 700)
start = int(SR * 0.035)
pocket[start:start + len(thud)] += thud
for k, at in enumerate([0.16, 0.25, 0.32, 0.37, 0.41, 0.44]):
    s = int(SR * at)
    tick = (0.35 / (k + 1)) * partials([1900 + 150 * k, 3100], [0.004, 0.003], [1, 0.4], 0.05)
    pocket[s:s + len(tick)] += tick[: len(pocket) - s]
save("pool_pocket.wav", pocket, 0.85)
