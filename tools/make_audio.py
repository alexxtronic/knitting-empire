"""Makes every sound in the game from scratch: no samples, no licences, all original.

    uv run --no-project --with numpy --with scipy python tools/make_audio.py [project_dir]

Writes assets/audio/*.wav (short effects) and *.ogg (music and ambience loops, via ffmpeg).
Loops are seamless: each one is rendered a little long and its tail is folded back onto its start.

These are placeholders with the right mood and timing. The roadmap plans real music from a composer;
when it arrives, drop the files in with the same names and nothing else needs to change.
"""
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

SR = 44100
rng = np.random.default_rng(7)
ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "audio")
os.makedirs(OUT, exist_ok=True)


# --- helpers -----------------------------------------------------------------------------------

def t_of(secs):
    return np.arange(int(secs * SR)) / SR


def band(x, lo=None, hi=None, order=2):
    if lo and hi:
        sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, btype="high", fs=SR, output="sos")
    else:
        sos = butter(order, hi, btype="low", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


def noise(n, ch=1):
    return rng.standard_normal((n, ch)) if ch > 1 else rng.standard_normal(n)


def expdec(n, secs):
    return np.exp(-np.arange(n) / (secs * SR))


def fade(n, attack, release=0.0):
    e = np.ones(n)
    a = max(1, int(attack * SR))
    e[:a] = np.linspace(0, 1, a)
    if release:
        r = max(1, int(release * SR))
        e[-r:] *= np.linspace(1, 0, r)
    return e


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def stereo(x, pan=0.0):
    """Mono to stereo with an equal-power pan (-1 left .. 1 right)."""
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def reverb(x, secs=1.6, wet=0.25, tone=5000):
    n = int(secs * SR)
    ir = band(noise(n, 2), hi=tone) * expdec(n, secs / 5.5)[:, None]
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))[:, None]  # a little pre-delay softness
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    if x.ndim == 1:
        x = stereo(x)
    out = np.stack([fftconvolve(x[:, c], ir[:, c]) for c in range(2)], axis=1)
    dry = np.zeros_like(out)
    dry[: len(x)] = x
    return dry * (1 - wet) + out * wet


def fold_loop(x, length):
    """Seamless loop: add everything past `length` back onto the start."""
    n = int(length * SR)
    y = x[:n].copy()
    tail = x[n:]
    while len(tail):
        k = min(len(tail), n)
        y[:k] += tail[:k]
        tail = tail[k:]
    return y


def crossfade_loop(x, length, xf=2.0):
    """Seamless loop for steady textures: crossfade the extra bit at the end over the start."""
    n, k = int(length * SR), int(xf * SR)
    y = x[:n].copy()
    a = np.linspace(0, np.pi / 2, k)
    w_in, w_out = np.sin(a), np.cos(a)
    if y.ndim == 2:
        w_in, w_out = w_in[:, None], w_out[:, None]
    y[:k] = x[:k] * w_in + x[n:n + k] * w_out
    return y


def write_wav(name, x):
    x = np.clip(x, -1, 1)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("  %-22s %5.2fs" % (name + ".wav", len(x) / SR))


def write_ogg(name, x, q=5):
    tmp = os.path.join(OUT, "_tmp_" + name + ".wav")
    wavfile.write(tmp, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q),
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(tmp)
    print("  %-22s %5.1fs" % (name + ".ogg", len(x) / SR))


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def pluck(midi, secs, bright=0.5, damp=0.996):
    """Karplus-Strong plucked string: a soft nylon-guitar / harp tone."""
    f = mtof(midi)
    p = int(SR / f)
    n = int(secs * SR)
    x = np.zeros(n)
    x[:p] = band(noise(p), hi=1500 + 6000 * bright)
    # y[i] = x[i] + damp/2 * (y[i-p] + y[i-p-1]): the delay line with its averaging filter, as one IIR
    a = np.zeros(p + 2)
    a[0], a[p], a[p + 1] = 1.0, -damp * 0.5, -damp * 0.5
    out = lfilter([1.0], a, x)
    return out * fade(n, 0.002, 0.08)


def flute(midi, secs):
    """A soft breathy wooden-flute voice with gentle vibrato."""
    n = int(secs * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.18) / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(mtof(midi) * vib) / SR
    tone = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    breath = band(noise(n), mtof(midi) * 0.9, mtof(midi) * 4) * 0.05
    return (tone + breath) * fade(n, 0.07, min(0.18, secs * 0.4))


