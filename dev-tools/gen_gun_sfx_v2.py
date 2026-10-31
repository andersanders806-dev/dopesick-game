#!/usr/bin/env python3
"""v2 (punchier shots + new gore/impact sounds). Synthesizes the first-person gun sounds into assets/sfx/guns/*.wav.

Our own sounds, made from noise, filtered noise and sine sweeps; no sample
from any other game or library. Deterministic (fixed seeds), 44.1 kHz mono
16-bit. Run:  python3 dev-tools/gen_gun_sfx.py
"""
import os
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "guns")  # drop-in for assets/sfx/guns/
THIS = os.path.dirname(os.path.abspath(__file__))


def t_of(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec, rng):
    return rng.uniform(-1.0, 1.0, int(SR * sec))


def band(x, lo, hi):
    """Brick-wall band-pass through the FFT (lo/hi in Hz, None = open)."""
    n0 = len(x)
    x = np.concatenate([x, np.zeros(int(SR * 0.25))])  # zero-pad: stops circular wrap-around pre-echo at the buffer end
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    m = np.ones_like(f)
    if lo:
        m *= 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4)
    if hi:
        m *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * m, len(x))[:n0]


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


PEAK_NORM = set()


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    if name in PEAK_NORM:
        x = x / max(np.max(np.abs(x)), 1e-9) * 0.8913  # -1 dBFS
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


# Per gun: (mechanical click hz, street echo slap-backs [(delay s, level)], sub-thump level, midrange punch level)
EXTRA = {
    "pistol": (2900, [(0.075, 0.30), (0.17, 0.17), (0.33, 0.09)], 0.9, 0.9),
    "smg": (3300, [(0.07, 0.26), (0.16, 0.14), (0.30, 0.07)], 0.7, 1.0),
    "ar": (2400, [(0.09, 0.34), (0.2, 0.2), (0.38, 0.11)], 1.1, 0.9),
    "shotgun": (1700, [(0.1, 0.4), (0.22, 0.26), (0.43, 0.14)], 1.5, 0.8),
    "sniper": (2100, [(0.14, 0.42), (0.3, 0.3), (0.55, 0.18), (0.85, 0.1)], 1.6, 0.7),
    "magnum": (2200, [(0.1, 0.4), (0.23, 0.26), (0.45, 0.14)], 1.4, 0.85),
    "lmg": (2000, [(0.09, 0.3), (0.2, 0.18), (0.4, 0.1)], 1.2, 0.9),
}


# v2 per-gun voicing: (crack hz low-edge, crack lvl, body band, body tau, body lvl, thump (f0,f1,tau,lvl),
#                      reverb RT seconds, reverb wet, click hz, length)
V2 = {
    "pistol":  (3000, 1.0, (400, 5000), 0.030, 0.9, (120, 70, 0.045, 0.8), 0.55, 0.35, 3200, 0.9),
    "smg":     (3600, 0.9, (600, 6500), 0.022, 0.8, (110, 75, 0.035, 0.6), 0.45, 0.28, 3600, 0.8),
    "ar":      (2600, 1.0, (250, 4800), 0.045, 1.0, (100, 55, 0.07, 1.0), 0.7, 0.38, 2600, 1.0),
    "shotgun": (1800, 1.0, (100, 3500), 0.090, 1.2, (90, 38, 0.16, 1.6), 1.0, 0.5, 1800, 1.4),
    "sniper":  (2200, 1.1, (120, 4500), 0.100, 1.1, (85, 32, 0.20, 1.7), 1.2, 0.6, 2200, 1.6),
    "magnum":  (2200, 1.1, (150, 4200), 0.075, 1.1, (95, 40, 0.15, 1.5), 0.95, 0.5, 2300, 1.3),
    "lmg":     (2300, 1.0, (180, 4200), 0.060, 1.0, (95, 45, 0.10, 1.3), 0.8, 0.42, 2100, 1.1),
}


def reverb_ir(rt, seed):
    """Street echo: exponentially decaying noise that darkens over time, plus a few discrete wall slap-backs."""
    rng = np.random.default_rng(seed)
    n = int(SR * rt)
    ir = rng.uniform(-1, 1, n)
    t = np.arange(n) / SR
    ir *= np.exp(-6.9 * t / rt) * np.minimum(t / 0.012, 1.0)  # -60 dB at rt
    dark = ir.copy()
    ir = 0.5 * band(ir, 150, 5000) + 0.5 * band(dark, 100, 1400) * (t / rt)  # highs die first
    ir = band(ir, 90, 6000)
    for dly, lvl in ((0.07, 0.8), (0.16, 0.55), (0.31, 0.35)):
        i = int(SR * dly * (rt / 0.8) ** 0.5)
        if i < n:
            ir[i : i + 1] += lvl * np.sign(rng.uniform(-1, 1))
    return ir


