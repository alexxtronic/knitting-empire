"""Lays the barn's review renders out as two sheets: outside and inside.

    uv run --no-project --with pillow python art/world_assets/barn/sheet.py <round folder>
"""
import os
import sys

from PIL import Image

d = sys.argv[1]


def sheet(name, tiles, cols, cell):
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (cell[0] * cols, cell[1] * rows), "white")
    for i, t in enumerate(tiles):
        im = Image.open(os.path.join(d, t + ".png")).convert("RGB")
        im.thumbnail(cell, Image.LANCZOS)
        out.paste(im, (cell[0] * (i % cols) + (cell[0] - im.width) // 2, cell[1] * (i // cols) + (cell[1] - im.height) // 2))
    out.save(os.path.join(d, name + ".png"))


sheet("sheet_outside", ["ref", "front", "back", "game"], 2, (960, 900))
sheet("sheet_inside", ["inside_game", "inside_low", "inside_left", "inside_top", "doors_open"], 2, (1000, 820))
