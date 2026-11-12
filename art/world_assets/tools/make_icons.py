"""Cuts the six hotbar icons (assets/icons/<tool>.png) out of reference_sheet.png: white paper
and soft shadows become transparent, and only the tool itself (the largest piece) is kept.
Stand-ins until each tool's own model is rendered.
  uv run --no-project --with numpy --with scipy --with pillow python art/world_assets/tools/make_icons.py
"""
import numpy as np
from PIL import Image
from scipy import ndimage

im = np.asarray(Image.open("art/world_assets/tools/reference_sheet.png").convert("RGB")).astype(np.int32)
H, W, _ = im.shape
cells = {"hoe": (0, 0), "watering_can": (1, 0), "shears": (2, 0), "shovel": (0, 1), "axe": (1, 1), "scythe": (2, 1)}
for name, (cx, cy) in cells.items():
    c = im[int(cy * H / 2):int((cy + 1) * H / 2), int(cx * W / 3):int((cx + 1) * W / 3)]
    mx, mn = c.max(axis=2), c.min(axis=2)
    paper = (mn > 150) & (mx - mn < 22)  # white paper and its grey shadow: pale and colourless
    lab, n = ndimage.label(paper)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bg = np.isin(lab, edge[edge > 0])  # only paper that reaches the cell's border
    fg = ndimage.binary_opening(~bg, iterations=2)
    lab, n = ndimage.label(fg)
    big = 1 + int(np.argmax(ndimage.sum(fg, lab, range(1, n + 1))))
    keep = ndimage.binary_fill_holes(lab == big)
    alpha = ndimage.gaussian_filter(keep.astype(float), 0.8)
    alpha = np.clip((alpha - 0.35) * 3.0, 0, 1)
    out = np.dstack([c, (alpha * 255)]).astype(np.uint8)
    ys, xs = np.where(keep)
    out = out[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    t = Image.fromarray(out, "RGBA")
    s = max(t.size) + 8
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(t, ((s - t.size[0]) // 2, (s - t.size[1]) // 2))
    sq.resize((128, 128), Image.LANCZOS).save(f"assets/icons/{name}.png")
