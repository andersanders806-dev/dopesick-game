#!/usr/bin/env python3
"""Ghetto Wars' story audio: the voices and the sounds and the music of the five chapters. Our own, from noise and
sines and Piper (the project's text-to-speech engine, see autoload/Voice.gd); deterministic; no borrowed samples or tunes.

  1. flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/dump_ghetto_lines.gd          (writes dev-tools/_ghetto_lines.json)
  2. python3 -I dev-tools/gen_story_audio.py dev-tools/_ghetto_lines.json [--voice-only | --sfx-only | --music-only] [--force]
  3. flatpak run org.godotengine.Godot --headless --path . --import      (writes the .import files)

Writes assets/sfx/ghetto/*.ogg, assets/sfx/ghetto/voice/<kind>_<key>.ogg (key = md5("kind|text")[:12], the name
fx/GhettoVoice.gd looks for) and assets/music/ghetto/*.ogg. Needs numpy, ffmpeg (libvorbis) and Piper
(tools/piper in the main checkout, or PIPER_DIR).
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SFX_OUT = os.path.join(ROOT, "assets", "sfx", "ghetto")
VOICE_OUT = os.path.join(SFX_OUT, "voice")
MUSIC_OUT = os.path.join(ROOT, "assets", "music", "ghetto")
MODEL = "en_US-libritts_r-medium.onnx"
SR = 22050


def piper_dir():
    for d in (os.environ.get("PIPER_DIR"), os.path.join(ROOT, "tools", "piper"),
              "/home/anders/dopesick-game/tools/piper"):
        if d and os.path.exists(os.path.join(d, "piper")):
            return d
    sys.exit("no Piper found (set PIPER_DIR)")


# --- little DSP kit (numpy only) --------------------------------------------------------------

def fft_band(x, lo, hi, sr=SR):
    """Band-pass by FFT; lo=0 is a low-pass, hi>=sr/2 a high-pass."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    m = np.ones_like(f)
    if lo > 0:
        m *= 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4)
    if hi < sr / 2:
        m *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(X * m, n)


def lp(x, fc, sr=SR):
    """One-pole low-pass as a truncated exponential kernel (fast, good enough for bass and pads)."""
    tau = sr / (2 * np.pi * fc)
    k = np.exp(-np.arange(int(tau * 6) + 1) / tau)
    k /= k.sum()
    return np.convolve(x, k)[: len(x)]


def noise(sec, rng, sr=SR):
    return rng.standard_normal(int(sr * sec))


def env(n, attack, tau, sr=SR):
    t = np.arange(n) / sr
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / tau)


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def softclip(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def osc(freq, n, shape="sine", sr=SR, phase=0.0):
    f = np.full(n, float(freq)) if np.isscalar(freq) else freq
    ph = phase + 2 * np.pi * np.cumsum(f) / sr
    if shape == "sine":
        return np.sin(ph)
    if shape == "saw":
        return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    if shape == "square":
        return np.sign(np.sin(ph))
    raise ValueError(shape)


def sweep(sec, f0, f1, tau, sr=SR):
    n = int(sr * sec)
    t = np.arange(n) / sr
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return osc(f, n, "sine", sr) * np.exp(-t / (sec * 0.45))


def put(out, x, at_s, level=1.0, sr=SR):
    i = int(at_s * sr)
    if i >= len(out) or i < 0:
        return
    j = min(len(out), i + len(x))
    out[i:j] += x[: j - i] * level


def echo(x, taps):
    out = x.copy()
    for d, g in taps:
        k = int(d * SR)
        out[k:] += x[: len(x) - k] * g
    return out


def pad_len(x, sec):
    n = int(sec * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:max(n, len(x))]


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
        if w.getnchannels() > 1:
            x = x.reshape(-1, w.getnchannels()).mean(axis=1)
    return x, sr


def write_ogg(path, x, sr=SR, q=3):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1, 1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        tmp = t.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), path], check=True)
    os.unlink(tmp)


# --- the voices -------------------------------------------------------------------------------

