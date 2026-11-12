"""Wood boards as images: one board per image, its grain cut from a model of a tree's growth rings,
with knots, fibre streaks, a bevelled edge and the gap to the next board. Five boards side by side
make an atlas the game lays walls and floors from (scripts/planks.gd).

Plain numpy, so it runs in Blender (build.py) and outside it:

    uv run --no-project --with numpy --with pillow python art/world_assets/planks/grain.py <out_dir>
"""
import math

import numpy as np

BOARD_W = 0.30          # metres across one board
PX_W, PX_H = 128, 1024  # one board in the atlas
VARIANTS = 5

# Colours are the references' (ref/*.png), about a tenth darker, as Alex asked.
KINDS = {
    # pale boards for the walls: quiet, nearly straight grain, small tight knots, a beaded groove
    "wall": dict(length=2.6, light="#e3cba9", dark="#c6a884", knot="#b58d5f", knot_dark="#8f6a42", gap="#a37c50",
                 depth=(0.3, 0.8), tilt=0.05, ring=(0.006, 0.009), contrast=0.36, figure=0.2, warp=0.006,
                 knots=(1, 3), knot_r=(0.009, 0.016), gap_px=2.2, bevel_px=6.0, ends=False, seed=40),
    # warm oak for the floor: flat-sawn, broad cathedral figure, big knots with cracked hearts
    "floor": dict(length=2.4, light="#edae5e", dark="#b0611d", knot="#a8672a", knot_dark="#6f3b12", gap="#5f3311",
                  depth=(0.0, 0.07), tilt=0.07, ring=(0.016, 0.023), contrast=0.78, figure=0.3, warp=0.03,
                  knots=(1, 2), knot_r=(0.026, 0.042), gap_px=1.4, bevel_px=4.0, ends=True, seed=70),
}


def C(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])


