"""Paints the tree's tileable textures (run with: uv run --no-project --with numpy --with pillow python make_tex.py):
canopy_albedo/normal = a dense layer of overlapping maple leaves in lime and leaf greens, bark_albedo/normal =
deep vertical bark grooves. Leaf outlines come from the traced green leaf (../leaf_shapes.json)."""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tex")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)
shape = json.load(open(os.path.join(HERE, "..", "leaf_shapes.json")))["leaf_green"]
radii = np.array(shape["radii"])


def outline(scale, rot):
    pts = []
    for deg in range(0, 360, 6):
        r = radii[deg] * scale
        a = math.radians(deg) + rot
        pts.append((math.sin(a) * r, -math.cos(a) * r))
    return pts


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


N = 1024
GREENS = ["#c6df2c", "#b2d329", "#9cc727", "#86b926", "#70a723", "#5a911f"]
albedo = Image.new("RGB", (N, N), hexc("#3f7420"))
height = Image.new("L", (N, N), 40)
da, dh = ImageDraw.Draw(albedo), ImageDraw.Draw(height)
leaves = []
for i in range(120):
    leaves.append((rng.uniform(0, N), rng.uniform(0, N), rng.uniform(95, 140), rng.uniform(0, 2 * math.pi), rng.random()))
leaves.sort(key=lambda l: l[4])  # darker leaves first, brighter ones on top
for x, y, s, rot, t in leaves:
    base = np.array(hexc(GREENS[min(int((1 - t) * len(GREENS)), len(GREENS) - 1)]), float)
    base = np.clip(base * rng.uniform(0.92, 1.06, 3), 0, 255)
    for ox in (-N, 0, N):
        for oy in (-N, 0, N):
            cx, cy = x + ox, y + oy
            if cx < -s or cx > N + s or cy < -s or cy > N + s:
                continue
            pts = [(cx + px, cy + py) for px, py in outline(s, rot)]
            da.polygon(pts, fill=tuple(int(c) for c in base))
            # lighter centre vein and darker rim so each leaf reads as its own
            tip = (cx + math.sin(rot) * s * 0.85, cy - math.cos(rot) * s * 0.85)
            da.line([(cx, cy), tip], fill=tuple(int(min(255, c * 1.12)) for c in base), width=3)
            dh.polygon(pts, fill=int(60 + 170 * t))
            dh.line([(cx, cy), tip], fill=int(75 + 170 * t), width=3)
albedo = albedo.filter(ImageFilter.GaussianBlur(0.8))
height = height.filter(ImageFilter.GaussianBlur(1.6))
a = np.asarray(albedo).astype(float) / 255
# warm tint towards the top of each leaf layer: brighten by height a little
h = np.asarray(height).astype(float) / 255
a = np.clip(a * (0.78 + 0.34 * h[..., None]), 0, 1)
Image.fromarray((a * 255).astype(np.uint8)).save(os.path.join(OUT, "canopy_albedo.png"))


def normal_png(hgt, strength, path):
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * strength
    dy = (np.roll(hgt, 1, 0) - np.roll(hgt, -1, 0)) * strength
    n = np.dstack([-dx, -dy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(path)


normal_png(h, 5.0, os.path.join(OUT, "canopy_normal.png"))

# --- bark: vertical grooves ------------------------------------------------------------------------
M = 512
xs = np.arange(M)
cols = np.zeros(M)
for k, w in ((7, 1.0), (15, 0.6), (31, 0.35)):
    ph = rng.uniform(0, 2 * math.pi)
    cols += w * np.sin(xs / M * 2 * math.pi * k + ph)
cols = (cols - cols.min()) / (cols.max() - cols.min())
yy = np.arange(M)[:, None]
wob = 0.5 + 0.5 * np.sin(yy / M * 2 * math.pi * 3 + cols[None, :] * 9)
noise = rng.random((M, M))
noise = np.asarray(Image.fromarray((noise * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.4))).astype(float) / 255
g = np.clip(cols[None, :] * 0.7 + wob * 0.15 + noise * 0.4, 0, 1)
dark, light = np.array([0.30, 0.19, 0.11]), np.array([0.55, 0.36, 0.21])
col = dark + (light - dark) * g[..., None]
Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "bark_albedo.png"))
normal_png(g, 6.0, os.path.join(OUT, "bark_normal.png"))
print("textures written")
