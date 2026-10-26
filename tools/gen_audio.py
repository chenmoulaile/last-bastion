"""Procedurally synthesize the original LAST BASTION soundtrack, ambience and SFX.

Everything is generated from oscillators and noise, then encoded to OGG. The
music is built as four aligned stems per theme (calm / combat / horde / tank)
so AudioManager can cross-fade layers without restarting the loop.

Run: py -3 tools/gen_audio.py
"""
import math
import os
import random
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
TMP = os.path.join(ROOT, "build", "audio_tmp")
FFMPEG = r"C:\Users\chenk\scoop\shims\ffmpeg.exe"

os.makedirs(MUSIC, exist_ok=True)
os.makedirs(SFX, exist_ok=True)
os.makedirs(TMP, exist_ok=True)

RNG = np.random.default_rng(20261026)
random.seed(20261026)


# --------------------------------------------------------------- utilities ---
def t_axis(seconds):
    return np.arange(int(SR * seconds), dtype=np.float64) / SR


def midi_hz(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def env_ad(n, attack=0.005, decay=1.0, power=2.0):
    a = max(1, int(attack * SR))
    e = np.ones(n, dtype=np.float64)
    e[:a] = np.linspace(0.0, 1.0, a) ** 0.6
    tail = np.linspace(1.0, 0.0, max(1, n - a)) ** power
    e[a:] *= tail
    return e


def env_adsr(n, attack=0.01, decay=0.2, sustain=0.6, release=0.3):
    a = max(1, int(attack * SR))
    d = max(1, int(decay * SR))
    r = max(1, int(release * SR))
    s = max(0, n - a - d - r)
    parts = [
        np.linspace(0.0, 1.0, a),
        np.linspace(1.0, sustain, d),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r),
    ]
    e = np.concatenate(parts)[:n]
    if len(e) < n:
        e = np.pad(e, (0, n - len(e)))
    return e


def noise(n):
    return RNG.standard_normal(n)


def lowpass(x, cutoff):
    # zero-phase FFT low-pass (one-pole magnitude response); much faster than a
    # per-sample Python loop and plenty accurate for procedural audio.
    if cutoff <= 0 or len(x) < 8:
        return x
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    spectrum *= 1.0 / np.sqrt(1.0 + (freqs / cutoff) ** 2)
    return np.fft.irfft(spectrum, len(x))


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def saw_phase(phase):
    return 2.0 * (phase - np.floor(phase + 0.5))


def square_phase(phase):
    return np.sign(np.sin(2.0 * math.pi * phase))


def triangle_phase(phase):
    return 2.0 * np.abs(saw_phase(phase)) - 1.0


def osc_freq(freq, n, kind="saw"):
    phase = np.cumsum(np.full(n, freq / SR))
    if kind == "saw":
        return saw_phase(phase)
    if kind == "square":
        return square_phase(phase)
    if kind == "triangle":
        return triangle_phase(phase)
    if kind == "sine":
        return np.sin(2.0 * math.pi * phase)
    return np.sin(2.0 * math.pi * phase)


def sweep(f0, f1, n, kind="sine", curve=2.0):
    x = np.linspace(0.0, 1.0, n)
    freq = f0 + (f1 - f0) * (x ** curve)
    phase = np.cumsum(freq / SR)
    if kind == "saw":
        return saw_phase(phase)
    if kind == "square":
        return square_phase(phase)
    return np.sin(2.0 * math.pi * phase)


def add_stereo(buf, start_s, sig, gain=1.0, pan=0.0):
    start = int(start_s * SR)
    if start >= buf.shape[0]:
        return
    end = min(buf.shape[0], start + len(sig))
    sig = sig[: end - start]
    l = math.sqrt((1.0 - pan) * 0.5)
    r = math.sqrt((1.0 + pan) * 0.5)
    buf[start:end, 0] += sig * gain * l
    buf[start:end, 1] += sig * gain * r


def add_note(buf, start_s, dur, freq, gain=0.2, kind="saw", attack=0.01,
             release=0.2, pan=0.0, sustain=0.6, detune=0.0):
    n = max(2, int(dur * SR))
    e = env_adsr(n, attack, min(0.2, dur * 0.2), sustain, release)
    sig = osc_freq(freq, n, kind)
    if detune:
        sig = 0.6 * sig + 0.4 * osc_freq(freq * (1.0 + detune), n, kind)
    add_stereo(buf, start_s, sig * e, gain, pan)


def add_chord(buf, start_s, dur, freqs, gain=0.12, kind="saw", attack=0.1,
              release=0.6, pan=0.0):
    for i, f in enumerate(freqs):
        p = pan + (i - (len(freqs) - 1) * 0.5) * 0.18
        add_note(buf, start_s, dur, f, gain, kind, attack, release, p, 0.7)


