"""Carpet maps for Marcus's house (Alex, 2026-11-17: "carpet textures"): seamless greyscale albedo and
normal maps that the game tints per floor (split_house.gd _floor_mat()).

    carpet_pile   a dense cut-pile carpet: fine tufts, a faint twist in each, soft shading drifts
                  and the odd vacuum track, for the grey, blue and cream carpets (0.6 m a tile)
    carpet_shag   a 70s-90s long shag: fat twisted strands lying every which way in clumps, deep
                  gaps between them, for the basement's green shag (0.5 m a tile)

Drawn from noise and strokes, no photographs, every map tiling on both axes.

    uv run --no-project --with numpy --with pillow python art/world_assets/carpet/build.py

Writes assets/textures/carpet/<id>.png and <id>_n.png (then import in Godot).
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "..", "assets", "textures", "carpet")
N = 512


def noise(n, beta, seed):
    """Seamless 1/f^beta noise in 0..1 (FFT, so it wraps)."""
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / r ** (beta * 0.5)
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / out.max()


def stamp(h, x, y, ang, length, width, value):
    """A soft strand from (x, y) along `ang`, added into height map h with wrap-round."""
    n = h.shape[0]
    steps = max(2, int(length))
    for i in range(steps):
        t = i / (steps - 1)
        cx = x + np.cos(ang) * length * t
        cy = y + np.sin(ang) * length * t
        r = int(np.ceil(width))
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                d = np.hypot(dx, dy) / max(width, 0.5)
                if d < 1.0:
                    yy = int(cy + dy) % n
                    xx = int(cx + dx) % n
                    # rounded strand, brightest along its spine, fading toward the tip
                    v = value * (1.0 - d * d) * (1.0 - 0.45 * t)
                    if v > h[yy, xx]:
                        h[yy, xx] = v


def normal_map(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    l = np.sqrt(gx * gx + gy * gy + nz * nz)
    n = np.stack([-gx / l, gy / l, nz / l], -1)  # OpenGL green up, as Godot wants
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, alb, nrm):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8), "L").convert("RGB").save(os.path.join(OUT, name + ".png"))
    Image.fromarray(nrm, "RGB").save(os.path.join(OUT, name + "_n.png"))
    print("wrote", name)


def pile():
    # tufts: a fine cellular speckle, each tuft a little dome with a twist highlight
    rng = np.random.default_rng(3)
    fine = noise(N, 0.2, 1)
    tuft = noise(N, 0.6, 2)
    h = 0.55 * fine + 0.45 * tuft
    # twist: short diagonal glints
    for _ in range(9000):
        x, y = rng.uniform(0, N, 2)
        stamp(h, x, y, rng.uniform(0.5, 1.1), rng.uniform(2, 4), 0.9, rng.uniform(0.75, 1.0))
    h = (h - h.min()) / (h.max() - h.min())
    drift = noise(N, 2.6, 4)  # soft shading drifts across the room
    tracks = 0.5 + 0.5 * np.sin((np.arange(N)[None, :] / N) * 2 * np.pi * 3 + 1.3 * noise(N, 2.8, 5) * 2 * np.pi)
    alb = 0.62 + 0.22 * h + 0.10 * (drift - 0.5) + 0.03 * (tracks - 0.5)
    alb = alb / alb.mean() * 0.78  # mean light grey, so the tint sets the colour
    save("carpet_pile", alb, normal_map(h, 3.0))


def shag():
    rng = np.random.default_rng(7)
    h = 0.15 * noise(N, 1.0, 8)
    clump = noise(N, 2.4, 9)  # where strands lie one way or another
    for _ in range(5200):
        x, y = rng.uniform(0, N, 2)
        base = clump[int(y) % N, int(x) % N] * 2 * np.pi * 1.5
        stamp(h, x, y, base + rng.normal(0, 0.5), rng.uniform(10, 22), rng.uniform(1.6, 2.6), rng.uniform(0.6, 1.0))
    h = (h - h.min()) / (h.max() - h.min())
    alb = 0.38 + 0.62 * h ** 0.8
    alb = alb / alb.mean() * 0.74
    save("carpet_shag", alb, normal_map(h, 5.0))


if __name__ == "__main__":
    pile()
    shag()
