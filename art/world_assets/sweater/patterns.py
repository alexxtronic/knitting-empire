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


# --- more motifs ---------------------------------------------------------------------------------------

PINE = [
    "....x....",
    "...xxx...",
    "..xxxxx..",
    "...xxx...",
    "..xxxxx..",
    ".xxxxxxx.",
    "..xxxxx..",
    ".xxxxxxx.",
    "xxxxxxxxx",
    "....t....",
    "....t....",
]
TULIP = [
    ".r.r.r.",
    ".rrrrr.",
    ".rrrrr.",
    "..rrr..",
    "...g...",
    "g..g..g",
    ".g.g.g.",
    "..ggg..",
    "...g...",
]
CLOUD = [
    "...xxx.....",
    "..xxxxx.xx.",
    ".xxxxxxxxxx",
    "xxxxxxxxxxx",
    ".xxxxxxxxx.",
]
STRAWBERRY = [
    ".g.g.g.",
    "..ggg..",
    ".rrrrr.",
    "rryrryr",
    "rrrrrrr",
    ".ryrry.",
    "..rrr..",
    "...r...",
]
SUNFLOWER = [
    "....y.y....",
    ".y.yyyyy.y.",
    "..yybbbyy..",
    ".yybbbbbyy.",
    "yyybbbbbyyy",
    ".yybbbbbyy.",
    "..yybbbyy..",
    ".y.yyyyy.y.",
    "....ygy....",
    ".....g.gg..",
    "..gg.gg....",
    ".....g.....",
    ".....g.....",
]
MAPLE = [
    ".....x.....",
    "....xxx....",
    ".x..xxx..x.",
    ".xx.xxx.xx.",
    "..xxxxxxx..",
    "xxxxxxxxxxx",
    ".xxxxxxxxx.",
    "..xxxxxxx..",
    "...xxxxx...",
    ".....x.....",
    ".....x.....",
]
FOX = [
    "o.........o",
    "oo.......oo",
    "ooo.....ooo",
    "ooooooooooo",
    "ookoooookoo",
    "wwoooooooww",
    ".wwwwowwww.",
    "..wwwkwww..",
    "....www....",
]
REINDEER = [
    ".x.x...........",
    "..xx.x.........",
    "x.xxx..........",
    ".xxx...........",
    "xxxxx..........",
    "..xxxx.........",
    "...xxx.........",
    "...xxxxxxxxxx..",
    "...xxxxxxxxxxxx",
    "....xxxxxxxxx..",
    "....x.x....x.x.",
    "....x.x....x.x.",
    "....x.x....x.x.",
]
BEE = [
    "..ww.ww...",
    "..ww.ww...",
    ".ykkykkyk.",
    "yykkykkykk",
    ".ykkykkyk.",
]
MUSHROOM = [
    "..rrrrr..",
    ".rrwrrrr.",
    "rrrrrwrrr",
    "rwrrrrrwr",
    "rrrrrrrrr",
    "...www...",
    "...www...",
    "...www...",
    "..wwwww..",
]
LIGHTHOUSE = [
    "...k...",
    "..yyy..",
    ".kyyyk.",
    "..kkk..",
    "..rrr..",
    "..rrr..",
    "..www..",
    "..www..",
    ".rrrrr.",
    ".rrrrr.",
    ".wwwww.",
    ".wwwww.",
    "rrrrrrr",
    "rrrrrrr",
    "kkkkkkk",
]
COTTAGE = [
    "...s.........",
    "..s..........",
    "...s.........",
    "..cc..r......",
    "..cc.rrr.....",
    "..ccrrrrr....",
    "...rrrrrrr...",
    "..rrrrrrrrr..",
    ".rrrrrrrrrrr.",
    "..wwwwwwwww..",
    "..wyywdwyyw..",
    "..wyywdwyyw..",
    "..wwwwdwwww..",
]
DAISY = [
    "..w..",
    ".www.",
    "wwyww",
    ".www.",
    "..w..",
]
XO = [
    "...x...",
    "..x.x..",
    ".x...x.",
    "x..x..x",
    ".x...x.",
    "..x.x..",
    "...x...",
]
DOT = [
    ".xx.",
    "xxxx",
    "xxxx",
    ".xx.",
]
GULL = [
    "x...x",
    ".x.x.",
]


def big(m, k=2):
    """A motif with every stitch made k by k."""
    return np.kron(m, np.ones((k, k), dtype=int))


# --- helpers for the fifty ---------------------------------------------------------------------------

def _phase(W, p):
    """Each column's place 0..1 in a repeat of about p stitches, the repeat fitted to go round a whole
    number of times, with a repeat's middle on the front (on a sleeve, its outer side)."""
    q = W / max(1, round(W / p))
    return ((np.arange(W) - W / 2) / q + 0.5) % 1.0


def _ribs(g, c, keys=("hem", "collar", "cuff")):
    for k in keys:
        g[k][:, :] = c


def _band(grid, motif, y, n, flip=False):
    """n of a motif evenly round at row y, one centred on the front; flip turns every other one."""
    H, W = grid.shape
    h, w = motif.shape
    for i in range(n):
        m = motif[:, ::-1] if flip and i % 2 else motif
        stamp(grid, m, round(i * W / n + W / 2 - w / 2) % W, y)


