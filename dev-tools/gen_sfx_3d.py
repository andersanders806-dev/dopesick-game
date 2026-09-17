#!/usr/bin/env python3
"""Synthesizes the positional room ambience and Dive Bar patron sounds for
the 3D rooms, in the same
stdlib-only, generated-not-sampled style as gen_sfx.py (kept separate so
rerunning this never changes the existing one-shot sounds).

Every *_loop file is built to loop seamlessly: tonal loops use whole numbers
of cycles over the loop length, and noise-based loops crossfade their tail
into their head. Their .import files set edit/loop_mode=2 (forward) so Godot
loops them sample-accurately.

    python3 dev-tools/gen_sfx_3d.py
"""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
SR = 22050
TAU = 2 * math.pi


def save(name, samples):
    path = os.path.join(OUT, f"{name}.wav")
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))
    peak = max(abs(s) for s in samples)
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    seam = abs(samples[0] - samples[-1])
    print(f"wrote {name:22s} {len(samples) / SR:5.2f}s  peak={peak:.2f} rms={rms:.3f} seam_jump={seam:.3f}")


def n_samples(seconds):
    return int(round(SR * seconds))


class OnePole:
    """One-pole low-pass. highpass() = input minus the low-passed signal."""

    def __init__(self, cutoff):
        self.a = math.exp(-TAU * cutoff / SR)
        self.y = 0.0

    def lowpass(self, x):
        self.y = (1 - self.a) * x + self.a * self.y
        return self.y

    def highpass(self, x):
        return x - self.lowpass(x)


class BandPass:
    """RBJ biquad band-pass (constant 0 dB peak gain)."""

    def __init__(self, freq, q):
        w = TAU * freq / SR
        alpha = math.sin(w) / (2 * q)
        a0 = 1 + alpha
        self.b0, self.b2 = alpha / a0, -alpha / a0
        self.a1, self.a2 = -2 * math.cos(w) / a0, (1 - alpha) / a0
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def __call__(self, x):
        y = self.b0 * x + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y


def loop_crossfade(samples, n, fade):
    """Given n + fade samples, fold the extra tail over the head so sample
    n-1 flows straight into sample 0."""
    out = samples[:n]
    for i in range(fade):
        k = i / fade
        out[i] = samples[i] * math.sin(k * math.pi / 2) + samples[n + i] * math.cos(k * math.pi / 2)
    return out


def normalize(samples, peak):
    m = max(abs(s) for s in samples) or 1.0
    return [s * peak / m for s in samples]


# --- Apartment ---------------------------------------------------------------

def gen_bulb_buzz():
    """Mains hum from cheap wiring: 60 Hz fundamental with a strong, slightly
    clipped 120 Hz buzz. 2 s = whole cycles of every partial."""
    n = n_samples(2.0)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.35 * math.sin(TAU * 60 * t) + 0.6 * math.sin(TAU * 120 * t) + 0.25 * math.sin(TAU * 240 * t) + 0.12 * math.sin(TAU * 360 * t)
        s = math.tanh(s * 1.8)
        out.append(s)
    save("bulb_buzz_loop", normalize(out, 0.5))


def gen_bulb_crackle():
    """A short burst of irregular pops, for when the bulb browns out."""
    rng = random.Random(7)
    n = n_samples(0.18)
    out = [0.0] * n
    for _ in range(9):
        start = rng.randrange(0, n - 200)
        length = rng.randrange(20, 160)
        amp = rng.uniform(0.3, 1.0)
        for j in range(length):
            out[start + j] += (rng.random() * 2 - 1) * amp * (1 - j / length) ** 2
    hp = OnePole(900)
    save("bulb_crackle", normalize([hp.highpass(s) for s in out], 0.7))