def say(text, vid, rate, pdir):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        tmp = t.name
    subprocess.run([os.path.join(pdir, "piper"), "-m", os.path.join(pdir, MODEL), "-s", str(vid), "--length_scale",
                    "%.2f" % rate, "--sentence_silence", "0.12", "-f", tmp], input=text.encode(),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    x, sr = read_wav(tmp)
    os.unlink(tmp)
    if sr != SR:
        x = np.interp(np.arange(int(len(x) * SR / sr)) / SR, np.arange(len(x)) / sr, x)
    return x


def crackle(n, rng, density, level):
    """Radio static: a hiss and now and then a pop."""
    out = band_hiss(n, rng) * level
    pops = rng.random(n) < density
    out += pops * rng.standard_normal(n) * level * 6
    return out


def band_hiss(n, rng):
    return fft_band(rng.standard_normal(n), 1500, 7000)


def squelch(rng, sec=0.09, level=0.35):
    n = int(SR * sec)
    return fft_band(rng.standard_normal(n), 800, 5000) * env(n, 0.002, sec * 0.35) * level


def fx_radio(x, rng):
    x = fft_band(x, 380, 3300)
    x = softclip(x * 1.6, 2.2)
    n = len(x) + int(SR * 0.3)
    out = np.zeros(n)
    out[int(SR * 0.08): int(SR * 0.08) + len(x)] = x
    out += crackle(n, rng, 0.0009, 0.03)
    put(out, squelch(rng, 0.09, 0.5), 0.0)
    put(out, squelch(rng, 0.14, 0.4), 0.08 + len(x) / SR)
    return norm(out, 0.8)


def fx_scan(x, rng):
    x = fft_band(x, 450, 2800)
    x = np.round(x * 24) / 24  # a harsh 5-bit grit
    x = softclip(x * 2.0, 2.5)
    lead = int(SR * 0.22)
    out = np.zeros(len(x) + lead + int(SR * 0.2))
    out[lead: lead + len(x)] = x
    t = np.arange(int(SR * 0.08)) / SR
    put(out, np.sin(2 * np.pi * 1180 * t) * 0.35 * np.minimum(t / 0.004, 1) * np.minimum((0.08 - t) / 0.004, 1), 0.04)
    out += crackle(len(out), rng, 0.0012, 0.05)
    put(out, squelch(rng, 0.1, 0.5), lead / SR + len(x) / SR)
    return norm(out, 0.78)


def fx_police(x, rng):
    x = fft_band(x, 320, 4800)
    x = softclip(x * 2.2, 2.8)
    out = np.zeros(len(x) + int(SR * 0.5))
    out[: len(x)] = x
    out = echo(out, [(0.07, 0.32), (0.16, 0.16), (0.29, 0.08)])
    out += crackle(len(out), rng, 0.0004, 0.012)
    return norm(out, 0.95)


def fx_bark(x, rng):
    x = fft_band(x, 120, 9000)
    x = softclip(x * 1.5, 1.8)
    out = np.zeros(len(x) + int(SR * 0.35))
    out[: len(x)] = x
    out = echo(out, [(0.045, 0.2), (0.11, 0.09), (0.21, 0.04)])
    return norm(out, 0.92)


def fx_cry(x, rng):
    n = len(x)
    t = np.arange(n) / SR
    x = fft_band(x, 160, 5000) * (1.0 + 0.16 * np.sin(2 * np.pi * 5.2 * t))
    x = x + fft_band(rng.standard_normal(n), 2000, 6000) * 0.012 * (np.abs(x) > 0.02)  # breath
    out = np.zeros(n + int(SR * 0.4))
    out[:n] = x
    out = echo(out, [(0.06, 0.18), (0.14, 0.1), (0.26, 0.05)])
    return norm(out, 0.62)


FX = {"radio": fx_radio, "scan": fx_scan, "police": fx_police, "bark": fx_bark, "cry": fx_cry}


def bake_voice(lines, force):
    pdir = piper_dir()
    os.makedirs(VOICE_OUT, exist_ok=True)
    done = skipped = 0
    for item in lines:
        path = os.path.join(VOICE_OUT, "%s_%s.ogg" % (item["kind"], item["key"]))
        if os.path.exists(path) and not force:
            skipped += 1
            continue
        rng = np.random.default_rng(int(item["key"], 16) % (2 ** 32))
        x = say(item["text"], item["id"], item["rate"], pdir)
        x = FX[item["fx"]](x, rng)
        write_ogg(path, x, SR, q=2)
        done += 1
    print("voice: %d baked, %d already there" % (done, skipped))


# --- the sounds -------------------------------------------------------------------------------

def thump(level=1.0, f0=95, f1=42, sec=0.22):
    return sweep(sec, f0, f1, 0.04) * level


def heartbeat(sec, rng):
    n = int(SR * sec)
    out = np.zeros(n)
    put(out, thump(1.0), 0.0)
    put(out, thump(0.7, 80, 38), 0.25)
    return out


def clack(rng, freq=2600, sec=0.09, level=1.0):
    n = int(SR * sec)
    t = np.arange(n) / SR
    ring = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.012) + 0.5 * np.sin(2 * np.pi * freq * 1.52 * t) * np.exp(-t / 0.008)
    hit = fft_band(rng.standard_normal(n), 1500, 9000) * np.exp(-t / 0.004)
    return (ring * 0.6 + hit * 0.8) * level


