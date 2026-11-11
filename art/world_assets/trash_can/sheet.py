"""Lays the trash can's review renders out beside the reference (colour and clay sheets).

    uv run --no-project --with pillow python art/world_assets/trash_can/sheet.py <round folder>
"""
import os
import sys

from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
d = sys.argv[1]
ref = Image.open(os.path.join(here, "ref", "reference.png")).convert("RGB").resize((640, 640))
tiles = ["ref", "front_left", "side", "back", "game", "close_arm"]
for tag in ("", "_clay"):
    sheet = Image.new("RGB", (640 + 960 * 2, 640 * 3), "white")
    sheet.paste(ref, (0, 0))
    for i, t in enumerate(tiles):
        im = Image.open(os.path.join(d, t + tag + ".png")).convert("RGB")
        if t == "ref":
            im = im.resize((960, 540))
        sheet.paste(im, (640 + 960 * (i % 2), 640 * (i // 2)))
    sheet.save(os.path.join(d, "sheet" + tag + ".png"))