def gen_tv_static():
    """Old CRT with no signal: bright hiss with a slow grainy flutter."""
    rng = random.Random(11)
    n, fade = n_samples(3.0), n_samples(0.3)
    hp, lp = OnePole(1800), OnePole(7000)
    out = []
    for i in range(n + fade):
        t = i / SR
        flutter = 0.8 + 0.2 * math.sin(TAU * 7 * t) * math.sin(TAU * 0.9 * t)
        out.append(lp.lowpass(hp.highpass(rng.random() * 2 - 1)) * flutter)
    save("tv_static_loop", normalize(loop_crossfade(out, n, fade), 0.5))


# --- Shop ----------------------------------------------------------------------

def gen_fluorescent_hum():
    """Magnetic-ballast fluorescent tubes: 120 Hz buzz rich in odd harmonics
    plus a faint high whine. 2 s = whole cycles of every partial."""
    n = n_samples(2.0)
    out = []
    for i in range(n):
        t = i / SR
        s = sum(math.sin(TAU * 120 * k * t) / k for k in (1, 3, 5, 7, 9))
        s += 0.08 * math.sin(TAU * 3000 * t)
        out.append(math.tanh(s * 1.4))
    save("fluorescent_hum_loop", normalize(out, 0.45))


def gen_cooler_hum():
    """Drinks cooler compressor: low drone, a rattly 25 Hz beat, and airy fan
    noise."""
    rng = random.Random(13)
    n, fade = n_samples(4.0), n_samples(0.4)
    lp = OnePole(500)
    out = []
    for i in range(n + fade):
        t = i / SR
        drone = 0.5 * math.sin(TAU * 55 * t) + 0.3 * math.sin(TAU * 110 * t)
        rattle = 0.25 * math.sin(TAU * 165 * t) * (0.5 + 0.5 * math.sin(TAU * 25 * t))
        fan = lp.lowpass(rng.random() * 2 - 1) * 0.9
        out.append(drone + rattle + fan)
    save("cooler_hum_loop", normalize(loop_crossfade(out, n, fade), 0.5))


# --- Dive Bar ------------------------------------------------------------------

def gen_jukebox():
    """A slow 12-bar-blues-in-A shuffle (condensed to 4 bars: A A D E) as
    heard through a cheap jukebox speaker: walking bass, offbeat chord stabs,
    brushed hat, all low-passed. 4 bars at 96 bpm = exactly 10 s, so it loops
    on the downbeat."""
    rng = random.Random(21)
    bpm = 96
    beat = 60 / bpm
    bars = [(110.0, [220.0, 277.18, 329.63, 392.0]),   # A7
            (110.0, [220.0, 277.18, 329.63, 392.0]),   # A7
            (146.83, [293.66, 369.99, 440.0, 523.25]),  # D7
            (164.81, [329.63, 415.30, 493.88, 587.33])]  # E7
    n = n_samples(beat * 4 * len(bars))
    out = [0.0] * n
    swing = 2 / 3  # shuffle: the "and" lands two-thirds through the beat

    def add_note(start_t, dur, freq, amp, kind):
        s0, ln = n_samples(start_t), n_samples(dur)
        for j in range(ln):
            idx = (s0 + j) % n  # wrap so a note ringing past the end loops cleanly
            t = j / SR
            env = min(1.0, j / 60) * (1 - j / ln) ** 1.5
            if kind == "bass":
                v = math.sin(TAU * freq * t) + 0.3 * math.sin(TAU * 2 * freq * t)
            else:
                v = 1.0 if math.sin(TAU * freq * t) >= 0 else -1.0
            out[idx] += v * env * amp

    for b, (root, chord) in enumerate(bars):
        bar_t = b * 4 * beat
        walk = [root, root * 1.25, root * 1.5, root * 1.68]  # 1 3 5 6
        for k in range(4):
            add_note(bar_t + k * beat, beat * 0.9, walk[k], 0.55, "bass")
            for f in chord[:3]:
                add_note(bar_t + (k + swing) * beat, beat * 0.22, f, 0.07, "stab")
        for k in range(4):
            for off in (0, swing):
                s0 = n_samples(bar_t + (k + off) * beat)
                for j in range(n_samples(0.04)):
                    out[(s0 + j) % n] += (rng.random() * 2 - 1) * 0.12 * (1 - j / n_samples(0.04)) ** 3

    # Two passes of a gentle low-pass, starting the filter state from the
    # end of a warm-up pass so the loop point has no filter transient.
    lp1, lp2 = OnePole(1600), OnePole(2400)
    for s in out:
        lp2.lowpass(lp1.lowpass(s))
    muffled = [lp2.lowpass(lp1.lowpass(s)) for s in out]
    save("jukebox_loop", normalize(muffled, 0.6))