def kick(buf, start_s, gain=0.5, pitch=120.0, decay=0.32, pan=0.0):
    n = int(decay * SR)
    body = sweep(pitch, 44.0, n, "sine", 2.4) * np.exp(-np.linspace(0, 7.0, n))
    click = highpass(noise(n), 3000.0) * np.exp(-np.linspace(0, 60.0, n))
    add_stereo(buf, start_s, body * 0.9 + click * 0.12, gain, pan)


def snare(buf, start_s, gain=0.3, pan=0.0, tone=190.0):
    n = int(0.24 * SR)
    nz = highpass(noise(n), 1100.0) * np.exp(-np.linspace(0, 22.0, n))
    body = np.sin(2 * math.pi * tone * t_axis(0.24)[:n]) * np.exp(-np.linspace(0, 30.0, n))
    add_stereo(buf, start_s, nz * 0.8 + body * 0.35, gain, pan)


def hat(buf, start_s, gain=0.08, pan=0.0, decay=0.05, open_hat=False):
    n = int((0.22 if open_hat else decay) * SR)
    nz = highpass(noise(n), 6500.0) * np.exp(-np.linspace(0, 28.0 if not open_hat else 10.0, n))
    add_stereo(buf, start_s, nz, gain, pan)


def tom(buf, start_s, gain=0.3, freq=95.0, pan=0.0):
    n = int(0.32 * SR)
    body = sweep(freq, freq * 0.55, n, "sine", 2.0) * np.exp(-np.linspace(0, 10.0, n))
    nz = lowpass(noise(n), 500.0) * np.exp(-np.linspace(0, 18.0, n)) * 0.2
    add_stereo(buf, start_s, body + nz, gain, pan)


def crash(buf, start_s, gain=0.14, pan=0.0):
    n = int(1.4 * SR)
    nz = highpass(noise(n), 3500.0) * np.exp(-np.linspace(0, 5.0, n))
    add_stereo(buf, start_s, nz, gain, pan)


def bell(buf, start_s, freq, gain=0.1, dur=1.4, pan=0.0):
    n = int(dur * SR)
    tt = t_axis(dur)[:n]
    sig = (
        np.sin(2 * math.pi * freq * tt) * 0.6
        + np.sin(2 * math.pi * freq * 2.01 * tt) * 0.25
        + np.sin(2 * math.pi * freq * 3.98 * tt) * 0.1
    ) * np.exp(-np.linspace(0, 6.0, n))
    add_stereo(buf, start_s, sig, gain, pan)


def fold_tail(buf, loop_len):
    out = buf[:loop_len].copy()
    tail = buf[loop_len:]
    if len(tail):
        idx = np.arange(len(tail)) % loop_len
        np.add.at(out, idx, tail)
    return out


def write_wav(path, stereo):
    data = np.clip(stereo, -1.0, 1.0)
    pcm = (data * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def encode(wav_path, ogg_path, quality=5):
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "libvorbis", "-q:a", str(quality), ogg_path],
        check=True,
    )


def save_sfx(name, mono, peak=0.85):
    stereo = np.column_stack([mono, mono])
    m = np.max(np.abs(stereo))
    if m > 0:
        stereo *= peak / m
    wav = os.path.join(TMP, name + ".wav")
    write_wav(wav, stereo)
    encode(wav, os.path.join(SFX, name + ".ogg"), 4)


# ------------------------------------------------------------------- music ---
THEMES = {
    "suburb": {"bpm": 96, "root": 45, "prog": [0, 5, 3, 4, 0, 5, 6, 4], "kind": "triangle"},
    "city": {"bpm": 104, "root": 43, "prog": [0, 3, 5, 4, 0, 3, 6, 5], "kind": "saw"},
    "military": {"bpm": 116, "root": 41, "prog": [0, 0, 5, 5, 3, 3, 4, 4], "kind": "square"},
    "subway": {"bpm": 88, "root": 38, "prog": [0, 6, 5, 4, 0, 6, 3, 4], "kind": "triangle"},
    "bridge": {"bpm": 124, "root": 40, "prog": [0, 5, 6, 4, 0, 5, 3, 4], "kind": "saw"},
}

MINOR = [0, 2, 3, 5, 7, 8, 10]
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]


def theme_scale(theme):
    return PHRYGIAN if theme in ("military", "bridge") else MINOR


def chord_notes(root, scale, degree):
    idx = degree % 7
    return [root + scale[idx], root + scale[(idx + 2) % 7] + (12 if idx + 2 >= 7 else 0),
            root + scale[(idx + 4) % 7] + (12 if idx + 4 >= 7 else 0)]