def sfx_chapter_hit():
    rng = np.random.default_rng(7)
    out = np.zeros(int(SR * 3.0))
    rise = fft_band(noise(0.9, rng), 300, 4000) * np.linspace(0, 1, int(SR * 0.9)) ** 2
    put(out, rise, 0.0, 0.5)
    put(out, sweep(2.2, 110, 30, 0.35) * 1.3, 0.9)
    put(out, fft_band(noise(1.6, rng), 40, 900) * env(int(SR * 1.6), 0.002, 0.3), 0.9, 0.7)
    put(out, clack(rng, 1700, 0.5, 0.9), 0.9, 0.4)
    return norm(softclip(out, 1.6), 0.9)


def sfx_text_in():
    rng = np.random.default_rng(8)
    out = np.zeros(int(SR * 0.8))
    for at in (0.0, 0.17):
        n = int(SR * 0.12)
        t = np.arange(n) / SR
        buzz = np.sign(np.sin(2 * np.pi * 168 * t)) * 0.5 * (1 + np.sin(2 * np.pi * 37 * t)) * np.minimum(t / 0.01, 1) * np.minimum((0.12 - t) / 0.02, 1)
        put(out, lp(buzz, 900) * 0.7, at)
    for at, f in ((0.38, 1318.5), (0.46, 1760.0)):
        n = int(SR * 0.1)
        t = np.arange(n) / SR
        put(out, np.sin(2 * np.pi * f * t) * np.exp(-t / 0.04) * np.minimum(t / 0.003, 1) * 0.35, at)
    return norm(out, 0.7)


def sfx_squelch_on():
    rng = np.random.default_rng(9)
    return norm(squelch(rng, 0.1, 1.0), 0.6)


def sfx_scanner_beep():
    rng = np.random.default_rng(10)
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * 1180 * t) * (t < 0.07) * 0.4 + fft_band(rng.standard_normal(n), 1200, 6000) * 0.05 * np.exp(-t / 0.1)
    return norm(out, 0.5)


def sfx_bag_pickup():
    rng = np.random.default_rng(11)
    n = int(SR * 0.5)
    t = np.arange(n) / SR
    rustle = fft_band(rng.standard_normal(n), 900, 6500) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 14 * t + 1.0))) * np.exp(-t / 0.18)
    out = rustle * 0.5
    put(out, thump(0.8, 120, 50, 0.18), 0.12)
    put(out, fft_band(rng.standard_normal(int(SR * 0.12)), 200, 1500) * env(int(SR * 0.12), 0.003, 0.03), 0.1, 0.7)
    return norm(out, 0.8)


