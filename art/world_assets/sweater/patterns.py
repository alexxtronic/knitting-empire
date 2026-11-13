"""The sweaters' knitted designs: each one a grid of stitches per part of the sweater (body, sleeve,
hem, collar, cuff), coloured from its own small palette, and the maps that draw every stitch as a knit V
(the body and sleeves, stockinette) or as knit-two purl-two rib (hem, collar, cuffs).

Plain numpy, so it runs in Blender (build.py) and outside it:

    uv run --no-project --with numpy --with pillow python art/world_assets/sweater/patterns.py OUT_DIR

writes a flat swatch of each design. Names and the rarity of each are drafts until Alex approves them.

Stars: 1 Common, 2 Rare, 3 Ultra Rare, 4 Legendary (Alex, 2026-11-13).
"""
import math

import numpy as np

RIB_KNIT = 2   # knit two, purl two


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def bitmap(rows, key):
    """A motif drawn as text, one string per row, top row first; `key` maps a character to a colour
    index (characters not in it are left alone, -1)."""
    h, w = len(rows), max(len(r) for r in rows)
    out = np.full((h, w), -1, dtype=int)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in key:
                out[y, x] = key[ch]
    return out


def stamp(grid, motif, x, y, wrap=True):
    """Puts `motif` (from bitmap) on `grid` with its top-left stitch at column x, row y (row 0 at the
    top). Columns wrap round the sweater; rows are clipped."""
    h, w = motif.shape
    H, W = grid.shape
    for j in range(h):
        yy = y + j
        if not 0 <= yy < H:
            continue
        for i in range(w):
            c = motif[j, i]
            if c < 0:
                continue
            xx = (x + i) % W if wrap else x + i
            if 0 <= xx < W:
                grid[yy, xx] = c


# --- the motifs ------------------------------------------------------------------------------------

SNOWFLAKE = [
    ".....x.....",
    "..x..x..x..",
    "...x.x.x...",
    "x...xxx...x",
    ".x..x.x..x.",
    "xxxxx.xxxxx",
    ".x..x.x..x.",
    "x...xxx...x",
    "...x.x.x...",
    "..x..x..x..",
    ".....x.....",
]
PEERIE = [            # a small four-row border, repeating every 6 stitches
    "..x...",
    ".x.x..",
    "x...x.",
    ".x.x..",
]
SHEEP = [
    "...wwwwww......",
    ".wwwwwwwwww....",
    "wwwwwwwwwwwwkk.",
    "wwwwwwwwwwwkkkk",
    "wwwwwwwwwwwkkk.",
    ".wwwwwwwwwwk...",
    "..wwwwwwwww....",
    "..k.k...k.k....",
    "..k.k...k.k....",
]
STAR5 = [
    "..x..",
    ".xxx.",
    "xxxxx",
    ".xxx.",
    "..x..",
]
STAR3 = [
    ".x.",
    "xxx",
    ".x.",
]
HEART = [
    ".xx.xx.",
    "xxxxxxx",
    "xxxxxxx",
    ".xxxxx.",
    "..xxx..",
    "...x...",
]


def moon(r, lit, light, dark):
    """A moon of radius r stitches: `lit` 0 (new: only a ring) .. 1 (full), lit from the right."""
    n = 2 * r + 1
    out = np.full((n, n), -1, dtype=int)
    for y in range(n):
        for x in range(n):
            dx, dy = x - r, y - r
            d = math.hypot(dx, dy)
            if d > r + 0.35:
                continue
            # the terminator: an ellipse across the disc, from the right limb (lit 0) to the left (1)
            half = math.sqrt(max(0.0, r * r - dy * dy))
            edge = half * (1.0 - 2.0 * lit)
            on = dx >= edge
            ring = d > r - 0.9
            out[y, x] = light if on else (dark if ring else -1)
    return out


# --- the sweaters --------------------------------------------------------------------------------

def _plain(parts, base):
    return {k: np.full(v, base, dtype=int) for k, v in parts.items()}


def cranberry(parts, marks):
    """The reference sweater: plain red stockinette, red ribs."""
    return _plain(parts, 0)


def oatmeal_stripe(parts, marks):
    """Oatmeal with pairs of chocolate stripes, the same down the sleeves; plain ribs."""
    g = _plain(parts, 0)
    for k in ("torso", "sleeve"):
        H = g[k].shape[0]
        for y in range(H):
            from_bottom = H - 1 - y
            if from_bottom % 10 in (4, 5) and from_bottom > 2:
                g[k][y, :] = 1
    return g


