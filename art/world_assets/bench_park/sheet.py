"""Lays the review renders out as contact sheets (colour, clay) and a comparison with the reference.

    uv run --no-project --with pillow python art/world_assets/bench_park/sheet.py <round folder>
"""
import os
import sys

from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
d = sys.argv[1]
ref = Image.open(os.path.join(here, "ref", "reference.png")).convert("RGB").resize((1280, 720))
mine = Image.open(os.path.join(d, "ref.png")).convert("RGB")
s = Image.new("RGB", (1280, 1440), "white")
s.paste(ref, (0, 0))
s.paste(mine, (0, 720))
s.save(os.path.join(d, "side_by_side.png"))
tiles = ["front_left", "front", "side", "back", "game", "close_arm", "close_back"]
for tag in ("", "_clay"):
    sheet = Image.new("RGB", (960 * 2, 640 * 4), "white")
    for i, t in enumerate(tiles):
        im = Image.open(os.path.join(d, t + tag + ".png")).convert("RGB")
        sheet.paste(im, (960 * (i % 2), 640 * (i // 2)))
    im = Image.open(os.path.join(d, "ref" + tag + ".png")).convert("RGB").resize((960, 540))
    sheet.paste(im, (960, 640 * 3 + 50))
    sheet.save(os.path.join(d, "sheet" + tag + ".png"))
