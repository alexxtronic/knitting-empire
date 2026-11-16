"""Letter the café's name on the plaque over the awning (Alex, 2026-11-16: the café is Cappuccino
Cafe, and it should say so on the building).

The plaque's face is cut from Alex's concept (make_faces.py): a cream coffee cup and two sprigs,
carved in relief on a green plank board. This keeps the board and the cup, lifts the cup and the
sprigs up into the hump of the frame at a smaller size, and carves "Cappuccino Cafe" across the
board under them in the same cream relief: a lit upper-left edge, a shadow down and to the right.

make_faces.py calls letter() on the plaque's crop before saving tex/face_plaque.png. Run alone it
writes review/plaque_named.png from the reference:

    uv run --no-project --with numpy --with pillow python art/world_assets/coffee_shop/name_plaque.py
"""
import json
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Cappuccino Cafe"
FONTS = ["/System/Library/Fonts/Supplemental/Georgia Bold Italic.ttf",
         "/Library/Fonts/Georgia Bold Italic.ttf"]
CREAM = (240, 226, 196)

# on the plaque's face as make_faces.py saves it (696 x 324: the reference's crop at 2x)
CUP = (250, 50, 452, 266)  # the cup, its saucer and its steam
SPRIGS = [(96, 136, 236, 262), (452, 136, 596, 262)]
INNER = (36, 0, 654, 276)  # the board inside the cream frame: its left, right and bottom edges
FRAME = 34  # the frame's width, from its outline in to the board
FACE_W, FACE_H = 696, 324
CUP_TO = (348, 42, 0.5)  # where the cup goes: its centre x, its top, and its scale
SPRIG_TO = 0.52  # the sprigs' scale; they sit either side of the cup
TEXT_BOX = (66, 152, 630, 262)  # the name fits inside this
SEED = (60, 200)  # a clean spot on the board
CLEAN = (40, 92)  # a clean strip of every row (x), left of the sprigs


def _board_mask(a):
    """The green board's own pixels: at least as green as they are red, and not bright."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (g >= r - 2) & (r + g + b < 420)


def _cream_mask(a):
    """The cream work (the frame, the cup, the sprigs) and its warm shading: redder than green."""
    r, g = a[..., 0], a[..., 1]
    return (r > g + 3) | (a.sum(axis=2) > 480)


def _inner():
    """The board inside the cream frame, on the face: the frame's outline as make_faces.py traced it
    (tex/plaque_outline.json, in reference pixels), pulled in by the frame's width."""
    with open(os.path.join(HERE, "tex", "plaque_outline.json")) as f:
        prof = json.load(f)
    x0, y0 = prof["crop"][0], prof["crop"][1]
    xs = (np.array(prof["x"]) - x0) * 2.0
    tops = (np.array(prof["top"]) - y0) * 2.0
    region = np.zeros((FACE_H, FACE_W), bool)
    for x in range(INNER[0], INNER[2]):
        top = np.interp(x, xs, tops) + FRAME
        region[int(np.ceil(top)):INNER[3], x] = True
    return region