def sfx_flush_done():
    rng = np.random.default_rng(12)
    sec = 2.6
    n = int(SR * sec)
    t = np.arange(n) / SR
    body = fft_band(rng.standard_normal(n), 250, 3800)
    swirl = 0.55 + 0.45 * np.sin(2 * np.pi * (1.6 + 1.2 * t / sec) * t)
    out = body * swirl * np.minimum(t / 0.2, 1) * np.where(t < 1.8, 1.0, np.exp(-(t - 1.8) / 0.25)) * 0.8
    # the gurgle at the end
    g = np.zeros(n)
    for k in range(9):
        at = 1.7 + k * 0.1
        f0 = 300 + 90 * k
        nn = int(SR * 0.09)
        tt = np.arange(nn) / SR
        put(g, np.sin(2 * np.pi * (f0 + 600 * tt) * tt) * np.exp(-tt / 0.03) * 0.3, at)
    return norm(out + g, 0.8)


def sfx_siren():
    sec = 6.0
    n = int(SR * sec)
    t = np.arange(n) / SR
    # a two-tone wail that swells in as it comes closer and goes by
    sweep_f = 760 + 360 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.55 * t - np.pi / 2))
    x = osc(sweep_f, n, "sine") + 0.35 * osc(sweep_f * 2, n, "sine") + 0.2 * osc(sweep_f, n, "square")
    x = lp(x, 3500)
    swell = np.exp(-((t - 3.2) / 1.6) ** 2)
    x *= 0.08 + 0.92 * swell
    return norm(x, 0.7)


def sfx_sting_clean():
    out = np.zeros(int(SR * 5.0))
    for k, m in enumerate([53, 60, 65, 69, 72]):
        n = int(SR * 4.2)
        tt = np.arange(n) / SR
        v = lp(osc(midi(m), n, "saw") * 0.5 + osc(midi(m) * 1.003, n, "saw") * 0.5, 1300) * np.minimum(tt / 0.8, 1) * np.exp(-tt / 2.2)
        put(out, v, 0.35 * k, 0.4)
    for k, m in enumerate([84, 88, 91, 96]):
        n = int(SR * 1.6)
        tt = np.arange(n) / SR
        put(out, np.sin(2 * np.pi * midi(m) * tt) * np.exp(-tt / 0.7) * 0.18, 1.0 + k * 0.4)
    return norm(out, 0.8)


def sfx_sting_bag():
    out = np.zeros(int(SR * 5.0))
    for k, m in enumerate([41, 53, 58, 63, 67]):
        n = int(SR * 4.4)
        tt = np.arange(n) / SR
        v = lp(osc(midi(m), n, "saw") * 0.5 + osc(midi(m) * 1.004, n, "saw") * 0.5, 800) * np.minimum(tt / 0.6, 1) * np.exp(-tt / 2.5)
        put(out, v, 0.2 * k, 0.4)
    put(out, thump(0.9, 70, 32, 0.4), 0.0)
    put(out, thump(0.6, 70, 32, 0.4), 1.3)
    return norm(out, 0.8)


def sfx_sting_busted():
    rng = np.random.default_rng(13)
    out = np.zeros(int(SR * 5.5))
    for at in (0.0, 0.33):
        put(out, clack(rng, 2300, 0.18, 1.0), at, 0.9)
    # the ratchet
    for k in range(9):
        put(out, clack(rng, 3100 + 80 * k, 0.04, 0.5), 0.55 + k * 0.045, 0.5)
    put(out, thump(1.2, 80, 28, 0.6), 0.95)
    drone = lp(osc(46.0, int(SR * 4.5), "saw") + osc(46.5, int(SR * 4.5), "saw"), 160)
    drone *= np.minimum(np.arange(len(drone)) / SR / 0.6, 1) * np.exp(-np.arange(len(drone)) / SR / 3.0)
    put(out, drone, 1.0, 0.6)
    for k in range(4):
        put(out, heartbeat(0.5, rng), 1.6 + k * 1.1, 0.5 / (1 + k * 0.2))
    return norm(softclip(out, 1.4), 0.85)


# --- the music --------------------------------------------------------------------------------

def bass_note(freq, sec, shape="saw", cutoff=260):
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = osc(freq, n, shape) * 0.6 + osc(freq / 2, n, "sine") * 0.7
    return lp(x, cutoff) * np.minimum(t / 0.006, 1) * np.exp(-t / (sec * 0.55))