def gen_bar_murmur():
    """Crowd walla: several 'voices', each band-passed noise at speech
    formants, gated into syllable-length bursts, plus the odd glass clink."""
    rng = random.Random(31)
    n, fade = n_samples(8.0), n_samples(0.6)
    total = n + fade
    out = [0.0] * total
    for v in range(6):
        f1 = BandPass(rng.uniform(350, 700), 2.5)
        f2 = BandPass(rng.uniform(900, 1700), 3.0)
        gain = rng.uniform(0.5, 1.0)
        env = 0.0
        target = 0.0
        next_change = 0
        for i in range(total):
            if i >= next_change:
                talking = rng.random() < 0.6
                target = rng.uniform(0.4, 1.0) if talking else 0.0
                next_change = i + n_samples(rng.uniform(0.08, 0.3))
            env += (target - env) * 0.004
            x = rng.random() * 2 - 1
            out[i] += (f1(x) + 0.6 * f2(x)) * env * gain
    for _ in range(3):
        start = rng.randrange(0, n - n_samples(0.3))
        freq = rng.uniform(2600, 3600)
        for j in range(n_samples(0.25)):
            t = j / SR
            out[start + j] += (math.sin(TAU * freq * t) + 0.5 * math.sin(TAU * freq * 2.76 * t)) * 0.05 * math.exp(-t * 25)
    save("bar_murmur_loop", normalize(loop_crossfade(out, n, fade), 0.45))


# --- Dive Bar patrons ------------------------------------------------------------
# Short positional one-shots each patron makes from their seat, plus a
# wordless mumbled "voice". Each patron's pitch_scale sets how the voice
# sounds on them (see NPC3D.gd), so the voice is synthesized at a neutral
# ~120 Hz.

VOWELS = [(730, 1090), (530, 1840), (570, 840), (440, 1020), (300, 870), (660, 1700)]


def glottal(freq, t, phase):
    """Buzzy voiced source: a band-limited-ish pulse (sum of harmonics with
    falling amplitude), which formant filters then shape into vowels."""
    return sum(math.sin(phase * k) / k ** 1.2 for k in range(1, 12))


def gen_mutter(name, seed, syllables):
    rng = random.Random(seed)
    out = []
    phase = 0.0
    f0 = 120.0
    for syl in range(syllables):
        f1, f2 = VOWELS[rng.randrange(len(VOWELS))]
        bp1, bp2 = BandPass(f1, 5.0), BandPass(f2, 7.0)
        consonant = rng.random() < 0.6
        c_len = n_samples(rng.uniform(0.02, 0.05)) if consonant else 0
        v_len = n_samples(rng.uniform(0.07, 0.15))
        gap = n_samples(rng.uniform(0.0, 0.06) if syl < syllables - 1 else 0.05)
        hp = OnePole(2500)
        for j in range(c_len):
            out.append(hp.highpass(rng.random() * 2 - 1) * 0.15 * (1 - j / c_len))
        # Pitch drifts down across the phrase, like a tired half-sentence.
        target = f0 * (1.1 - 0.25 * syl / max(1, syllables - 1)) * rng.uniform(0.95, 1.05)
        for j in range(v_len):
            t = j / SR
            freq = target * (1 + 0.01 * math.sin(TAU * 5 * t))
            phase += TAU * freq / SR
            src = glottal(freq, t, phase)
            env = math.sin(math.pi * j / v_len) ** 0.8
            out.append((bp1(src) + 0.5 * bp2(src)) * env)
        out.extend([0.0] * gap)
    lp = OnePole(1800)  # mumbled through a beard / a drink, not crisp speech
    save(name, normalize([lp.lowpass(v) for v in out], 0.6))