def make_music(theme, cfg):
    bpm = cfg["bpm"]
    spb = 60.0 / bpm
    bars = 8
    loop_len = int(bars * 4 * spb * SR)
    total = loop_len + int(2.5 * SR)
    scale = theme_scale(theme)
    root = cfg["root"]
    prog = cfg["prog"]
    layers = {name: np.zeros((total, 2), dtype=np.float64) for name in
              ("calm", "combat", "horde", "tank")}

    for bar in range(bars):
        degree = prog[bar % len(prog)]
        chord = chord_notes(root + 12, scale, degree)
        t0 = bar * 4 * spb
        # calm: sustained pad, slow bass, distant bell motif
        add_chord(layers["calm"], t0, 4 * spb * 0.98, [midi_hz(n) for n in chord],
                  0.075, cfg["kind"], attack=0.7, release=1.4, pan=0.0)
        add_note(layers["calm"], t0, 4 * spb, midi_hz(root - 12 + scale[degree % 7]),
                 0.11, "sine", attack=0.15, release=1.2, sustain=0.5)
        if bar % 2 == 0:
            bell(layers["calm"], t0 + 2.5 * spb, midi_hz(root + 24 + scale[(degree + 4) % 7]),
                 0.055, 2.2, 0.25)
        # airy noise wash
        n = int(4 * spb * SR)
        wash = lowpass(noise(n), 700.0) * np.exp(-np.linspace(0, 2.0, n)) * 0.012
        add_stereo(layers["calm"], t0, wash, 1.0, 0.0)

        # combat: 4/4 groove, eighth bass, arpeggio
        for beat in range(4):
            bt = t0 + beat * spb
            if beat in (0, 2):
                kick(layers["combat"], bt, 0.38, 110.0, 0.3)
            if beat in (1, 3):
                snare(layers["combat"], bt, 0.24, 0.0)
            hat(layers["combat"], bt + spb * 0.5, 0.055, 0.25)
        for e in range(8):
            et = t0 + e * spb * 0.5
            note = root + scale[degree % 7] + (-12 if e % 4 == 3 else 0)
            add_note(layers["combat"], et, spb * 0.42, midi_hz(note), 0.11,
                     "saw", 0.005, 0.08, -0.15, 0.3, 0.005)
        for s in range(16):
            st = t0 + s * spb * 0.25
            note = chord[s % 3] + (12 if s % 8 >= 4 else 0)
            add_note(layers["combat"], st, spb * 0.2, midi_hz(note), 0.028,
                     "square", 0.003, 0.05, 0.35, 0.2)

        # horde: driving double-time, 16th bass
        for s in range(16):
            st = t0 + s * spb * 0.25
            if s % 4 == 0:
                kick(layers["horde"], st, 0.42, 130.0, 0.22)
            if s % 4 == 2:
                snare(layers["horde"], st, 0.28, 0.0, 210.0)
            if s % 2 == 1:
                hat(layers["horde"], st, 0.05, -0.3)
            note = root + scale[degree % 7] + (12 if s % 8 >= 4 else 0)
            add_note(layers["horde"], st, spb * 0.2, midi_hz(note), 0.085,
                     "square", 0.002, 0.04, 0.1, 0.2, 0.01)
        if bar % 2 == 0:
            add_chord(layers["horde"], t0, 4 * spb, [midi_hz(n) for n in chord],
                      0.055, "saw", 0.05, 0.4, 0.0)

        # tank: half-time weight, distorted bass, brass clusters
        kick(layers["tank"], t0, 0.58, 90.0, 0.5)
        kick(layers["tank"], t0 + 2.5 * spb, 0.5, 82.0, 0.42)
        snare(layers["tank"], t0 + 2 * spb, 0.34, 0.0, 150.0)
        tom(layers["tank"], t0 + 3 * spb, 0.32, 78.0, -0.2)
        tom(layers["tank"], t0 + 3.5 * spb, 0.28, 68.0, 0.2)
        for e in range(4):
            et = t0 + e * spb
            note = root - 12 + scale[degree % 7]
            add_note(layers["tank"], et, spb * 0.85, midi_hz(note), 0.17,
                     "saw", 0.01, 0.3, 0.0, 0.5, 0.02)
        if bar % 2 == 0:
            add_chord(layers["tank"], t0, 2 * spb, [midi_hz(n + 12) for n in chord],
                      0.055, "saw", 0.02, 0.6, 0.0)
            crash(layers["tank"], t0, 0.12)
            bell(layers["tank"], t0, midi_hz(root + 36), 0.045, 1.8, -0.2)

    for name, buf in layers.items():
        # cheap stereo width and a folded delay tail for seamless looping
        delay = int(0.21 * SR)
        tail = np.zeros_like(buf)
        tail[delay:] = buf[:-delay] * 0.16
        mixed = buf + tail
        mixed = fold_tail(mixed, loop_len)
        # gentle bus compression / soft clip
        mixed = np.tanh(mixed * 1.15) * 0.92
        wav = os.path.join(TMP, f"{theme}_{name}.wav")
        write_wav(wav, mixed)
        encode(wav, os.path.join(MUSIC, f"{theme}_{name}.ogg"), 5)
    print(f"music: {theme}")


