"""Lays a Tripo animal's loop renders out on one review sheet (plain Python, Pillow).

    uv run --no-project --with pillow python art/world_assets/wildlife/tripo_sheet.py <id> [...]

tripo_build.py --render writes review/<id>/tripo_<loop>_<view>_<k>.png: Idle, Walk and Run, from the
side and from the front three-quarter, four frames each (0, 1/4, 1/2 and 3/4 of the loop). This puts
them in a grid, one row per loop and view, with the reference lineup's picture of the animal on top
where there is one, and saves review/<id>/tripo_sheet.png (the one review file git keeps).
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 260


def sheet(sid):
    d = os.path.join(HERE, "review", sid)
    rows = [(loop, view) for loop in ("idle", "walk", "run") for view in ("side", "q")]
    W, H = 4 * CELL + 120, len(rows) * CELL + 40
    out = Image.new("RGB", (W, H), (200, 200, 200))
    dr = ImageDraw.Draw(out)
    dr.rectangle((0, 0, W, 30), fill=(40, 40, 40))
    dr.text((10, 9), sid, fill=(240, 240, 240))
    for r, (loop, view) in enumerate(rows):
        y = 40 + r * CELL
        dr.text((10, y + CELL // 2), "%s\n%s" % (loop, "side" if view == "side" else "3/4"), fill=(30, 30, 30))
        for k in range(4):
            p = os.path.join(d, "tripo_%s_%s_%d.png" % (loop, view, k))
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGB")
            im.thumbnail((CELL, CELL))
            out.paste(im, (120 + k * CELL, y))
    path = os.path.join(d, "tripo_sheet.png")
    out.save(path)
    print("SHEET", os.path.relpath(path, HERE))


for sid in sys.argv[1:]:
    sheet(sid)