def gen_cough(name, seed, wet):
    """Two or three harsh bursts: band-passed noise with a hard attack and a
    little vocal body; `wet` adds a low rattly chest resonance."""
    rng = random.Random(seed)
    out = []
    for burst in range(rng.choice([2, 3])):
        ln = n_samples(rng.uniform(0.12, 0.2))
        bp, body = BandPass(rng.uniform(900, 1400), 1.2), BandPass(rng.uniform(250, 350), 2.0)
        for j in range(ln):
            t = j / SR
            env = min(1.0, j / 80) * math.exp(-t * 18)
            x = rng.random() * 2 - 1
            rattle = body(x) * (0.5 + 0.5 * math.sin(TAU * 32 * t)) * 2.5 * wet
            out.append((bp(x) * 1.5 + rattle) * env)
        out.extend([0.0] * n_samples(rng.uniform(0.08, 0.16)))
    # Coughs are all attack, so they read louder than their peak suggests;
    # kept at the same peak as the sighs rather than hotter.
    save(name, normalize(out, 0.5))


def gen_sniff():
    """A sharp nasal inhale: high band noise with a rising swell."""
    rng = random.Random(51)
    ln = n_samples(0.22)
    bp = BandPass(3200, 1.5)
    out = []
    for j in range(ln):
        k = j / ln
        env = (k ** 1.5) * (1 - k) ** 0.3 * 3
        out.append(bp(rng.random() * 2 - 1) * env)
    save("patron_sniff", normalize(out, 0.5))


def gen_sigh():
    """A long, heavy exhale: breathy low noise that swells then fades, with a
    faint voiced groan underneath."""
    rng = random.Random(53)
    ln = n_samples(1.1)
    lp, bp = OnePole(900), BandPass(500, 3.0)
    out = []
    phase = 0.0
    for j in range(ln):
        k = j / ln
        env = math.sin(math.pi * min(1.0, k * 1.6)) ** 1.5 if k < 0.625 else (1 - k) / 0.375 * 0.92
        freq = 105 - 25 * k
        phase += TAU * freq / SR
        breath = lp.lowpass(rng.random() * 2 - 1) * 2.0
        groan = bp(glottal(freq, 0, phase)) * 0.25
        out.append((breath + groan) * env)
    save("patron_sigh", normalize(out, 0.5))


def clink(out, start, freq, amp):
    """Inharmonic glass partials with a fast decay."""
    for j in range(n_samples(0.35)):
        idx = start + j
        if idx >= len(out):
            break
        t = j / SR
        v = math.sin(TAU * freq * t) + 0.6 * math.sin(TAU * freq * 2.32 * t) + 0.3 * math.sin(TAU * freq * 4.25 * t)
        out[idx] += v * amp * math.exp(-t * 14)


def thunk(out, start, amp):
    """Heavy glass bottom landing on a wooden bar top."""
    rng = random.Random(start)
    lp = OnePole(400)
    for j in range(n_samples(0.08)):
        t = j / SR
        out[start + j] += (lp.lowpass(rng.random() * 2 - 1) * 3 + math.sin(TAU * 140 * t)) * amp * math.exp(-t * 60)


def gen_glass_down():
    out = [0.0] * n_samples(0.45)
    thunk(out, 0, 0.8)
    clink(out, n_samples(0.005), 2900, 0.12)
    save("patron_glass_down", normalize(out, 0.55))


def gen_sip():
    """Glass lifted with a clink, then two throaty gulps."""
    out = [0.0] * n_samples(1.0)
    clink(out, 0, 3300, 0.25)
    for g, start_t in enumerate((0.38, 0.66)):
        s0 = n_samples(start_t)
        bp = BandPass(260, 4.0)
        rng = random.Random(61 + g)
        for j in range(n_samples(0.13)):
            t = j / SR
            freq = 180 + 260 * t / 0.13
            v = math.sin(TAU * freq * t) * 0.8 + bp(rng.random() * 2 - 1) * 2.0
            out[s0 + j] += v * math.sin(math.pi * j / n_samples(0.13)) * 0.6
    save("patron_sip", normalize(out, 0.55))


