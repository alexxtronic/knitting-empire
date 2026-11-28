"""The characters' mumble voices: five short CC0 syllables by dodrio on Freesound ("dialogue_mumble",
sounds 554017 to 554023), trimmed, faded and evened out into assets/audio/voice/mumble_N.wav.

The game (scripts/audio.gd, speak()) strings a few of them together for each line, pitched and paced
per character from data/voices.json. Credits: assets/audio/voice/CREDITS.md.

    uv run --no-project --with numpy python tools/make_voice.py "$PWD" <folder with the five mp3s>

The folder holds Freesound's previews (or the original OGGs) named hah, heh, huh, huuh and haeh.
"""
import os
import subprocess
import sys

import numpy as np

ROOT, SRC = sys.argv[1], sys.argv[2]
OUT = os.path.join(ROOT, "assets", "audio", "voice")
SR = 44100
NAMES = ["hah", "heh", "huh", "huuh", "haeh"]
os.makedirs(OUT, exist_ok=True)


def find(name):
    for ext in (".ogg", ".wav", ".flac", ".mp3"):
        p = os.path.join(SRC, name + ext)
        if os.path.exists(p):
            return p
    raise SystemExit("missing " + name)


for i, name in enumerate(NAMES, 1):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", find(name), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    loud = np.where(np.abs(a) > 0.02 * np.abs(a).max())[0]  # trim the silence round it
    a = a[max(0, loud[0] - 60): loud[-1] + 200]
    a -= a.mean()
    fin, fout = int(0.004 * SR), int(0.03 * SR)  # no click at either end
    a[:fin] *= np.linspace(0.0, 1.0, fin)
    a[-fout:] *= np.linspace(1.0, 0.0, fout)
    rms = np.sqrt(np.mean(a ** 2))
    a *= 0.18 / max(rms, 1e-6)  # the same loudness each, then kept under the peak
    a *= min(1.0, 0.85 / np.abs(a).max())
    out = os.path.join(OUT, "mumble_%d.wav" % i)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f64le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "pcm_s16le", out], input=a.tobytes(), check=True)
    print("VOICE %s <- %s  %.2f s" % (os.path.basename(out), name, len(a) / SR))