def _smooth(rng, shape, cells):
    """Smooth value noise, 0..1: a random grid of `cells` (rows, cols) blown up to `shape`."""
    (h, w), (cy, cx) = shape, cells
    g = rng.random((cy + 1, cx + 1))
    fy, fx = np.linspace(0, cy, h, endpoint=False), np.linspace(0, cx, w, endpoint=False)
    iy, ix = fy.astype(int), fx.astype(int)
    ty, tx = fy - iy, fx - ix
    ty, tx = (ty * ty * (3 - 2 * ty))[:, None], (tx * tx * (3 - 2 * tx))[None, :]
    a, b = g[iy][:, ix], g[iy][:, ix + 1]
    c, d = g[iy + 1][:, ix], g[iy + 1][:, ix + 1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def _step(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def board(kind, variant):
    """One board: (rgb, height), each (PX_H, PX_W[, 3]), sRGB 0..1, row 0 at the board's top end."""
    k = KINDS[kind]
    rng = np.random.default_rng(k["seed"] + variant * 13)
    L = k["length"]
    jj, ii = np.mgrid[0:PX_H, 0:PX_W]
    x = (ii + 0.5) / PX_W * BOARD_W - BOARD_W / 2
    y = (jj + 0.5) / PX_H * L

    # the tree: its pith runs nearly along the board, wandering sideways and in depth, so the face
    # cuts the rings at a changing distance. Shallow cuts give cathedrals, deep ones straight lines.
    wob = _smooth(rng, (PX_H, 1), (5, 1))
    wob2 = _smooth(rng, (PX_H, 1), (4, 1))
    pith = rng.uniform(-0.08, 0.08) + rng.uniform(-0.03, 0.03) * (y - L / 2) + 0.06 * (wob - 0.5)
    depth = rng.uniform(*k["depth"]) + rng.choice((-1, 1)) * rng.uniform(0.4, 1.0) * k["tilt"] * (y - L / 2) + 0.03 * (wob2 - 0.5)
    r = np.sqrt((x - pith) ** 2 + depth ** 2 + 0.004 ** 2)
    r = r + 0.0045 * (_smooth(rng, (PX_H, PX_W), (22, 5)) - 0.5) + k["warp"] * (_smooth(rng, (PX_H, PX_W), (6, 2)) - 0.5)

    # knots push the rings aside into an eye, then sit in it
    knots = []
    for _ in range(rng.integers(k["knots"][0], k["knots"][1] + 1)):
        kr = rng.uniform(*k["knot_r"])
        kx, ky = rng.uniform(-BOARD_W / 2 + 0.05, BOARD_W / 2 - 0.05), rng.uniform(0.2, L - 0.2)
        if any(abs(ky - o[1]) < 0.35 for o in knots):
            continue
        knots.append((kx, ky, kr))
        r = r + (0.9 + 1.6 * kr / 0.03) * kr * np.exp(-(((x - kx) / (2.4 * kr)) ** 2 + ((y - ky) / (7.0 * kr)) ** 2))

    ring = rng.uniform(*k["ring"])
    t = r / ring + rng.uniform(0, 1)
    f = t - np.floor(t)
    late = f ** 2.6                                                   # each ring darkens to its edge
    f2 = t * 3.0 - np.floor(t * 3.0)
    late = late * 0.85 + 0.15 * f2 ** 3                               # and has finer lines within it
    tone = np.sin(np.floor(t) * 12.9898 + variant) * 43758.5453
    tone = tone - np.floor(tone)                                      # a different weight for every ring
    figure = _smooth(rng, (PX_H, PX_W), (7, 2))
    streak = _smooth(rng, (PX_H, PX_W), (16, 60))
    v = 0.16 + k["contrast"] * late * (0.55 + 0.45 * tone) + k["figure"] * (figure - 0.5) + 0.12 * (streak - 0.5)
    light, dark = C(k["light"]), C(k["dark"])
    rgb = light + (dark - light) * np.clip(v, 0, 1)[..., None]
    hgt = 0.06 * (1 - late) + 0.05 * streak

    for kx, ky, kr in knots:
        dx, dy = x - kx, y - ky
        d = np.sqrt(dx * dx + (dy * 0.82) ** 2)
        kt = d / (kr * 0.24)
        kf = (kt - np.floor(kt)) ** 2
        kcol = C(k["knot"]) + (C(k["knot_dark"]) - C(k["knot"])) * (0.25 + 0.6 * kf)[..., None]
        kcol = kcol + (C(k["knot_dark"]) - kcol) * (np.exp(-((d - kr) / (0.16 * kr)) ** 2) * 0.75)[..., None]
        ang = np.arctan2(dy, dx)
        for a in rng.uniform(0, 2 * math.pi, rng.integers(2, 5)):     # cracks from the heart
            off = np.abs(np.sin(ang - a)) * d
            crack = (np.cos(ang - a) > 0) & (off < 0.0011) & (d < kr * rng.uniform(0.45, 0.8))
            kcol = np.where(crack[..., None], C(k["knot_dark"]) * 0.7, kcol)
        alpha = 1 - _step(kr * 0.92, kr * 1.12, d)
        rgb = rgb + (kcol - rgb) * alpha[..., None]
        hgt = hgt - 0.12 * alpha

    rgb = rgb * rng.uniform(0.95, 1.04) * (1 + rng.uniform(-0.025, 0.025) * np.array([1.0, 0.0, -1.0]))

    # the long edges: a bevel into the gap between boards (and, on a floor board, the two ends)
    e = np.minimum(ii + 0.5, PX_W - ii - 0.5).astype(float)
    if k["ends"]:
        e = np.minimum(e, np.minimum(jj + 0.5, PX_H - jj - 0.5) * 1.3)
    gap = 1 - _step(k["gap_px"] * 0.55, k["gap_px"] * 1.25, e)
    edge = 1 - _step(k["gap_px"], k["gap_px"] + k["bevel_px"], e)
    rgb = rgb * (1 - 0.1 * edge[..., None])
    rgb = rgb + (C(k["gap"]) - rgb) * gap[..., None]
    hgt = hgt + 1.0 * _step(0.0, k["gap_px"] + k["bevel_px"], e)
    return np.clip(rgb, 0, 1), hgt


def normal_from_height(hgt, strength):
    """A tangent-space normal map (OpenGL, +Y up) from a height image (row 0 at the top)."""
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * strength
    dy = (np.roll(hgt, 1, axis=0) - np.roll(hgt, -1, axis=0)) * strength
    n = np.dstack([-dx, -dy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def atlas(kind):
    """The five boards of a kind side by side: (rgb, normal), each (PX_H, 5 * PX_W, 3)."""
    boards = [board(kind, i) for i in range(VARIANTS)]
    return (np.concatenate([b[0] for b in boards], axis=1),
            np.concatenate([normal_from_height(b[1], 2.2) for b in boards], axis=1))


if __name__ == "__main__":
    import os
    import sys

    from PIL import Image

    os.makedirs(sys.argv[1], exist_ok=True)
    for kind in KINDS:
        rgb, nrm = atlas(kind)
        Image.fromarray((rgb * 255).astype("uint8")).save(os.path.join(sys.argv[1], kind + "_planks.png"))
        Image.fromarray((nrm * 255).astype("uint8")).save(os.path.join(sys.argv[1], kind + "_planks_n.png"))