def shot(kind, seed):
    """Layers: 1-3 ms mechanical transient, filtered-noise crack/body with pitch-down, 40-90 Hz sine thump, convolved street echo."""
    clo, clvl, bb, btau, blvl, (tf0, tf1, ttau, tlvl), rt, wet, mech_hz, length = V2[kind]
    rng = np.random.default_rng(seed)
    n = int(SR * length)
    # 1. transient: 1-3 ms bright click (tiny decaying burst), per-variant length
    tn = int(SR * (0.001 + 0.0015 * rng.random()))
    tr = np.zeros(n)
    tr[:tn] = rng.uniform(-1, 1, tn) * np.linspace(1, 0, tn)
    tr = band(tr, 1500, 12000) * 6.0
    tick = at(click(mech_hz, 0.012, 0.0015, seed + 9, 0.5) * 0.5, 0.0, length)[:n]
    # 2. crack: HF noise burst; body: band noise whose centre drops (pitch-down) via 3 crossfaded bands
    crack = band(noise(length, rng), clo, 14000)[:n] * env(n, 0.00015, 0.0045)
    t = np.arange(n) / SR
    lo, hi = bb
    bodyn = noise(length, rng)
    b1 = band(bodyn, lo * 2.2, hi) * np.exp(-t / (btau * 0.5))
    b2 = band(bodyn, lo * 1.3, hi * 0.5) * np.exp(-t / (btau * 0.9))
    b3 = band(bodyn, lo, hi * 0.2) * np.exp(-t / (btau * 1.5))
    body = (b1 + b2 + b3)[:n] * env(n, 0.0003, 1e3) * blvl * 0.55
    # 3. thump: sine sweep 40-90 Hz range with fast decay, plus low-pass kick-like click start
    thump = sweep(length, tf0, tf1, ttau)[:n] * tlvl
    sub = sweep(length, tf1 * 1.1, 28.0, ttau * 2.2)[:n] * tlvl * 0.5
    dry = crack * clvl * 0.9 + body + thump * 1.1 + sub + tr * 0.5 + tick
    dry = np.tanh(dry / max(np.max(np.abs(dry)), 1e-6) * 2.2)  # glue/saturate
    # 4. street tail: convolve with synthetic IR (FFT conv) and mix wet
    ir = reverb_ir(rt, seed + 77)
    nfft = 1 << int(np.ceil(np.log2(len(dry) + len(ir))))
    wetsig = np.fft.irfft(np.fft.rfft(dry, nfft) * np.fft.rfft(ir, nfft), nfft)[: int(SR * (length + rt * 0.9))]
    wetsig = wetsig / max(np.max(np.abs(wetsig)), 1e-6) * np.max(np.abs(dry)) * wet * 0.55
    total = int(SR * (length + rt * 0.9))
    out = np.zeros(total)
    out[:n] += dry
    out += wetsig[:total]
    # fade last 80 ms to zero, no click at end
    f = int(SR * 0.08)
    out[-f:] *= np.linspace(1, 0, f)
    out = np.tanh(out * 1.15)
    return out / np.max(np.abs(out)) * 0.8913


# --- new v2 sounds: gore + impacts -------------------------------------------


def _wet(n, rng, lo, hi, tau, atk=0.002):
    return band(rng.uniform(-1, 1, n), lo, hi) * env(n, atk, tau)


def flesh_hit(seed, v):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.28)
    thud = sweep(0.28, 150 - 20 * v, 55, 0.05)[:n] * 0.9
    slap = _wet(n, rng, 200, 2200, 0.035 + 0.01 * v, 0.0008)
    wet = _wet(n, rng, 600, 3500, 0.07, 0.01) * 0.35
    tick = _wet(n, rng, 2500, 8000, 0.004, 0.0001) * 0.4
    return norm(thud + slap * 1.1 + wet + tick, 0.9)


def headshot_crunch(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.4)
    crack = _wet(n, rng, 1500, 9000, 0.008, 0.0001)
    bones = sum(at(_wet(int(SR * 0.05), rng, 800, 5000, 0.012, 0.0002)[: int(SR * 0.05)] * (0.8 - 0.1 * k), 0.012 * k + 0.004 * rng.random(), 0.4)[:n] for k in range(5))
    pop = sweep(0.4, 200, 50, 0.07)[:n]
    wet = _wet(n, rng, 200, 1800, 0.1, 0.01) * 0.5
    return norm(crack * 0.9 + bones * 0.8 + pop * 1.1 + wet, 0.92)


