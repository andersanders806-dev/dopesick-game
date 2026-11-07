#!/usr/bin/env python3
"""Synthesizes the Ghetto Wars sounds: the crack and whizz of rounds going past the player, the grenade and the
molotov, a police helicopter, a car going by, and the war's own beat (a dark drone with a slow kick and hats).
Our own sounds, from noise and sines, deterministic; reuses the helpers of gen_gun_sfx.py (which it must sit beside).
  python3 -I dev-tools/gen_gang_sfx.py     (add the dev-tools dir to the path itself)
Writes assets/sfx/guns/*.wav (bullet_crack_N, bullet_whizz_N, grenade_boom, glass_smash, fire_whoosh,
fire_loop, heli_loop, car_pass) and assets/music/gangwar.wav (22.05 kHz, loops).
"""
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_gun_sfx as g  # noqa: E402

SR = g.SR
MUSIC_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "music")


def crack(seed):
    """A supersonic round close by: one hard snap, a little ring, gone."""
    rng = np.random.default_rng(seed)
    n = int(SR * 0.28)
    snap = g.band(g.noise(0.28, rng), 2500, 14000) * g.env(n, 0.0004, 0.0035)
    body = g.band(g.noise(0.28, rng), 500, 3500) * g.env(n, 0.0006, 0.012) * 0.5
    ring = g.sweep(0.28, 3800 + 300 * seed, 2200, 0.03) * 0.25
    thump = g.sweep(0.28, 160, 70, 0.025) * 0.35
    return g.norm(snap + body + ring + thump, 0.9)


def whizz(seed):
    """A round passing: noise whose pitch falls as it goes by (the doppler), with a flutter."""
    rng = np.random.default_rng(seed)
    sec = 0.32 + 0.04 * seed
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = g.noise(sec, rng)
    out = np.zeros(n)
    # Three bands sliding down across the pass.
    for lo, hi, lvl in ((2800, 9000, 0.7), (1500, 5000, 0.5), (700, 2600, 0.3)):
        k = 1.0 - 0.55 * (t / sec)
        out += g.band(x, lo, hi) * lvl * k
    peak = np.exp(-((t - sec * 0.38) / (sec * 0.2)) ** 2)
    flutter = 1 + 0.25 * np.sin(2 * np.pi * 70 * t)
    tone = np.sin(2 * np.pi * np.cumsum(3400 - 2200 * (t / sec)) / SR) * 0.18
    return g.norm((out + tone) * peak * flutter, 0.85)


def boom(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 1.8)
    body = g.band(g.noise(1.8, rng), 40, 2200) * g.env(n, 0.002, 0.28)
    thump = g.sweep(1.8, 95, 28, 0.35) * 1.2
    crack_ = g.band(g.noise(1.8, rng), 1500, 9000) * g.env(n, 0.0005, 0.02) * 0.6
    rumble = g.band(g.noise(1.8, rng), 30, 400) * g.env(n, 0.05, 0.7) * 0.7
    return g.norm(body + thump + crack_ + rumble, 0.92)


def glass_smash(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.6)
    x = g.band(g.noise(0.6, rng), 2500, 12000) * g.env(n, 0.0005, 0.05)
    for i in range(14):
        t0 = rng.uniform(0.02, 0.35)
        x = x + g.at(g.sweep(0.1, rng.uniform(3500, 7500), rng.uniform(2500, 5000), 0.02) * rng.uniform(0.1, 0.3), t0, 0.6)[:n]
    return g.norm(x, 0.8)


def fire_whoosh(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 1.0)
    t = np.arange(n) / SR
    x = g.band(g.noise(1.0, rng), 120, 1800) * np.minimum(t / 0.08, 1) * np.exp(-t / 0.5)
    x += g.band(g.noise(1.0, rng), 1200, 5000) * g.env(n, 0.02, 0.25) * 0.4
    return g.norm(x, 0.8)


def fire_loop(seed):
    """Burning: low roar with crackles; ends where it starts."""
    rng = np.random.default_rng(seed)
    sec = 2.0
    n = int(SR * sec)
    roar = g.band(g.noise(sec, rng), 80, 900) * 0.45
    for i in range(70):
        t0 = rng.uniform(0, sec - 0.05)
        roar = roar + g.at(g.band(g.noise(0.03, rng), 1500, 9000) * g.env(int(SR * 0.03), 0.0003, 0.004) * rng.uniform(0.2, 0.9), t0, sec)[:n]
    fade = int(SR * 0.05)
    roar[:fade] *= np.linspace(0, 1, fade)
    roar[-fade:] *= np.linspace(1, 0, fade)
    return g.norm(roar, 0.8)


def heli_loop():
    """A helicopter: rotor chop at 11 Hz over a turbine whine; 2 s, 22 chops exactly."""
    rng = np.random.default_rng(77)
    sec = 2.0
    n = int(SR * sec)
    t = np.arange(n) / SR
    chop = (0.5 + 0.5 * np.sin(2 * np.pi * 11 * t)) ** 3
    x = g.band(g.noise(sec, rng), 60, 700) * chop
    x += g.band(g.noise(sec, rng), 800, 2600) * chop * 0.25
    whine = np.sin(2 * np.pi * 410 * t) * 0.05 + np.sin(2 * np.pi * 823 * t) * 0.03
    x = x + whine
    return g.norm(x, 0.8)