def _scatter(grid, motifs, density, seed, rows=None, pad=1):
    """Motifs dropped at random without touching: about one a `density` stitches of the rows given."""
    rng = np.random.default_rng(seed)
    if not isinstance(motifs, list):
        motifs = [motifs]
    H, W = grid.shape
    y0, y1 = rows or (0, H)
    want = int(W * (y1 - y0) / density)
    taken = np.zeros((H, W), dtype=bool)
    placed = tries = 0
    while placed < want and tries < want * 40:
        tries += 1
        m = motifs[int(rng.integers(len(motifs)))]
        h, w = m.shape
        y = int(rng.integers(y0, max(y0 + 1, y1 - h + 1)))
        x = int(rng.integers(0, W))
        ys = slice(max(0, y - pad), min(H, y + h + pad))
        xs = [(x + i) % W for i in range(-pad, w + pad)]
        if taken[ys][:, xs].any():
            continue
        taken[ys, :][:, xs] = True
        stamp(grid, m, x, y)
        placed += 1


def _flecks(a, rng, rate, colours):
    m = rng.random(a.shape) < rate
    a[m] = rng.choice(colours, size=int(m.sum()))


def _peerie_row(grid, y, c):
    W = grid.shape[1]
    for j, row in enumerate(PEERIE):
        for x in range(W):
            if row[(x - W // 2) % 6] == "x" and 0 <= y + j < grid.shape[0]:
                grid[y + j, x] = c


def _body(g):
    return g["torso"], g["sleeve"]


# --- common: one star ----------------------------------------------------------------------------

def solid(parts, marks):
    """Plain stockinette in one colour, ribs to match."""
    return _plain(parts, 0)


def _tweed(seed, colours, rate=0.06):
    def draw(parts, marks):
        g = _plain(parts, 0)
        rng = np.random.default_rng(seed)
        for a in g.values():
            _flecks(a, rng, rate, colours)
        return g
    draw.__doc__ = "A tweedy yarn: the main colour flecked with other colours at random."
    return draw


def contrast_ribs(parts, marks):
    """Plain body, ribs in a second colour."""
    g = _plain(parts, 0)
    _ribs(g, 1)
    return g


def tipped(parts, marks):
    """Plain body, ribs in a second colour and a line of it just above the hem and each cuff."""
    g = contrast_ribs(parts, marks)
    for a in _body(g):
        a[-3, :] = 1
    return g


def breton(parts, marks):
    """Breton stripes: a two-row stripe every five rows from the chest down, plain above; striped
    sleeves; plain ribs."""
    g = _plain(parts, 0)
    t, s = _body(g)
    for y in range(marks["chest"] + 4, t.shape[0]):
        if (t.shape[0] - 1 - y) % 5 in (1, 2):
            t[y, :] = 1
    for y in range(8, s.shape[0]):
        if (s.shape[0] - 1 - y) % 5 in (1, 2):
            s[y, :] = 1
    return g


def wide_stripe(parts, marks):
    """Even six-row stripes of two colours, all over."""
    g = _plain(parts, 0)
    for a in _body(g):
        H = a.shape[0]
        for y in range(H):
            if ((H - 1 - y) // 6) % 2:
                a[y, :] = 1
    return g


def candy_stripe(parts, marks):
    """Two rows of the second colour and one of the third every nine rows."""
    g = _plain(parts, 0)
    for a in _body(g):
        H = a.shape[0]
        for y in range(H):
            k = (H - 1 - y) % 9
            if k in (3, 4):
                a[y, :] = 1
            elif k == 6:
                a[y, :] = 2
    return g


def colourblock(parts, marks):
    """The top in one colour, the bottom in another, a line of a third between; the sleeves split at
    the elbow the same way."""
    g = _plain(parts, 0)
    for a in _body(g):
        H = a.shape[0]
        cut = int(H * 0.45)
        a[cut:, :] = 1
        a[cut, :] = 2
    g["hem"][:, :] = g["cuff"][:, :] = 1
    return g


def other_sleeves(parts, marks):
    """The body in one colour, the sleeves and collar in another."""
    g = _plain(parts, 0)
    g["sleeve"][:, :] = g["cuff"][:, :] = g["collar"][:, :] = 1
    return g


def pinstripe(parts, marks):
    """A thin vertical stripe every six stitches."""
    g = _plain(parts, 0)
    for a in _body(g):
        W = a.shape[1]
        a[:, (np.arange(W) - W // 2) % 6 == 0] = 1
    return g


def pin_dots(parts, marks):
    """Single-stitch dots on a staggered six by six grid."""
    g = _plain(parts, 0)
    for a in _body(g):
        H, W = a.shape
        x = (np.arange(W) - W // 2) % 6
        for y in range(H):
            if y % 6 == 0:
                a[y, x == 0] = 1
            elif y % 6 == 3:
                a[y, x == 3] = 1
    return g


def chest_stripe(parts, marks):
    """Plain, with three stripes across the chest and the upper sleeves (cream, gold, cream)."""
    g = _plain(parts, 0)
    t, s = _body(g)
    for a, c in ((t, marks["chest"]), (s, 9)):
        a[c:c + 2, :] = 1
        a[c + 3, :] = 2
        a[c + 5:c + 7, :] = 1
    return g


def ombre(parts, marks):
    """Five shades in bands from dark at the hem to light at the shoulders, the edges dithered."""
    g = _plain(parts, 0)
    rng = np.random.default_rng(7)
    for a in _body(g):
        H, W = a.shape
        t = (H - 1 - np.arange(H))[:, None] / H * 5 + rng.normal(0, 0.12, (H, W))
        a[:, :] = np.clip(t, 0, 4).astype(int)
    g["collar"][:, :] = 4
    return g


# --- rare: two stars -------------------------------------------------------------------------------

def argyle(parts, marks):
    """Argyle: diamonds of a second colour on the main one, crossed by thin lines of a third."""
    g = _plain(parts, 0)
    for a in _body(g):
        H, W = a.shape
        p, h = 18, 26
        u = _phase(W, p)[None, :]
        v = ((np.arange(H) + h * 0.5) / h % 1.0)[:, None]
        a[(np.abs(u - 0.5) + np.abs(v - 0.5)) <= 0.5] = 1
        e1 = (u + v + 0.5) % 1.0 - 0.5
        e2 = (u - v + 0.5) % 1.0 - 0.5
        a[(np.abs(e1) < 0.6 / p) | (np.abs(e2) < 0.6 / p)] = 2
    return g


def gingham(parts, marks):
    """Gingham: four-stitch checks, where the two colours cross they make the deep one."""
    g = _plain(parts, 0)
    for a in _body(g):
        H, W = a.shape
        cx = (_phase(W, 8) * 2).astype(int)[None, :]
        cy = ((np.arange(H) // 4) % 2)[:, None]
        a[:, :] = cx + cy
    _ribs(g, 2)
    return g


def houndstooth(parts, marks):
    """Houndstooth on an eight-stitch repeat."""
    g = _plain(parts, 0)
    for a in _body(g):
        H, W = a.shape
        X = ((np.arange(W) - W // 2) % 8)[None, :]
        Y = (np.arange(H) % 8)[:, None]
        dark = (X < 4) & (Y < 4)
        mixed = (X < 4) != (Y < 4)
        tooth = mixed & (((X + Y) % 4) < 2)
        a[dark | tooth] = 1
    _ribs(g, 1)
    return g


def chevron(parts, marks):
    """Zigzag stripes of three colours, the points down the front."""
    g = _plain(parts, 0)
    for a in _body(g):
        H, W = a.shape
        off = (np.abs(_phase(W, 16) - 0.5) * 2 * 8)[None, :]
        y = np.arange(H)[:, None]
        a[:, :] = (((y + off) // 4).astype(int)) % 3
    return g


def polka(parts, marks):
    """Round dots, four stitches across, on a staggered grid."""
    g = _plain(parts, 0)
    dot = bitmap(DOT, {"x": 1})
    for a in _body(g):
        H, W = a.shape
        n = max(1, round(W / 10))
        for j, y in enumerate(range(1, H, 9)):
            for i in range(n):
                stamp(a, dot, round((i + 0.5 * (j % 2)) * W / n + W / 2 - 2) % W, y)
    return g


def lattice(parts, marks):
    """A diamond lattice of thin lines, a dot in every other diamond."""
    g = _plain(parts, 0)
    for a in _body(g):
        H, W = a.shape
        p, h = 12, 14
        u = _phase(W, p)[None, :]
        v = (np.arange(H) / h % 1.0)[:, None]
        e1 = (u + v + 0.5) % 1.0 - 0.5
        e2 = (u - v + 0.5) % 1.0 - 0.5
        a[(np.abs(e1) < 0.55 / p) | (np.abs(e2) < 0.55 / p)] = 1
        vv = (v + 0.5) % 1.0 - 0.5
        a[(np.abs(u - 0.5) < 0.55 / p) & (np.abs(vv) < 0.55 / h)] = 2
    return g


def raindrops(parts, marks):
    """Clouds on the shoulders and rain falling below them, a drop at a time."""
    g = _plain(parts, 0)
    t, s = _body(g)
    cloud = bitmap(CLOUD, {"x": 1})
    drop = bitmap(["x", "x"], {"x": 2})
    _scatter(t, cloud, 230, 3, rows=(1, int(t.shape[0] * 0.45)), pad=3)
    _scatter(t, drop, 26, 4, rows=(6, t.shape[0] - 2), pad=2)
    _scatter(s, cloud, 300, 5, rows=(1, 25), pad=3)
    _scatter(s, drop, 30, 6, rows=(6, s.shape[0] - 2), pad=2)
    _ribs(g, 3)
    return g


def strawberries(parts, marks):
    """Strawberries scattered all over, seeds and leaves and all."""
    g = _plain(parts, 0)
    berry = bitmap(STRAWBERRY, {"r": 1, "g": 2, "y": 3})
    for a, seed in zip(_body(g), (8, 9)):
        _scatter(a, berry, 120, seed, pad=2)
    _ribs(g, 1)
    return g


def heart_band(parts, marks):
    """A row of hearts across the chest between pink peerie borders, and hearts above the cuffs."""
    g = _plain(parts, 0)
    t, s = _body(g)
    heart = bitmap(HEART, {"x": 1})
    c = marks["chest"]
    _peerie_row(t, c - 6, 2)
    _band(t, heart, c, round(t.shape[1] / 11))
    _peerie_row(t, c + 8, 2)
    _band(s, heart, s.shape[0] - 14, round(s.shape[1] / 11))
    _ribs(g, 1)
    return g


def peerie_bands(parts, marks):
    """Little peerie borders all the way down in brown, red and green, with thin lines between."""
    g = _plain(parts, 0)
    for a in _body(g):
        H = a.shape[0]
        for k, y in enumerate(range(2, H - 4, 11)):
            _peerie_row(a, y, 1 + k % 3)
            if y + 7 < H:
                a[y + 7, :] = 1
    g["collar"][-2:, :] = 2
    return g


def pine_band(parts, marks):
    """A forest of cream pines round the bottom of the body and above the cuffs, snow falling above."""
    g = _plain(parts, 0)
    t, s = _body(g)
    pine = bitmap(PINE, {"x": 1, "t": 2})
    _scatter(t, bitmap(["x"], {"x": 1}), 14, 12, rows=(0, t.shape[0] - 26), pad=2)
    _band(t, pine, t.shape[0] - 14, round(t.shape[1] / 11))
    t[-2:, :] = 1
    _scatter(s, bitmap(["x"], {"x": 1}), 16, 13, rows=(0, s.shape[0] - 18), pad=2)
    _band(s, pine, s.shape[0] - 13, round(s.shape[1] / 11))
    g["collar"][-2:, :] = 1
    return g


def tulip_border(parts, marks):
    """A border of tulips in three colours round the hem and above each cuff."""
    g = _plain(parts, 0)
    t, s = _body(g)
    for a in (t, s):
        H, W = a.shape
        n = round(W / 9)
        for i in range(n):
            m = bitmap(TULIP, {"r": 1 + i % 3, "g": 4})
            stamp(a, m, round(i * W / n + W / 2 - 3) % W, H - 11)
        a[-2, :] = 4
    _ribs(g, 4)
    return g


def mountains(parts, marks):
    """The Greyspine range round the body: grey peaks with snow caps against the sky, a line of dark
    pines along their feet."""
    g = _plain(parts, 0)
    rng = np.random.default_rng(31)
    for a, top, low in ((g["torso"], 30, 10), (g["sleeve"], 44, 8)):
        H, W = a.shape
        hgt = np.zeros(W)
        n = max(2, round(W / 18))
        for i in range(n):
            cx = i * W / n + W / 2 + rng.uniform(-3, 3)
            ph = rng.uniform(0.55, 1.0) * (H - top - low)
            for x in range(W):
                d = min(abs(x - cx), W - abs(x - cx))
                hgt[x] = max(hgt[x], ph - d * 1.1)
        for x in range(W):
            peak = H - low - int(hgt[x])
            a[peak:H - low, x] = 1
            if hgt[x] > (H - top - low) * 0.45:
                a[peak:peak + 3, x] = 2
        pine = bitmap(PINE[:9], {"x": 3})
        _band(a, pine, H - low - 6, round(W / 6))
        a[H - low + 2:, :] = 3
    _ribs(g, 3)
    return g


def daisy_chain(parts, marks):
    """Daisies round the yoke and the hem and above the cuffs, joined by a green line."""
    g = _plain(parts, 0)
    t, s = _body(g)
    daisy = bitmap(DAISY, {"w": 1, "y": 2})
    for a, y in ((t, 3), (t, t.shape[0] - 9), (s, s.shape[0] - 11)):
        a[y + 2, :] = 3
        _band(a, daisy, y, round(a.shape[1] / 8))
    return g


# --- ultra rare: three stars ---------------------------------------------------------------------

def sunflowers(parts, marks):
    """A field of tall sunflowers round the bottom of the body against a summer sky, one on each
    sleeve."""
    g = _plain(parts, 0)
    t, s = _body(g)
    sun = bitmap(SUNFLOWER, {"y": 1, "b": 2, "g": 3})
    H, W = t.shape
    n = round(W / 13)
    for i in range(n):
        y = H - 28 + (i % 2) * 5
        x = round(i * W / n + W / 2 - 5) % W
        stamp(t, sun, x, y)
        for yy in range(y + 13, H):
            t[yy, (x + 5) % W] = 3
    t[-4:, :] = 3
    stamp(s, sun, s.shape[1] // 2 - 5, 12)
    _ribs(g, 3)
    return g


def autumn_leaves(parts, marks):
    """Maple leaves falling all over in orange, red and gold."""
    g = _plain(parts, 0)
    leaves = [bitmap(MAPLE, {"x": c}) for c in (1, 2, 3)]
    leaves += [m[:, ::-1] for m in leaves]
    for a, seed in zip(_body(g), (14, 15)):
        _scatter(a, leaves, 150, seed, pad=2)
    _ribs(g, 2)
    return g


def fox_forest(parts, marks):
    """Foxes peeping out across the chest, between bands of pines; pines above the cuffs."""
    g = _plain(parts, 0)
    t, s = _body(g)
    fox = bitmap(FOX, {"o": 1, "w": 2, "k": 3})
    pine = bitmap(PINE, {"x": 4, "t": 3})
    c = marks["chest"]
    t[c - 3, :] = 2
    _band(t, fox, c, round(t.shape[1] / 15))
    t[c + 11, :] = 2
    _band(t, pine, t.shape[0] - 16, round(t.shape[1] / 10))
    _band(t, pine, t.shape[0] - 13, round(t.shape[1] / 10))
    for k in range(t.shape[1]):
        t[-3:, k] = 4
    _band(s, pine, s.shape[0] - 13, round(s.shape[1] / 10))
    _band(s, fox, 10, 1)
    _ribs(g, 4)
    return g


def reindeer(parts, marks):
    """Nordic reindeer facing each other across the chest between snowflake and peerie bands, red and
    cream."""
    g = _plain(parts, 0)
    t, s = _body(g)
    deer = bitmap(REINDEER, {"x": 1})
    flake = bitmap(STAR5, {"x": 1})
    c = marks["chest"]
    _peerie_row(t, c - 14, 1)
    _band(t, flake, c - 8, round(t.shape[1] / 9))
    _band(t, deer, c, round(t.shape[1] / 19), flip=True)
    t[c + 15, :] = 1
    _peerie_row(t, c + 17, 1)
    _band(t, flake, t.shape[0] - 10, round(t.shape[1] / 9))
    _peerie_row(s, 8, 1)
    _band(s, flake, s.shape[0] - 12, round(s.shape[1] / 9))
    _ribs(g, 1)
    g["hem"][:2, :] = g["cuff"][:2, :] = 0
    return g


def honeycomb(parts, marks):
    """Honeycomb all over in two golds, busy bees here and there."""
    g = _plain(parts, 0)
    bee = bitmap(BEE, {"y": 4, "k": 2, "w": 3})
    for a, seed in zip(_body(g), (17, 18)):
        H, W = a.shape
        n = max(1, round(W / 10))
        q = W / n
        rh = q * 0.866 * 0.009 / 0.0075          # rows between lines of cells (stitches are wider)
        cs = []
        for j in range(-1, int(H / rh) + 2):
            for i in range(n):
                cs.append(((i + 0.5 * (j % 2)) * q + W / 2, j * rh))
        cs = np.array(cs)
        xx, yy = np.meshgrid(np.arange(W), np.arange(H))
        d = []
        for cx, cy in cs:
            dx = np.abs(xx - cx) % W
            dx = np.minimum(dx, W - dx)
            d.append(np.hypot(dx, (yy - cy) * 0.0075 / 0.009))
        d = np.sort(np.array(d), axis=0)
        a[(d[1] - d[0]) < 0.9] = 1
        _scatter(a, [bee, bee[:, ::-1]], 260, seed, pad=1)
    _ribs(g, 1)
    return g


def mushrooms(parts, marks):
    """Toadstools, red and brown, round the bottom of a mossy body and here and there above."""
    g = _plain(parts, 0)
    t, s = _body(g)
    red = bitmap(MUSHROOM, {"r": 1, "w": 2})
    brown = bitmap(MUSHROOM, {"r": 4, "w": 2})
    n = round(t.shape[1] / 11)
    for i in range(n):
        stamp(t, red if i % 2 else brown, round(i * t.shape[1] / n + t.shape[1] / 2 - 4) % t.shape[1], t.shape[0] - 14 + (i % 3))
    t[-4:, :] = 3
    _scatter(t, [red, brown], 260, 21, rows=(2, t.shape[0] - 20), pad=3)
    stamp(s, red, s.shape[1] // 2 - 4, s.shape[0] - 14)
    _scatter(s, [red, brown], 320, 22, rows=(2, s.shape[0] - 18), pad=3)
    _ribs(g, 3)
    return g


def lighthouse(parts, marks):
    """Saltmeadow's lighthouse on the front, gulls overhead, waves all the way round below."""
    g = _plain(parts, 0)
    t, s = _body(g)
    H, W = t.shape
    lh = big(bitmap(LIGHTHOUSE, {"r": 1, "w": 2, "y": 3, "k": 4}))
    sea = H - 16
    # light beams either side of the lamp
    by = sea - lh.shape[0] + 6
    for k in range(1, 18):
        for dy in (0, 1):
            t[by + dy + k // 4, (W // 2 + 7 + k) % W] = 3
            t[by + dy + k // 4, (W // 2 - 8 - k) % W] = 3
    _scatter(t, bitmap(GULL, {"x": 4}), 120, 25, rows=(2, sea - 10), pad=4)
    for a, top in ((t, sea), (s, s.shape[0] - 12)):
        HH, WW = a.shape
        for x in range(WW):
            crest = top + int(round(1.5 * math.sin(x / WW * 2 * math.pi * round(WW / 8))))
            a[crest:, x] = 5
            a[crest, x] = 2
            a[crest + 5:, x] = 6
            if (x + crest) % 7 == 0 and crest + 3 < HH:
                a[crest + 3, x] = 2
    stamp(t, lh, W // 2 - 7, sea - lh.shape[0] + 4)
    _scatter(s, bitmap(GULL, {"x": 4}), 140, 26, rows=(2, s.shape[0] - 20), pad=4)
    _ribs(g, 6)
    g["collar"][:, :] = 2
    return g


def cottage(parts, marks):
    """Gran's cottage on the front: red roof, lit windows, smoke from the chimney, on green hills that
    roll round to pines at the back."""
    g = _plain(parts, 0)
    t, s = _body(g)
    H, W = t.shape
    for a, base in ((t, H - 18), (s, s.shape[0] - 12)):
        HH, WW = a.shape
        for x in range(WW):
            ph = (x - WW / 2) / WW * 2 * math.pi
            top = base + int(round(3 * math.cos(ph * 2) + 1.5 * math.sin(ph * 5)))
            a[top:, x] = 7
            for y in range(top, HH):
                if (y - top) % 6 == 5:
                    a[y, x] = 8
    house = big(bitmap(COTTAGE, {"s": 6, "c": 5, "r": 1, "w": 2, "y": 3, "d": 4}))
    stamp(t, house, W // 2 - 13, H - 18 - house.shape[0] + 3)
    pine = bitmap(PINE, {"x": 8, "t": 4})
    for i in range(5):
        stamp(t, pine, round(i * 9 - 22) % W, H - 26 + (i % 2) * 2)
    _scatter(t, bitmap(CLOUD, {"x": 6}), 400, 27, rows=(1, 14), pad=4)
    _ribs(g, 8)
    return g


def rainbow(parts, marks):
    """A rainbow across the front with clouds at its ends, little clouds round the back, rainbow
    stripes above the cuffs."""
    g = _plain(parts, 0)
    t, s = _body(g)
    H, W = t.shape
    cx, cy = W / 2 - 0.5, marks["chest"] + 30
    for y in range(H):
        for x in range(W):
            dx = min(abs(x - cx), W - abs(x - cx)) * 0.009
            r = math.hypot(dx, (y - cy) * 0.0075) / 0.009
            if y <= cy and 14 < r <= 35:
                t[y, x] = 1 + min(6, int((35 - r) // 3))
    cloud = big(bitmap(CLOUD, {"x": 7}))
    for side in (-1, 1):
        stamp(t, cloud, round(cx + side * 25 - 11) % W, int(cy) - 6)
    _scatter(t, bitmap(CLOUD, {"x": 7}), 300, 33, rows=(2, H - 8), pad=3)
    for k in range(6):
        s[s.shape[0] - 18 + k * 2: s.shape[0] - 16 + k * 2, :] = 1 + k
    _ribs(g, 7)
    return g


# --- legendary: four stars ----------------------------------------------------------------------------

def golden_fleece(parts, marks):
    """Deep teal and gold: a flock of golden sheep across the chest between gold peerie borders, gold
    and cream stars all over, a golden sheep on each sleeve, gold-tipped ribs."""
    g = _plain(parts, 0)
    t, s = _body(g)
    sheep = bitmap(SHEEP, {"w": 1, "k": 2})
    rng = np.random.default_rng(41)
    for a in (t, s):
        H, W = a.shape
        for _ in range(int(W * H / 90)):
            stamp(a, bitmap(STAR3 if rng.random() < 0.75 else STAR5, {"x": 3 if rng.random() < 0.5 else 1}),
                  int(rng.integers(0, W)), int(rng.integers(0, H)))
    c = marks["chest"]
    t[c - 8: c + 13, :] = 0
    _peerie_row(t, c - 7, 4)
    t[c - 2, :] = 1
    _band(t, sheep, c, round(t.shape[1] / 19), flip=True)
    t[c + 10, :] = 1
    _peerie_row(t, c + 12, 4)
    s[8:21, :] = 0
    stamp(s, sheep, s.shape[1] // 2 - 7, 10)
    for k in ("hem", "cuff"):
        g[k][:2, :] = 1
    g["collar"][-2:, :] = 1
    return g


def northern_lights(parts, marks):
    """The northern lights over a night sky: green curtains with violet tops fading to teal, stars
    above, a black forest round the bottom."""
    g = _plain(parts, 0)
    rng = np.random.default_rng(23)
    pine = bitmap(PINE, {"x": 5, "t": 5})
    for a, top, depth, waves in ((g["torso"], 6, 34, 3), (g["sleeve"], 6, 26, 2)):
        H, W = a.shape
        _scatter(a, bitmap(["x"], {"x": 4}), 18, int(rng.integers(1000)), pad=2)
        x = np.arange(W)
        ph = (x - W / 2) / W * 2 * math.pi
        c = top + 4 * np.sin(ph * waves) + 2.5 * np.sin(ph * waves * 2 + 1.0)
        L = depth * (0.55 + 0.45 * (0.5 + 0.5 * np.sin(ph * waves * 3 + 2.0)))
        streak = rng.random(W)
        for xx in range(W):
            for y in range(H):
                tt = (y - c[xx]) / L[xx]
                if tt < 0 or tt > 1:
                    continue
                r = rng.random()
                if tt < 0.14:
                    col = 3 if r < 0.75 else 0
                elif tt < 0.55:
                    col = 1 if r < 0.75 + 0.25 * streak[xx] else 2
                else:
                    col = 2 if r < (1.0 - tt) * 2.0 * (0.5 + streak[xx]) else 0
                a[y, xx] = col
        n = round(W / 6)
        for i in range(n):
            stamp(a, pine, round(i * W / n + W / 2 - 4) % W, H - 13 + int(rng.integers(0, 4)))
        a[-3:, :] = 5
    _ribs(g, 0)
    g["collar"][-2:, :] = 1
    return g


def grans_heirloom(parts, marks):
    """Gran's heirloom: Fair Isle bands from collar to hem in six colours, peerie, XO, snowflake and
    star borders on changing grounds, the same down the sleeves."""
    g = _plain(parts, 0)
    bands = [  # (rows, ground, pattern colour, motif)
        (5, 1, 3, "peerie"), (1, 0, 0, None), (9, 2, 0, XO), (1, 0, 0, None),
        (13, 5, 0, SNOWFLAKE), (1, 0, 0, None), (5, 4, 3, "peerie"), (7, 0, 2, STAR5),
        (1, 1, 1, None),
    ]
    for a in _body(g):
        H, W = a.shape
        y = 0
        k = 0
        while y < H:
            rows, ground, fg, motif = bands[k % len(bands)]
            a[y:y + rows, :] = ground
            if motif == "peerie":
                _peerie_row(a, y + (rows - 4) // 2, fg)
            elif motif is not None:
                m = bitmap(motif, {"x": fg})
                _band(a, m, y + (rows - m.shape[0]) // 2, max(1, round(W / (m.shape[1] + 3))))
            y += rows
            k += 1
    g["hem"][:, :] = g["cuff"][:, :] = 1
    g["hem"][:2, :] = g["cuff"][:2, :] = 2
    g["collar"][:, :] = 1
    return g


def four_seasons(parts, marks):
    """The year round the body: spring tulips on the front, summer sunflowers on her left, autumn
    leaves on the back, winter snowflakes on her right, cream seams between; the sleeves go through
    the seasons from shoulder to cuff."""
    g = _plain(parts, 0)
    t, s = _body(g)
    H, W = t.shape
    seasons = [
        (1, [bitmap(TULIP, {"r": 5, "g": 8}), bitmap(TULIP, {"r": 6, "g": 8})]),
        (2, [bitmap(SUNFLOWER, {"y": 6, "b": 7, "g": 8})]),
        (3, [bitmap(MAPLE, {"x": 10}), bitmap(MAPLE, {"x": 6})[:, ::-1]]),
        (4, [bitmap(SNOWFLAKE, {"x": 9}), bitmap(STAR5, {"x": 9})]),
    ]
    q = W / 4
    quarter = (((np.arange(W) - W / 2 + q / 2) % W) // q).astype(int)
    for k, (ground, motifs) in enumerate(seasons):
        cols = np.where(quarter == k)[0]
        part = np.full((H, len(cols)), ground, dtype=int)
        _scatter(part, motifs, 95, 50 + k, pad=2)
        sub = part[:, :]
        for j, x in enumerate(cols):
            t[:, x] = sub[:, j]
    for k in range(4):
        x0 = int(round(W / 2 - q / 2 + k * q)) % W
        t[:, x0] = 0
    Hs, Ws = s.shape
    for k, (ground, motifs) in enumerate(seasons):
        y0, y1 = int(k * Hs / 4), int((k + 1) * Hs / 4)
        part = np.full((y1 - y0, Ws), ground, dtype=int)
        small = [m for m in motifs if m.shape[0] <= 11]
        _scatter(part, small or motifs, 110, 60 + k, pad=1)
        s[y0:y1, :] = part
        if k:
            s[y0, :] = 0
    _ribs(g, 0)
    return g


def _sw(id, name, stars, draw, *colours):
    return dict(id=id, name=name, stars=stars, draw=draw, colours=list(colours))


SWEATERS = [
    # common
    _sw("cranberry", "Cranberry Classic", 1, cranberry, "#c0261d"),
    _sw("oatmeal_stripe", "Oatmeal Stripe", 1, oatmeal_stripe, "#dccdb0", "#5b3a26"),
    _sw("forest", "Forest Green", 1, solid, "#2f5a3a"),
    _sw("harbour_navy", "Harbour Navy", 1, solid, "#22304f"),
    _sw("mustard", "Mustard Seed", 1, solid, "#c99a2e"),
    _sw("lavender", "Lavender", 1, solid, "#a493c4"),
    _sw("pumpkin", "Pumpkin", 1, solid, "#cf6a2a"),
    _sw("heather_tweed", "Heather Tweed", 1, _tweed(1, [1, 2, 3, 4]),
        "#8c8b88", "#b8322a", "#d8a83a", "#4a7a9a", "#efe3c8"),
    _sw("bark_tweed", "Bark Tweed", 1, _tweed(2, [1, 2, 3]), "#6b4a33", "#d8c7a6", "#a0522d", "#557a46"),
    _sw("cream_forest", "Cream and Forest", 1, contrast_ribs, "#efe6d2", "#2f5a3a"),
    _sw("charcoal_tipped", "Charcoal Tipped", 1, tipped, "#3a3a3c", "#b8322a"),
    _sw("breton", "Breton", 1, breton, "#f2ece0", "#4f7fb8"),
    _sw("rust_stripe", "Rust Stripe", 1, wide_stripe, "#a8492a", "#e9dcc2"),
    _sw("mint_candy", "Mint Candy", 1, candy_stripe, "#9fd3bf", "#fbf7ee", "#7d8c88"),
    _sw("rose_block", "Rose Block", 1, colourblock, "#d98a95", "#7a2a3a", "#f3e7d3"),
    _sw("sage_cream", "Sage and Cream", 1, other_sleeves, "#8fa58a", "#efe6d2"),
    _sw("denim", "Denim Pinstripe", 1, pinstripe, "#3b5a80", "#9fb4cc"),
    _sw("butter_dots", "Buttercup Dots", 1, pin_dots, "#f1d77a", "#fffaf0"),
    _sw("plum_stripe", "Plum Stripe", 1, chest_stripe, "#5e2f55", "#efe3c8", "#e0b43c"),
    _sw("dusk_ombre", "Dusk Ombre", 1, ombre, "#1f3b4d", "#2f5d73", "#4f8a99", "#86b8bc", "#c7e0d9"),
    # rare
    _sw("snowfall_yoke", "Snowfall Yoke", 2, snowfall_yoke, "#1f2c4a", "#efe3c8", "#b8322a"),
    _sw("argyle", "Argyle", 2, argyle, "#2d4a3e", "#b98f57", "#c9372f"),
    _sw("gingham", "Picnic Gingham", 2, gingham, "#f6f0e4", "#e4958f", "#c43b35"),
    _sw("houndstooth", "Houndstooth", 2, houndstooth, "#efe6d2", "#2a2724"),
    _sw("chevron", "Chevron", 2, chevron, "#2a7f7a", "#f1e8d6", "#e2725b"),
    _sw("polka", "Navy Polka", 2, polka, "#22304f", "#f1e8d6"),
    _sw("lattice", "Cornflower Lattice", 2, lattice, "#6a8fd0", "#f4eee0", "#e0b43c"),
    _sw("raindrops", "April Showers", 2, raindrops, "#7d93a8", "#f7f7f4", "#cfe3f0", "#4c5e70"),
    _sw("strawberries", "Strawberry Patch", 2, strawberries, "#f3ead6", "#c8302c", "#4f8a3a", "#f2d36b"),
    _sw("heart_band", "Sweetheart", 2, heart_band, "#f3e7d3", "#c8302c", "#e79aa6"),
    _sw("peerie_bands", "Peerie Bands", 2, peerie_bands, "#e3d3b4", "#5b3a26", "#a8322a", "#3f6a4a"),
    _sw("pine_band", "Winter Pines", 2, pine_band, "#2f5a3a", "#f1e8d6", "#6b4a33"),
    _sw("tulip_border", "Tulip Border", 2, tulip_border, "#a9cfe6", "#d9434a", "#e98aa8", "#f2c94c", "#4f8a3a"),
    _sw("greyspine", "Greyspine Peaks", 2, mountains, "#7fa3c4", "#8a8f99", "#f6f4ee", "#2f4a3a"),
    _sw("daisy_chain", "Daisy Chain", 2, daisy_chain, "#b6a3d1", "#fbf7ee", "#f2c94c", "#5f8a4a"),
    # ultra rare
    _sw("flock", "Flock of Friends", 3, flock, "#7f9a6d", "#f3ead6", "#2f2a26", "#3f5a3a"),
    _sw("sunflowers", "Sunflower Field", 3, sunflowers, "#8cc3e0", "#f2c12e", "#5a3a1e", "#3f7a3f"),
    _sw("autumn_leaves", "Falling Leaves", 3, autumn_leaves, "#4a2e2a", "#e0782a", "#b8322a", "#e2b23c"),
    _sw("fox_forest", "Fox in the Pines", 3, fox_forest, "#2b4a35", "#d2691e", "#f3ead6", "#2a2320", "#5f8a5a"),
    _sw("reindeer", "Reindeer", 3, reindeer, "#a52a2a", "#f3e7d3"),
    _sw("honeycomb", "Honeycomb", 3, honeycomb, "#e0a92a", "#b07a14", "#2a2320", "#f6f2e6", "#f8dc5a"),
    _sw("mushrooms", "Toadstools", 3, mushrooms, "#6d8a52", "#c8302c", "#f3ead6", "#3f5a32", "#8a5a32"),
    _sw("lighthouse", "Saltmeadow Light", 3, lighthouse, "#cfe3ec", "#c23a30", "#f6f1e6", "#f2c94c", "#2b2f3a", "#2f6f9a", "#1f4a6e"),
    _sw("cottage", "Home Sweet Home", 3, cottage, "#bcd7e6", "#a83a2c", "#f3ead6", "#f2c94c", "#6b4226", "#7a6a5a", "#f4f4f2", "#6a9a5a", "#3f6a3f"),
    _sw("rainbow", "After the Rain", 3, rainbow, "#9cc9e6", "#d6453d", "#ee8a3a", "#f2cf4a", "#5fae5a", "#4a86c8", "#7a5aa8", "#fafafa"),
    # legendary
    _sw("midnight_moon", "Midnight Moon", 4, midnight_moon, "#22204a", "#e0b43c", "#f4ead0", "#3a3870"),
    _sw("golden_fleece", "Golden Fleece", 4, golden_fleece, "#1d4a4f", "#e2b23c", "#2a2320", "#f3e7c8", "#a8761c"),
    _sw("northern_lights", "Northern Lights", 4, northern_lights, "#141a33", "#3fd08a", "#2a8f8a", "#8a5cd0", "#f4ead0", "#0b1f19"),
    _sw("grans_heirloom", "Gran's Heirloom", 4, grans_heirloom, "#e3d3b4", "#5b3a26", "#a8322a", "#d1a23a", "#3f6a4a", "#33507a"),
    _sw("four_seasons", "Four Seasons", 4, four_seasons, "#f1e8d4", "#a8d5b5", "#8cc3e0", "#b5532b", "#22304f",
        "#e07a95", "#f0c43a", "#5a3a22", "#3f7a3f", "#fafafa", "#e08a2a"),
]
assert [sum(1 for s in SWEATERS if s["stars"] == k) for k in (1, 2, 3, 4)] == [20, 15, 10, 5]


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
    import json
    lay = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "layout.json")))
    parts = {k: (v["h"], v["w"]) for k, v in lay["regions"].items()}
    marks = lay["marks"]
    for sw in SWEATERS:
        g = sw["draw"](parts, marks)
        rgb, _ = stitch_maps(g["torso"], palette(sw), px=8)
        Image.fromarray((rgb * 255).astype("uint8")).save(os.path.join(out, sw["id"] + ".png"))