def gen_tap():
    """Restless fingers drumming on the table: a quick four-finger roll,
    twice."""
    rng = random.Random(71)
    out = [0.0] * n_samples(0.9)
    lp = OnePole(1500)
    for roll_t in (0.0, 0.45):
        for f in range(4):
            s0 = n_samples(roll_t + f * 0.055 + rng.uniform(-0.005, 0.005))
            amp = rng.uniform(0.6, 1.0)
            for j in range(n_samples(0.03)):
                t = j / SR
                out[s0 + j] += (rng.random() * 2 - 1 + math.sin(TAU * 420 * t)) * amp * math.exp(-t * 180)
    save("patron_tap", normalize([lp.lowpass(v) for v in out], 0.5))


# --- Street -----------------------------------------------------------------------

def gen_lookout_whistle():
    """A lookout's warning: two sharp, rising two-finger whistles with a bit
    of breath noise, loud enough to carry down the block."""
    rng = random.Random(101)
    out = []
    for rep in range(2):
        ln = n_samples(0.32)
        phase = 0.0
        bp = BandPass(2600, 3.0)
        for j in range(ln):
            k = j / ln
            # Swoop up, hold, then drop off at the end.
            freq = 1900 + 900 * min(1.0, k * 2.5) - (500 * (k - 0.8) / 0.2 if k > 0.8 else 0)
            phase += TAU * freq / SR
            env = min(1.0, j / 300) * (1 - max(0.0, k - 0.85) / 0.15)
            breath = bp(rng.random() * 2 - 1) * 0.35
            out.append((math.sin(phase) + breath) * env)
        out.extend([0.0] * n_samples(0.12))
    save("lookout_whistle", normalize(out, 0.6))


# --- City --------------------------------------------------------------------

def gen_city_ambience():
    """Night street: distant traffic rumble (low-passed brown noise), a slow
    wind swell, and one car passing somewhere off-screen."""
    rng = random.Random(41)
    n, fade = n_samples(12.0), n_samples(1.0)
    total = n + fade
    lp_rumble, lp_wind, hp_wind = OnePole(180), OnePole(900), OnePole(250)
    brown = 0.0
    out = []
    pass_center, pass_width = 6.0, 1.8
    for i in range(total):
        t = i / SR
        brown = max(-1.0, min(1.0, brown + (rng.random() * 2 - 1) * 0.02))
        rumble = lp_rumble.lowpass(brown) * 3.0
        wind = hp_wind.highpass(lp_wind.lowpass(rng.random() * 2 - 1)) * (0.25 + 0.15 * math.sin(TAU * t / 12.0))
        car = math.exp(-((t - pass_center) / pass_width) ** 2)
        tire = rng.random() * 2 - 1
        out.append(rumble + wind + car * 0.35 * tire * (0.6 + 0.4 * math.sin(TAU * 38 * t)))
    lp = OnePole(2500)
    for s in out[-n_samples(0.5):]:
        lp.lowpass(s)
    smoothed = [lp.lowpass(s) for s in out]
    save("city_ambience_loop", normalize(loop_crossfade(smoothed, n, fade), 0.5))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_bulb_buzz()
    gen_bulb_crackle()
    gen_tv_static()
    gen_fluorescent_hum()
    gen_cooler_hum()
    gen_jukebox()
    gen_bar_murmur()
    gen_city_ambience()
    gen_mutter("patron_mutter_a", 81, 5)
    gen_mutter("patron_mutter_b", 82, 3)
    gen_mutter("patron_mutter_c", 83, 7)
    gen_cough("patron_cough", 91, wet=0.2)
    gen_cough("patron_cough_wet", 92, wet=1.0)
    gen_sniff()
    gen_sigh()
    gen_glass_down()
    gen_sip()
    gen_tap()
    gen_lookout_whistle()
