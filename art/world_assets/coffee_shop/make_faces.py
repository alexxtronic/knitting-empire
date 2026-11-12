"""Lift the coffee shop's two painted faces out of Alex's reference, like the shop signs
(shop_signs/make_faces.py): the plaque over the awning (the coffee cup between two sprigs) and
the chalkboard's face. Both are square-on in the concept. build.py maps them onto flat panels.

Run: uv run --no-project --with pillow python art/world_assets/coffee_shop/make_faces.py
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FACES = {  # name: (x0, y0, x1, y1) in the reference
    "plaque": (512, 412, 860, 574),
    "chalkboard": (1110, 860, 1202, 972),
}


def main():
    ref = Image.open(os.path.join(HERE, "ref", "coffee_shop_concept.png")).convert("RGB")
    os.makedirs(os.path.join(HERE, "tex"), exist_ok=True)
    for name, box in FACES.items():
        face = ref.crop(box)
        face = face.resize((face.width * 2, face.height * 2), Image.LANCZOS)
        face.save(os.path.join(HERE, "tex", "face_%s.png" % name))
        print(name, face.size)
    # the plaque's outline: its top edge (notched corners, a hump in the middle) traced off the
    # cream frame, per column; its sides and bottom are straight
    a = np.asarray(ref).astype(int)
    x0, y0, x1, y1 = FACES["plaque"]
    cream = (a[..., 0] > 215) & (a[..., 1] > 180) & (a[..., 2] > 130) & (a[..., 0] - a[..., 2] < 95)
    cols, tops = [], []
    for x in range(x0 + 4, x1 - 3, 4):
        run = cream[y0:y0 + 90, x] & np.roll(cream[y0:y0 + 90, x], -1) & np.roll(cream[y0:y0 + 90, x], -2)
        hit = np.nonzero(run)[0]
        if len(hit):
            cols.append(x)
            tops.append(int(y0 + hit[0] + 2))
    with open(os.path.join(HERE, "tex", "plaque_outline.json"), "w") as f:
        json.dump({"x": cols, "top": tops, "bottom": 568, "crop": list(FACES["plaque"])}, f)
    print("plaque top", min(tops), max(tops), "over", cols[0], cols[-1])


if __name__ == "__main__":
    main()