def make_menu():
    bpm = 76
    spb = 60.0 / bpm
    bars = 8
    loop_len = int(bars * 4 * spb * SR)
    total = loop_len + int(2.5 * SR)
    buf = np.zeros((total, 2))
    root = 45
    scale = MINOR
    prog = [0, 5, 3, 4, 0, 6, 5, 4]
    for bar in range(bars):
        t0 = bar * 4 * spb
        degree = prog[bar]
        chord = chord_notes(root + 12, scale, degree)
        add_chord(buf, t0, 4 * spb * 0.98, [midi_hz(n) for n in chord], 0.08,
                  "triangle", 0.9, 1.5, 0.0)
        add_note(buf, t0, 4 * spb, midi_hz(root - 12 + scale[degree]), 0.09,
                 "sine", 0.4, 1.4, 0.0, 0.5)
        if bar % 2 == 1:
            bell(buf, t0 + spb, midi_hz(root + 24 + scale[(degree + 2) % 7]), 0.06, 2.4, 0.3)
    mixed = fold_tail(buf + np.roll(buf, int(0.29 * SR), axis=0) * 0.12, loop_len)
    mixed = np.tanh(mixed * 1.1) * 0.9
    wav = os.path.join(TMP, "menu.wav")
    write_wav(wav, mixed)
    encode(wav, os.path.join(MUSIC, "menu.ogg"), 5)
    print("music: menu")


def make_result():
    # victory fanfare in D minor -> relative major lift
    for name, notes, bpm, gain in (
        ("result", [62, 65, 69, 74, 77, 81], 108, 0.16),
        ("result_s", [62, 65, 69, 74, 77, 81, 86], 124, 0.18),
        ("result_f", [50, 53, 49, 46, 45], 60, 0.14),
    ):
        dur = 6.5 if name != "result_f" else 5.5
        buf = np.zeros((int((dur + 1.0) * SR), 2))
        spb = 60.0 / bpm
        for i, note in enumerate(notes):
            add_note(buf, i * spb * 0.85, spb * 1.6, midi_hz(note), gain,
                     "saw", 0.01, 0.5, 0.0, 0.6, 0.006)
            add_note(buf, i * spb * 0.85, spb * 1.6, midi_hz(note + 12), gain * 0.35,
                     "square", 0.01, 0.5, 0.3, 0.5)
        if name != "result_f":
            add_chord(buf, 0, dur * 0.7, [midi_hz(50), midi_hz(57), midi_hz(62)],
                      0.06, "triangle", 0.05, 1.4, 0.0)
            for i in range(4):
                kick(buf, i * spb * 2, 0.28, 100.0, 0.25)
        else:
            add_note(buf, 0, dur, midi_hz(38), 0.12, "sine", 0.2, 1.6, 0.0, 0.5)
            add_stereo(buf, 0.2, lowpass(noise(int(3.0 * SR)), 300.0) *
                       np.exp(-np.linspace(0, 3.0, int(3.0 * SR))) * 0.06, 1.0, 0.0)
        mixed = np.tanh(buf[: int(dur * SR)] * 1.1) * 0.92
        wav = os.path.join(TMP, name + ".wav")
        write_wav(wav, mixed)
        encode(wav, os.path.join(MUSIC, name + ".ogg"), 5)
        print(f"music: {name}")


# -------------------------------------------------------------------- sfx ----
def gunshot(kind):
    if kind in ("m9", "ar15", "smg"):
        dur = {"m9": 0.24, "ar15": 0.3, "smg": 0.2}[kind]
        body_f = {"m9": 190.0, "ar15": 150.0, "smg": 230.0}[kind]
        n = int(dur * SR)
        crack = highpass(noise(n), 2200.0) * np.exp(-np.linspace(0, 30.0, n))
        body = sweep(body_f, 48.0, n, "sine", 2.2) * np.exp(-np.linspace(0, 14.0, n))
        tail = lowpass(noise(n), 1200.0) * np.exp(-np.linspace(0, 8.0, n)) * 0.5
        return crack * 0.55 + body * 0.6 + tail * 0.35
    if kind == "shotgun":
        n = int(0.55 * SR)
        blast = highpass(noise(n), 900.0) * np.exp(-np.linspace(0, 10.0, n))
        body = sweep(120.0, 38.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 8.0, n))
        pump = lowpass(noise(int(0.08 * SR)), 800.0) * 0.2
        out = blast * 0.7 + body * 0.8
        out[int(0.32 * SR): int(0.32 * SR) + len(pump)] += pump
        return out
    if kind == "sniper":
        n = int(0.8 * SR)
        crack = highpass(noise(n), 1800.0) * np.exp(-np.linspace(0, 9.0, n))
        boom = sweep(95.0, 30.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 7.0, n))
        tail = lowpass(noise(n), 900.0) * np.exp(-np.linspace(0, 4.0, n)) * 0.4
        return crack * 0.65 + boom * 0.9 + tail
    if kind == "lmg":
        n = int(0.26 * SR)
        crack = highpass(noise(n), 1400.0) * np.exp(-np.linspace(0, 24.0, n))
        body = sweep(110.0, 40.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 12.0, n))
        return crack * 0.6 + body * 0.75
    # generic
    n = int(0.28 * SR)
    crack = highpass(noise(n), 2000.0) * np.exp(-np.linspace(0, 28.0, n))
    body = sweep(160.0, 45.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 13.0, n))
    return crack * 0.55 + body * 0.6