# --- short effects -----------------------------------------------------------------------------

def footstep_grass(i):
    n = int(0.2 * SR)
    body = band(noise(n), 250, 2400) * expdec(n, 0.035)
    crunch = np.zeros(n)
    for _ in range(14):  # dry blades snapping
        k = int(rng.uniform(0, 0.09) * SR)
        crunch[k] += rng.uniform(0.4, 1.0)
    crunch = band(crunch, 2500, 7500) * expdec(n, 0.05)
    x = body * 0.8 + crunch * 1.6
    return normalize(x * fade(n, 0.004), 0.5 + 0.06 * i)


def footstep_wood(i):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f0 = rng.uniform(105, 140)
    thump = np.sin(2 * np.pi * f0 * t) * expdec(n, 0.045)
    knock = band(noise(n), 700, 2600) * expdec(n, 0.012)
    ring = np.sin(2 * np.pi * rng.uniform(380, 460) * t) * expdec(n, 0.03) * 0.25
    return normalize((thump + knock * 0.9 + ring) * fade(n, 0.002), 0.55)


def needle_click(i):
    n = int(0.09 * SR)
    x = np.zeros(n)
    for k, a in [(0, 1.0), (int(rng.uniform(0.012, 0.022) * SR), 0.55)]:  # tip, then the slide
        imp = np.zeros(n)
        imp[k] = a
        f = rng.uniform(2300, 3300)
        x += band(imp, f * 0.92, f * 1.08, order=2) * 40
    x += band(noise(n), 3000, 9000) * expdec(n, 0.004) * 0.15
    return normalize(x * expdec(n, 0.025), 0.35)


def ui_click():
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    f = 520 * np.exp(-t * 18) + 260
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * expdec(n, 0.018)
    x += band(noise(n), 1500, 5000) * expdec(n, 0.003) * 0.3
    return normalize(x, 0.4)


def ui_open():
    x = pluck(74, 0.5, 0.3) * 0.7
    hi = pluck(81, 0.42, 0.3) * 0.5
    s = int(0.05 * SR)
    x[s:s + len(hi)] += hi[: len(x) - s]
    return normalize(reverb(x, 0.7, 0.2)[: int(0.7 * SR)], 0.35)


def journal_chime():
    x = np.zeros(int(1.2 * SR))
    for k, m in enumerate([69, 74, 78]):
        p = pluck(m, 0.9, 0.25)
        s = int(k * 0.09 * SR)
        x[s:s + len(p)] += p
    return normalize(reverb(x, 1.2, 0.3)[: int(1.6 * SR)], 0.4)


# --- ambience loops ----------------------------------------------------------------------------

def wind(secs, level=1.0, low=420):
    n = int(secs * SR)
    t = np.arange(n) / SR
    gust = 0.55 + 0.25 * np.sin(2 * np.pi * 0.071 * t + 1.3) + 0.2 * np.sin(2 * np.pi * 0.133 * t)
    w = band(noise(n, 2), hi=low, order=2) * gust[:, None]
    leaves = band(noise(n, 2), 2200, 6500) * (np.clip(gust - 0.6, 0, 1) ** 2)[:, None] * 0.6
    return (w * 1.6 + leaves) * level


def bird_phrase():
    """2-5 quick rising-falling chirps, like a small songbird."""
    out = []
    base = rng.uniform(2600, 4200)
    for _ in range(int(rng.integers(2, 6))):
        d = rng.uniform(0.05, 0.11)
        n = int(d * SR)
        t = np.arange(n) / SR
        sweep = base * (1 + rng.uniform(0.2, 0.5) * np.sin(np.pi * t / d)) * (1 + 0.03 * np.sin(2 * np.pi * 38 * t))
        out.append(np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.sin(np.pi * t / d) ** 2)
        out.append(np.zeros(int(rng.uniform(0.03, 0.09) * SR)))
    return np.concatenate(out)


def ambience_day(secs=40):
    x = wind(secs + 2, 0.45)
    for _ in range(16):
        b = bird_phrase() * rng.uniform(0.12, 0.3)
        s = int(rng.uniform(0, secs) * SR)
        b = stereo(b, rng.uniform(-0.8, 0.8))
        e = min(len(x), s + len(b))
        x[s:e] += b[: e - s]
    return normalize(crossfade_loop(x, secs), 0.5)


