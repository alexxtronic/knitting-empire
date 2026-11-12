"""A knitted colourwork pattern as a grid of stitches, and the maps that draw each stitch as a knit V.
Plain numpy, so it runs in Blender (build.py) and outside it (to look at the pattern).

    uv run --no-project --with numpy --with pillow python art/world_assets/house_furniture/knit.py out.png
"""
import math

import numpy as np


def rug_pattern(W=65, L=89):
    """The rug's colourwork, True where a stitch is cream: a frame, a panel of diamonds and a daisy
    at each end, and in the field an eight-pointed star between two leafy sprigs with berries.
    Lines and diamonds are set stitch by stitch; the round shapes are drawn finer than the
    stitches and each stitch takes the colour that covers most of it."""
    p = np.zeros((L, W), dtype=bool)
    yy, xx = np.mgrid[0:L, 0:W]
    cx, cy = W // 2, L // 2
    S = 4
    fy, fx = np.mgrid[0:L * S, 0:W * S]
    fx, fy = (fx + 0.5) / S - 0.5, (fy + 0.5) / S - 0.5
    fine = np.zeros(fx.shape, dtype=bool)       # everything that is the same after a half turn
    sprig = np.zeros(fx.shape, dtype=bool)

    # frame and the two lines that close off the end panels
    for k in (2, 3):
        p[k, 2:W - 2] = p[L - 1 - k, 2:W - 2] = True
        p[2:L - 2, k] = p[2:L - 2, W - 1 - k] = True
        p[16 + k, 2:W - 2] = p[L - 17 - k, 2:W - 2] = True

    def diamond(x0, y0, r):
        d = np.abs(xx - x0) + np.abs(yy - y0)
        p[(d == r) | (d == r - 1)] = True
        p[y0, x0] = True

    def petals(x0, y0, reach, long, wide, start=0.0):
        """Eight pointed petals round (x0, y0): each starts `start` out, is `long[k % 2]` long and
        `wide` at its widest, a third of the way along."""
        for k in range(8):
            a = k * math.pi / 4
            along = (fx - x0) * math.cos(a) + (fy - y0) * math.sin(a) - start
            across = np.abs(-(fx - x0) * math.sin(a) + (fy - y0) * math.cos(a))
            n = long[k % 2]
            w = np.where(along < n * 0.36, 0.25 + (wide - 0.25) * along / (n * 0.36), wide * (n - along) / (n * 0.64))
            fine[(along >= 0) & (along <= n) & (across <= w)] = True

    for y0 in (10, L - 11):
        for k in range(8):
            a = k * math.pi / 4
            fine[(fx - cx - 4.3 * math.cos(a)) ** 2 + (fy - y0 - 4.3 * math.sin(a)) ** 2 <= 1.45 ** 2] = True
        fine[(fx - cx) ** 2 + (fy - y0) ** 2 <= 1.4 ** 2] = True
        for off in (12, 22):
            diamond(cx - off, y0, 4)
            diamond(cx + off, y0, 4)

    petals(cx, cy, 0, (13.5, 11.5), 3.2, start=2.0)
    fine[(fx - cx) ** 2 + (fy - cy) ** 2 <= 1.0 ** 2] = True
    for y0 in (cy - 20, cy + 20):
        diamond(cx, y0, 2)

    P0, P1, P2 = (cx - 10.0, cy + 20.0), (cx - 35.0, cy + 0.0), (cx - 10.0, cy - 20.0)

    def bez(t):
        return ((1 - t) ** 2 * P0[0] + 2 * t * (1 - t) * P1[0] + t * t * P2[0],
                (1 - t) ** 2 * P0[1] + 2 * t * (1 - t) * P1[1] + t * t * P2[1])

    for i in range(161):
        bx, by = bez(0.05 + 0.9 * i / 160)
        sprig |= (fx - bx) ** 2 + (fy - by) ** 2 <= 0.85 ** 2
    for t in (0.14, 0.32, 0.5, 0.68, 0.86):
        (bx, by), (b2x, b2y) = bez(t), bez(t + 0.01)
        tx, ty = b2x - bx, b2y - by
        ln = math.hypot(tx, ty)
        tx, ty = tx / ln, ty / ln
        for side in (-1, 1):                                          # a pair of leaves at each node
            nx, ny = -ty * side, tx * side
            ax, ay = tx * 0.6 + nx * 0.8, ty * 0.6 + ny * 0.8         # each points on and outwards
            lx, ly = bx + ax * 3.0, by + ay * 3.0
            along = (fx - lx) * ax + (fy - ly) * ay
            across = -(fx - lx) * ay + (fy - ly) * ax
            sprig |= (along / 2.6) ** 2 + (across / 1.3) ** 2 <= 1.0
    for (ex, ey), dots in ((bez(0.95), ((2.4, -1.8), (-0.8, -3.2), (3.8, 1.2))), (bez(0.05), ((2.6, 1.6), (-0.6, 3.2)))):
        for ox, oy in dots:
            sprig |= (fx - ex - ox) ** 2 + (fy - ey - oy) ** 2 <= 1.15 ** 2
    fine |= sprig | sprig[::-1, ::-1]
    return p | (fine.reshape(L, S, W, S).mean(axis=(1, 3)) >= 0.45)