def melee_hit(kind="flesh"):
    n = int(0.3 * SR)
    if kind == "metal":
        tt = t_axis(0.3)[:n]
        return (np.sin(2 * math.pi * 780 * tt) + np.sin(2 * math.pi * 1330 * tt) * 0.6) * \
            np.exp(-np.linspace(0, 18.0, n)) * 0.5
    if kind == "wood":
        nz = lowpass(noise(n), 1800.0) * np.exp(-np.linspace(0, 22.0, n))
        thud = sweep(120.0, 55.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 15.0, n))
        return nz * 0.35 + thud * 0.7
    squelch = lowpass(noise(n), 900.0) * np.exp(-np.linspace(0, 16.0, n))
    thud = sweep(90.0, 42.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 13.0, n))
    return squelch * 0.55 + thud * 0.7


def zombie_voice(kind):
    if kind == "attack":
        dur = 0.5
        n = int(dur * SR)
        sig = sweep(95.0, 140.0, n, "saw", 1.5) * np.exp(-np.linspace(0, 5.0, n))
        sig *= 0.7 + 0.3 * np.sin(2 * math.pi * 8.0 * t_axis(dur)[:n])
        return lowpass(sig, 1500.0) * 0.6 + highpass(noise(n), 600.0) * 0.2
    if kind == "die":
        dur = 0.9
        n = int(dur * SR)
        sig = sweep(150.0, 45.0, n, "saw", 2.0) * np.exp(-np.linspace(0, 5.0, n))
        return lowpass(sig, 1100.0) * 0.7 + lowpass(noise(n), 500.0) * 0.2
    if kind == "scream":
        dur = 1.1
        n = int(dur * SR)
        sig = sweep(420.0, 680.0, n, "saw", 1.2) * np.exp(-np.linspace(0, 3.0, n))
        return lowpass(sig, 2200.0) * 0.45 + highpass(noise(n), 1200.0) * 0.18
    if kind == "land":
        n = int(0.22 * SR)
        return lowpass(noise(n), 700.0) * np.exp(-np.linspace(0, 20.0, n)) * 0.5
    return lowpass(noise(int(0.4 * SR)), 800.0) * 0.3


