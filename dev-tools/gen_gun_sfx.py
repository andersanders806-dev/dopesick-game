#!/usr/bin/env python3
"""Synthesizes the first-person gun sounds into assets/sfx/guns/*.wav.

Our own sounds, made from noise, filtered noise and sine sweeps; no sample
from any other game or library. Deterministic (fixed seeds), 44.1 kHz mono
16-bit. Run:  python3 dev-tools/gen_gun_sfx.py
"""
import os
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "guns")


def t_of(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec, rng):
    return rng.uniform(-1.0, 1.0, int(SR * sec))


def band(x, lo, hi):
    """Brick-wall band-pass through the FFT (lo/hi in Hz, None = open)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    m = np.ones_like(f)
    if lo:
        m *= 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4)
    if hi:
        m *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * m, len(x))


def env(n, attack, tau):
    t = np.arange(n) / SR
    a = np.minimum(t / max(attack, 1e-5), 1.0)
    return a * np.exp(-t / tau)


def sweep(sec, f0, f1, tau):
    t = t_of(sec)
    k = np.log(f1 / f0) / sec
    phase = 2 * np.pi * f0 * (np.exp(k * t) - 1.0) / k
    return np.sin(phase) * np.exp(-t / tau)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def pad(x, sec):
    n = int(SR * sec)
    out = np.zeros(max(n, len(x)))
    out[: len(x)] = x
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, sec, total):
    out = np.zeros(int(SR * total))
    i = int(SR * sec)
    out[i : i + len(x)] += x[: len(out) - i]
    return out


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


# --- gunshots ----------------------------------------------------------------

# name: (crack tau, body tau, body band, boom hz (start, end), boom tau, tail tau, tail level, length)
SHOTS = {
    "pistol": (0.006, 0.035, (300, 5500), (210, 70), 0.05, 0.22, 0.10, 0.5),
    "smg": (0.005, 0.03, (400, 6500), (240, 85), 0.04, 0.18, 0.09, 0.4),
    "ar": (0.006, 0.05, (200, 5000), (170, 55), 0.07, 0.28, 0.12, 0.6),
    "shotgun": (0.008, 0.09, (120, 3800), (130, 38), 0.14, 0.4, 0.16, 0.9),
    "sniper": (0.010, 0.10, (150, 4500), (150, 32), 0.2, 0.7, 0.2, 1.4),
    "magnum": (0.008, 0.07, (150, 4200), (140, 40), 0.15, 0.42, 0.16, 0.9),
    "lmg": (0.007, 0.06, (150, 4200), (140, 46), 0.09, 0.3, 0.12, 0.6),
}


def shot(kind, seed):
    ct, bt, bb, (f0, f1), boomtau, tail_tau, tail_lvl, length = SHOTS[kind]
    rng = np.random.default_rng(seed)
    n = int(SR * length)
    crack = band(noise(length, rng), 2500, None)[:n] * env(n, 0.0002, ct)
    body = band(noise(length, rng), bb[0], bb[1])[:n] * env(n, 0.0003, bt)
    boom = pad(sweep(length, f0, f1, boomtau), length)[:n]
    tail = band(noise(length, rng), 80, 1800)[:n] * env(n, 0.02, tail_tau) * tail_lvl
    x = crack * 0.9 + body * 1.2 + boom * 1.1 + tail
    # a little saturation: the gun is loud
    x = np.tanh(norm(x, 1.0) * 1.8)
    return norm(x, 0.95)


def wonder(seed):
    rng = np.random.default_rng(seed)
    length = 0.8
    n = int(SR * length)
    t = t_of(length)
    zap = band(noise(length, rng), 1500, 9000)[:n] * env(n, 0.001, 0.05)
    down = sweep(length, 2400, 220, 0.18)
    wob = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.3)
    return norm(zap * 0.8 + down * 0.9 + wob * 0.5, 0.9)


# --- handling ------------------------------------------------------------------


def click(freq=2400, sec=0.03, tau=0.006, seed=1, noise_amt=0.5):
    rng = np.random.default_rng(seed)
    n = int(SR * sec)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) * np.exp(-t / tau)
    nz = band(noise(sec, rng), 1500, 8000)[:n] * np.exp(-t / (tau * 0.7))
    return tone * (1 - noise_amt) + nz * noise_amt


def metal_clack(seed, lo=900, hi=7000, tau=0.012, ring=2300):
    rng = np.random.default_rng(seed)
    sec = 0.12
    n = int(SR * sec)
    t = np.arange(n) / SR
    nz = band(noise(sec, rng), lo, hi)[:n] * np.exp(-t / tau)
    r = (np.sin(2 * np.pi * ring * t) + 0.5 * np.sin(2 * np.pi * ring * 1.52 * t)) * np.exp(-t / (tau * 2.5))
    return norm(nz + 0.35 * r, 0.8)


def mag_out():
    return norm(mix(metal_clack(11, 700, 5000, 0.010, 1800), at(metal_clack(12, 400, 3000, 0.02, 900) * 0.6, 0.07, 0.22)), 0.7)


def mag_in():
    thud = sweep(0.1, 180, 90, 0.03) * 0.7
    return norm(mix(at(metal_clack(21, 900, 6500, 0.008, 2600), 0.0, 0.25), at(thud, 0.015, 0.25), at(metal_clack(22, 1200, 6500, 0.006, 3000) * 0.7, 0.07, 0.25)), 0.85)


def rack():
    a = metal_clack(31, 600, 4500, 0.02, 1500)
    b = metal_clack(32, 1000, 7000, 0.012, 2700)
    scr = band(noise(0.1, np.random.default_rng(33)), 2000, 6000)[: int(SR * 0.1)] * env(int(SR * 0.1), 0.01, 0.04) * 0.25
    return norm(mix(at(scr, 0.0, 0.4), at(a, 0.05, 0.4), at(b, 0.2, 0.4)), 0.8)


def pump():
    a = metal_clack(41, 300, 3500, 0.03, 900)
    b = metal_clack(42, 500, 5000, 0.02, 1800)
    thud = sweep(0.12, 140, 70, 0.04) * 0.6
    return norm(mix(at(a, 0.0, 0.5), at(thud, 0.0, 0.5), at(b, 0.16, 0.5), at(thud * 0.7, 0.16, 0.5)), 0.85)


def bolt():
    a = metal_clack(51, 500, 4000, 0.025, 1400)
    b = metal_clack(52, 900, 6500, 0.012, 2500)
    scr = band(noise(0.18, np.random.default_rng(53)), 1500, 5000)[: int(SR * 0.18)] * env(int(SR * 0.18), 0.02, 0.07) * 0.3
    return norm(mix(at(a, 0.0, 0.7), at(scr, 0.08, 0.7), at(b, 0.4, 0.7), at(a * 0.8, 0.5, 0.7)), 0.8)


def shell_in():
    return norm(mix(metal_clack(61, 800, 4500, 0.01, 1700), at(sweep(0.06, 260, 140, 0.02) * 0.5, 0.0, 0.14)), 0.65)


def brass(seed):
    """A casing on concrete: two or three bright rings."""
    rng = np.random.default_rng(seed)
    sec = 0.35
    n = int(SR * sec)
    t = np.arange(n) / SR
    base = rng.uniform(4200, 5600)
    x = np.zeros(n)
    for k, (dt, lvl) in enumerate([(0.0, 1.0), (0.07, 0.5), (0.12, 0.25)]):
        i = int(dt * SR)
        tt = t[: n - i]
        x[i:] += lvl * (np.sin(2 * np.pi * base * tt) + 0.4 * np.sin(2 * np.pi * base * 2.76 * tt)) * np.exp(-tt / 0.05)
    x += band(noise(sec, rng), 3000, 9000)[:n] * np.exp(-t / 0.004) * 0.5
    return norm(x, 0.55)


def swish(sec, lo, hi, seed, peak_at=0.4, level=0.6):
    rng = np.random.default_rng(seed)
    n = int(SR * sec)
    x = noise(sec, rng)
    # a moving band: crossfade a few fixed bands over time
    out = np.zeros(n)
    centres = np.geomspace(lo, hi, 6)
    t = np.linspace(0, 1, n)
    for i, c in enumerate(centres):
        b = band(x, c * 0.7, c * 1.4)[:n]
        w = np.exp(-((t - i / 5.0) ** 2) / 0.04)
        out += b * w
    shape = np.sin(np.pi * t ** peak_at) ** 2
    return norm(out * shape, level)


def slide():
    rng = np.random.default_rng(71)
    sec = 0.85
    n = int(SR * sec)
    t = np.linspace(0, 1, n)
    scrape = band(noise(sec, rng), 500, 3500)[:n] * (0.2 + 0.8 * np.clip(1 - t, 0, 1) ** 1.5)
    rumble = band(noise(sec, rng), 40, 220)[:n] * (1 - t) ** 1.2
    cloth = swish(sec, 700, 2800, 72, 0.5, 0.5)
    return norm(scrape * 0.7 + rumble * 1.0 + cloth * 0.6, 0.85)


def hit_tick(freq, sec=0.045):
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.006) + 0.5 * np.sin(2 * np.pi * freq * 1.5 * t) * np.exp(-t / 0.004)
    x += band(noise(sec, np.random.default_rng(81)), 2500, 7000)[:n] * np.exp(-t / 0.003) * 0.4
    return norm(x, 0.8)


def kill_thump():
    n = int(SR * 0.3)
    thump = sweep(0.3, 150, 48, 0.09)
    snap = band(noise(0.3, np.random.default_rng(91)), 200, 2500)[:n] * env(n, 0.001, 0.025)
    tick = pad(hit_tick(2800, 0.04), 0.3)[:n] * 0.6
    return norm(thump + snap * 0.6 + tick, 0.9)


def main():
    for kind in SHOTS:
        for i, seed in enumerate((101, 202)):
            save("fire_%s_%s" % (kind, "ab"[i]), shot(kind, seed + sum(map(ord, kind)) % 7))
    for i, seed in enumerate((301, 302)):
        save("fire_wonder_%s" % "ab"[i], wonder(seed))
    save("dry_click", norm(click(1700, 0.04, 0.008, 5), 0.6))
    save("mag_out", mag_out())
    save("mag_in", mag_in())
    save("rack", rack())
    save("pump", pump())
    save("bolt", bolt())
    save("shell_in", shell_in())
    save("brass_a", brass(401))
    save("brass_b", brass(402))
    save("brass_c", brass(403))
    save("ads_in", swish(0.22, 500, 2200, 501, 0.5, 0.45))
    save("ads_out", swish(0.18, 400, 1800, 502, 0.6, 0.38))
    save("draw", mix(swish(0.3, 500, 2000, 503, 0.5, 0.5), at(metal_clack(504, 800, 5000, 0.01, 2000) * 0.5, 0.22, 0.4)))
    save("inspect", swish(0.5, 450, 1800, 505, 0.5, 0.45))
    save("slide", slide())
    save("whoosh", swish(0.22, 600, 3400, 506, 0.45, 0.7))
    save("hit_body", hit_tick(3000))
    save("hit_head", mix(hit_tick(4000, 0.06), at(hit_tick(3300, 0.05) * 0.7, 0.025, 0.09)))
    save("hit_kill", kill_thump())
    print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
