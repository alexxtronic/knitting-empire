"""Silhouette IoU of a wardrobe review render against the reference, in the same frame (the review
camera is the reference's own), and the rows and columns where they differ most.

    uv run --no-project --with pillow --with numpy python art/world_assets/house_furniture/wardrobe_iou.py <render.png> [overlay.png]
"""
import sys

import numpy as np
from PIL import Image

REF = "art/world_assets/house_furniture/ref/wardrobe.png"


def mask(path):
    a = np.asarray(Image.open(path).convert("RGB").resize((1024, 1536))).astype(int)
    return (a.min(axis=2) < 235)


r, m = mask(REF), mask(sys.argv[1])
iou = (r & m).sum() / max(1, (r | m).sum())
print("IoU %.3f" % iou)
for y in (60, 140, 200, 260, 400, 800, 1200, 1340, 1420, 1480, 1500):
    rx, mx = np.nonzero(r[y])[0], np.nonzero(m[y])[0]
    print("row %4d  ref %s  render %s" % (y, (rx.min(), rx.max()) if rx.size else "-", (mx.min(), mx.max()) if mx.size else "-"))
ys_r, ys_m = np.nonzero(r.any(1))[0], np.nonzero(m.any(1))[0]
print("rows ref %d..%d  render %d..%d" % (ys_r.min(), ys_r.max(), ys_m.min(), ys_m.max()))
if len(sys.argv) > 2:
    o = np.zeros(r.shape + (3,), np.uint8) + 255
    o[r & ~m] = (220, 60, 60)
    o[m & ~r] = (60, 90, 220)
    o[r & m] = (170, 170, 170)
    Image.fromarray(o).save(sys.argv[2])
