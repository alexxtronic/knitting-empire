"""The review sheets, from the designs in patterns.py.

    uv run --no-project --with numpy --with pillow python art/world_assets/sweater/sheet.py [nora] [id ...]

With design ids: the detail sheet, review/<cid>_sheet.jpg: the reference and the bare sweater on the top
row, then each design from the front, the back and close up. Without: the catalogue,
review/<cid>_catalogue.jpg: every design from the front and the back, grouped by stars.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patterns as PT  # noqa: E402

TIERS = {1: "Common", 2: "Rare", 3: "Ultra rare", 4: "Legendary"}
W, H = 350, 450


def font(size):
    for p in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _img(path, box):
    im = Image.open(path).convert("RGB")
    im.thumbnail(box)
    return im


def detail(cid, ids):
    rv = os.path.join(HERE, "review")
    designs = [sw for sw in PT.SWEATERS if sw["id"] in ids]
    cols = max(3, len(designs))
    sheet = Image.new("RGB", (W * cols, (H + 40) * 4), "white")
    d = ImageDraw.Draw(sheet)
    f = font(22)
    top = [("ref_sweater.png", "Reference"), ("review/alone_front.png", "Sweater, front"),
           ("review/alone_side.png", "Sweater, side")]
    for i, (p, label) in enumerate(top):
        im = _img(os.path.join(HERE, p), (W, H))
        sheet.paste(im, (i * W + (W - im.width) // 2, 40))
        d.text((i * W + 10, 8), label, fill="black", font=f)
    for n, sw in enumerate(designs):
        x = n * W
        for r, view in enumerate(("front", "back", "close")):
            p = os.path.join(rv, "%s_%s_%s.png" % (cid, sw["id"], view))
            if os.path.exists(p):
                sheet.paste(_img(p, (W, H)), (x, (H + 40) * (r + 1) + 40))
        d.text((x + 10, (H + 40) + 8), "%s  %s" % (sw["name"], "*" * sw["stars"]), fill="black", font=f)
    out = os.path.join(rv, "%s_sheet.jpg" % cid)
    sheet.save(out, quality=88)
    print(out)


def catalogue(cid):
    rv = os.path.join(HERE, "review")
    cw, ch, cols, head, lab = 190, 245, 5, 46, 30      # one view; a design is a front and a back
    rows = []
    for stars in (1, 2, 3, 4):
        tier = [sw for sw in PT.SWEATERS if sw["stars"] == stars]
        rows.append(("head", stars, len(tier)))
        for i in range(0, len(tier), cols):
            rows.append(("row", tier[i:i + cols], None))
    height = sum(head if r[0] == "head" else ch + lab for r in rows)
    sheet = Image.new("RGB", (cw * 2 * cols + 20 * (cols - 1), height + 20), "white")
    d = ImageDraw.Draw(sheet)
    fh, fl = font(30), font(17)
    y = 10
    for kind, a, b in rows:
        if kind == "head":
            d.text((12, y + 8), "%s  %s   (%d)" % ("*" * a, TIERS[a], b), fill="black", font=fh)
            y += head
            continue
        for i, sw in enumerate(a):
            x = i * (cw * 2 + 20)
            for k, view in enumerate(("front", "back")):
                p = os.path.join(rv, "%s_%s_%s.png" % (cid, sw["id"], view))
                if os.path.exists(p):
                    im = _img(p, (cw, ch))
                    sheet.paste(im, (x + k * cw + (cw - im.width) // 2, y))
            d.text((x + 8, y + ch + 4), sw["name"], fill="black", font=fl)
        y += ch + lab
    out = os.path.join(rv, "%s_catalogue.jpg" % cid)
    sheet.save(out, quality=86)
    print(out)


if __name__ == "__main__":
    args = sys.argv[1:]
    cid = args.pop(0) if args else "nora"
    if args:
        detail(cid, args)
    else:
        catalogue(cid)
