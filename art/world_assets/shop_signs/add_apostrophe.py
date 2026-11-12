"""Paints a carved apostrophe into the Mayors Office reference: Mayor's Office (Alex, 2026-11-12).

Run once, on the reference without one: uv run --no-project --with numpy --with pillow python
art/world_assets/shop_signs/add_apostrophe.py <in.png> art/world_assets/shop_signs/ref/sign_mayors_office.png
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(float)
S = 4  # supersampling
X0, Y0, W, H = 960, 285, 60, 75  # the patch worked on
big = Image.new("L", (W * S, H * S), 0)
d = ImageDraw.Draw(big)
def p(x, y):
    return ((x - X0) * S, (y - Y0) * S)
cx, cy, r = 992.0, 309.0, 10.0
d.ellipse([p(cx - r, cy - r), p(cx + r, cy + r)], fill=255)
d.polygon([p(cx - r * 0.95, cy + 1), p(cx + r * 0.9, cy + 3), p(cx + 4, cy + 16), p(cx - 3, cy + 26), p(cx - 7.5, cy + 27.5), p(cx - 5, cy + 16)], fill=255)
mask = np.asarray(big.resize((W, H), Image.LANCZOS)).astype(float) / 255.0
# soft drop shadow down and to the right, as under the letters
sh = Image.fromarray((mask * 255).astype(np.uint8)).transform((W, H), Image.AFFINE, (1, 0, -2, 0, 1, -4)).filter(ImageFilter.GaussianBlur(3))
shadow = np.asarray(sh).astype(float) / 255.0
patch = a[Y0:Y0 + H, X0:X0 + W].copy()
patch *= (1.0 - 0.38 * shadow)[..., None]
# the carving: cream face, a bright lip top-left, a warm darker edge bottom-right
er = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))).astype(float) / 255.0
edge = np.clip(mask - er, 0, 1)
yy, xx = np.mgrid[0:H, 0:W]
gx = np.gradient(mask, axis=1)
gy = np.gradient(mask, axis=0)
lit = np.clip((gx + gy) * 3.0, -1, 1)  # >0 on the top-left edge (mask rises toward the inside)
cream = np.array([251, 212, 169.0])
col = np.broadcast_to(cream, patch.shape).copy()
col = col * (1 - 0.06 * (yy - (cy - Y0)) / H)[..., None]  # a little shade toward the bottom
hi = np.array([255, 243, 212.0])
lo = np.array([214, 140, 86.0])
w_hi = (edge * np.clip(lit, 0, 1))[..., None]
w_lo = (edge * np.clip(-lit, 0, 1))[..., None]
col = col * (1 - w_hi - w_lo) + hi * w_hi + lo * w_lo
out = patch * (1 - mask[..., None]) + col * mask[..., None]
a[Y0:Y0 + H, X0:X0 + W] = out
Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(dst)