def pad_chord(notes, sec, cutoff=900, detune=1.004, atk=0.9):
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for m in notes:
        f = midi(m)
        x += osc(f, n, "saw") + osc(f * detune, n, "saw") * 0.8 + osc(f / detune, n, "saw") * 0.6
    x = lp(x, cutoff) / (len(notes) * 2.4)
    return x * np.minimum(t / atk, 1) * np.minimum((sec - t) / atk, 1)


def hat(rng, level=1.0, sec=0.04):
    n = int(SR * sec)
    return fft_band(rng.standard_normal(n), 5500, 10500) * env(n, 0.0004, sec * 0.18) * level


def snare(rng, level=1.0):
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    return (fft_band(rng.standard_normal(n), 1200, 8000) * np.exp(-t / 0.05) * 0.8 + np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04) * 0.5) * level


def bell(freq, sec=2.2, level=0.3):
    n = int(SR * sec)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.45 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.4) + 0.3 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.15)
    return x * np.exp(-t / (sec * 0.35)) * np.minimum(t / 0.004, 1) * level


def finish(out, loop=True):
    out = softclip(out, 1.5) * 0.85
    if loop:
        f = int(0.05 * SR)
        ramp = np.linspace(0, 1, f)
        out[:f] = out[:f] * ramp + out[-f:] * (1 - ramp)
        out = out[:-f]
    return out


def music_corner():
    """THE CORNER: 76 BPM, F minor. A sub bass line, a slow kick, hats, a cold bell now and then."""
    rng = np.random.default_rng(101)
    bpm = 76.0
    beat = 60.0 / bpm
    bars = 8
    total = bars * 4 * beat
    out = np.zeros(int(SR * total))
    roots = [29, 29, 32, 29, 27, 27, 32, 31]  # F1 F1 Ab1 F1 Eb1 Eb1 Ab1 G1
    for b in range(bars):
        t0 = b * 4 * beat
        put(out, pad_chord([roots[b] + 24, roots[b] + 31, roots[b] + 36], 4 * beat, 700), t0, 0.5)
        for at, ln in ((0, 1.5), (2.5, 0.75), (3.25, 0.5)):
            put(out, bass_note(midi(roots[b]), ln * beat, "saw", 220), t0 + at * beat, 0.95)
        put(out, thump(1.0, 110, 42, 0.3), t0, 0.9)
        put(out, thump(0.9, 110, 42, 0.3), t0 + 2.5 * beat, 0.8)
        put(out, snare(rng, 0.45), t0 + 3 * beat)
        for i in range(8):
            put(out, hat(rng, 0.2 if i % 2 else 0.32), t0 + i * 0.5 * beat)
        if b % 2 == 1:
            for k in range(3):
                put(out, hat(rng, 0.25), t0 + 3.5 * beat + k * beat / 6)
    for at, m in ((2, 77), (6, 80), (10, 75), (13, 77), (20, 72), (26, 80)):
        put(out, bell(midi(m)), at * beat, 0.5)
    return finish(out)


def music_stash():
    """STASH RUN: 96 BPM, A minor. A running bass, a ticking clock on every beat, a riser into every fourth bar."""
    rng = np.random.default_rng(102)
    bpm = 96.0
    beat = 60.0 / bpm
    bars = 8
    out = np.zeros(int(SR * bars * 4 * beat))
    roots = [33, 33, 36, 31, 33, 33, 29, 31]
    for b in range(bars):
        t0 = b * 4 * beat
        put(out, pad_chord([roots[b] + 24, roots[b] + 27, roots[b] + 34], 4 * beat, 600, 1.006), t0, 0.4)
        for i in range(16):
            octv = 12 if i % 4 == 3 else 0
            put(out, bass_note(midi(roots[b] + octv), beat * 0.22, "square", 340), t0 + i * 0.25 * beat, 0.5 if i % 2 == 0 else 0.32)
        put(out, thump(1.0, 105, 44, 0.26), t0, 0.85)
        put(out, thump(0.8, 105, 44, 0.26), t0 + 2 * beat, 0.7)
        put(out, snare(rng, 0.5), t0 + beat)
        put(out, snare(rng, 0.5), t0 + 3 * beat)
        for i in range(4):
            put(out, clack(rng, 4200, 0.03, 0.18), t0 + i * beat)
        if b % 4 == 3:
            n = int(SR * 2 * beat)
            put(out, fft_band(rng.standard_normal(n), 400, 6000) * np.linspace(0, 1, n) ** 2, t0 + 2 * beat, 0.35)
    return finish(out)