def kill_thump():  # noqa: F811 (v2 heavier)
    n = int(SR * 0.5)
    rng = np.random.default_rng(88)
    body = sweep(0.5, 95, 38, 0.14)[:n]
    sub = sweep(0.5, 55, 28, 0.2)[:n] * 0.6
    air = _wet(n, rng, 100, 900, 0.06, 0.003) * 0.5
    return norm(body + sub + air, 0.92)


def sever(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.45)
    chop = _wet(n, rng, 1000, 7000, 0.006, 0.0002)
    snap = at(_wet(int(SR * 0.08), rng, 600, 4000, 0.014, 0.0003), 0.02, 0.45)[:n]
    tear = _wet(n, rng, 300, 2500, 0.12, 0.03) * 0.6
    thud = sweep(0.45, 180, 50, 0.07)[:n]
    return norm(chop * 0.8 + snap * 0.9 + tear + thud, 0.92)


def gib_splat(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * (0.5 + 0.05 * (seed % 3)))
    t = np.arange(n) / SR
    thud = sweep(n / SR, 140, 40, 0.1)[:n]
    wet = _wet(n, rng, 120, 1800, 0.12, 0.002)
    chunks = sum(_wet(n, rng, 500, 3500, 0.02, 0.0005) * np.exp(-((t - d) ** 2) / 0.00003) for d in rng.uniform(0.04, 0.3, 5))
    drip = _wet(n, rng, 1000, 5000, 0.03, 0.001) * (np.sin(2 * np.pi * 30 * t) > 0.6) * np.exp(-t / 0.2) * 0.3
    return norm(thud * 0.9 + wet + chunks * 2.0 + drip, 0.92)


def head_pop(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.45)
    pop = sweep(0.45, 320, 60, 0.04)[:n]
    burst = _wet(n, rng, 400, 6000, 0.03, 0.0002)
    wet = _wet(n, rng, 200, 2000, 0.1, 0.015) * 0.6
    sub = sweep(0.45, 80, 32, 0.12)[:n] * 0.7
    return norm(pop + burst * 1.0 + wet + sub, 0.92)


def blood_squirt(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.5)
    t = np.arange(n) / SR
    jet = band(rng.uniform(-1, 1, n), 1200, 5500) * np.minimum(t / 0.02, 1) * np.exp(-t / 0.12)
    jet *= 0.6 + 0.4 * np.sin(2 * np.pi * (14 + 4 * (seed % 2)) * t)
    wet = _wet(n, rng, 300, 2500, 0.08, 0.005) * 0.7
    bub = sweep(0.5, 400, 900, 0.03)[:n] * 0.2 * (np.sin(2 * np.pi * 22 * t) > 0)
    return norm(jet + wet + bub, 0.85)