def snowfall_yoke(parts, marks):
    """Navy with a cream Fair Isle yoke: a band of snowflakes between peerie borders round the
    shoulders, red seeds between the flakes, and a peerie band above each cuff. Cream collar edge."""
    g = _plain(parts, 0)
    t = g["torso"]
    H, W = t.shape
    top = marks["yoke_top"] + 2               # just under the collar
    band = 11
    for x in range(W):
        for j, row in enumerate(PEERIE):
            if row[x % 6] == "x":
                t[top + j, x] = 1
                t[top + 4 + band + 3 + j, x] = 1
    flake = bitmap(SNOWFLAKE, {"x": 1})
    n = max(1, round(W / 16))
    for i in range(n):
        x = round(i * W / n + W / 2 - 5) % W     # one centred on the front
        stamp(t, flake, x, top + 6)
        stamp(t, bitmap(["x"], {"x": 2}), x + 13, top + 11)
    for k in range(W):
        if k % 4 == 0:
            t[top + 6 + band + 2, k] = 2
    s = g["sleeve"]
    Hs, Ws = s.shape
    for x in range(Ws):
        for j, row in enumerate(PEERIE):
            if row[x % 6] == "x":
                s[Hs - 10 + j, x] = 1
    s[: Hs - 0, :][Hs - 12, ::3] = 2
    g["collar"][-3:, :] = 1                    # the collar's top edge (it folds over there)
    return g