def ambience_night(secs=40):
    x = wind(secs + 2, 0.35, 300)
    n = len(x)
    t = np.arange(n) / SR
    for f, rate, pan, ph in [(4400, 0.55, -0.5, 0.0), (4750, 0.63, 0.6, 0.21), (4100, 0.71, 0.1, 0.4)]:
        # a cricket: bursts of 3-4 pulses, repeating every `rate` seconds
        cyc = ((t + ph) % rate) / rate
        pulses = (np.sin(2 * np.pi * 32 * t) > 0.2) * (cyc < 0.12)
        env = band(pulses.astype(float), hi=300)
        c = np.sin(2 * np.pi * f * t) * env * 0.12
        x += stereo(c, pan)
    return normalize(crossfade_loop(x, secs), 0.45)


def rain(secs=24):
    n = int((secs + 2) * SR)
    hiss = band(noise(n, 2), 400, 6000) * 0.5
    drops = np.zeros((n, 2))
    for _ in range(int(secs * 70)):
        k = int(rng.uniform(0, n - 2000))
        c = int(rng.integers(0, 2))
        drops[k, c] += rng.uniform(0.3, 1.0)
    drops = band(drops, 1200, 5000) * 3.0
    patter = band(noise(n, 2), 150, 600) * 0.25
    return normalize(crossfade_loop(hiss + drops + patter, secs), 0.5)


# --- music -------------------------------------------------------------------------------------

CHORDS = {  # root, fifth, octave, high third (MIDI)
    "D": [50, 57, 62, 66], "Bm": [47, 54, 59, 62], "G": [43, 50, 55, 59],
    "A": [45, 52, 57, 61], "Em": [40, 47, 52, 55],
}
PROG = ["D", "Bm", "G", "A"] * 2 + ["G", "D", "Em", "A"] * 2 + ["D", "Bm", "G", "A"] * 3

# melody: bar (1-based) -> [(beat, midi, beats)]
A1 = [[(0, 69, 1), (1, 74, 1), (2, 76, 1), (3, 78, 1)],
      [(0, 78, 2), (2, 76, 1), (3, 74, 1)],
      [(0, 71, 1.5), (1.5, 74, 0.5), (2, 76, 2)],
      [(0, 73, 1), (1, 69, 3)]]
B = [[(0, 74, 1), (1, 79, 2), (3, 78, 1)],
     [(0, 76, 1), (1, 74, 1), (2, 69, 2)],
     [(0, 71, 1), (1, 76, 1), (2, 79, 1), (3, 78, 1)],
     [(0, 76, 3), (3, 73, 1)],
     [(0, 74, 1), (1, 71, 1), (2, 74, 1), (3, 79, 1)],
     [(0, 78, 2), (2, 81, 2)],
     [(0, 79, 1), (1, 78, 1), (2, 76, 2)],
     [(0, 76, 1), (1, 73, 1), (2, 69, 2)]]
A2 = [[(0, 69, 1), (1, 74, 1), (2, 78, 1), (3, 81, 1)],
      [(0, 83, 2), (2, 81, 1), (3, 78, 1)],
      [(0, 79, 1), (1, 78, 1), (2, 76, 1), (3, 74, 1)],
      [(0, 76, 2), (2, 73, 2)]]
OUTRO = [[(0, 74, 4)], [], [(0, 71, 2), (2, 74, 2)], [(0, 73, 2), (2, 69, 2)]]
MELODY = {}
for i, bar in enumerate(A1 + B + A1 + A2 + OUTRO):
    MELODY[5 + i] = bar


def music(bpm=84):
    beat = 60.0 / bpm
    bars = len(PROG)
    length = bars * 4 * beat
    n = int((length + 4) * SR)
    gtr = np.zeros(n)
    mel = np.zeros(n)
    pad = np.zeros(n)
    for b, ch in enumerate(PROG):
        tones = CHORDS[ch]
        t0 = b * 4 * beat
        for k, idx in enumerate([0, 1, 2, 1, 3, 1, 2, 1]):  # a fingerpicked arpeggio in eighths
            s = int((t0 + k * beat / 2 + rng.normal(0, 0.006)) * SR)
            p = pluck(tones[idx] + (12 if idx else 0), 1.6, 0.35 if idx else 0.25) * (0.9 if idx == 0 else 0.55)
            gtr[s:s + len(p)] += p
        # a very soft held pad under it
        s = int(t0 * SR)
        m = int(4 * beat * SR)
        tt = np.arange(m) / SR
        chord = sum(np.sin(2 * np.pi * mtof(x + 12) * tt) for x in tones[1:]) * fade(m, 0.8, 0.8)
        pad[s:s + m] += chord * 0.05
        for (bt, midi, dur) in MELODY.get(b + 1, []):
            s = int((t0 + bt * beat) * SR)
            f = flute(midi, dur * beat * 0.98)
            mel[s:s + len(f)] += f * 0.32
    mix = stereo(gtr, -0.25) + stereo(mel, 0.3) + stereo(pad, 0.0)
    mix = reverb(mix, 2.2, 0.28)
    return normalize(fold_loop(mix, length), 0.7)