def music_snitch():
    """THE SNITCH: 60 BPM, a cold cluster that trembles, a double heartbeat, no drums: you can not trust the room."""
    rng = np.random.default_rng(103)
    sec = 32.0
    out = np.zeros(int(SR * sec))
    for b, chord in enumerate([[38, 50, 56, 57], [37, 49, 55, 56], [36, 48, 54, 57], [38, 50, 56, 62]]):
        d = 8.0
        n = int(SR * d)
        t = np.arange(n) / SR
        trem = 0.6 + 0.4 * np.sin(2 * np.pi * 6.5 * t)
        x = pad_chord(chord, d, 1500, 1.01, 1.6) * trem
        put(out, x, b * d, 0.9)
    for s in range(32):
        put(out, heartbeat(0.5, rng), s * 1.0, 0.55)
    for at in (5, 13, 21, 28):
        n = int(SR * 2.0)
        put(out, fft_band(rng.standard_normal(n), 2500, 7500) * np.sin(np.linspace(0, np.pi, n)) ** 2, at, 0.07)
    for at, m in ((3.5, 86), (11, 85), (17.5, 82), (24.5, 86)):
        put(out, bell(midi(m), 3.0, 0.12), at)
    return finish(out)


def music_tainted():
    """TAINTED: no drums, nothing to dance to. A low pad, a slow bell, a heartbeat at rest."""
    rng = np.random.default_rng(104)
    sec = 32.0
    out = np.zeros(int(SR * sec))
    for b, chord in enumerate([[38, 45, 50, 53], [34, 41, 46, 53], [36, 43, 48, 52], [38, 45, 50, 57]]):
        put(out, pad_chord(chord, 8.0, 750, 1.003, 2.0), b * 8.0, 0.8)
    for s in range(0, 32, 2):
        put(out, heartbeat(0.5, rng), s * 1.0, 0.28)
    for at, m in ((2, 74), (6, 77), (10, 73), (14, 74), (18, 70), (22, 77), (26, 74), (30, 69)):
        put(out, bell(midi(m), 3.5, 0.2), at)
    return finish(out)


def music_bust():
    """THE BUST: 132 BPM. A four on the floor, a chopping rotor, a siren in the distance, a saw bass that does not stop."""
    rng = np.random.default_rng(105)
    bpm = 132.0
    beat = 60.0 / bpm
    bars = 16
    total = bars * 4 * beat
    out = np.zeros(int(SR * total))
    t = np.arange(len(out)) / SR
    rotor = fft_band(rng.standard_normal(len(out)), 60, 600) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 11.0 * t))) * 0.25
    out += rotor
    wail = osc(700 + 260 * np.sin(2 * np.pi * 0.35 * t), len(out), "sine") * 0.04 * np.clip((t - total * 0.25) / 6.0, 0, 1)
    out += wail
    roots = [31, 31, 34, 29, 31, 31, 36, 34]
    for b in range(bars):
        t0 = b * 4 * beat
        r = roots[b % 8]
        for i in range(4):
            put(out, thump(1.0, 118, 46, 0.24), t0 + i * beat, 0.9)
        put(out, snare(rng, 0.6), t0 + beat)
        put(out, snare(rng, 0.6), t0 + 3 * beat)
        for i in range(16):
            put(out, hat(rng, 0.22 if i % 2 else 0.14, 0.03), t0 + i * 0.25 * beat)
        for i in range(8):
            put(out, bass_note(midi(r + (12 if i == 7 else 0)), beat * 0.4, "saw", 420), t0 + i * 0.5 * beat, 0.6)
        if b % 4 == 0:
            put(out, pad_chord([r + 24, r + 27, r + 31], 16 * beat, 900, 1.007, 0.3), t0, 0.35)
        if b % 8 == 7:
            n = int(SR * 4 * beat)
            put(out, fft_band(rng.standard_normal(n), 300, 8000) * np.linspace(0, 1, n) ** 2, t0, 0.3)
    return finish(out)