def car_pass():
    """A car going past fast: engine rumble rising and falling (a doppler), tyre hiss."""
    rng = np.random.default_rng(88)
    sec = 3.0
    n = int(SR * sec)
    t = np.arange(n) / SR
    pitch = 1.25 - 0.5 * (1 / (1 + np.exp(-(t - sec * 0.5) * 3)))
    ph = 2 * np.pi * np.cumsum(62 * pitch) / SR
    eng = (np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.4 * np.sin(3 * ph) + 0.25 * np.sin(5.01 * ph)) * 0.4
    vol = np.exp(-((t - sec * 0.5) / (sec * 0.22)) ** 2)
    hiss = g.band(g.noise(sec, rng), 1500, 7000) * 0.2
    return g.norm((eng + hiss) * vol, 0.85)


# --- the beat -------------------------------------------------------------------------

def gangwar_music():
    """Eight bars at 78 BPM, 22.05 kHz: a detuned minor drone, a sub kick on 1 and the 'and' of 3, hats in
    triplet rolls now and then, a rim on 4. Dark, slow, a bit menacing; no sample, no borrowed melody."""
    sr = 22050
    bpm = 78.0
    beat = 60.0 / bpm
    bars = 8
    total = bars * 4 * beat
    n = int(sr * total)
    rng = np.random.default_rng(2026)
    t = np.arange(n) / sr
    out = np.zeros(n)

    def put(x, at_s, level=1.0):
        i = int(at_s * sr)
        j = min(n, i + len(x))
        if i < n:
            out[i:j] += x[: j - i] * level

    # Pad: root F1/F2, minor third and fifth drifting, each bar changes the root a little.
    roots = [43.65, 43.65, 51.91, 43.65, 38.89, 38.89, 51.91, 48.99]
    for b in range(bars):
        t0 = b * 4 * beat
        i0 = int(t0 * sr)
        seg = int(4 * beat * sr)
        tt = np.arange(seg) / sr
        f = roots[b]
        pad = np.zeros(seg)
        for mult, lvl in ((1, 0.5), (2.003, 0.3), (2.997, 0.14), (3.99, 0.08)):
            pad += np.sign(np.sin(2 * np.pi * f * mult * tt)) * lvl * 0.35 + np.sin(2 * np.pi * f * mult * 1.004 * tt) * lvl * 0.5
        # one-pole low-pass that opens slowly through the bar
        a = 0.02 + 0.03 * (tt / tt[-1])
        y = np.zeros(seg)
        s = 0.0
        for k in range(seg):
            s += (pad[k] - s) * a[k]
            y[k] = s
        fade = np.minimum(tt / 0.4, 1) * np.minimum((tt[-1] - tt) / 0.4, 1)
        out[i0: i0 + seg] += y * fade * 0.9
    # Kick: on 1 and the and-of-3 of every bar, a pickup in bar 4 and 8.
    kick = g.sweep(0.5, 120, 38, 0.12) * 1.0
    kick = np.interp(np.arange(int(sr * 0.5)) / sr, np.arange(len(kick)) / g.SR, kick)
    for b in range(bars):
        t0 = b * 4 * beat
        put(kick, t0, 0.9)
        put(kick, t0 + 2.5 * beat, 0.75)
        if b % 4 == 3:
            put(kick, t0 + 3.5 * beat, 0.6)
    # Rim on 4, hats in eighths with triplet rolls at the end of every second bar.
    for b in range(bars):
        t0 = b * 4 * beat
        rim = g.band(g.noise(0.05, rng), 1500, 6000) * g.env(int(g.SR * 0.05), 0.0005, 0.012)
        rim = np.interp(np.arange(int(sr * 0.05)) / sr, np.arange(len(rim)) / g.SR, rim)
        put(rim, t0 + 3 * beat, 0.35)
        hits = [i * 0.5 * beat for i in range(8)]
        if b % 2 == 1:
            hits += [3.5 * beat + k * beat / 6 for k in range(1, 3)]
        for h in hits:
            hat = g.band(g.noise(0.04, rng), 6000, 10500) * g.env(int(g.SR * 0.04), 0.0003, 0.006)
            hat = np.interp(np.arange(int(sr * 0.04)) / sr, np.arange(len(hat)) / g.SR, hat)
            put(hat, t0 + h, 0.1 if (h / beat) % 1 else 0.16)
    # Siren-ish distant wail over the last two bars (a sine gliding), very quiet.
    wail = np.sin(2 * np.pi * np.cumsum(700 + 300 * np.sin(2 * np.pi * 0.25 * t)) / sr) * 0.015
    wail *= np.clip((t - total * 0.75) / 2.0, 0, 1) * np.clip((total - t) / 2.0, 0, 1)
    out += wail
    out = np.tanh(out * 1.4) * 0.8
    # Loop-safe: crossfade the last 0.05 s into the first.
    f = int(0.05 * sr)
    ramp = np.linspace(0, 1, f)
    out[:f] = out[:f] * ramp + out[-f:] * (1 - ramp)
    out = out[:-f]
    return out, sr


def save_wav(path, x, sr):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def main():
    for i in range(3):
        g.save("bullet_crack_%d" % (i + 1), crack(11 + i))
        g.save("bullet_whizz_%d" % (i + 1), whizz(21 + i))
    g.save("grenade_boom", boom(31))
    g.save("glass_smash", glass_smash(41))
    g.save("fire_whoosh", fire_whoosh(51))
    g.save("fire_loop", fire_loop(61))
    g.save("heli_loop", heli_loop())
    g.save("car_pass", car_pass())
    x, sr = gangwar_music()
    os.makedirs(MUSIC_OUT, exist_ok=True)
    save_wav(os.path.join(MUSIC_OUT, "gangwar.wav"), x, sr)
    print("wrote the Ghetto Wars sounds and assets/music/gangwar.wav (%.1f s)" % (len(x) / sr))


if __name__ == "__main__":
    main()