def special_sfx(name):
    if name == "hunter_pounce":
        n = int(0.6 * SR)
        return sweep(500.0, 180.0, n, "saw", 1.5) * np.exp(-np.linspace(0, 5.0, n)) * 0.5 + \
            lowpass(noise(n), 900.0) * 0.15
    if name == "hunter_scream":
        n = int(0.8 * SR)
        return sweep(700.0, 300.0, n, "square", 1.3) * np.exp(-np.linspace(0, 4.0, n)) * 0.35 + \
            highpass(noise(n), 900.0) * 0.2
    if name == "hunter_pin":
        n = int(0.7 * SR)
        return lowpass(noise(n), 700.0) * np.exp(-np.linspace(0, 6.0, n)) * 0.5 + \
            sweep(120.0, 60.0, n, "sine", 2.0) * 0.4
    if name == "smoker_cough":
        n = int(0.8 * SR)
        return lowpass(noise(n), 1100.0) * (0.4 + 0.4 * np.sin(2 * math.pi * 3.0 * t_axis(0.8)[:n])) * \
            np.exp(-np.linspace(0, 5.0, n)) * 0.5
    if name == "smoker_tongue":
        n = int(0.7 * SR)
        return highpass(noise(n), 500.0) * np.exp(-np.linspace(0, 9.0, n)) * 0.35 + \
            sweep(220.0, 90.0, n, "saw", 2.0) * 0.3
    if name == "boomer_burp":
        n = int(0.55 * SR)
        return lowpass(sweep(120.0, 55.0, n, "square", 2.0), 500.0) * np.exp(-np.linspace(0, 6.0, n)) * 0.5
    if name == "boomer_explode":
        n = int(1.0 * SR)
        return lowpass(noise(n), 1400.0) * np.exp(-np.linspace(0, 6.0, n)) * 0.6 + \
            sweep(90.0, 35.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 8.0, n)) * 0.5
    if name in ("charger_charge", "charger_roar", "charger_pound", "charger_impact"):
        n = int(0.8 * SR)
        base = 70.0 if name != "charger_pound" else 50.0
        sig = sweep(base * 2, base, n, "saw", 2.0) * np.exp(-np.linspace(0, 5.0, n))
        nz = lowpass(noise(n), 600.0) * np.exp(-np.linspace(0, 8.0, n))
        return sig * 0.5 + nz * 0.3
    if name == "spitter_hiss":
        n = int(1.2 * SR)
        return highpass(noise(n), 1800.0) * (0.5 + 0.5 * np.sin(2 * math.pi * 5.0 * t_axis(1.2)[:n])) * \
            np.exp(-np.linspace(0, 3.0, n)) * 0.3
    if name == "jockey_giggle":
        n = int(0.65 * SR)
        tt = t_axis(0.65)[:n]
        mod = 1.0 + 0.35 * np.sin(2 * math.pi * 9.0 * tt)
        return lowpass(sweep(420.0, 620.0, n, "square", 1.0) * mod, 2400.0) * \
            np.exp(-np.linspace(0, 5.0, n)) * 0.35
    if name == "jockey_ride":
        n = int(1.2 * SR)
        tt = t_axis(1.2)[:n]
        return lowpass(sweep(300.0, 500.0, n, "saw", 1.0) * (1.0 + 0.3 * np.sin(2 * math.pi * 11.0 * tt)),
                       1800.0) * np.exp(-np.linspace(0, 3.0, n)) * 0.35
    if name == "tank_roar":
        n = int(1.8 * SR)
        sig = sweep(90.0, 55.0, n, "saw", 1.4) * np.exp(-np.linspace(0, 3.0, n))
        return lowpass(sig, 900.0) * 0.7 + lowpass(noise(n), 400.0) * 0.25
    if name == "tank_punch":
        n = int(0.5 * SR)
        return sweep(80.0, 32.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 9.0, n)) * 0.8 + \
            lowpass(noise(n), 600.0) * np.exp(-np.linspace(0, 12.0, n)) * 0.3
    if name == "tank_bell":
        return bell_mix([220.0, 277.0, 330.0], 3.0, 0.4)
    if name == "witch_scream":
        n = int(1.6 * SR)
        sig = sweep(600.0, 1100.0, n, "saw", 1.0) * np.exp(-np.linspace(0, 2.0, n))
        return lowpass(sig, 3000.0) * 0.45 + highpass(noise(n), 1500.0) * 0.2
    if name == "witch_attack":
        n = int(0.45 * SR)
        return highpass(noise(n), 1500.0) * np.exp(-np.linspace(0, 12.0, n)) * 0.4 + \
            sweep(300.0, 120.0, n, "saw", 2.0) * 0.35
    if name == "witch_crowned":
        return bell_mix([880.0, 1320.0, 1760.0], 2.2, 0.22)
    if name == "special_sting":
        return bell_mix([110.0, 164.8, 220.0], 2.0, 0.3)
    return np.zeros(100)


def bell_mix(freqs, dur, gain):
    n = int(dur * SR)
    tt = t_axis(dur)[:n]
    out = np.zeros(n)
    for i, f in enumerate(freqs):
        out += np.sin(2 * math.pi * f * tt + i) * np.exp(-np.linspace(0, 4.0 + i, n)) * gain / (i + 1)
    return out


def mix(*signals):
    n = max(len(s) for s in signals)
    out = np.zeros(n)
    for sig in signals:
        out[:len(sig)] += sig
    return out