def _clear(img):
    """The board with the cup and the sprigs taken off: inside the frame it is painted again row by
    row, each row its own board colour (the median of its green pixels: the planks and their seams
    run along the rows), with a faint smooth grain, and blended into the old board over a few
    pixels at the frame's edge."""
    a = np.asarray(img).astype(float)
    region = _inner()
    green = _board_mask(a) & region
    rng = np.random.default_rng(7)
    out = a.copy()
    paint = a.copy()
    for y in range(img.height):
        if not region[y].any():
            continue
        row = green[y] if green[y].sum() >= 8 else green[max(0, y - 2):y + 3].any(axis=0)
        base = np.median(a[y][row], axis=0) if row.any() else a[y][region[y]].mean(axis=0)
        grain = np.convolve(rng.normal(0, 5, img.width + 40), np.ones(25) / 25, mode="same")[20:-20]
        paint[y] = base + grain[:, None] * np.array([1.0, 1.0, 0.8])
    soft = np.asarray(Image.fromarray((region * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(2.0))).astype(float)[..., None] / 255
    out = paint * soft + a * (1 - soft)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def _carving(img, box):
    """A carved piece cut from the face with a soft mask of everything that isn't board."""
    piece = img.crop(box)
    a = np.asarray(piece).astype(float)
    mask = Image.fromarray((_cream_mask(a) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    return piece, mask


def _paste_scaled(dst, piece, mask, scale, at):
    w, h = int(piece.width * scale), int(piece.height * scale)
    dst.paste(piece.resize((w, h), Image.LANCZOS), at, mask.resize((w, h), Image.LANCZOS))
    return w, h


def _font(size):
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    raise SystemExit("no Georgia Bold Italic on this computer")


def _name(dst):
    """The name in raised cream letters, as big as fits TEXT_BOX."""
    bx0, by0, bx1, by1 = TEXT_BOX
    size = 120
    while True:
        f = _font(size)
        l, t, r, b = f.getbbox(NAME)
        if r - l <= bx1 - bx0 and b - t <= by1 - by0:
            break
        size -= 2
    w, h = r - l, b - t
    ox = bx0 + (bx1 - bx0 - w) // 2 - l
    oy = by0 + (by1 - by0 - h) // 2 - t
    mask = Image.new("L", dst.size, 0)
    ImageDraw.Draw(mask).text((ox, oy), NAME, font=f, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    # the shadow it casts down and to the right on the board
    shadow = ImageChops.offset(mask, 3, 4).filter(ImageFilter.GaussianBlur(2.2))
    dark = Image.new("RGB", dst.size, (36, 48, 26))
    dst.paste(dark, (0, 0), shadow.point(lambda v: int(v * 0.75)))
    # the letters: cream, a little darker toward their foot
    grad = Image.linear_gradient("L").resize(dst.size)
    face = Image.merge("RGB", [grad.point(lambda v, c=c: int(c - v * 0.10 * (c / 255.0) * 255 / 255 * 0.6)) for c in CREAM])
    face = Image.composite(Image.new("RGB", dst.size, CREAM), face, Image.new("L", dst.size, 90))
    dst.paste(face, (0, 0), mask)
    # the carved edge: lit along the upper left, in shade along the lower right
    inner = mask.filter(ImageFilter.MinFilter(3))
    rim = ImageChops.subtract(mask, inner)
    lit = ImageChops.multiply(rim, ImageChops.subtract(mask, ImageChops.offset(mask, -2, -2)))
    shade = ImageChops.multiply(rim, ImageChops.subtract(mask, ImageChops.offset(mask, 2, 2)))
    dst.paste(Image.new("RGB", dst.size, (255, 247, 228)), (0, 0), lit.point(lambda v: min(255, v * 2)))
    dst.paste(Image.new("RGB", dst.size, (176, 150, 112)), (0, 0), shade.point(lambda v: min(255, v * 2)))
    return size


def letter(face):
    """The plaque's face (make_faces.py's crop, 696 x 324) with the café's name carved on it."""
    face = face.convert("RGB")
    cup, cup_m = _carving(face, CUP)
    sprigs = [_carving(face, b) for b in SPRIGS]
    out = _clear(face)
    cx, top, s = CUP_TO
    w, h = _paste_scaled(out, cup, cup_m, s, (int(cx - cup.width * s / 2), top))
    cup_l, cup_r = int(cx - w / 2), int(cx + w / 2)
    for i, (piece, m) in enumerate(sprigs):
        sw, sh = int(piece.width * SPRIG_TO), int(piece.height * SPRIG_TO)
        x = cup_l - sw - 10 if i == 0 else cup_r + 10
        _paste_scaled(out, piece, m, SPRIG_TO, (x, top + h - sh - 6))
    size = _name(out)
    print("plaque named: %s at %d px, cup %dx%d" % (NAME, size, w, h))
    return out


if __name__ == "__main__":
    ref = Image.open(os.path.join(HERE, "ref", "coffee_shop_concept.png")).convert("RGB")
    crop = ref.crop((512, 412, 860, 574))
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)
    os.makedirs(os.path.join(HERE, "review"), exist_ok=True)
    letter(crop).save(os.path.join(HERE, "review", "plaque_named.png"))