# --- the arrival: Nora sees the Maple Grove sign, the rain stops ----------------------------------
# Alex, 2026-11-12: "the rain stops and we hear a pleasant music like she had just found heaven".
# Not a loop: a soft swell, harp arpeggios climbing, a warm flute line, and a long held last chord.
ARR_CHORDS = [[50, 57, 62, 66], [43, 50, 55, 59], [47, 54, 59, 62], [45, 52, 57, 61],
              [43, 50, 55, 59], [50, 57, 62, 66], [45, 52, 57, 64], [50, 57, 62, 66]]
ARR_MELODY = {2: [(0, 74, 2), (2, 76, 1), (3, 78, 1)], 3: [(0, 79, 3), (3, 78, 1)],
              4: [(0, 76, 2), (2, 73, 2)], 5: [(0, 74, 1), (1, 76, 1), (2, 79, 2)],
              6: [(0, 81, 2), (2, 78, 2)], 7: [(0, 76, 2), (2, 73, 1), (3, 76, 1)], 8: [(0, 74, 4)]}


def arrival(bpm=66):
    beat = 60.0 / bpm
    bars = len(ARR_CHORDS)
    tail = 6.0
    n = int((bars * 4 * beat + tail) * SR)
    harp = np.zeros(n)
    mel = np.zeros(n)
    pad = np.zeros(n)
    for b, tones in enumerate(ARR_CHORDS):
        t0 = b * 4 * beat
        last = b == bars - 1
        # harp: a climbing arpeggio across two octaves, every bar (the last one rolled and left ringing)
        notes = [tones[0], tones[1], tones[2], tones[3], tones[1] + 12, tones[2] + 12, tones[3] + 12, tones[2] + 24]
        for k, m in enumerate(notes):
            s = int((t0 + k * (beat / 2 if not last else 0.09) + rng.normal(0, 0.004)) * SR)
            p = pluck(m + 12, 3.0 if not last else 6.0, 0.55, 0.998) * (0.5 if k else 0.7)
            harp[s:s + len(p)] += p[:max(0, n - s)]
        # a pad that swells in from nothing over the first two bars, like the clouds parting
        s = int(t0 * SR)
        m = int((4 * beat + (tail if last else 0.0)) * SR)
        tt = np.arange(m) / SR
        chord = sum(np.sin(2 * np.pi * mtof(x + 12) * tt) + 0.3 * np.sin(2 * np.pi * mtof(x + 24) * tt * 1.002) for x in tones)
        swell = np.clip((t0 + tt) / (8 * beat), 0, 1) ** 1.5
        pad[s:s + m] += chord * fade(m, 0.6, 1.5 if last else 0.6) * swell * 0.035
        for (bt, midi, dur) in ARR_MELODY.get(b + 1, []):
            s = int((t0 + bt * beat) * SR)
            f = flute(midi, dur * beat * (0.98 if not last else 1.6))
            mel[s:s + len(f)] += f[:max(0, n - s)] * 0.3
    mix = stereo(harp, -0.2) + stereo(mel, 0.25) + stereo(pad, 0.0)
    mix = reverb(mix, 2.8, 0.35)
    return normalize(mix * fade(len(mix), 0.01, 3.0)[:, None], 0.7)


if __name__ == "__main__":
    print("writing to", OUT)
    for i in range(4):
        write_wav("step_grass_%d" % (i + 1), footstep_grass(i))
        write_wav("step_wood_%d" % (i + 1), footstep_wood(i))
    for i in range(3):
        write_wav("needle_%d" % (i + 1), needle_click(i))
    write_wav("ui_click", ui_click())
    write_wav("ui_open", ui_open())
    write_wav("journal", journal_chime())
    write_ogg("amb_day", ambience_day(), 4)
    write_ogg("amb_night", ambience_night(), 4)
    write_ogg("amb_rain", rain(), 4)
    write_ogg("music_cast_on", music(), 6)
    write_ogg("music_arrival", arrival(), 6)