def ui_sfx(name):
    if name == "ui_click":
        return bell_mix([1200.0, 1800.0], 0.12, 0.5)
    if name == "ui_deny":
        n = int(0.2 * SR)
        return np.sign(np.sin(2 * math.pi * 180 * t_axis(0.2)[:n])) * np.exp(-np.linspace(0, 14.0, n)) * 0.3
    if name == "achievement":
        return bell_mix([523.25, 659.25, 783.99, 1046.5], 1.6, 0.4)
    if name == "unlock":
        return bell_mix([392.0, 523.25, 659.25], 1.2, 0.4)
    if name == "secret":
        return bell_mix([440.0, 554.37, 659.25, 880.0], 1.8, 0.35)
    if name == "checkpoint":
        return bell_mix([330.0, 440.0], 0.8, 0.45)
    if name == "pickup":
        return bell_mix([880.0, 1320.0], 0.35, 0.45)
    if name == "heal":
        return bell_mix([523.25, 659.25], 0.7, 0.4)
    if name == "medkit_use":
        n = int(0.8 * SR)
        return lowpass(noise(n), 2200.0) * np.exp(-np.linspace(0, 6.0, n)) * 0.15 + \
            bell_mix([392.0, 523.25], 0.8, 0.25)
    if name == "pills":
        n = int(0.35 * SR)
        return highpass(noise(n), 3000.0) * np.exp(-np.linspace(0, 20.0, n)) * 0.2 + \
            bell_mix([1046.5, 1318.5], 0.35, 0.25)
    if name == "revive":
        return bell_mix([261.63, 329.63, 392.0], 1.4, 0.4)
    if name == "empty":
        n = int(0.08 * SR)
        return highpass(noise(n), 2500.0) * np.exp(-np.linspace(0, 40.0, n)) * 0.4
    if name == "reload":
        n = int(0.3 * SR)
        a = highpass(noise(n), 1800.0) * np.exp(-np.linspace(0, 18.0, n))
        b = np.zeros(n)
        b[int(0.13 * SR):] = highpass(noise(n - int(0.13 * SR)), 2200.0) * \
            np.exp(-np.linspace(0, 20.0, n - int(0.13 * SR)))
        return (a + b) * 0.3
    if name == "reload_done":
        n = int(0.35 * SR)
        a = highpass(noise(int(0.1 * SR)), 2000.0) * 0.35
        out = np.zeros(n)
        out[:len(a)] = a
        b = highpass(noise(int(0.12 * SR)), 2600.0) * 0.4
        start = int(0.18 * SR)
        out[start:start + len(b)] = b
        return out
    if name == "skill":
        return bell_mix([220.0, 330.0, 440.0, 660.0], 1.0, 0.4)
    return bell_mix([440.0, 660.0], 0.5, 0.4)


def make_sfx():
    # guns + melee
    for wid in ("m9", "ar15", "smg", "shotgun", "sniper", "lmg", "gunshot"):
        save_sfx(wid, gunshot(wid))
    save_sfx("gunshot_2", gunshot("ar15") * 0.9)
    save_sfx("m9_2", gunshot("m9") * 1.05)
    for wid in ("katana", "axe", "chainsaw"):
        if wid == "chainsaw":
            n = int(0.5 * SR)
            tt = t_axis(0.5)[:n]
            sig = saw_phase(np.cumsum((90.0 + 25.0 * np.sin(2 * math.pi * 30 * tt)) / SR))
            save_sfx(wid, lowpass(sig, 900.0) * 0.4 + highpass(noise(n), 1200.0) * 0.1)
        else:
            n = int(0.35 * SR)
            nz = highpass(noise(n), 1200.0) * np.exp(-np.linspace(0, 8.0, n))
            save_sfx(wid, mix(nz * 0.35, melee_hit("metal" if wid == "katana" else "wood") * 0.4))
    save_sfx("melee_swing", highpass(noise(int(0.22 * SR)), 900.0) *
             np.exp(-np.linspace(0, 9.0, int(0.22 * SR))) * 0.35)
    save_sfx("melee_hit", melee_hit("flesh"))
    save_sfx("metal_hit", melee_hit("metal"))
    save_sfx("wood_hit", melee_hit("wood"))
    save_sfx("ricochet", bell_mix([1800.0, 2400.0, 3100.0], 0.5, 0.22))
    save_sfx("jump", sweep(300.0, 500.0, int(0.12 * SR), "sine", 1.0) *
             np.exp(-np.linspace(0, 12.0, int(0.12 * SR))) * 0.18)
    save_sfx("slide", lowpass(noise(int(0.4 * SR)), 900.0) *
             np.exp(-np.linspace(0, 5.0, int(0.4 * SR))) * 0.25)
    save_sfx("throw", highpass(noise(int(0.25 * SR)), 800.0) *
             np.exp(-np.linspace(0, 10.0, int(0.25 * SR))) * 0.25)

    # zombie + specials
    for name, kind in (("zombie_attack", "attack"), ("zombie_die", "die"),
                       ("zombie_scream", "scream"), ("zombie_land", "land")):
        save_sfx(name, zombie_voice(kind))
        if kind in ("attack", "scream"):
            save_sfx(name + "_2", zombie_voice(kind) * 0.9)
    for name in ("hunter_pounce", "hunter_scream", "hunter_pin", "smoker_cough",
                 "smoker_tongue", "boomer_burp", "boomer_explode", "charger_charge",
                 "charger_roar", "charger_pound", "charger_impact", "spitter_hiss",
                 "jockey_giggle", "jockey_ride", "tank_roar", "tank_punch", "tank_bell",
                 "witch_scream", "witch_attack", "witch_crowned", "special_sting"):
        save_sfx(name, special_sfx(name))

    # world / combat
    n = int(1.6 * SR)
    exp = lowpass(noise(n), 900.0) * np.exp(-np.linspace(0, 5.0, n))
    boom = sweep(70.0, 28.0, n, "sine", 2.0) * np.exp(-np.linspace(0, 5.0, n))
    save_sfx("explosion", exp * 0.7 + boom * 0.9)
    n = int(0.7 * SR)
    save_sfx("firebomb", highpass(noise(n), 700.0) * np.exp(-np.linspace(0, 5.0, n)) * 0.4 +
             lowpass(noise(n), 300.0) * 0.2)
    n = int(0.5 * SR)
    save_sfx("acid_splash", highpass(noise(n), 1200.0) * np.exp(-np.linspace(0, 8.0, n)) * 0.3)
    save_sfx("bile_splash", lowpass(noise(int(0.6 * SR)), 900.0) *
             np.exp(-np.linspace(0, 6.0, int(0.6 * SR))) * 0.35)
    save_sfx("crate_break", mix(melee_hit("wood") * 0.8, lowpass(noise(int(0.4 * SR)), 1200.0) * 0.15))
    save_sfx("door_hit", melee_hit("wood") * 0.7)
    save_sfx("door_break", mix(melee_hit("wood") * 1.0, lowpass(noise(int(0.5 * SR)), 700.0) * 0.25))
    save_sfx("door_kick", melee_hit("wood") * 1.1)
    save_sfx("player_hurt", lowpass(noise(int(0.35 * SR)), 1300.0) *
             np.exp(-np.linspace(0, 10.0, int(0.35 * SR))) * 0.3 +
             sweep(180.0, 90.0, int(0.35 * SR), "saw", 2.0) * 0.2)
    save_sfx("player_die", zombie_voice("die") * 0.9)
    save_sfx("downed", bell_mix([180.0, 140.0, 110.0], 1.2, 0.3))
    save_sfx("grabbed", lowpass(noise(int(0.5 * SR)), 800.0) * 0.3 + zombie_voice("attack") * 0.4)
    save_sfx("ally_downed", bell_mix([220.0, 165.0], 0.8, 0.3))
    save_sfx("gunshot_2", gunshot("ar15"))
    for name in ("ui_click", "ui_deny", "achievement", "unlock", "secret", "checkpoint",
                 "pickup", "heal", "medkit_use", "pills", "revive", "empty", "reload",
                 "reload_done", "skill"):
        save_sfx(name, ui_sfx(name))

    # ambience beds
    make_ambience()