def impact_concrete(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    tick = _wet(n, rng, 2000, 9000, 0.004, 0.0001)
    crack = _wet(n, rng, 800, 4000, 0.02, 0.0002)
    thump = sweep(0.3, 260 - 20 * (seed % 3), 80, 0.03)[:n] * 0.7
    grit = _wet(n, rng, 3000, 10000, 0.02, 0.002) * np.exp(-((t - 0.05) ** 2) / 0.0008) * 0.4
    debris = sum(at(_wet(int(SR * 0.02), rng, 2500, 9000, 0.004, 0.0001) * 0.25, d, 0.3)[:n] for d in rng.uniform(0.05, 0.2, 4))
    return norm(tick * 0.8 + crack * 0.8 + thump + grit + debris, 0.9)


def impact_metal(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    tick = _wet(n, rng, 2500, 11000, 0.004, 0.0001)
    base = 1100 + 350 * (seed % 2)
    ring = sum(np.sin(2 * np.pi * base * r * t) * np.exp(-t / (0.12 / r)) * a for r, a in ((1, 0.6), (1.58, 0.45), (2.31, 0.3), (3.4, 0.2)))
    thunk = sweep(0.6, 300, 110, 0.03)[:n] * 0.6
    return norm(tick + ring * 0.7 + thunk, 0.9)


def ricochet_v2(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.7)
    t = np.arange(n) / SR
    f = 4200 - 2800 * (1 - np.exp(-t / 0.18)) + 300 * (seed % 2)  # classic pitch-down whine
    ph = 2 * np.pi * np.cumsum(f) / SR
    whine = np.sin(ph) * np.exp(-t / 0.2) * 0.6 + np.sin(ph * 2.01) * np.exp(-t / 0.1) * 0.25
    whine *= 1 + 0.15 * np.sin(2 * np.pi * 40 * t)
    tick = _wet(n, rng, 2500, 11000, 0.006, 0.0001) * 0.9
    zing = _wet(n, rng, 3000, 9000, 0.04, 0.003) * 0.4
    return norm(tick + whine + zing, 0.85)


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


def flesh(seed, depth=1.0):
    """A bullet in meat: a wet thud and a small squelch."""
    rng = np.random.default_rng(seed)
    sec = 0.22
    n = int(SR * sec)
    t = np.arange(n) / SR
    thud = sweep(sec, 210 * depth, 70, 0.05)
    wet = band(noise(sec, rng), 250, 2200)[:n] * env(n, 0.001, 0.04)
    sq = band(noise(sec, rng), 900, 3200)[:n] * np.exp(-((t - 0.05) ** 2) / 0.0004) * 0.5
    return norm(thud * 1.0 + wet * 0.9 + sq, 0.9)


def crunch(seed):
    """A skull: a hard snap, a wet crack and a dull knock."""
    rng = np.random.default_rng(seed)
    sec = 0.3
    n = int(SR * sec)
    snap = band(noise(sec, rng), 1800, 7000)[:n] * env(n, 0.0004, 0.012)
    crack = band(noise(sec, rng), 500, 3000)[:n] * env(n, 0.0006, 0.035) * 0.9
    knock = sweep(sec, 260, 80, 0.07)
    splat = band(noise(sec, rng), 200, 1500)[:n] * env(n, 0.02, 0.09) * 0.5
    return norm(snap * 0.8 + crack + knock * 0.9 + splat, 0.95)


def splat(seed, sec=0.35):
    """Something heavy and wet hitting the ground."""
    rng = np.random.default_rng(seed)
    n = int(SR * sec)
    t = np.arange(n) / SR
    thud = sweep(sec, 160, 45, 0.09)
    wet = band(noise(sec, rng), 150, 1600)[:n] * env(n, 0.002, 0.08)
    drip = band(noise(sec, rng), 1200, 4200)[:n] * np.exp(-((t - 0.09) ** 2) / 0.0006) * 0.4
    return norm(thud + wet * 0.9 + drip, 0.9)


def bone_snap(seed):
    rng = np.random.default_rng(seed)
    sec = 0.25
    n = int(SR * sec)
    a = band(noise(sec, rng), 1000, 6000)[:n] * env(n, 0.0003, 0.01)
    b = at(band(noise(sec, rng), 700, 4000)[:n] * env(n, 0.0003, 0.015), 0.035, sec)[:n]
    wet = band(noise(sec, rng), 200, 1400)[:n] * env(n, 0.01, 0.07) * 0.6
    return norm(a + b * 0.8 + wet + sweep(sec, 190, 70, 0.05) * 0.6, 0.95)


def impact(seed, hard=1.0):
    """A bullet into concrete or brick: a sharp tick, a puff of grit."""
    rng = np.random.default_rng(seed)
    sec = 0.16
    n = int(SR * sec)
    t = np.arange(n) / SR
    tick = band(noise(sec, rng), 1800, 8000)[:n] * env(n, 0.0002, 0.006 * hard)
    thump = sweep(sec, 420, 130, 0.025) * 0.6
    grit = band(noise(sec, rng), 2500, 9000)[:n] * np.exp(-((t - 0.03) ** 2) / 0.0004) * 0.25
    return norm(tick + thump + grit, 0.8)


def ricochet(seed):
    rng = np.random.default_rng(seed)
    sec = 0.4
    n = int(SR * sec)
    t = np.arange(n) / SR
    ping = sweep(sec, 3600 + 400 * (seed % 3), 1500, 0.09) * 0.7
    zing = band(noise(sec, rng), 3000, 9000)[:n] * env(n, 0.0005, 0.02) * 0.5
    return norm(ping + zing, 0.65)


def main():
    PEAK_NORM.update("fire_%s_%s" % (k, v) for k in SHOTS for v in "ab")
    for kind in SHOTS:
        for i, seed in enumerate((101, 202)):
            save("fire_%s_%s" % (kind, "ab"[i]), shot(kind, seed + sum(map(ord, kind)) % 7))
    global OUT
    OUT = os.path.join(THIS, "fx")
    for i in range(3):
        save("flesh_hit_%d" % (i + 1), flesh_hit(700 + i, i))
        save("gib_splat_%d" % (i + 1), gib_splat(720 + i))
        save("bullet_impact_concrete_%d" % (i + 1), impact_concrete(740 + i))
    for i in range(2):
        save("headshot_crunch_%d" % (i + 1), headshot_crunch(710 + i))
        save("sever_%d" % (i + 1), sever(715 + i))
        save("head_pop_%d" % (i + 1), head_pop(730 + i))
        save("blood_squirt_%d" % (i + 1), blood_squirt(735 + i))
        save("bullet_impact_metal_%d" % (i + 1), impact_metal(750 + i))
        save("ricochet_%d" % (i + 1), ricochet_v2(760 + i))
    save("kill_thump", kill_thump())
    print("done")


if __name__ == "__main__":
    main()
