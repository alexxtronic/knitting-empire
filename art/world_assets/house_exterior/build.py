"""The outside of Nora's house (and Rosewood Cottage): lime plaster laid on with a trowel, the oak
of its timber frame, and the fieldstone of its footing and the flags round it. Each is one tiling
colour map and a normal map, drawn here from noise and strokes (no photographs, nothing to
license), which scripts/house_skin.gd projects onto the house's boxes from three sides.

    uv run --no-project --with numpy --with pillow python art/world_assets/house_exterior/build.py

Writes tex/<kind>.png and <kind>_n.png (and timber_h, the oak with its grain across, and shingles_r, the shingles for the far slope) and a review sheet (review/sheet.png), and copies the maps
to assets/textures/house/. Then import (see AGENTS.md).

Every map tiles both ways: the noise is made in frequency space (so it wraps), and every stroke,
crack and stone is drawn with wrapped coordinates.
"""
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TEX = os.path.join(HERE, "tex")
GAME = os.path.join(ROOT, "assets", "textures", "house")

# metres one tile covers (scripts/house_skin.gd scales by these) and its size in pixels
SIZES = {"plaster": (2.0, 1024), "timber": (1.0, 512), "stone": (2.0, 1024), "shingles": (1.0, 512), "boards": (2.0, 1024), "tiles": (1.0, 512), "brick": (2.0, 1024), "paintwood": (1.0, 512)}