def make_ambience():
    def rain():
        n = int(8.0 * SR)
        bed = highpass(noise(n), 900.0) * 0.055 + lowpass(noise(n), 500.0) * 0.02
        drops = np.zeros(n)
        for _ in range(90):
            p = random.randint(0, n - 4000)
            d = highpass(noise(4000), 2500.0) * np.exp(-np.linspace(0, 18.0, 4000)) * 0.05
            drops[p:p + 4000] += d
        return bed + drops

    def wind():
        n = int(8.0 * SR)
        t = t_axis(8.0)[:n]
        mod = 0.6 + 0.4 * np.sin(2 * math.pi * 0.08 * t) * np.sin(2 * math.pi * 0.031 * t)
        return lowpass(noise(n), 420.0) * 0.09 * mod

    def city():
        n = int(8.0 * SR)
        bed = lowpass(noise(n), 300.0) * 0.05
        t = t_axis(8.0)[:n]
        siren = np.sin(2 * math.pi * (300 + 80 * np.sin(2 * math.pi * 0.11 * t)) * t) * 0.008
        return bed + siren

    def military():
        n = int(8.0 * SR)
        t = t_axis(8.0)[:n]
        hum = np.sin(2 * math.pi * 60.0 * t) * 0.02 + np.sin(2 * math.pi * 120.0 * t) * 0.008
        return lowpass(noise(n), 500.0) * 0.03 + hum

    def subway():
        n = int(8.0 * SR)
        t = t_axis(8.0)[:n]
        rumble = lowpass(noise(n), 160.0) * 0.09
        clack = np.zeros(n)
        for k in range(8):
            p = int((k * 1.0 + 0.2) * SR)
            clack[p:p + 2000] = lowpass(noise(2000), 400.0) * np.exp(-np.linspace(0, 20.0, 2000)) * 0.08
        return rumble + clack

    def bridge():
        n = int(8.0 * SR)
        return wind() * 1.4 + lowpass(noise(n), 200.0) * 0.04

    for name, fn in (("rain", rain), ("suburb", wind), ("city", city),
                     ("military", military), ("subway", subway), ("bridge", bridge)):
        data = fn()
        # crossfade the loop boundary so ambience never clicks
        fade = int(0.5 * SR)
        loop = data[:-fade].copy() if len(data) > fade else data.copy()
        head = data[-fade:]
        loop[:fade] = loop[:fade] * np.linspace(0.0, 1.0, fade) + head * np.linspace(1.0, 0.0, fade)
        save_sfx("ambience_" + name, loop, 0.7)


def main():
    for theme, cfg in THEMES.items():
        make_music(theme, cfg)
    make_menu()
    make_result()
    make_sfx()
    print("audio complete")


if __name__ == "__main__":
    main()