def music_end(kind):
    rng = np.random.default_rng({"clean": 111, "bag": 112, "busted": 113}[kind])
    sec = 26.0
    out = np.zeros(int(SR * sec))
    if kind == "clean":
        chords = [[41, 48, 57, 64], [43, 50, 59, 66], [41, 48, 57, 64]]
        for b, c in enumerate(chords):
            put(out, pad_chord(c, 10.0, 1500, 1.003, 2.5), b * 8.0, 0.7)
        for k, m in enumerate([72, 76, 79, 84, 79, 76, 83, 79, 76, 72]):
            put(out, bell(midi(m), 3.0, 0.2), 2.0 + k * 2.2)
    elif kind == "bag":
        for b, c in enumerate([[38, 45, 53, 60], [36, 43, 51, 58], [38, 45, 53, 60]]):
            put(out, pad_chord(c, 10.0, 900, 1.006, 2.0), b * 8.0, 0.7)
        for s in range(0, 26):
            put(out, heartbeat(0.5, rng), s * 1.0, 0.3)
        put(out, lp(rng.standard_normal(len(out)), 140) * 0.9, 0.0, 0.5)
    else:
        put(out, lp(osc(44.0, len(out), "saw") + osc(44.4, len(out), "saw"), 150) * 0.5, 0.0, 0.6)
        for s in range(0, 26, 2):
            put(out, heartbeat(0.5, rng), s * 1.0 + 0.4, 0.5 / (1 + s * 0.03))
        wail = osc(700 + 250 * np.sin(2 * np.pi * 0.3 * np.arange(len(out)) / SR), len(out), "sine") * 0.03
        wail *= np.exp(-np.arange(len(out)) / SR / 12.0)
        out += wail
    fade = np.minimum(np.arange(len(out)) / SR / 1.5, 1.0) * np.minimum((sec - np.arange(len(out)) / SR) / 3.0, 1.0)
    return finish(out * fade, loop=False)


SFX = {
    "chapter_hit": sfx_chapter_hit, "text_in": sfx_text_in, "squelch_on": sfx_squelch_on,
    "scanner_beep": sfx_scanner_beep, "bag_pickup": sfx_bag_pickup, "flush_done": sfx_flush_done,
    "siren": sfx_siren, "sting_clean": sfx_sting_clean, "sting_bag": sfx_sting_bag, "sting_busted": sfx_sting_busted,
}
MUSIC = {
    "ch1_corner": music_corner, "ch2_stash": music_stash, "ch3_snitch": music_snitch, "ch4_tainted": music_tainted,
    "ch5_bust": music_bust, "end_clean": lambda: music_end("clean"), "end_bag": lambda: music_end("bag"),
    "end_busted": lambda: music_end("busted"),
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    force = "--force" in flags
    only = {"--voice-only": "voice", "--sfx-only": "sfx", "--music-only": "music"}
    pick = next((v for k, v in only.items() if k in flags), "all")
    if pick in ("all", "sfx"):
        for name, fn in SFX.items():
            write_ogg(os.path.join(SFX_OUT, name + ".ogg"), fn(), SR, q=4)
        print("sfx: %d sounds" % len(SFX))
    if pick in ("all", "music"):
        for name, fn in MUSIC.items():
            x = fn()
            write_ogg(os.path.join(MUSIC_OUT, name + ".ogg"), x, SR, q=3)
            print("music %s: %.1f s" % (name, len(x) / SR))
    if pick in ("all", "voice"):
        if not args:
            sys.exit("voice needs the lines json (dev-tools/dump_ghetto_lines.gd)")
        bake_voice(json.load(open(args[0])), force)


if __name__ == "__main__":
    main()
