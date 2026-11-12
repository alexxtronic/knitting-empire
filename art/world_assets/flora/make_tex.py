"""Paints the ground-cover, bush, hedge and flower textures (run with:
uv run --no-project --with numpy --with pillow python art/world_assets/flora/make_tex.py)."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tex")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(3)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def normal_png(h, strength, path, wrap=True):
    r = np.roll if wrap else None
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * strength
    n = np.dstack([-dx, -dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(path)


import json
_RAD = json.load(open(os.path.join(HERE, "..", "leaf_shapes.json")))["leaf_green"]["radii"]


def maple_poly(cx, cy, size, ang):
    """The traced maple outline (the same one the map trees' leaves use), `size` = its reach in pixels."""
    out = []
    for deg in range(0, 360, 8):
        r = _RAD[deg] * size
        a = math.radians(deg) + ang
        out.append((cx + math.sin(a) * r, cy - math.cos(a) * r))
    return out


def leaf_poly(cx, cy, length, width, ang, pts=10):
    out = []
    for i in range(pts * 2):
        t = i / (pts * 2) * 2 * math.pi
        # pointed oval: x along the leaf, y across
        s = math.cos(t)
        x = s * length / 2
        y = math.sin(t) * width / 2 * (1 - 0.35 * abs(s) ** 2)
        out.append((cx + x * math.cos(ang) - y * math.sin(ang), cy + x * math.sin(ang) + y * math.cos(ang)))
    return out


def leafy(name, bg, greens, count, size, berries=None, seed=0):
    r = np.random.default_rng(seed)
    N = 512
    im = Image.new("RGB", (N, N), hexc(bg))
    hm = Image.new("L", (N, N), 30)
    d, dh = ImageDraw.Draw(im), ImageDraw.Draw(hm)
    leaves = [(r.uniform(0, N), r.uniform(0, N), r.uniform(*size), r.uniform(0, 2 * math.pi), r.random()) for _ in range(count)]
    leaves.sort(key=lambda l: l[4])
    for x, y, s, a, t in leaves:
        col = np.array(hexc(greens[min(int(t * len(greens)), len(greens) - 1)]), float) * r.uniform(0.93, 1.07, 3)
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                cx, cy = x + ox, y + oy
                if -s < cx < N + s and -s < cy < N + s:
                    d.polygon(maple_poly(cx, cy, s * 0.62, a), fill=tuple(int(min(255, c)) for c in col))
                    d.line([(cx, cy), (cx + math.sin(a) * s * 0.5, cy - math.cos(a) * s * 0.5)],
                           fill=tuple(int(min(255, c * 1.15)) for c in col), width=2)
                    dh.polygon(maple_poly(cx, cy, s * 0.62, a), fill=int(50 + 190 * t))
    if berries:
        for _ in range(berries):
            x, y = r.uniform(0, N), r.uniform(0, N)
            rr = r.uniform(6, 9)
            for ox in (-N, 0, N):
                for oy in (-N, 0, N):
                    d.ellipse([x + ox - rr, y + oy - rr, x + ox + rr, y + oy + rr], fill=hexc("#85262e"))
                    d.ellipse([x + ox - rr * 0.4 - 2, y + oy - rr * 0.5 - 2, x + ox - rr * 0.4 + 2, y + oy - rr * 0.5 + 2], fill=hexc("#c07070"))
                    dh.ellipse([x + ox - rr, y + oy - rr, x + ox + rr, y + oy + rr], fill=255)
    im = im.filter(ImageFilter.GaussianBlur(0.7))
    hm = hm.filter(ImageFilter.GaussianBlur(1.4))
    a = np.asarray(im).astype(float) / 255
    h = np.asarray(hm).astype(float) / 255
    a = np.clip(a * (0.8 + 0.32 * h[..., None]), 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    normal_png(h, 4.5, os.path.join(OUT, name + "_n.png"))


leafy("bush_leaf", "#2d4220", ["#3f5b28", "#456229", "#4b6a2d", "#527230", "#587935"], 300, (40, 64), seed=1)
leafy("hedge_leaf", "#243a1a", ["#2f4a21", "#34512a", "#395730", "#3f5d33"], 520, (30, 46), seed=2)
leafy("berry_leaf", "#2d4220", ["#3f5b28", "#456229", "#4b6a2d", "#527230"], 300, (40, 60), berries=70, seed=4)
leafy("autumn_leaf", "#5a3318", ["#7e4a20", "#88521f", "#925b26", "#9c652c"], 300, (40, 64), seed=5)

# grass blade: u across (0..1), v from the root (0) to the tip (1); the image's top row is the tip
W, H = 64, 256
v = np.linspace(1, 0, H)[:, None]
u = np.linspace(-1, 1, W)[None, :]
root, mid, tip = np.array(hexc("#263f18"), float), np.array(hexc("#436a22"), float), np.array(hexc("#7b9a37"), float)
t = v
col = np.where(t[..., None] < 0.5, root + (mid - root) * (t[..., None] / 0.5), mid + (tip - mid) * ((t[..., None] - 0.5) / 0.5))
rib = np.exp(-(u / 0.14) ** 2)[..., None]
col = col * (1 + 0.18 * rib) * (0.94 + 0.12 * rng.random((H, W, 1)))
Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "blade.png"))
hb = 0.6 * rib[..., 0] + 0.15 * rng.random((H, W))
normal_png(np.repeat(hb, 1, 0), 3.0, os.path.join(OUT, "blade_n.png"))

