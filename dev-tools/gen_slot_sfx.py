#!/usr/bin/env python3
"""Synthesizes the Dive Bar slot machine's sounds (assets/sfx/slot_*.wav):
the reel motor with its ratchet, a reel clunking to a stop, the lever's
ratchet and spring, the coin dropping through the slot, the rising tone of a
third reel that could still land it, and the bells for a win and for the
jackpot. Synthesized like the pool sounds, so there's no licence to track;
the chip and coin rattles of the payout are Kenney's CC0 Casino Audio
(assets/sfx/kenney_casino/).

    .venv-portraits/bin/python3 dev-tools/gen_slot_sfx.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")
rng = np.random.default_rng(77)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def onepole(sig, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.empty_like(sig)
    y = 0.0
    for i, v in enumerate(sig):
        y = (1 - a) * v + a * y
        out[i] = y
    return out


def highpass(sig, cutoff):
    return sig - onepole(sig, cutoff)


def click(sec=0.012, cutoff=6000, decay=0.002):
    x = t(sec)
    return highpass(rng.standard_normal(len(x)) * np.exp(-x / decay), cutoff * 0.3)


def bell(f, sec, decay, amp=1.0):
    # Inharmonic partials of a small struck bell.
    x = t(sec)
    ratios = [1.0, 2.0, 2.76, 5.4, 8.9]
    amps = [1.0, 0.5, 0.35, 0.18, 0.08]
    sig = sum(a * np.sin(2 * np.pi * f * r * x) * np.exp(-x / (decay / (1 + 0.6 * k)))
              for k, (r, a) in enumerate(zip(ratios, amps)))
    return amp * sig


def place(dst, src, at):
    i = int(at * SR)
    n = min(len(src), len(dst) - i)
    if n > 0:
        dst[i:i + n] += src[:n]


def save(name, sig, gain=0.9, fade_out=0.0):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * gain
    n = int(SR * 0.003)
    sig[:n] *= np.linspace(0, 1, n)
    if fade_out > 0:
        m = int(SR * fade_out)
        sig[-m:] *= np.linspace(1, 0, m)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())
    print("wrote", name)


def reel_loop():
    # Exactly 1 s so it loops seamlessly: a motor hum at 60 Hz (whole number
    # of cycles) and 24 ratchet ticks off the reel teeth.
    sec = 1.0
    x = t(sec)
    hum = 0.25 * np.sin(2 * np.pi * 60 * x) + 0.12 * np.sin(2 * np.pi * 120 * x) + 0.05 * np.sin(2 * np.pi * 180 * x)
    hiss = onepole(rng.standard_normal(len(x)), 900) * 0.15
    sig = hum + hiss
    for k in range(24):
        place(sig, click(0.02, 5000, 0.0025) * (0.55 + 0.1 * rng.random()), k / 24.0)
    return sig


def reel_stop():
    sec = 0.35
    x = t(sec)
    thud = np.sin(2 * np.pi * (95 - 40 * x) * x) * np.exp(-x / 0.05)
    metal = bell(1450, sec, 0.04, 0.25)
    sig = thud + metal
    place(sig, click(0.02, 7000, 0.003) * 1.2, 0.0)
    place(sig, click(0.02, 6000, 0.002) * 0.4, 0.045)  # the latch settling
    return sig


def lever():
    sec = 0.75
    sig = np.zeros(int(SR * sec))
    # Ratchet going down, clicks speeding up.
    at = 0.0
    for k in range(9):
        place(sig, click(0.02, 4500, 0.003) * (0.6 + 0.05 * k), at)
        at += 0.045 - k * 0.003
    # The spring: a damped, slightly detuned twang.
    x = t(0.45)
    spring = (np.sin(2 * np.pi * 210 * x * (1 + 0.15 * np.exp(-x / 0.05))) * np.exp(-x / 0.12)
              + 0.4 * np.sin(2 * np.pi * 523 * x) * np.exp(-x / 0.06))
    place(sig, spring * 0.5, at + 0.02)
    place(sig, click(0.03, 3000, 0.004) * 1.2, at)
    return sig


def coin_in():
    sec = 0.6
    sig = np.zeros(int(SR * sec))
    # Clink on the slot, a short slide, two bounces in the box.
    place(sig, bell(2800, 0.3, 0.05, 0.8), 0.0)
    slide = highpass(rng.standard_normal(int(SR * 0.12)), 2000) * np.linspace(0.25, 0.0, int(SR * 0.12))
    place(sig, slide, 0.03)
    place(sig, bell(2350, 0.25, 0.04, 0.6), 0.2)
    place(sig, bell(2350, 0.2, 0.03, 0.3), 0.3)
    return sig


def anticipation():
    # 1.6 s rising tremolo: the third reel's still turning and you know it.
    sec = 1.6
    x = t(sec)
    f = 330 * np.power(2, x / sec * 1.0)
    phase = 2 * np.pi * np.cumsum(f) / SR
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * (8 + 10 * x / sec) * x)
    sig = (np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.15 * np.sin(3 * phase)) * trem
    sig *= np.minimum(1.0, x / 0.2)
    return sig


C5, E5, G5, C6, E6, G6 = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0


def win_small():
    sec = 1.2
    sig = np.zeros(int(SR * sec))
    for k, f in enumerate([C5, E5, G5, C6]):
        place(sig, bell(f, 0.9, 0.35), k * 0.09)
    return sig


def win_big():
    sec = 3.2
    sig = np.zeros(int(SR * sec))
    seq = [C5, E5, G5, C6, G5, C6, E6, G6] * 2
    for k, f in enumerate(seq):
        place(sig, bell(f, 1.2, 0.4, 0.8 + 0.2 * (k % 2)), k * 0.11)
    # A ringing alarm bell under it.
    x = t(2.0)
    ring = bell(2093, 2.0, 1.5, 0.3) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 18 * x)))
    place(sig, ring, 0.3)
    return sig


def lose():
    # Two falling notes, quiet: the machine shrugging.
    sec = 0.6
    sig = np.zeros(int(SR * sec))
    place(sig, bell(392.0, 0.4, 0.15, 0.6), 0.0)
    place(sig, bell(311.1, 0.45, 0.18, 0.6), 0.14)
    return sig


def tick():
    # A meter tick for counting the credits up.
    sig = bell(3150, 0.08, 0.015, 1.0)
    place(sig, click(0.01, 8000, 0.001) * 0.3, 0.0)
    return sig


save("slot_reel_loop.wav", reel_loop(), 0.55)
save("slot_reel_stop.wav", reel_stop(), 0.9)
save("slot_lever.wav", lever(), 0.85)
save("slot_coin_in.wav", coin_in(), 0.7)
save("slot_anticipation.wav", anticipation(), 0.5, 0.05)
save("slot_win_small.wav", win_small(), 0.75, 0.1)
save("slot_win_big.wav", win_big(), 0.8, 0.3)
save("slot_lose.wav", lose(), 0.5, 0.05)
save("slot_tick.wav", tick(), 0.5)