def C(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def noise(rng, n, freq, aspect=(1.0, 1.0)):
    """Tiling smooth noise, mean 0 and spread 1: white noise kept below `freq` cycles a tile
    (across x / aspect[0] and y / aspect[1], so (4, 0.2) streaks it along y)."""
    w = rng.standard_normal((n, n))
    k = np.fft.fftfreq(n) * n
    ky, kx = k[:, None] * aspect[1], k[None, :] * aspect[0]
    f = np.fft.fft2(w) * np.exp(-(kx * kx + ky * ky) / (freq * freq))
    out = np.real(np.fft.ifft2(f))
    return (out - out.mean()) / (out.std() + 1e-9)


def fbm(rng, n, base, octaves=4, gain=0.5, aspect=(1.0, 1.0)):
    out, amp, tot = np.zeros((n, n)), 1.0, 0.0
    for o in range(octaves):
        out += amp * noise(rng, n, base * 2 ** o, aspect)
        tot += amp
        amp *= gain
    return out / tot


def step(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def normal_from_height(h, strength):
    """Tangent-space normal map (OpenGL, +Y up, as Godot reads it), from a tiling height map."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, 1, axis=0) - np.roll(h, -1, axis=0)) * strength
    n = np.dstack([-dx, -dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def window(n, cx, cy, r):
    """Wrapped pixel indices of a square of half-size r round (cx, cy), and the offsets to it."""
    xs = np.arange(int(cx - r), int(cx + r) + 1)
    ys = np.arange(int(cy - r), int(cy + r) + 1)
    return ys % n, xs % n, (xs - cx)[None, :], (ys - cy)[:, None]


def crack(rng, h, rgb, n, length, col, depth, width=0.9):
    """A hairline crack: a wandering line `length` px long, darkened into rgb and cut into h."""
    x, y = rng.uniform(0, n), rng.uniform(0, n)
    a = rng.uniform(0, 2 * math.pi)
    for i in range(int(length)):
        a += rng.normal(0, 0.25)
        x, y = x + math.cos(a), y + math.sin(a)
        fade = math.sin(math.pi * i / length) # thin at both ends
        yi, xi, dx, dy = window(n, x, y, 2)
        d = np.sqrt(dx * dx + dy * dy)
        m = np.clip(1.0 - d / (width * (0.4 + 0.6 * fade)), 0, 1) * fade
        sub = rgb[np.ix_(yi, xi)]
        rgb[np.ix_(yi, xi)] = sub + (col - sub) * m[..., None] * 0.8
        h[np.ix_(yi, xi)] -= depth * m


def plaster():
    """Lime plaster over wattle, laid on by hand: overlapping trowel swipes, each a smooth sweep
    with a soft ridge where the blade's edge lifted, over a gently lumpy coat; warm and cool
    patches where the limewash took differently, sand in it, and a few hairline cracks."""
    size, n = SIZES["plaster"]
    rng = np.random.default_rng(31)
    px = n / size
    h = 0.5 * fbm(rng, n, 3, 3) # the lumps of the daub under it
    polish = np.zeros((n, n))
    for _ in range(260):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        L = rng.uniform(0.24, 0.5) * px
        W = rng.uniform(0.11, 0.2) * px
        ang = rng.uniform(0, math.pi) if rng.random() < 0.35 else rng.normal(0.25, 0.5) # most swipes run one way, as a right hand does
        bend = rng.uniform(-1.6, 1.6) / L
        yi, xi, dx, dy = window(n, cx, cy, L * 0.6 + W)
        u = dx * math.cos(ang) + dy * math.sin(ang)
        v = -dx * math.sin(ang) + dy * math.cos(ang) - bend * u * u
        inside = (1 - step(L * 0.35, L * 0.5, np.abs(u))) * (1 - step(W * 0.38, W * 0.5, np.abs(v)))
        lead = np.exp(-((v - W * 0.46) / (W * 0.09)) ** 2) * (1 - step(L * 0.3, L * 0.5, np.abs(u))) # the ridge left at the blade's edge
        flat = 0.3 * (v / W) + 0.05 * rng.standard_normal()
        sub = h[np.ix_(yi, xi)]
        h[np.ix_(yi, xi)] = sub + (flat - sub) * inside * 0.85 + 0.22 * lead
        polish[np.ix_(yi, xi)] = np.maximum(polish[np.ix_(yi, xi)] * (1 - inside), inside * rng.uniform(0.3, 1.0))
    sand = noise(rng, n, 300)
    pits = np.clip(noise(rng, n, 180) - 2.6, 0, None) # a few tiny holes where a grit came out
    h = h + 0.05 * sand - 0.8 * pits

    base, warm, cool = C("#e8d7b6"), C("#ebd2aa"), C("#e2d8c2")
    m1, m2 = fbm(rng, n, 2.5, 3), fbm(rng, n, 9, 2)
    rgb = base + (warm - base) * np.clip(m1, 0, 2)[..., None] * 0.4 + (cool - base) * np.clip(-m1, 0, 2)[..., None] * 0.35
    rgb = rgb * (1 + 0.02 * m2)[..., None]
    rgb = rgb * (1 + 0.04 * (polish - 0.5))[..., None] # smoothed plaster is a touch brighter
    ridge = np.clip(h - np.roll(h, 2, axis=0) * 0.5 - np.roll(h, -2, axis=0) * 0.5, -0.4, 0.4)
    rgb = rgb * (1 - 0.18 * np.clip(-ridge, 0, None) - 0.03 * sand)[..., None] # dust settles in the hollows
    rgb = rgb * (1 - 0.45 * np.clip(pits, 0, 0.5))[..., None]
    for _ in range(7):
        crack(rng, h, rgb, n, rng.uniform(40, 160), C("#a8957a"), 0.25)
    return np.clip(rgb, 0, 1), h, 2.6


def timber():
    """The house's frame: dark, hand-hewn oak with its grain running along the beam (down the
    image), slow wandering rings, hewing marks across it, and drying checks along the grain."""
    size, n = SIZES["timber"]
    rng = np.random.default_rng(52)
    px = n / size
    warp = fbm(rng, n, 2.0, 2, aspect=(1.0, 2.5))
    streak = fbm(rng, n, 40, 3, aspect=(0.5, 12.0)) # fine fibres along the beam
    x = np.arange(n)[None, :] / n * np.ones((n, 1))
    t = x * 26 + 0.9 * warp # rings cut along the beam's face
    f = t - np.floor(t)
    late = f ** 2.4
    hew = fbm(rng, n, 3.0, 2, aspect=(4.0, 0.5)) # broad shallow facets across the beam from the adze
    figure = fbm(rng, n, 4, 2)
    dark, mid, light = C("#3f2716"), C("#5a3820"), C("#7a5130")
    v = 0.45 + 0.45 * (late - 0.5) + 0.2 * streak + 0.07 * figure + 0.08 * hew
    rgb = np.where(v[..., None] < 0.5, dark + (mid - dark) * np.clip(v / 0.5, 0, 1)[..., None],
        mid + (light - mid) * np.clip((v - 0.5) / 0.5, 0, 1)[..., None])
    h = 0.3 * (1 - late) + 0.3 * streak + 0.9 * hew
    # drying checks: dark splits running with the grain, wandering a little
    for _ in range(6):
        x0, y0 = rng.uniform(0, n), rng.uniform(0, n)
        L = rng.uniform(0.2, 0.7) * px
        for i in range(int(L)):
            fade = math.sin(math.pi * i / L)
            yi, xi, dx, dy = window(n, x0 + 2.5 * math.sin(i / 37.0) + 0.6 * warp[int(y0 + i) % n, int(x0) % n], y0 + i, 2)
            d = np.abs(dx) + 0 * dy
            m = np.clip(1.0 - d / (1.3 * fade + 0.2), 0, 1) * fade
            sub = rgb[np.ix_(yi, xi)]
            rgb[np.ix_(yi, xi)] = sub + (C("#22140b") - sub) * m[..., None] * 0.85
            h[np.ix_(yi, xi)] -= 0.6 * m
    return np.clip(rgb, 0, 1), h, 2.0


def stone():
    """Fieldstone footing: rounded stones in rough courses, wider than tall, each its own grey or
    warm buff, bedded in pale lime mortar that sits back from their faces."""
    size, n = SIZES["stone"]
    rng = np.random.default_rng(73)
    rows, cols = 9, 6 # courses about 0.18 m, stones about 0.29 m long
    seeds = []
    for r in range(rows):
        shift = rng.uniform(0, 1)
        for c in range(cols):
            seeds.append(((c + shift + rng.uniform(-0.25, 0.25)) / cols % 1.0, (r + 0.5 + rng.uniform(-0.18, 0.18)) / rows))
    seeds = np.array(seeds)
    pal = [C("#918c82"), C("#6b665e"), C("#9a8f7c"), C("#80786b"), C("#a39a8a"), C("#76716a")]
    tints = np.array([pal[rng.integers(len(pal))] * rng.uniform(0.9, 1.08) for _ in seeds])
    ys, xs = np.mgrid[0:n, 0:n] / n
    f1 = np.full((n, n), 9.0)
    f2 = np.full((n, n), 9.0)
    owner = np.zeros((n, n), int)
    for i, (sx, sy) in enumerate(seeds):
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                # measured in stones: x in stone lengths, y in course heights, so cells come out wider than tall
                d = np.sqrt(((xs - sx - ox) * cols) ** 2 + ((ys - sy - oy) * rows) ** 2)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                owner = np.where(closer, i, owner)
                f1 = np.where(closer, d, f1)
    edge = (f2 - f1) * 0.5 * n / rows # about px to the mortar line
    wob = fbm(rng, n, 24, 3)
    e = edge + 3.0 * wob
    face = step(2.0, 14.0, e) # 0 in the mortar, 1 on the stone's crown
    mortar = 1 - step(1.5, 3.5, e)
    grain = fbm(rng, n, 60, 3)
    spots = np.clip(noise(rng, n, 90) - 1.8, 0, 1) # lichen and darker flecks
    rgb = tints[owner] * (1 + 0.08 * grain + 0.06 * fbm(rng, n, 8, 2))[..., None]
    rgb = rgb * (0.82 + 0.18 * face)[..., None] # the stone's rounded shoulders in shade
    rgb = rgb + (C("#9aa06a") - rgb) * (spots * 0.5)[..., None]
    mcol = C("#bdb19a") * (1 + 0.06 * grain)[..., None]
    rgb = rgb + (mcol - rgb) * mortar[..., None]
    h = 0.9 * np.sqrt(np.clip(face, 0, 1)) + 0.12 * grain - 0.25 * mortar
    return np.clip(rgb, 0, 1), h, 3.2


def shingles():
    """Cedar shingles stained the roof's red-brown: courses 0.25 m apart, each shingle its own
    width and shade, thin under the course above and thick at its butt, which throws a shadow
    line on the course below; gaps between them, grain down the slope, a little moss. Drawn with
    the courses across the image (butts at the bottom of each); main() turns it for the roof."""
    size, n = SIZES["shingles"]
    rng = np.random.default_rng(91)
    px = n / size
    rows = 4
    R = n // rows
    rgb = np.zeros((n, n, 3))
    h = np.zeros((n, n))
    grain = fbm(rng, n, 50, 3, aspect=(1.0, 0.08)) # streaks down the slope (down the image)
    blot = fbm(rng, n, 6, 2)
    pal = [C("#6b3529"), C("#7a3d2c"), C("#5e2e24"), C("#834633"), C("#6a3a2e"), C("#734030")]
    ys = np.arange(n)
    for r in range(rows):
        y0 = r * R
        x = rng.uniform(0, 0.1) * px
        while x < n + 0.1 * px:
            w = rng.uniform(0.11, 0.3) * px
            if x + w > n and x < n: # the course's last shingle ends where the first began
                w = n - x
            col = pal[rng.integers(len(pal))] * rng.uniform(0.88, 1.1)
            butt = R - rng.uniform(0, 4) # a ragged lower edge
            x0, x1 = int(x), int(x + w)
            xs = np.arange(x0, x1) % n
            for xi in xs:
                t = (ys[y0:y0 + R] - y0) / butt
                inside = t <= 1.0
                rgb[y0:y0 + R, xi][inside] = col
                h[y0:y0 + R, xi] = np.where(inside, 0.15 + 0.85 * np.clip(t, 0, 1), 0.0)
            # the gap at its edge
            rgb[y0:y0 + R, x0 % n] *= 0.45
            h[y0:y0 + R, x0 % n] -= 0.3
            x += w
    # the shadow each butt throws on the course below
    rowpos = (ys % R) / R
    shade = 1.0 - 0.45 * np.exp(-rowpos / 0.06)
    rgb = rgb * shade[:, None, None]
    rgb = rgb * (1 + 0.12 * grain + 0.05 * blot)[..., None]
    moss = np.clip(noise(rng, n, 25) * 0.6 + fbm(rng, n, 4, 2) - 1.4, 0, 1) * (rowpos[:, None] < 0.35)
    rgb = rgb + (C("#6d7a3c") - rgb) * (moss * 0.55)[..., None]
    h = h + 0.08 * grain
    return np.clip(rgb, 0, 1), h, 3.0


def boards():
    """Board siding for the town's buildings and the barn: upright boards of uneven width, each its
    own cut of grain and shade, with a dark gap and a bevel between them and the odd knot. A
    middling brown, so a building's own colour can be laid over it (scripts/building_skin.gd)."""
    size, n = SIZES["boards"]
    rng = np.random.default_rng(17)
    px = n / size
    grain = fbm(rng, n, 50, 3, aspect=(0.5, 12.0))
    rings = fbm(rng, n, 2.0, 2, aspect=(1.0, 2.5))
    blot = fbm(rng, n, 5, 2)
    xs = np.arange(n)
    rgb = np.zeros((n, n, 3))
    h = np.zeros((n, n))
    x = 0.0
    edges = []
    while x < n - 0.1 * px:
        w = rng.uniform(0.16, 0.26) * px
        if n - (x + w) < 0.12 * px:
            w = n - x
        edges.append((x, x + w))
        x += w
    light, dark = C("#a77c55"), C("#6e4a2e")
    for x0, x1 in edges:
        cols = slice(int(x0), int(x1))
        local = (xs[cols] - x0) / (x1 - x0)
        t = local[None, :] * rng.uniform(6, 12) + 0.8 * rings[:, cols] + rng.uniform(0, 1)
        late = (t - np.floor(t)) ** 2.4
        v = 0.45 + 0.35 * (late - 0.5) + 0.2 * grain[:, cols] + 0.06 * blot[:, cols] + rng.uniform(-0.15, 0.15)
        rgb[:, cols] = light + (dark - light) * np.clip(v, 0, 1)[..., None]
        e = np.minimum(xs[cols] - x0, x1 - xs[cols])[None, :] * np.ones((n, 1))
        h[:, cols] = step(0.0, 10.0, e) + 0.2 * (1 - late) + 0.2 * grain[:, cols]
        rgb[:, cols] *= (0.3 + 0.7 * step(1.5, 7.0, e))[..., None] # the dark gap and its bevel
        for _ in range(rng.integers(0, 3)): # knots
            ky, kx, kr = rng.uniform(0, n), rng.uniform(x0 + 8, max(x0 + 9, x1 - 8)), rng.uniform(4, 9)
            yy, xx = np.mgrid[0:n, int(x0):int(x1)]
            d = np.sqrt(((xx - kx) * 1.0) ** 2 + (((yy - ky + n / 2) % n - n / 2) * 0.7) ** 2)
            m = np.clip(1.2 - d / kr, 0, 1)
            rgb[:, cols] = rgb[:, cols] * (1 - 0.5 * m[..., None])
            h[:, cols] -= 0.3 * m
    return np.clip(rgb, 0, 1), h, 2.2


def tiles():
    """Clay roof tiles for the town: plain tiles laid in courses, each course half a tile over from
    the last, every tile a little curved across, its corners rounded, its own shade; the course
    above throws a shadow on each, and there's lichen here and there. Light and neutral, so each
    roof keeps its own colour; the butts are at the bottom of each course (down the slope)."""
    size, n = SIZES["tiles"]
    rng = np.random.default_rng(23)
    px = n / size
    across, rows = 6, 6 # tiles about 0.17 m wide and 0.17 m showing
    tw, th = n / across, n / rows
    ys, xs = np.mgrid[0:n, 0:n].astype(float)
    row = (ys // th).astype(int)
    off = np.where(row % 2 == 1, tw / 2, 0.0)
    col = (((xs + off) // tw).astype(int)) % across
    u = ((xs + off) % tw) / tw # across the tile
    v = (ys % th) / th # down the tile, 1 at its butt
    shade = rng.uniform(0.82, 1.12, (rows, across))
    hue = rng.uniform(-0.04, 0.04, (rows, across))
    base = C("#c9b39f")
    s = shade[row, col]
    rgb = base * s[..., None] * (1 + hue[row, col][..., None] * np.array([1.0, 0.0, -1.0]))
    gap = 1 - step(0.02, 0.06, np.minimum(u, 1 - u)) # the joint between two tiles
    corner = np.sqrt(np.clip(0.18 - np.minimum(u, 1 - u), 0, 1) ** 2 + np.clip(v - 0.82, 0, 1) ** 2) > 0.16 # rounded lower corners
    curve = np.sin(np.pi * u) # a little curved across
    shadow = np.exp(-v / 0.12) # under the course above
    grit = fbm(rng, n, 80, 2)
    rgb = rgb * (1 - 0.5 * shadow - 0.08 * (1 - curve))[..., None] * (1 + 0.06 * grit)[..., None]
    rgb = np.where((gap > 0.5)[..., None] | corner[..., None], rgb * 0.45, rgb)
    lichen = np.clip(noise(rng, n, 30) * 0.7 + fbm(rng, n, 5, 2) - 1.5, 0, 1)
    rgb = rgb + (C("#a9a77a") - rgb) * (lichen * 0.5)[..., None]
    h = 0.6 * v + 0.25 * curve - 0.6 * gap - 0.6 * corner + 0.05 * grit
    return np.clip(rgb, 0, 1), h, 3.2


def brick():
    """Brick in running bond (0.215 by 0.065 m with 10 mm joints): each brick its own fired shade
    with darker ends, a slightly worn face, set in a pale recessed mortar."""
    size, n = SIZES["brick"]
    rng = np.random.default_rng(47)
    px = n / size
    bw, bh, mj = 0.225 * px, 0.075 * px, 0.01 * px
    across, rows = int(round(n / bw)), int(round(n / bh))
    bw, bh = n / across, n / rows
    ys, xs = np.mgrid[0:n, 0:n].astype(float)
    row = (ys // bh).astype(int)
    off = np.where(row % 2 == 1, bw / 2, 0.0)
    col = (((xs + off) // bw).astype(int)) % across
    u, v = (xs + off) % bw, ys % bh
    e = np.minimum(np.minimum(u, bw - u), np.minimum(v, bh - v))
    face = step(mj * 0.5, mj * 0.5 + 2.0, e)
    shade = rng.uniform(0.78, 1.15, (rows, across))
    pal = np.array([C("#a8553c"), C("#9a4a35"), C("#b8664a"), C("#8c4433"), C("#a0583f")])
    pick = rng.integers(0, len(pal), (rows, across))
    grit = fbm(rng, n, 90, 2)
    burn = np.clip(1 - np.minimum(u, bw - u) / (bw * 0.25), 0, 1) ** 2 # darker ends
    rgb = pal[pick[row, col]] * (shade[row, col] * (1 + 0.08 * grit) * (1 - 0.2 * burn))[..., None]
    mortar = C("#c4b8a4") * (1 + 0.05 * grit)[..., None]
    rgb = rgb + (mortar - rgb) * (1 - face)[..., None]
    h = 0.8 * face + 0.1 * grit
    return np.clip(rgb, 0, 1), h, 3.0


def paintwood():
    """Painted wood for window frames, trim and columns: a pale coat over grain that still shows
    through a little, with brush marks along it. Near white, so a frame's own colour tints it."""
    size, n = SIZES["paintwood"]
    rng = np.random.default_rng(61)
    grain = fbm(rng, n, 40, 3, aspect=(0.5, 12.0))
    brush = fbm(rng, n, 90, 2, aspect=(0.4, 20.0))
    rgb = C("#e9e4da") * (1 + 0.025 * grain + 0.015 * brush)[..., None]
    h = 0.25 * grain + 0.12 * brush
    return np.clip(rgb, 0, 1), h, 0.7


def save(name, rgb, nrm):
    for suffix, img in (("", rgb), ("_n", nrm)):
        path = os.path.join(TEX, name + suffix + ".png")
        Image.fromarray((img * 255 + 0.5).astype("uint8")).save(path)
        shutil.copyfile(path, os.path.join(GAME, name + suffix + ".png"))


def sheet(maps):
    """Each map tiled 2 x 2 (to show the seams don't), its normal map lit from the upper left."""
    tiles = []
    for name, (rgb, nrm) in maps.items():
        t = np.tile(rgb, (2, 2, 1))
        nv = nrm * 2 - 1
        light = np.clip(nv[..., 0] * -0.5 + nv[..., 1] * 0.5 + nv[..., 2] * 0.7, 0, 1)
        lit = np.tile(rgb * (0.35 + 0.75 * light)[..., None], (2, 2, 1))
        im = Image.fromarray((np.concatenate([t, lit], axis=1) * 255).astype("uint8")).resize((1024, 512))
        tiles.append(np.asarray(im))
    os.makedirs(os.path.join(HERE, "review"), exist_ok=True)
    Image.fromarray(np.concatenate(tiles, axis=0)).save(os.path.join(HERE, "review", "sheet.png"))


def main():
    os.makedirs(TEX, exist_ok=True)
    os.makedirs(GAME, exist_ok=True)
    want = sys.argv[1:] or list(SIZES)
    maps = {}
    for name in want:
        rgb, h, strength = globals()[name]()
        maps[name] = (rgb, normal_from_height(h, strength))
        save(name, *maps[name])
        if name == "timber": # the same oak turned a quarter, for the rails and lintels that lie flat
            save("timber_h", rgb.transpose(1, 0, 2), normal_from_height(h.T, strength))
        if name == "shingles": # turned so the courses run along the ridge and the butts face down
            # the slope (+x in each slope's space); shingles_r for the other slope, where down is -x
            t, th = rgb.transpose(1, 0, 2), h.T
            save("shingles", t, normal_from_height(th, strength))
            save("shingles_r", t[:, ::-1], normal_from_height(th[:, ::-1], strength))
            maps[name] = (t, normal_from_height(th, strength))
        print("wrote", name)
    sheet(maps)


if __name__ == "__main__":
    main()
