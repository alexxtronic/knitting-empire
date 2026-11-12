"""Lift each sign's painted face out of Alex's reference (tex/<sign>_face.png) and trace its board.

Alex, 2026-11-12: get the lettering exactly like the reference, the same way as the Maple Grove
welcome sign (welcome_sign/make_face.py): the words, emblem, sprigs, flourish and cream border are
the reference itself, laid on the modelled board as a texture, with a normal map that lifts the
cream work. These references are already square-on (2000 x 667), so no perspective warp is needed:
a reference pixel maps straight to the board (build.py's P()).

For each sign this writes, into tex/:
  <sign>_face.png     the reference cropped to the board (pixels FX0..FX1, FY0..FY1)
  <sign>_face_n.png   the normal map: the cream work raised a little
  <sign>_board.json   the board's outline, traced off the picture: per column, the top and bottom
                      edge in reference pixels (the hanger's straps, which cross the top edge, are
                      bridged from either side)
  <sign>_trace.png    the outline drawn over the reference, to check the trace

Run: uv run --no-project --with numpy --with pillow python art/world_assets/shop_signs/make_faces.py
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SIGNS = ["willow_homes", "builders_delight", "yarn_barn", "heart_bakery", "mayors_office"]
FX0, FX1, FY0, FY1 = 120, 1880, 40, 640  # the crop: the whole board with some margin
STEP = 6  # trace every STEP columns
SHRINK = 3  # pull the traced edge in a few pixels, so no white fringe shows on the model's edge
ROD_LOW = 92  # the rod's underside (px): the board's hump runs up behind it
STRAPS = (455, 1535)  # where the hanger's straps and rings cross the board's top edge (px)


def background(rgb):
    """The reference's white backdrop (and its soft grey shadow): bright and colourless."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (np.minimum(np.minimum(r, g), b) > 205) & (np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b) < 30)


def outside(rgb):
    """The backdrop that is joined to the picture's edges (flood-filled in from the sides, the bottom
    and just under the rod), so near-white paint inside the board never counts."""
    bg = background(rgb)
    m = Image.fromarray((bg * 255).astype(np.uint8)).copy()  # (fromarray shares a read-only buffer)
    h, w = bg.shape
    seeds = [(0, y) for y in range(100, h, 40)] + [(w - 1, y) for y in range(100, h, 40)] + [(x, h - 1) for x in range(0, w, 50)]
    seeds += [(x, ROD_LOW + 4) for x in range(0, w, 8)]  # the pockets walled in by rod, straps and hump
    for seed in seeds:
        if m.getpixel(seed) == 255:
            ImageDraw.floodfill(m, seed, 128)
    return np.asarray(m) == 128


def trace(rgb):
    out = outside(rgb)
    h, w = out.shape
    mid = 420  # a row through the middle of every board
    cols, top, bot = [], [], []
    for x in range(0, w, STEP):
        col = out[:, x]
        if col[mid]:
            continue  # off the board's end
        up = np.nonzero(col[:mid][::-1])[0]
        dn = np.nonzero(col[mid:])[0]
        if len(dn) == 0:
            continue
        cols.append(x)
        # no backdrop above: the board's hump runs up behind the rod; stop at the rod's underside
        top.append(max(mid - up[0] + SHRINK, ROD_LOW) if len(up) else ROD_LOW)
        bot.append(mid + dn[0] - 1 - SHRINK)
    cols, top, bot = np.array(cols), np.array(top, float), np.array(bot, float)
    # bridge the straps: there the column runs on up through ring and strap into the rod
    for sx in STRAPS:
        near = np.abs(cols - sx) < 80
        ok = ~near & (np.abs(cols - sx) < 170)
        if near.any() and ok.any():
            top[near] = np.interp(cols[near], cols[ok], top[ok])
    k = 5
    top = np.convolve(np.pad(top, 2, mode="edge"), np.ones(k) / k, mode="valid")
    bot = np.convolve(np.pad(bot, 2, mode="edge"), np.ones(k) / k, mode="valid")
    return cols, top, bot


def main():
    os.makedirs(os.path.join(HERE, "tex"), exist_ok=True)
    for key in SIGNS:
        ref = Image.open(os.path.join(HERE, "ref", "sign_%s.png" % key)).convert("RGB")
        rgb = np.asarray(ref).astype(float)
        cols, top, bot = trace(rgb)
        x0, x1 = int(cols[0]) + SHRINK, int(cols[-1]) - SHRINK
        cols = np.clip(cols, x0, x1)
        with open(os.path.join(HERE, "tex", "%s_board.json" % key), "w") as f:
            json.dump({"x": [int(c) for c in cols], "top": [round(float(t), 1) for t in top],
                       "bot": [round(float(b), 1) for b in bot], "crop": [FX0, FX1, FY0, FY1]}, f)

        face = ref.crop((FX0, FY0, FX1, FY1))
        # paint the backdrop round the board with the board's own edge colour, so mip-mapping and
        # filtering at the model's edge never pull in white
        a = np.asarray(face).astype(float)
        bg = outside(np.asarray(ref).astype(float))[FY0:FY1, FX0:FX1]
        fill = a[~bg].reshape(-1, 3)
        fill = np.median(fill[fill.sum(1) < 330], axis=0)  # the dark wood
        a[bg] = fill
        Image.fromarray(a.astype(np.uint8)).save(os.path.join(HERE, "tex", "%s_face.png" % key))

        # relief: the cream work (warm and bright) stands up off the wood
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        cream = ((r > 195) & (g > 160) & (r - b > 20)).astype(np.uint8) * 255
        hgt = np.asarray(Image.fromarray(cream).filter(ImageFilter.GaussianBlur(2.5))).astype(float) / 255
        gy, gx = np.gradient(hgt)
        n = np.dstack((-gx * 5.0, gy * 5.0, np.ones_like(hgt)))
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(HERE, "tex", "%s_face_n.png" % key))

        chk = ref.copy()
        d = ImageDraw.Draw(chk)
        d.line(list(zip(cols, top)) + list(zip(cols[::-1], bot[::-1])) + [(cols[0], top[0])], fill=(0, 200, 255), width=3)
        chk.save(os.path.join(HERE, "tex", "%s_trace.png" % key))
        print(key, "board x %d..%d, top %.0f..%.0f, bottom %.0f..%.0f" % (x0, x1, top.min(), top.max(), bot.min(), bot.max()))


if __name__ == "__main__":
    main()
