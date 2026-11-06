#!/usr/bin/env python3
"""Ghetto Wars' set sounds (assets/sfx/ghetto/), synthesised from noise and sines, nothing sampled:
spray_hiss (a can being shaken, then the hiss), pickup_pill (a bottle rattled), pickup_cash (a roll
riffled), search_lock (the searchlight finding you: a low thump and a rising whine), tyre_squeal.

    /home/anders/dopesick-game/.venv-portraits/bin/python3 dev-tools/gen_ghetto_sfx.py
"""
import os
import wave

import numpy as np

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx", "ghetto")
os.makedirs(OUT, exist_ok=True)
SR = 22050
rng = np.random.default_rng(5)


def save(name, x):
    x = np.clip(x / max(1e-6, np.abs(x).max()) * 0.8, -1, 1)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print("wrote", name)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")


def highpass(x, k):
    return x - lowpass(x, k)


def click(n, at, x, amp=1.0, ring=3000):
    tt = np.arange(n) / SR
    x[at:at + n] += amp * np.sin(tt * ring * 2 * np.pi) * np.exp(-tt * 90) * rng.uniform(0.7, 1.0)


def spray_hiss():
    x = np.zeros(int(SR * 1.5))
    for i in range(7):  # the rattle
        click(500, int(SR * (0.03 + i * 0.065 + rng.uniform(0, 0.02))), x, 0.7, rng.uniform(2200, 4200))
    n = highpass(rng.standard_normal(len(x)), 6)
    env = np.zeros(len(x))
    s, e = int(SR * 0.5), int(SR * 1.45)
    env[s:e] = np.minimum(1, (np.arange(e - s) / (SR * 0.04))) * np.exp(-np.arange(e - s) / SR * 1.2)
    save("spray_hiss", x + n * env * 0.55)


def pickup_pill():
    x = np.zeros(int(SR * 0.5))
    for i in range(9):
        click(400, int(SR * (0.01 + i * 0.035 + rng.uniform(0, 0.015))), x, rng.uniform(0.3, 0.8), rng.uniform(2800, 5200))
    click(900, int(SR * 0.33), x, 1.0, 900)  # the cap
    save("pickup_pill", x)


def pickup_cash():
    n = highpass(rng.standard_normal(int(SR * 0.45)), 8)
    tt = t(0.45)
    env = np.abs(np.sin(tt * 2 * np.pi * 28)) ** 0.7 * np.exp(-tt * 7)
    save("pickup_cash", n * env)


def search_lock():
    tt = t(1.2)
    thump = np.sin(2 * np.pi * (70 - 35 * tt) * tt) * np.exp(-tt * 7)
    whine = np.sin(2 * np.pi * (300 + 700 * tt ** 1.5) * tt) * np.minimum(1, tt * 8) * np.exp(-tt * 2.2) * 0.35
    save("search_lock", thump + whine)


def tyre_squeal():
    tt = t(1.4)
    f = 1500 + 260 * np.sin(2 * np.pi * 7 * tt) + 200 * tt
    sq = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5 + highpass(rng.standard_normal(len(tt)), 5) * 0.35
    env = np.minimum(1, tt * 10) * np.minimum(1, (1.4 - tt) * 4)
    save("tyre_squeal", sq * env)


if __name__ == "__main__":
    spray_hiss()
    pickup_pill()
    pickup_cash()
    search_lock()
    tyre_squeal()
