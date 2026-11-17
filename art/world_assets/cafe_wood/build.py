"""The Cappuccino Cafe's wood (Alex, 2026-11-17: "add better wood textures realistic throughout cafe").

Turns four CC0 photo scans from Poly Haven (art/world_assets/textures_web, see its README) into the
game's wood maps in assets/textures/wood/: a colour map and an OpenGL normal map for each, 1024 px,
seamless as Poly Haven makes them, with the grain or the boards running up the image (v), which is
how scripts/building_skin.gd lays them: up a wall, up a roof's slope, along the room on a floor.

    floor   wood_floor      oak floorboards, staggered ends               1.70 m square
    boards  wood_planks     honey pine boards (turned upright here)       1.50 m square
    oak     oak_veneer_01   fine light oak, for tables and counter tops   1.83 m square
    walnut  wood_table_001  dark walnut, for shelves, beams and the stairs 1.50 m square

Run:  uv run --no-project --with pillow --with numpy python art/world_assets/cafe_wood/build.py
then import (Godot --headless --path . --import).
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SRC = os.path.join(ROOT, "art", "world_assets", "textures_web")
OUT = os.path.join(ROOT, "assets", "textures", "wood")

# kind: (scan, turn a quarter left so the grain runs up the image)
MAPS = {
    "floor": ("wood_floor", False),
    "boards": ("wood_planks", True),
    "oak": ("oak_veneer_01", False),
    "walnut": ("wood_table_001", False),
}


def turn_normal(img):
    """A tangent-space normal map turned a quarter left: the picture turns, and so do the
    normals in it, (x, y) -> (-y, x)."""
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    a = np.rot90(a, 1)  # a quarter left, as Image.rotate(90)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    out = np.stack([255 - g, r, b], -1).astype(np.uint8)
    return Image.fromarray(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind, (scan, turn) in MAPS.items():
        diff = Image.open(os.path.join(SRC, scan, scan + "_diff_1k.jpg")).convert("RGB")
        nrm = Image.open(os.path.join(SRC, scan, scan + "_nor_gl_1k.jpg")).convert("RGB")
        if turn:
            diff = diff.rotate(90, expand=True)
            nrm = turn_normal(nrm)
        diff.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, kind + ".jpg"), quality=92)
        nrm.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, kind + "_n.png"))
        print("wood", kind, "from", scan)


if __name__ == "__main__":
    main()
