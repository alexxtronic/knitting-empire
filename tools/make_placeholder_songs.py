"""Four short placeholder songs for the knitting game, until the real ones are made (ElevenLabs).

They are synthesised here, so there are no samples or licences to track, and they give the chart
maker (tools/make_chart.py) and the game's tests something real to play. Each is a few bars of
kick, snare, hat, bass and a plucked pentatonic tune at its own tempo, getting busier with the
difficulty. Replace a song by putting a new file at the same path and running make_chart.py on it.

  uv run --no-project --with numpy --with scipy python tools/make_placeholder_songs.py "$PWD"
"""
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile

SR = 32000
ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
OUT = os.path.join(ROOT, "assets", "audio", "songs")
os.makedirs(OUT, exist_ok=True)

# (id, bpm, bars, melody density: notes per beat)
SONGS = [("cast_on", 76, 16, 1), ("plain_stitch", 98, 20, 2), ("cable_knit", 122, 26, 2), ("fair_isle", 148, 32, 4)]
PENTA = [0, 2, 4, 7, 9, 12, 14, 16]  # semitones above the root
rng = np.random.default_rng(7)


def env(n, attack=0.004, decay=0.2):
    t = np.arange(n) / SR
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def tone(freq, dur, kind="tri", decay=0.25):
    n = int(SR * dur)
    t = np.arange(n) / SR
    if kind == "tri":
        w = 2 * np.abs(2 * ((t * freq) % 1.0) - 1.0) - 1.0
    else:
        w = np.sin(2 * np.pi * freq * t)
    return w * env(n, 0.003, decay)


def kick():
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    f = 120 * np.exp(-t * 28) + 42
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.09) * 1.1


def snare():
    n = int(SR * 0.2)
    return (rng.standard_normal(n) * 0.5 + np.sin(2 * np.pi * 190 * np.arange(n) / SR) * 0.4) * env(n, 0.001, 0.07)


def hat():
    n = int(SR * 0.06)
    x = rng.standard_normal(n)
    return np.diff(np.concatenate([[0], x])) * env(n, 0.001, 0.02) * 0.5


def place(buf, clip, at):
    i = int(at * SR)
    if i < len(buf):
        j = min(len(buf), i + len(clip))
        buf[i:j] += clip[: j - i]


for sid, bpm, bars, density in SONGS:
    beat = 60.0 / bpm
    total = bars * 4 * beat + 2.0
    buf = np.zeros(int(total * SR))
    root_hz = 196.0  # G3
    prog = [0, 0, 5, 7]  # a simple four-chord loop, in semitones
    rng2 = np.random.default_rng(hash(sid) % 1000)
    start = 4 * beat  # a bar of count-in beats first
    for b in range(bars * 4):
        t0 = start + b * beat if b >= 0 else 0.0
        if t0 + beat > total:
            break
        bar = b // 4
        chord = prog[bar % 4]
        if b % 4 in (0, 2) or density >= 4:
            place(buf, kick(), t0)
        if b % 4 in (1, 3):
            place(buf, snare(), t0)
        place(buf, hat(), t0 + beat * 0.5)
        if density >= 2:
            place(buf, hat(), t0)
        if b % 2 == 0:
            place(buf, tone(root_hz * 2 ** ((chord - 12) / 12), beat * 1.6, "sin", 0.5) * 0.6, t0)
        # the tune: bars 2 onwards
        if bar >= 2:
            steps = density if density < 4 else 4
            for s in range(steps):
                if density == 1 and b % 2:
                    continue
                if rng2.random() < (0.55 if density < 3 else 0.85):
                    deg = PENTA[(b * 3 + s * 2 + bar) % len(PENTA)]
                    place(buf, tone(root_hz * 2 ** ((chord + deg) / 12) * 2, beat * 0.9, "tri", 0.18) * 0.38, t0 + s * beat / steps)
    # count-in: four soft clicks
    for k in range(4):
        place(buf, hat() * 1.5, k * beat)
    buf /= max(1e-6, np.max(np.abs(buf))) * 1.15
    wav = os.path.join(OUT, sid + ".wav")
    wavfile.write(wav, SR, (buf * 32767).astype(np.int16))
    ogg = os.path.join(OUT, sid + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
    os.remove(wav)
    print("wrote", ogg, "%.0f s" % total)