def flock(parts, marks):
    """Sage green with a flock of cream sheep (dark faces and legs) across the chest and a smaller
    line of them round the back, a scatter of cream daisies below, a sheep on each upper sleeve.
    Ribs in deep green."""
    g = _plain(parts, 0)
    t = g["torso"]
    H, W = t.shape
    sheep = bitmap(SHEEP, {"w": 1, "k": 2})
    row = marks["chest"] - 4
    n = max(1, round(W / 22))
    for i in range(n):
        x = round(i * W / n + W / 2 - 7) % W
        stamp(t, sheep, x, row + (i % 2) * 2)
    for y in (row - 4, row + 14):
        if 0 <= y < H:
            t[y, :] = 3
    rng = np.random.default_rng(5)
    for _ in range(int(W * H / 140)):
        y = int(rng.integers(row + 18, H - 2))
        x = int(rng.integers(0, W))
        stamp(t, bitmap(STAR3, {"x": 1}), x, y)
    s = g["sleeve"]
    Hs, Ws = s.shape
    stamp(s, sheep, Ws // 2 - 7, 14, wrap=True)
    for k in ("hem", "collar", "cuff"):
        g[k][:, :] = 3
    return g


def midnight_moon(parts, marks):
    """Indigo, scattered with gold stars, and across the chest the moon going round: eight phases from
    new to full and back, in cream with gold rings, between two gold lines. Gold-tipped ribs."""
    g = _plain(parts, 0)
    t = g["torso"]
    H, W = t.shape
    rng = np.random.default_rng(11)
    big, small = bitmap(STAR5, {"x": 1}), bitmap(STAR3, {"x": 1})
    for _ in range(int(W * H / 110)):
        y = int(rng.integers(0, H))
        x = int(rng.integers(0, W))
        stamp(t, small if rng.random() < 0.7 else big, x, y)
    cy = marks["chest"] + 8
    t[cy - 7: cy + 8, :] = 0
    t[cy - 7, :] = t[cy + 7, :] = 1
    n = 12
    for i in range(n):
        lit = 1.0 - abs((i + 0.5) / n * 2.0 - 1.0)
        m = moon(4, lit, 2, 3)
        x = round(i * W / n + W / 2 - W / (2 * n) - 4) % W
        stamp(t, m, x, cy - 4)
    s = g["sleeve"]
    Hs, Ws = s.shape
    for _ in range(int(Ws * Hs / 75)):
        stamp(s, small, int(rng.integers(0, Ws)), int(rng.integers(0, Hs)))
    for k in ("hem", "cuff"):
        g[k][:2, :] = 1
    g["collar"][-2:, :] = 1
    return g


SWEATERS = [
    dict(id="cranberry", name="Cranberry Classic", stars=1, draw=cranberry,
         colours=["#c0261d"]),
    dict(id="oatmeal_stripe", name="Oatmeal Stripe", stars=1, draw=oatmeal_stripe,
         colours=["#dccdb0", "#5b3a26"]),
    dict(id="snowfall_yoke", name="Snowfall Yoke", stars=2, draw=snowfall_yoke,
         colours=["#1f2c4a", "#efe3c8", "#b8322a"]),
    dict(id="flock", name="Flock of Friends", stars=3, draw=flock,
         colours=["#7f9a6d", "#f3ead6", "#2f2a26", "#3f5a3a"]),
    dict(id="midnight_moon", name="Midnight Moon", stars=4, draw=midnight_moon,
         colours=["#22204a", "#e0b43c", "#f4ead0", "#3a3870"]),
]


# --- drawing the stitches ------------------------------------------------------------------------

def _vees(grid, px):
    """Every stitch as a knit V: returns (index of the stitch each pixel belongs to as (row, col),
    height 0..1, twist of the ply -1..1). Columns run down the image, row 0 at the top."""
    L, W = grid.shape
    H, Wd = L * px, W * px
    yy, xx = np.mgrid[0:H, 0:Wd]
    U, V = (xx + 0.5) / px, (yy + 0.5) / px
    col, row = np.floor(U).astype(int), np.floor(V).astype(int)
    u = U - col
    best = np.full((H, Wd), -1.0)
    who = np.zeros((H, Wd), dtype=int)
    twist = np.zeros((H, Wd))
    for dr in (-1, 0, 1):
        r = row + dr
        v = V - r
        leg = 0.19 + 0.21 * v
        left = u < 0.5
        d = np.where(left, np.abs(u - leg), np.abs(u - (1.0 - leg)))
        ends = np.clip((v + 0.5) / 0.22, 0, 1) * np.clip((1.5 - v) / 0.22, 0, 1)
        h = np.sqrt(np.clip(1.0 - (d / 0.2) ** 2, 0, 1)) * ends * (0.82 + 0.18 * np.clip(v, 0, 1))
        ok = (r >= 0) & (r < L)
        h = np.where(ok, h, 0.0)
        take = h > best
        best = np.where(take, h, best)
        who = np.where(take, grid[np.clip(r, 0, L - 1), col], who)
        slant = np.where(left, 1.0, -1.0)
        twist = np.where(take, np.cos(2 * math.pi * (2.6 * v + slant * 2.2 * u)), twist)
    return who, np.clip(best, 0, 1), twist, (U, V, col)


def stitch_maps(grid, palette, px=10, fibre=None):
    """Stockinette: (rgb, height) of shape (rows*px, cols*px[, 3]); palette: sRGB triples."""
    who, h, twist, _ = _vees(grid, px)
    pal = np.array(palette)
    shade = 0.62 + 0.38 * h ** 0.6
    rgb = pal[who] * shade[..., None] * (0.955 + 0.045 * twist[..., None])
    return _fibre(rgb, fibre), h * (1.0 + 0.06 * twist)


def rib_maps(grid, palette, px=10, fibre=None):
    """Knit-two purl-two rib: the knit columns stand up as Vs, the purl columns between them sink in
    as rows of little bumps, darker in their shadow."""
    who, h, twist, (U, V, col) = _vees(grid, px)
    purl = (col % (2 * RIB_KNIT)) >= RIB_KNIT
    v = V - np.floor(V)
    u = U - col
    bump = np.sqrt(np.clip(1.0 - ((v - 0.5) / 0.5) ** 2, 0, 1)) * np.sqrt(np.clip(1.0 - ((u - 0.5) / 0.62) ** 2, 0, 1))
    h = np.where(purl, 0.08 + 0.32 * bump, 0.25 + 0.75 * h)
    pal = np.array(palette)
    shade = np.where(purl, 0.6 + 0.25 * bump, 0.55 + 0.45 * h ** 0.55)
    rgb = pal[who] * shade[..., None] * (0.955 + 0.045 * twist[..., None])
    return _fibre(rgb, fibre), h


def _fibre(rgb, fibre):
    if fibre is not None:
        fh, fw = fibre.shape
        yy, xx = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]
        rgb = rgb * fibre[yy % fh, xx % fw][..., None]
    return np.clip(rgb, 0, 1)


def palette(sw):
    return [_hex(c) for c in sw["colours"]]


if __name__ == "__main__":
    import os
    import sys

    from PIL import Image

    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    parts = {"torso": (84, 118), "sleeve": (74, 56), "hem": (11, 118), "collar": (9, 56), "cuff": (11, 30)}
    marks = {"yoke_top": 0, "chest": 26}
    for sw in SWEATERS:
        g = sw["draw"](parts, marks)
        rgb, _ = stitch_maps(g["torso"], palette(sw), px=8)
        Image.fromarray((rgb * 255).astype("uint8")).save(os.path.join(out, sw["id"] + ".png"))
