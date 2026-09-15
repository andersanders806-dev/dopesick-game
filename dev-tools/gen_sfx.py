#!/usr/bin/env python3
"""Procedurally synthesizes low-budget chiptune-style sound effects for
Dope Sick using pure stdlib (wave/struct/math/random) -- no external audio
libs or samples, matching the rest of the project's generated-not-sourced
asset pipeline. Outputs 16-bit mono PCM WAVs to dopesick-game/assets/sfx/.
"""
import math
import os
import random
import struct
import wave

OUT = "/home/anders/dopesick-game/assets/sfx"
os.makedirs(OUT, exist_ok=True)

SR = 22050


def save(name, samples):
    path = os.path.join(OUT, f"{name}.wav")
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
        f.writeframes(frames)
    print("wrote", name, f"({len(samples)/SR:.2f}s)")


def n_samples(seconds):
    return int(SR * seconds)


def envelope_ad(i, n, attack, decay_curve=2.0):
    """0..1 amplitude: quick linear attack, then a curved decay to 0."""
    a = int(n * attack)
    if i < a and a > 0:
        return i / a
    return max(0.0, (1 - (i - a) / max(1, n - a)) ** decay_curve)


def sine(freq, t):
    return math.sin(2 * math.pi * freq * t)


def square(freq, t):
    return 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0


def mix(*sigs):
    return sum(sigs) / len(sigs)


# --- one-shot SFX ---------------------------------------------------------

def gen_footstep(name, base_freq, seed):
    rng = random.Random(seed)
    n = n_samples(0.07)
    out = []
    for i in range(n):
        t = i / SR
        env = envelope_ad(i, n, 0.02, decay_curve=3.0)
        tone = sine(base_freq, t) * 0.5
        noise = (rng.random() * 2 - 1) * 0.5
        out.append((tone + noise) * env * 0.5)
    save(name, out)


def gen_door():
    n = n_samples(0.22)
    out = []
    for i in range(n):
        t = i / SR
        frac = i / n
        freq = 220 + 180 * math.sin(frac * math.pi)
        env = envelope_ad(i, n, 0.05, decay_curve=1.5)
        noise = (random.random() * 2 - 1) * 0.15
        out.append((square(freq, t) * 0.5 + noise) * env * 0.35)
    save("door", out)


def gen_steal():
    n = n_samples(0.18)
    out = []
    for i in range(n):
        t = i / SR
        frac = i / n
        freq = 500 + 700 * frac
        env = envelope_ad(i, n, 0.05, decay_curve=2.0)
        out.append(square(freq, t) * env * 0.35)
    save("steal", out)


def gen_cash():
    notes = [523.25, 659.25, 783.99, 1046.5]  # C5 E5 G5 C6
    note_len = 0.09
    out = []
    for note_i, freq in enumerate(notes):
        n = n_samples(note_len)
        for i in range(n):
            t = i / SR
            env = envelope_ad(i, n, 0.1, decay_curve=2.5)
            out.append(mix(sine(freq, t), sine(freq * 2, t) * 0.3) * env * 0.4)
    save("cash", out)


def gen_busted():
    n = n_samples(0.6)
    out = []
    for i in range(n):
        t = i / SR
        frac = i / n
        freq = 300 - 220 * frac
        env = envelope_ad(i, n, 0.03, decay_curve=1.2)
        wobble = 1.0 + 0.15 * math.sin(2 * math.pi * 14 * t)
        val = square(freq * wobble, t)
        val = max(-0.7, min(0.7, val * 1.6))  # soft clip / distortion
        out.append(val * env * 0.45)
    save("busted", out)


def gen_blip():
    n = n_samples(0.05)
    out = []
    for i in range(n):
        t = i / SR
        env = envelope_ad(i, n, 0.15, decay_curve=2.0)
        out.append(square(900, t) * env * 0.3)
    save("blip", out)


def gen_fix():
    n = n_samples(0.5)
    out = []
    freq = 660.0
    for i in range(n):
        t = i / SR
        env = envelope_ad(i, n, 0.08, decay_curve=1.6)
        val = mix(sine(freq, t), sine(freq * 1.5, t) * 0.5, sine(freq * 2, t) * 0.25)
        out.append(val * env * 0.4)
    save("fix", out)


def gen_sleep():
    n = n_samples(0.5)
    out = []
    for i in range(n):
        t = i / SR
        frac = i / n
        freq = 440 - 260 * frac
        env = envelope_ad(i, n, 0.2, decay_curve=1.4)
        out.append(sine(freq, t) * env * 0.35)
    save("sleep", out)


def gen_phone():
    n = n_samples(0.32)
    out = []
    for i in range(n):
        t = i / SR
        cycle = (t * 5) % 1.0
        gate = 1.0 if cycle < 0.5 else 0.0
        env = envelope_ad(i, n, 0.1, decay_curve=1.0)
        out.append(mix(sine(1000, t), sine(1200, t)) * gate * env * 0.3)
    save("phone", out)


# --- looping ambience -------------------------------------------------------

def gen_siren():
    duration = 2.0
    n = n_samples(duration)
    out = []
    for i in range(n):
        t = i / SR
        lfo = (math.sin(2 * math.pi * 1.0 * t) + 1) / 2  # 0..1, 1Hz, seamless loop
        freq = 480 + 260 * lfo
        out.append(sine(freq, t) * 0.28)
    save("siren_loop", out)


def gen_heartbeat():
    duration = 1.0
    n = n_samples(duration)
    out = [0.0] * n

    def thump(center_time, freq_start=90, freq_end=45, length=0.14, amp=0.6):
        start = n_samples(center_time)
        ln = n_samples(length)
        for j in range(ln):
            idx = start + j
            if idx >= n:
                break
            t = j / SR
            frac = j / ln
            freq = freq_start + (freq_end - freq_start) * frac
            env = envelope_ad(j, ln, 0.05, decay_curve=1.8)
            out[idx] += sine(freq, t) * env * amp

    thump(0.0)
    thump(0.22, amp=0.42)
    save("heartbeat_loop", out)


gen_footstep("footstep_a", 90, 1)
gen_footstep("footstep_b", 80, 2)
gen_door()
gen_steal()
gen_cash()
gen_busted()
gen_blip()
gen_fix()
gen_sleep()
gen_phone()
gen_siren()
gen_heartbeat()

print("done:", sorted(os.listdir(OUT)))
