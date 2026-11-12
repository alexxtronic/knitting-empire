"""Turns a song into a note chart for the knitting game (scripts/knit_game.gd).

It listens to the audio: finds the beats and where the notes start, picks which of them to ask the
player for (more of them the harder the difficulty), puts each in one of four lanes by how bright it
sounds (low sounds on the left, bright ones on the right), and makes a note into a hold where the
sound rings on. The chart is written to data/songs/<id>.json, in seconds from the start of the audio.

  uv run --no-project --with librosa --with numpy --with scipy --with soundfile \\
      python tools/make_chart.py <audio file> <id> "<Song name>" <difficulty 1-4> [--seed N] [--bpm N]

Difficulty 1 is on the beat only, a few holds; 4 is sixteenths, doubles and long runs. Run it again
with another --seed for a different chart of the same song. Copy the audio to
assets/audio/songs/<id>.<ext> first (the chart stores that path).
"""
import json
import os
import sys

import librosa
import numpy as np

args = [a for a in sys.argv[1:] if not a.startswith("--")]
audio_path, sid, name, diff = args[0], args[1], args[2], int(args[3])
opts = {}
for i, a in enumerate(sys.argv):
    if a.startswith("--") and i + 1 < len(sys.argv):
        opts[a[2:]] = sys.argv[i + 1]
SEED = int(opts.get("seed", 1))
rng = np.random.default_rng(SEED + diff * 100)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# difficulty: (subdivisions per beat, keep the strongest fraction of onsets, minimum gap in s,
#              chance a sustained note becomes a hold, chance of a double, approach time in s)
LEVELS = {
    1: dict(div=1, keep=0.55, gap=0.55, hold=0.5, double=0.0, approach=1.9),
    2: dict(div=2, keep=0.55, gap=0.34, hold=0.55, double=0.0, approach=1.7),
    3: dict(div=2, keep=0.75, gap=0.22, hold=0.5, double=0.06, approach=1.45),
    4: dict(div=4, keep=0.8, gap=0.15, hold=0.4, double=0.12, approach=1.25),
}
L = LEVELS[diff]

y, sr = librosa.load(audio_path, sr=22050, mono=True)
length = len(y) / sr
hop = 256
env_on = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
tempo, beat_frames = librosa.beat.beat_track(onset_envelope=env_on, sr=sr, hop_length=hop, start_bpm=float(opts.get("bpm", 100)))
tempo = float(np.atleast_1d(tempo)[0])
beats = librosa.frames_to_time(beat_frames, sr=sr, hop_length=hop)
if len(beats) < 8:
    raise SystemExit("couldn't find a steady beat in %s" % audio_path)
frame_t = librosa.frames_to_time(np.arange(len(env_on)), sr=sr, hop_length=hop)

# the grid: every beat split into `div` equal slots, following the beats the song really has
grid = []
for a, b in zip(beats[:-1], beats[1:]):
    for k in range(L["div"]):
        grid.append(a + (b - a) * k / L["div"])
grid = np.array(grid)


def strength_at(t, win=0.045):
    i0 = np.searchsorted(frame_t, t - win)
    i1 = np.searchsorted(frame_t, t + win)
    return float(env_on[i0:max(i1, i0 + 1)].max()) if i0 < len(env_on) else 0.0


s = np.array([strength_at(t) for t in grid])
thr = np.quantile(s, 1.0 - L["keep"]) if L["keep"] < 1 else 0.0
cand = [(t, st) for t, st in zip(grid, s) if st >= thr and t >= 1.4 and t <= length - 1.5]

# keep the strongest first, with a minimum gap, then put back in time order
chosen = []
for t, st in sorted(cand, key=lambda x: -x[1]):
    if all(abs(t - u) >= L["gap"] for u, _ in chosen):
        chosen.append((t, st))
chosen.sort()

# how bright each moment sounds -> lane
cent = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop)[0]
rms = librosa.feature.rms(y=y, hop_length=hop)[0]


def at(arr, t):
    return float(arr[min(len(arr) - 1, int(t * sr / hop))])


cents = np.array([at(cent, t + 0.02) for t, _ in chosen])
edges = np.quantile(cents, [0.25, 0.5, 0.75])
notes = []
last_lane, run = -1, 0
for (t, st), c in zip(chosen, cents):
    lane = int(np.searchsorted(edges, c))
    if lane == last_lane:
        run += 1
        if run >= 2:  # no more than two in a row in one lane
            lane = int(np.clip(lane + rng.choice([-1, 1]), 0, 3))
            run = 0
    else:
        run = 0
    if last_lane >= 0 and abs(lane - last_lane) == 3 and L["gap"] < 0.3:
        lane = last_lane + int(np.sign(lane - last_lane)) * 2  # don't jump the whole width at speed
    lane = int(np.clip(lane, 0, 3))
    # a hold where the sound keeps ringing until the next chosen onset
    hold = 0.0
    nxt = next((u for u, _ in chosen if u > t + 0.05), length)
    room = nxt - t - 0.12
    if room >= 0.7 and rng.random() < L["hold"]:
        i0, i1 = int((t + 0.1) * sr / hop), int((t + room) * sr / hop)
        if i1 > i0 and rms[i0:i1].mean() > 0.45 * rms[max(0, i0 - 2):i0 + 2].max():
            hold = round(min(room, 2.4), 3)
    notes.append([round(float(t), 3), lane, hold])
    last_lane = lane
    if hold == 0.0 and rng.random() < L["double"] and st > np.quantile(s, 0.9):
        notes.append([round(float(t), 3), (lane + 2) % 4, 0.0])  # a double: the other hand
notes.sort(key=lambda n: (n[0], n[1]))

out = {
    "id": sid, "name": name, "difficulty": diff, "bpm": round(tempo, 1), "length": round(length, 2),
    "audio": "res://assets/audio/songs/" + os.path.basename(audio_path),
    "approach": L["approach"], "chart_seed": SEED, "notes": notes,
}
os.makedirs(os.path.join(ROOT, "data", "songs"), exist_ok=True)
path = os.path.join(ROOT, "data", "songs", sid + ".json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(out, f, separators=(",", ":"))
holds = sum(1 for n in notes if n[2] > 0)
print("%s: %.0f BPM, %.0f s, %d notes (%d holds), lanes %s -> %s" % (
    sid, tempo, length, len(notes), holds, np.bincount([n[1] for n in notes], minlength=4).tolist(), path))