def stitch_maps(pat, colours, px=12, fibre=None):
    """Draws every stitch of `pat` (True = colours[1], False = colours[0]; sRGB 0..1 triples) as a
    knit V of plied yarn, columns running down the image. Returns (rgb, height): (L*px, W*px, 3)
    and (L*px, W*px), row 0 at the top. `fibre`: an optional tiling detail map (any size, about 1.0
    on average) multiplied in, a scan of real knit for the yarn's speckle."""
    L, W = pat.shape
    H, Wd = L * px, W * px
    yy, xx = np.mgrid[0:H, 0:Wd]
    U, V = (xx + 0.5) / px, (yy + 0.5) / px
    col, row = np.floor(U).astype(int), np.floor(V).astype(int)
    u = U - col
    best = np.full((H, Wd), -1.0)
    who = np.zeros((H, Wd), dtype=bool)
    twist = np.zeros((H, Wd))
    for dr in (-1, 0, 1):
        r = row + dr
        v = V - r                                   # -1..2: a V's legs run past its own cell
        leg = 0.19 + 0.21 * v                       # the left leg's centre line; the right mirrors it
        left = u < 0.5
        d = np.where(left, np.abs(u - leg), np.abs(u - (1.0 - leg)))
        ends = np.clip((v + 0.42) / 0.3, 0, 1) * np.clip((1.42 - v) / 0.3, 0, 1)
        h = np.sqrt(np.clip(1.0 - (d / 0.2) ** 2, 0, 1)) * ends * (0.82 + 0.18 * np.clip(v, 0, 1))
        ok = (r >= 0) & (r < L)
        h = np.where(ok, h, 0.0)
        take = h > best
        best = np.where(take, h, best)
        who = np.where(take, pat[np.clip(r, 0, L - 1), col], who)
        slant = np.where(left, 1.0, -1.0)
        twist = np.where(take, np.cos(2 * math.pi * (2.6 * v + slant * 2.2 * u)), twist)
    best = np.clip(best, 0, 1)
    base = np.where(who[..., None], np.array(colours[1]), np.array(colours[0]))
    shade = 0.5 + 0.5 * best ** 0.55                 # the gaps between stitches fall dark
    rgb = base * shade[..., None] * (0.955 + 0.045 * twist[..., None])
    height = best * (1.0 + 0.06 * twist)
    if fibre is not None:
        fh, fw = fibre.shape
        rgb = rgb * fibre[yy % fh, xx % fw][..., None]
    return np.clip(rgb, 0, 1), height


if __name__ == "__main__":
    import sys

    from PIL import Image

    pat = rug_pattern()
    rgb, hgt = stitch_maps(pat, ((0.74, 0.16, 0.13), (0.95, 0.87, 0.70)))
    Image.fromarray((rgb.transpose(1, 0, 2)[::-1] * 255).astype("uint8")).save(sys.argv[1])
