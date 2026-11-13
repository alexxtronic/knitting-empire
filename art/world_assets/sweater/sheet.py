"""The review sheet: the reference and the bare sweater on the top row, then each design on Nora from
the front, the back and close up, with its name and stars.

    uv run --no-project --with pillow python art/world_assets/sweater/sheet.py [nora]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
DESIGNS = [("cranberry", "Cranberry Classic", 1), ("oatmeal_stripe", "Oatmeal Stripe", 1),
           ("snowfall_yoke", "Snowfall Yoke", 2), ("flock", "Flock of Friends", 3),
           ("midnight_moon", "Midnight Moon", 4)]
W, H = 350, 450


def font(size):
    for p in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def main(cid):
    rv = os.path.join(HERE, "review")
    cols = 5
    sheet = Image.new("RGB", (W * cols, (H + 40) * 4), "white")
    d = ImageDraw.Draw(sheet)
    f = font(22)
    top = [("ref_sweater.png", "Reference"), ("review/alone_front.png", "Sweater, front"),
           ("review/alone_side.png", "Sweater, side")]
    for i, (p, label) in enumerate(top):
        im = Image.open(os.path.join(HERE, p)).convert("RGB")
        im.thumbnail((W, H))
        sheet.paste(im, (i * W + (W - im.width) // 2, 40))
        d.text((i * W + 10, 8), label, fill="black", font=f)
    for n, (did, name, stars) in enumerate(DESIGNS):
        x = n * W
        for r, view in enumerate(("front", "back", "close")):
            p = os.path.join(rv, "%s_%s_%s.png" % (cid, did, view))
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGB")
            im.thumbnail((W, H))
            sheet.paste(im, (x, (H + 40) * (r + 1) + 40))
        d.text((x + 10, (H + 40) + 8), "%s  %s" % (name, "*" * stars), fill="black", font=f)
    out = os.path.join(rv, "%s_sheet.jpg" % cid)
    sheet.save(out, quality=88)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "nora")
