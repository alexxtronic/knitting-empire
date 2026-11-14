"""Lays an animal's review pictures beside its reference sheet (plain Python, Pillow).

    uv run --no-project --with numpy --with pillow python art/world_assets/wildlife/sheet.py <id>

Splits ref/<id>.png into its two views (the side view on the left, the front three-quarter on the
right, at the widest white gap between them), writes them to review/<id>/ref_side.png and
ref_threeq.png, and makes review/<id>/sheet.png: the reference views over the renders, then the
loops. Run the blender-image-to-3d skill's compose_review.py on ref_side.png and side.png for the
silhouette numbers.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def split(path):
    """The two views, cut where grid.py cuts; the side view cropped exactly to its figure (u 0 at the
    nose, v 0 at the ground, 1 at the top), as review.py frames side_world.png."""
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(float)
    ink = a.min(axis=2) < 225
    cols = ink.sum(axis=0) > 2
    w = len(cols)
    best, run = (0, 0), 0
    for x in range(w // 4, 3 * w // 4):
        if not cols[x]:
            run += 1
            if run > best[0]:
                best = (run, x - run + 1)
        else:
            run = 0
    cut = best[1] + best[0] // 2 if best[0] > 5 else w // 2
    ys, xs = np.where(ink[:, :cut])
    side = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return side, trim(im.crop((cut, 0, im.width, im.height)))


def gate(rev, side_ref):
    """Silhouette IoU on the reference's own grid, and where they differ: red where the reference
    has fur and the model hasn't, blue where the model sticks out."""
    path = os.path.join(rev, "side_world.png")
    if not os.path.exists(path):
        return
    r = Image.open(path).convert("RGBA")
    ref = side_ref.resize(r.size, Image.LANCZOS)
    A = np.asarray(ref).astype(float).min(axis=2) < 225
    B = np.asarray(r)[:, :, 3] > 16
    iou = (A & B).sum() / max(1, (A | B).sum())
    out = np.full(A.shape + (3,), 255, np.uint8)
    out[A & B] = (190, 190, 190)
    out[A & ~B] = (225, 40, 40)
    out[B & ~A] = (40, 90, 225)
    h, w = A.shape
    img = Image.fromarray(out)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    for i in range(0, int(w / h * 10) + 1):  # the grid in tenths of the figure's height
        d.line([(i * h / 10, 0), (i * h / 10, h)], fill=(120, 120, 120))
    for j in range(11):
        d.line([(0, h - j * h / 10), (w, h - j * h / 10)], fill=(120, 120, 120))
    img.save(os.path.join(rev, "gate_side.png"))
    msg = "GATE side IoU %.3f (red: the reference's fur the model lacks; blue: the model's extra)" % iou
    print(msg)
    with open(os.path.join(rev, "gate.txt"), "w") as f:
        f.write(msg + "\n")


def trim(im, pad=12):
    a = np.asarray(im).astype(float)
    ink = a.min(axis=2) < 225
    rows, cols = np.where(ink.any(axis=1))[0], np.where(ink.any(axis=0))[0]
    box = (max(0, cols.min() - pad), max(0, rows.min() - pad), min(im.width, cols.max() + pad), min(im.height, rows.max() + pad))
    return im.crop(box)


def on_white(im):
    im = im.convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    return bg.convert("RGB")


def fit(im, h):
    return im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS)


def main(sid):
    rev = os.path.join(HERE, "review", sid)
    side_ref, q_ref = split(os.path.join(HERE, "ref", sid + ".png"))
    side_ref.save(os.path.join(rev, "ref_side.png"))
    gate(rev, side_ref)
    q_ref.save(os.path.join(rev, "ref_threeq.png"))
    H = 360
    rows = []
    side = trim(on_white(Image.open(os.path.join(rev, "side.png"))))
    clay = trim(on_white(Image.open(os.path.join(rev, "side_clay.png"))))
    q = trim(on_white(Image.open(os.path.join(rev, "threeq.png"))))
    rows.append([fit(side_ref, H), fit(q_ref, H)])
    rows.append([fit(side, H), fit(q, H), fit(clay, H // 2)])
    loops = sorted({f.split("_")[1] for f in os.listdir(rev) if f.startswith("loop_")})
    for name in loops:
        frames = [trim(on_white(Image.open(os.path.join(rev, "loop_%s_%d.png" % (name, i))))) for i in range(6)]
        rows.append([fit(f, H // 2) for f in frames])
    W = max(sum(i.width for i in r) + 16 * len(r) for r in rows)
    Ht = sum(r[0].height + 16 for r in rows)
    sheet = Image.new("RGB", (W, Ht), (255, 255, 255))
    y = 0
    for r in rows:
        x = 0
        for i in r:
            sheet.paste(i, (x, y))
            x += i.width + 16
        y += max(i.height for i in r) + 16
    sheet.save(os.path.join(rev, "sheet.png"))
    print("SHEET", os.path.join(rev, "sheet.png"), sheet.size)


if __name__ == "__main__":
    for sid in sys.argv[1:]:
        main(sid)
