"""The Bretton Oaks sign's face (2026-11-17): the town sign's board face (tex/board_face.png, from
make_face.py) with "Maple Grove" taken off and "Bretton Oaks" lettered in its place in the same
Superclarendon Black and cream, and the face's normal map to match. The game puts these on the
welcome_sign model's sign_face material for the suburb's sign (scripts/suburb.gd); the model itself
isn't changed. The name is a draft until Alex approves it.

Run: uv run --no-project --with numpy --with pillow python art/world_assets/welcome_sign/make_bretton.py
Writes assets/textures/signs/bretton_oaks_face.png and bretton_oaks_face_n.png.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "signs")
FONT_TTC = "/System/Library/Fonts/Supplemental/SuperClarendon.ttc"
FONT_FACE = 7  # Superclarendon Black, as build.py uses for the lettering
TEXT = "Bretton Oaks"
# the old name's band on the 1600 x 1344 face: between the two plank seams under "Welcome to" and
# over the pines, and the clear wood either side of it that the band is filled from
Y0, Y1 = 712, 978
X0, X1 = 118, 1492
CREAM = (241, 225, 190)
TOP, BOTTOM = 688, 994  # how far the old letters' tops and feet reach
PINES = (620, 990)      # the pines under the band, left alone


def main():
    face = np.asarray(Image.open(os.path.join(HERE, "tex", "board_face.png")).convert("RGB")).astype(float)
    nrm = np.asarray(Image.open(os.path.join(HERE, "tex", "board_face_normal.png")).convert("RGB")).astype(float)
    h, w, _ = face.shape
    # wipe the band: each row runs from the wood at its left end to the wood at its right, so the
    # grain carries straight across, with a little noise so it doesn't look smeared
    rng = np.random.default_rng(5)
    t = np.linspace(0, 1, X1 - X0)[None, :, None]
    left = face[Y0:Y1, X0 - 6:X0].mean(1, keepdims=True)
    right = face[Y0:Y1, X1:X1 + 6].mean(1, keepdims=True)
    band = left * (1 - t) + right * t
    streak = rng.normal(0, 1, (Y1 - Y0, 1, 1)) * 4 + rng.normal(0, 1, (Y1 - Y0, X1 - X0, 1)) * 2.5
    face[Y0:Y1, X0:X1] = band + streak
    nrm[Y0:Y1, X0:X1] = (128, 128, 255)
    # the tall letters reached past the band: the tops of "l" and "G" up to the seam under "Welcome to",
    # the feet down to the pines; the rows there are filled from just outside them, left of the pines
    # and right of them only
    for ya, yb, src in ((TOP, Y0, TOP - 3), (Y1, BOTTOM, BOTTOM + 3)):
        for xa, xb in ((X0, PINES[0]), (PINES[1], X1)) if ya == Y1 else ((X0, X1),):
            row = face[src:src + 1, xa:xb]
            face[ya:yb, xa:xb] = row + rng.normal(0, 2.5, (yb - ya, xb - xa, 1))
            nrm[ya:yb, xa:xb] = (128, 128, 255)
    # the new name, as big as the old one: the cream letters with the soft dark edge they had
    font = ImageFont.truetype(FONT_TTC, 200, index=FONT_FACE)
    for size in range(240, 120, -4):
        font = ImageFont.truetype(FONT_TTC, size, index=FONT_FACE)
        box = font.getbbox(TEXT)
        if box[2] - box[0] <= (X1 - X0) - 90 and box[3] - box[1] <= (Y1 - Y0) - 40:
            break
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    box = font.getbbox(TEXT)
    tx = (X0 + X1) / 2 - (box[0] + box[2]) / 2
    ty = (Y0 + Y1) / 2 - (box[1] + box[3]) / 2 + 6
    d.text((tx, ty), TEXT, font=font, fill=255)
    m = np.asarray(mask).astype(float) / 255.0
    shadow = np.asarray(mask.filter(ImageFilter.GaussianBlur(7))).astype(float) / 255.0
    shadow = np.roll(np.roll(shadow, 5, 0), 3, 1)
    face *= (1 - 0.45 * np.clip(shadow - m, 0, 1))[..., None]
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.2))).astype(float)[..., None] / 255.0
    shade = 0.9 + 0.1 * (np.asarray(mask.filter(ImageFilter.GaussianBlur(10))).astype(float)[..., None] / 255.0)
    face = face * (1 - soft) + np.array(CREAM) * shade * soft
    # the letters' relief in the normal map: their edges round over like the old ones
    hgt = np.asarray(mask.filter(ImageFilter.GaussianBlur(4))).astype(float) / 255.0
    dx = np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)
    dy = np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)
    k = 6.0
    n = np.dstack([-dx * k, dy * k, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    sel = hgt > 0.01
    nrm[sel] = (n[sel] * 0.5 + 0.5) * 255
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.clip(face, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "bretton_oaks_face.png"))
    Image.fromarray(np.clip(nrm, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "bretton_oaks_face_n.png"))
    print("WROTE", OUT, "font size", font.size)


if __name__ == "__main__":
    main()