# clover: a rounded leaflet with a pale chevron
S = 256
im = Image.new("RGB", (S, S), hexc("#37602a"))
d = ImageDraw.Draw(im)
for i in range(60):
    cx, cy = rng.uniform(0, S), rng.uniform(0, S)
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=tuple(int(c * rng.uniform(0.9, 1.1)) for c in hexc("#427030")))
d.line([(S * 0.18, S * 0.62), (S * 0.5, S * 0.36), (S * 0.82, S * 0.62)], fill=hexc("#b9cf94"), width=14)
d.line([(S * 0.5, S * 0.55), (S * 0.5, S * 0.95)], fill=hexc("#6fb04a"), width=6)
im = im.filter(ImageFilter.GaussianBlur(1.2))
im.save(os.path.join(OUT, "clover.png"))
normal_png(np.asarray(im.convert("L")).astype(float) / 255, 2.0, os.path.join(OUT, "clover_n.png"))

# petals: radial gradient along the petal (v), soft edge
for name, a, b in (("petal_white", "#fbf8ee", "#efe3b8"), ("petal_yellow", "#ffe36a", "#f2b51e"), ("petal_purple", "#c6a2e8", "#7c4cb8"), ("petal_pink", "#f6b8d2", "#d86aa0"), ("petal_red", "#e8402e", "#a8161c")):
    v = np.linspace(0, 1, 128)[:, None]
    ca, cb = np.array(hexc(a), float), np.array(hexc(b), float)
    col = ca + (cb - ca) * (1 - v)[..., None] * np.ones((128, 64, 1))
    col = col * (0.96 + 0.08 * rng.random((128, 64, 1)))
    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))


def cluster(name, greens, seed, n=30):
    """A cut-out cluster of overlapping maple leaves (RGBA), like the leaf cards on the map trees."""
    r = np.random.default_rng(seed)
    S = 512
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    leaves = []
    for _ in range(n):
        a = r.uniform(0, 2 * math.pi)
        rr = 175 * math.sqrt(r.random())
        leaves.append((S / 2 + math.cos(a) * rr, S / 2 + math.sin(a) * rr, r.uniform(62, 92), r.uniform(0, 2 * math.pi), r.random()))
    leaves.sort(key=lambda l: l[4])
    for x, y, s_, ang, t in leaves:
        col = np.array(hexc(greens[min(int(t * len(greens)), len(greens) - 1)]), float) * r.uniform(0.94, 1.06, 3)
        col = tuple(int(min(255, c)) for c in col) + (255,)
        pts = maple_poly(x, y, s_, ang)
        d.polygon(pts, fill=col)
        d.line(pts + [pts[0]], fill=tuple(int(c * 0.78) for c in col[:3]) + (255,), width=2)
        tip = (x + math.sin(ang) * s_ * 0.85, y - math.cos(ang) * s_ * 0.85)
        d.line([(x, y), tip], fill=tuple(int(min(255, c * 1.18)) for c in col[:3]) + (255,), width=3)
        for sa in (-0.7, 0.7):
            d.line([(x, y), (x + math.sin(ang + sa) * s_ * 0.6, y - math.cos(ang + sa) * s_ * 0.6)], fill=tuple(int(min(255, c * 1.1)) for c in col[:3]) + (255,), width=2)
    im.save(os.path.join(OUT, name + ".png"))


cluster("cluster_green", ["#3b5726", "#446229", "#4d6b2e", "#587733", "#65823a", "#748f40"], 21)
cluster("cluster_dark", ["#2f4a21", "#37532a", "#405d2e", "#496833", "#547438"], 22)
cluster("cluster_autumn", ["#7a431c", "#8a4f20", "#9a5b25", "#a86a2c", "#b57a35"], 23)
print("flora textures written")
