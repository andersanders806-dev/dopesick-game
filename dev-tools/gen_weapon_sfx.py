#!/usr/bin/env python3
"""Synthesizes the first-person combat sounds -- rifle and pistol shots,
reload, dry fire, impacts, hitmarker, hurt -- in the same pure-stdlib,
generated-not-sourced way as gen_sfx.py. Writes 16-bit mono WAVs next to
the rest of the game's sounds in assets/sfx/.

    python3 dev-tools/gen_weapon_sfx.py
"""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
os.makedirs(OUT, exist_ok=True)

SR = 44100


def save(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = 0.95 / peak if peak > 0.95 else 1.0
    path = os.path.join(OUT, f"{name}.wav")
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples))
    print("wrote", name, f"({len(samples) / SR:.2f}s)")


def lowpass(samples, cutoff):
    """One-pole low-pass: cheap, and enough to take the fizz off white noise."""
    rc = 1.0 / (2 * math.pi * cutoff)
    a = (1.0 / SR) / (rc + 1.0 / SR)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    lp = lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, lp)]


def gunshot(seed, length, crack_cut, body_hz, tail, crack_gain=1.0):
    """A shot is three layers: a bright crack (the muzzle blast), a low thump
    (the chest-hit you feel), and a long filtered tail (the room answering)."""
    rng = random.Random(seed)
    n = int(SR * length)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    crack = lowpass(noise, crack_cut)
    body = lowpass(noise, 900)
    out = []
    for i in range(n):
        t = i / SR
        env_crack = math.exp(-t * 38.0)
        env_body = math.exp(-t * 14.0)
        env_tail = math.exp(-t * (1.0 / tail)) * min(1.0, t * 60)
        thump = math.sin(2 * math.pi * body_hz * t * (1.0 - t * 0.8)) * math.exp(-t * 22.0)
        s = crack[i] * env_crack * 1.6 * crack_gain + body[i] * env_body * 1.1 + thump * 0.9 + body[i] * env_tail * 0.35
        # A hard transient for the first couple of milliseconds.
        if t < 0.002:
            s += rng.uniform(-1, 1) * 1.2
        out.append(s)
    return out


def click(seed, length, freq, decay, noise_amt=0.5):
    rng = random.Random(seed)
    n = int(SR * length)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * decay)
        out.append((math.sin(2 * math.pi * freq * t) * 0.6 + rng.uniform(-1, 1) * noise_amt) * env)
    return highpass(out, 400)


def silence(seconds):
    return [0.0] * int(SR * seconds)


def mix_at(base, add, at_seconds, gain=1.0):
    start = int(at_seconds * SR)
    need = start + len(add)
    if need > len(base):
        base = base + [0.0] * (need - len(base))
    for i, s in enumerate(add):
        base[start + i] += s * gain
    return base


def main():
    save("rifle_shot", gunshot(11, 0.9, 5200, 70, 0.22))
    save("rifle_shot_b", gunshot(12, 0.9, 4800, 64, 0.24))
    save("pistol_shot", gunshot(21, 0.6, 6500, 110, 0.16, crack_gain=0.8))
    save("dry_fire", click(31, 0.08, 2400, 90))

    # Reload: mag release, mag out, mag in (seated), bolt back, bolt forward.
    r = silence(2.1)
    r = mix_at(r, click(41, 0.06, 1800, 70), 0.10, 0.7)
    r = mix_at(r, lowpass(click(42, 0.18, 300, 18, 0.9), 2500), 0.22, 0.5)
    r = mix_at(r, click(43, 0.10, 1300, 45, 0.8), 1.05, 1.0)
    r = mix_at(r, click(44, 0.05, 2600, 80), 1.12, 0.8)
    r = mix_at(r, click(45, 0.09, 900, 40, 0.9), 1.55, 0.9)
    r = mix_at(r, click(46, 0.12, 1500, 35, 0.9), 1.78, 1.0)
    save("reload", r)

    save("impact_wall", lowpass(click(51, 0.15, 700, 30, 1.0), 3500))
    save("impact_flesh", lowpass(click(52, 0.18, 180, 20, 1.0), 900))
    # Hitmarker: short, bright, and unmistakable over gunfire.
    save("hitmarker", [math.sin(2 * math.pi * 3100 * i / SR) * math.exp(-i / SR * 70) for i in range(int(SR * 0.07))])
    save("kill_confirm", [(math.sin(2 * math.pi * 1700 * i / SR) + math.sin(2 * math.pi * 2550 * i / SR)) * 0.5 * math.exp(-i / SR * 18)
                          for i in range(int(SR * 0.22))])

    # Hurt: a filtered thud plus a short low grunt.
    rng = random.Random(61)
    n = int(SR * 0.35)
    grunt = []
    for i in range(n):
        t = i / SR
        f = 140 - t * 120
        grunt.append((math.sin(2 * math.pi * f * t) * 0.7 + rng.uniform(-1, 1) * 0.3) * math.exp(-t * 9) * min(1.0, t * 80))
    save("player_hurt", lowpass(grunt, 1200))

    # A single brass casing hitting the floor.
    save("shell", highpass(click(71, 0.25, 5200, 22, 0.15), 2500))
    save("pickup_ammo", click(81, 0.2, 900, 20, 0.6))


if __name__ == "__main__":
    main()
